-- super-excavate: wireless-enabled quarry turtle
-- Arguments: excavate <length> <width> [depth]
-- Places mined items into a chest directly above the turtle at the start position.

local args = { ... }

if #args < 2 then
  print("Usage: excavate <length> <width> [depth]")
  print("  length: blocks in the direction the turtle faces")
  print("  width : blocks to the right (turtle will snake rows)")
  print("  depth : layers down to remove (default 1)")
  return
end

local length = tonumber(args[1])
local width = tonumber(args[2])
local depth = tonumber(args[3]) or 1

if not length or not width or not depth or length < 1 or width < 1 or depth < 1 then
  error("length, width, and depth must be positive numbers")
end

local totalBlocks = length * width * depth
local cleared = 0

local pos = { x = 0, y = 0, z = 0 }
local facing = 0 -- 0 = east, 1 = south, 2 = west, 3 = north

local function dirVector(dir)
  if dir == 0 then return 1, 0 end
  if dir == 1 then return 0, 1 end
  if dir == 2 then return -1, 0 end
  return 0, -1
end

local function turnRight()
  turtle.turnRight()
  facing = (facing + 1) % 4
end

local function turnLeft()
  turtle.turnLeft()
  facing = (facing + 3) % 4
end

local function face(dir)
  while facing ~= dir do
    turnRight()
  end
end

local function digForward()
  while turtle.detect() do
    turtle.dig()
    sleep(0.1)
  end
  while turtle.attack() do
    sleep(0.1)
  end
end

local function digUp()
  while turtle.detectUp() do
    turtle.digUp()
    sleep(0.1)
  end
  while turtle.attackUp() do
    sleep(0.1)
  end
end

local function digDown()
  while turtle.detectDown() do
    turtle.digDown()
    sleep(0.1)
  end
  while turtle.attackDown() do
    sleep(0.1)
  end
end

local function tryForward()
  while not turtle.forward() do
    digForward()
  end
  local dx, dz = dirVector(facing)
  pos.x = pos.x + dx
  pos.z = pos.z + dz
end

local function tryUp()
  while not turtle.up() do
    digUp()
  end
  pos.y = pos.y + 1
end

local function tryDown()
  while not turtle.down() do
    digDown()
  end
  pos.y = pos.y - 1
end

local function moveAxis(delta, positiveMove, negativeMove)
  while delta > 0 do
    positiveMove()
    delta = delta - 1
  end
  while delta < 0 do
    negativeMove()
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

  -- Restore facing east for consistency when we explicitly face again later
end

local modemSide
for _, side in ipairs(rs.getSides()) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
    modemSide = side
    break
  end
end

local hasModem = false
if modemSide then
  rednet.open(modemSide)
  hasModem = true
else
  print("[warn] No wireless modem found; status will not broadcast")
end

local function now()
  return os.epoch("utc")
end

local lastBroadcastBlocks = -1
local lastBroadcastState = nil
local lastBroadcastTime = 0
local progressStep = math.max(math.floor(totalBlocks / 40), 1) -- ~2.5% updates

local function headingName(dir)
  if dir == 0 then return "east" end
  if dir == 1 then return "south" end
  if dir == 2 then return "west" end
  return "north"
end

local function distanceFromHome()
  return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
end

local function broadcast(state, detail)
  if not hasModem then return end
  lastBroadcastState = state
  lastBroadcastTime = now()
  local payload = {
    id = os.getComputerID(),
    label = os.getComputerLabel(),
    state = state,
    detail = detail,
    progress = cleared / totalBlocks,
    cleared = cleared,
    total = totalBlocks,
    fuel = turtle.getFuelLevel(),
    position = { x = pos.x, y = pos.y, z = pos.z },
    heading = headingName(facing),
    distance_from_home = distanceFromHome(),
    job = { length = length, width = width, depth = depth },
    timestamp = lastBroadcastTime,
  }
  rednet.broadcast(payload, "super_excavate")
end

local function maybeBroadcastProgress()
  if not hasModem then return end
  if cleared == totalBlocks then
    broadcast(lastBroadcastState or "excavating", "Layer complete")
    return
  end

  if cleared >= lastBroadcastBlocks + progressStep or now() - lastBroadcastTime > 7000 then
    lastBroadcastBlocks = cleared
    broadcast(lastBroadcastState or "excavating", string.format("%.1f%% done", (cleared / totalBlocks) * 100))
  end
end

local function isInventoryFull()
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then
      return false
    end
  end
  return true
end

local function unloadToChest()
  local chestFound = false
  local ok, data = turtle.inspectUp()
  if ok and data and data.name then
    chestFound = string.find(data.name, "chest") ~= nil
  end

  for i = 1, 16 do
    turtle.select(i)
    if turtle.getItemCount(i) > 0 then
      local isFuel = turtle.refuel(0)
      if not isFuel then
        if not chestFound then
          print("[warn] No chest above; dropping items")
        end
        turtle.dropUp()
      end
    end
  end
  turtle.select(1)
end

local function ensureFuel(required)
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return true end

  if fuel >= required then return true end

  for i = 1, 16 do
    turtle.select(i)
    while turtle.getItemCount(i) > 0 and turtle.refuel(1) and turtle.getFuelLevel() < required do
      -- keep refuelling
    end
    if turtle.getFuelLevel() >= required then
      turtle.select(1)
      return true
    end
  end

  turtle.select(1)
  return turtle.getFuelLevel() >= required
end

local function estimateFuelCost()
  -- Rough overestimate to keep things safe
  return math.max(totalBlocks * 2 + depth * (length + width) + 16, 0)
end

local function goHomeAndUnload(reason)
  local target = { x = pos.x, y = pos.y, z = pos.z, facing = facing }
  broadcast("unloading", reason)

  moveTo(0, pos.y, 0)
  moveTo(0, 0, 0)
  face(0)
  unloadToChest()

  moveTo(target.x, target.y, target.z)
  face(target.facing)
end

local function markProgress(count)
  cleared = cleared + count
  maybeBroadcastProgress()
end

local function checkInventory()
  if isInventoryFull() then
    goHomeAndUnload("Inventory full")
  end
end

local function clearLayer(layerIndex)
  digDown()
  tryDown()
  markProgress(1)
  checkInventory()

  for row = 1, width do
    for col = 1, length - 1 do
      digForward()
      tryForward()
      markProgress(1)
      checkInventory()
    end

    if row < width then
      if row % 2 == 1 then
        turnRight()
        digForward()
        tryForward()
        markProgress(1)
        checkInventory()
        turnRight()
      else
        turnLeft()
        digForward()
        tryForward()
        markProgress(1)
        checkInventory()
        turnLeft()
      end
    end
  end

  moveTo(0, pos.y, 0)
  face(0)
end

local function run()
  local requiredFuel = estimateFuelCost()
  if not ensureFuel(requiredFuel) then
    broadcast("error", "Not enough fuel")
    error("Not enough fuel. Need ~" .. requiredFuel .. ". Place fuel in inventory.")
  end

  broadcast("ready", string.format("%dx%dx%d", length, width, depth))
  unloadToChest()

  for layer = 1, depth do
    broadcast("excavating", string.format("Layer %d/%d", layer, depth))
    clearLayer(layer)
  end

  moveTo(0, 0, 0)
  face(0)
  unloadToChest()
  broadcast("done", "Excavation complete")
  print("Excavation complete")
end

run()
