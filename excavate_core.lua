-- Core logic for super-excavate. Accepts a ComputerCraft-like environment
-- and argument list, and runs the excavation routine. Designed so it can be
-- required by tests or a simulator without immediately executing.

local stateStore = dofile("state_store.lua")

local function defaultPrint(...)
  return print(...)
end

local function defaultEpoch()
  if os and os.time then
    return os.time() * 1000
  end
  return 0
end

local function defaultSleep(seconds)
  if _G.sleep then return _G.sleep(seconds) end
  -- No-op outside ComputerCraft
end

local function resolveEnv(env)
  env = env or _G
  local envOs = env.os or {}
  if not envOs.epoch then
    envOs = setmetatable({ epoch = function() return defaultEpoch() end }, { __index = envOs })
  end
  return {
    args = env.args,
    turtle = assert(env.turtle, "turtle API is required"),
    rednet = env.rednet,
    rs = env.rs or { getSides = function() return {} end },
    peripheral = env.peripheral or {
      getType = function() return nil end,
      call = function() return nil end,
    },
    os = envOs,
    sleep = env.sleep or defaultSleep,
    print = env.print or defaultPrint,
    fs = env.fs or _G.fs,
    textutils = env.textutils or _G.textutils,
  }
end

local function makeBroadcaster(env, state)
  local hasModem = false
  local modemSide
  for _, side in ipairs(env.rs.getSides()) do
    if env.peripheral.getType(side) == "modem" and env.peripheral.call(side, "isWireless") then
      modemSide = side
      break
    end
  end

  if modemSide and env.rednet then
    env.rednet.open(modemSide)
    hasModem = true
  else
    env.print("[warn] No wireless modem found; status will not broadcast")
  end

  local lastBroadcastBlocks = -1
  local lastBroadcastState = nil
  local lastBroadcastTime = 0

  local function broadcast(payload)
    if hasModem and env.rednet then
      env.rednet.broadcast(payload, "super_excavate")
    end
    lastBroadcastState = payload.state
    lastBroadcastTime = payload.timestamp
  end

  local function maybeBroadcast(progressStep)
    if not hasModem or not env.rednet then return end
    return function(cleared, totalBlocks, detail, position)
      if cleared == totalBlocks then
        broadcast(state.buildPayload(lastBroadcastState or "excavating", "Layer complete", cleared, position))
        return
      end

      if cleared >= lastBroadcastBlocks + progressStep or env.os.epoch("utc") - lastBroadcastTime > 7000 then
        lastBroadcastBlocks = cleared
        broadcast(state.buildPayload(lastBroadcastState or "excavating", detail, cleared, position))
      end
    end
  end

  return broadcast, maybeBroadcast
end

local function run(env, args, opts)
  env = resolveEnv(env)
  args = args or {}
  opts = opts or {}

  local stateManager = opts.state or (opts.statePath and stateStore.new(opts.statePath, env)) or nil
  local restored = opts.resumeState

  local turtle = env.turtle

  local length = tonumber(args[1])
  local width = tonumber(args[2])
  local depth = tonumber(args[3]) or 1

  if restored and restored.job then
    length = restored.job.length or length
    width = restored.job.width or width
    depth = restored.job.depth or depth
  end

  if not length or not width or not depth or length < 1 or width < 1 or depth < 1 then
    if not restored then
      env.print("Usage: excavate <length> <width> [depth]")
      env.print("  length: blocks in the direction the turtle faces")
      env.print("  width : blocks to the right (turtle will snake rows)")
      env.print("  depth : layers down to remove (default 1)")
      return { completed = false, reason = "invalid_args" }
    end
    error("length, width, and depth must be positive numbers")
  end

  local totalBlocks = (restored and restored.total) or length * width * depth
  local cleared = (restored and restored.cleared) or 0

  local pos = (restored and restored.pos and { x = restored.pos.x or 0, y = restored.pos.y or 0, z = restored.pos.z or 0 }) or { x = 0, y = 0, z = 0 }
  local facing = (restored and restored.facing) or 0 -- 0 = east, 1 = south, 2 = west, 3 = north
  local progress = (restored and restored.progress) or {}
  local currentLayer = progress.layer or 1
  local currentRow = progress.row or 1
  local currentCol = progress.col or 1
  local descended = progress.descended or false

  local function snapshot()
    return {
      job = { length = length, width = width, depth = depth },
      total = totalBlocks,
      cleared = cleared,
      pos = { x = pos.x, y = pos.y, z = pos.z },
      facing = facing,
      progress = {
        layer = currentLayer,
        row = currentRow,
        col = currentCol,
        descended = descended,
      },
      timestamp = env.os.epoch("utc"),
    }
  end

  local function persistState()
    if not stateManager then return end
    stateManager.save(snapshot())
  end

  local function dirVector(dir)
    if dir == 0 then return 1, 0 end
    if dir == 1 then return 0, 1 end
    if dir == 2 then return -1, 0 end
    return 0, -1
  end

  local function headingName(dir)
    if dir == 0 then return "east" end
    if dir == 1 then return "south" end
    if dir == 2 then return "west" end
    return "north"
  end

  local function distanceFromHome()
    return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
  end

  local state = {}
  function state.buildPayload(label, detail, clearedBlocks, position)
    return {
      id = env.os.getComputerID and env.os.getComputerID(),
      label = env.os.getComputerLabel and env.os.getComputerLabel(),
      state = label,
      detail = detail,
      progress = clearedBlocks / totalBlocks,
      cleared = clearedBlocks,
      total = totalBlocks,
      fuel = turtle.getFuelLevel and turtle.getFuelLevel(),
      position = position and { x = position.x, y = position.y, z = position.z },
      heading = headingName(facing),
      distance_from_home = distanceFromHome(),
      job = { length = length, width = width, depth = depth },
      timestamp = env.os.epoch("utc"),
    }
  end

  local broadcast, makeMaybeBroadcast = makeBroadcaster(env, state)
  local progressStep = math.max(math.floor(totalBlocks / 40), 1) -- ~2.5% updates
  local maybeBroadcastProgress = makeMaybeBroadcast(progressStep)

  local function turnRight()
    if turtle.turnRight then turtle.turnRight() end
    facing = (facing + 1) % 4
    persistState()
  end

  local function turnLeft()
    if turtle.turnLeft then turtle.turnLeft() end
    facing = (facing + 3) % 4
    persistState()
  end

  local function face(dir)
    while facing ~= dir do
      turnRight()
    end
  end

  local function digForward()
    while turtle.detect and turtle.detect() do
      if turtle.dig then turtle.dig() end
      env.sleep(0.1)
    end
    while turtle.attack and turtle.attack() do
      env.sleep(0.1)
    end
  end

  local function digUp()
    while turtle.detectUp and turtle.detectUp() do
      if turtle.digUp then turtle.digUp() end
      env.sleep(0.1)
    end
    while turtle.attackUp and turtle.attackUp() do
      env.sleep(0.1)
    end
  end

  local function digDown()
    while turtle.detectDown and turtle.detectDown() do
      if turtle.digDown then turtle.digDown() end
      env.sleep(0.1)
    end
    while turtle.attackDown and turtle.attackDown() do
      env.sleep(0.1)
    end
  end

  local function tryForward()
    while turtle.forward and not turtle.forward() do
      digForward()
    end
    local dx, dz = dirVector(facing)
    pos.x = pos.x + dx
    pos.z = pos.z + dz
  end

  local function tryUp()
    while turtle.up and not turtle.up() do
      digUp()
    end
    pos.y = pos.y + 1
  end

  local function tryDown()
    while turtle.down and not turtle.down() do
      digDown()
    end
    pos.y = pos.y - 1
  end

  local function moveAxis(delta, positiveMove, negativeMove)
    while delta > 0 do
      positiveMove()
      persistState()
      delta = delta - 1
    end
    while delta < 0 do
      negativeMove()
      persistState()
      delta = delta + 1
    end
  end

  local function moveTo(x, y, z)
    if pos.y < y then moveAxis(y - pos.y, tryUp, tryDown) end
    if pos.y > y then moveAxis(pos.y - y, tryDown, tryUp) end

    if pos.x ~= x then
      face(pos.x < x and 0 or 2)
      moveAxis(math.abs(x - pos.x), tryForward, tryForward)
    end

    if pos.z ~= z then
      face(pos.z < z and 1 or 3)
      moveAxis(math.abs(z - pos.z), tryForward, tryForward)
    end
  end

  local function isInventoryFull()
    for i = 1, 16 do
      if turtle.getItemCount and turtle.getItemCount(i) == 0 then
        return false
      end
    end
    return true
  end

  local function unloadToChest()
    local chestFound = false
    if turtle.inspectUp then
      local ok, data = turtle.inspectUp()
      if ok and data and data.name then
        chestFound = string.find(data.name, "chest") ~= nil
      end
    end

    for i = 1, 16 do
      if turtle.select then turtle.select(i) end
      if turtle.getItemCount and turtle.getItemCount(i) > 0 then
        local isFuel = turtle.refuel and turtle.refuel(0)
        if not isFuel then
          if not chestFound then
            env.print("[warn] No chest above; dropping items")
          end
          if turtle.dropUp then turtle.dropUp() end
        end
      end
    end
    if turtle.select then turtle.select(1) end
  end

  local function ensureFuel(required)
    local fuel = turtle.getFuelLevel and turtle.getFuelLevel() or 0
    if fuel == "unlimited" then return true end
    if fuel >= required then return true end

    for i = 1, 16 do
      if turtle.select then turtle.select(i) end
      while turtle.getItemCount and turtle.getItemCount(i) > 0 and turtle.refuel and turtle.refuel(1) and turtle.getFuelLevel() < required do
      end
      if turtle.getFuelLevel and turtle.getFuelLevel() >= required then
        if turtle.select then turtle.select(1) end
        return true
      end
    end

    if turtle.select then turtle.select(1) end
    return turtle.getFuelLevel and turtle.getFuelLevel() >= required
  end

  local function estimateFuelCost()
    return math.max(totalBlocks * 2 + depth * (length + width) + 16, 0)
  end

  local function goHomeAndUnload(reason)
    local target = { x = pos.x, y = pos.y, z = pos.z, facing = facing }
    broadcast(state.buildPayload("unloading", reason, cleared, pos))

    moveTo(0, pos.y, 0)
    moveTo(0, 0, 0)
    face(0)
    unloadToChest()
    persistState()

    moveTo(target.x, target.y, target.z)
    face(target.facing)
    persistState()
  end

  local maybeBroadcast = maybeBroadcastProgress or function() end

  local function markProgress(count)
    cleared = cleared + count
    if opts.shouldAbort and opts.shouldAbort(cleared) then
      persistState()
      error("aborted by test hook")
    end
    if maybeBroadcast then
      maybeBroadcast(cleared, totalBlocks, string.format("%.1f%% done", (cleared / totalBlocks) * 100), pos)
    end
    persistState()
  end

  local function checkInventory()
    if isInventoryFull() then
      goHomeAndUnload("Inventory full")
    end
  end

  local function clearLayer()
    if not descended then
      digDown()
      tryDown()
      descended = true
      currentCol = 1
      currentRow = 1
      markProgress(1)
      checkInventory()
    end

    while currentRow <= width do
      while currentCol < length do
        digForward()
        tryForward()
        currentCol = currentCol + 1
        markProgress(1)
        checkInventory()
      end

      if currentRow >= width then
        break
      end

      if currentRow % 2 == 1 then
        turnRight()
        digForward()
        tryForward()
        currentRow = currentRow + 1
        currentCol = 1
        markProgress(1)
        checkInventory()
        turnRight()
      else
        turnLeft()
        digForward()
        tryForward()
        currentRow = currentRow + 1
        currentCol = 1
        markProgress(1)
        checkInventory()
        turnLeft()
      end
    end

    moveTo(0, pos.y, 0)
    face(0)
    currentLayer = currentLayer + 1
    currentRow = 1
    currentCol = 1
    descended = false
    persistState()
  end

  local requiredFuel = estimateFuelCost()
  if not ensureFuel(requiredFuel) then
    broadcast(state.buildPayload("error", "Not enough fuel", cleared, pos))
    error("Not enough fuel. Need ~" .. requiredFuel .. ". Place fuel in inventory.")
  end

  local startDetail = string.format("%dx%dx%d", length, width, depth)
  if restored then
    startDetail = string.format("Resuming %dx%dx%d @ %d/%d", length, width, depth, cleared, totalBlocks)
  end
  broadcast(state.buildPayload("ready", startDetail, cleared, pos))
  if not restored then
    unloadToChest()
  end
  persistState()

  while currentLayer <= depth do
    broadcast(state.buildPayload("excavating", string.format("Layer %d/%d", currentLayer, depth), cleared, pos))
    clearLayer()
  end

  moveTo(0, 0, 0)
  face(0)
  unloadToChest()
  broadcast(state.buildPayload("done", "Excavation complete", cleared, pos))
  env.print("Excavation complete")
  if stateManager then stateManager.clear() end

  return {
    completed = true,
    cleared = cleared,
    total = totalBlocks,
    position = { x = pos.x, y = pos.y, z = pos.z, facing = facing },
  }
end

return {
  run = run,
}
