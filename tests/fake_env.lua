local FakeEnv = {}

local function makeSerializer()
  local function encode(value)
    if type(value) == "number" or type(value) == "boolean" then
      return tostring(value)
    elseif type(value) == "string" then
      return string.format("%q", value)
    elseif type(value) == "table" then
      local parts = {}
      for k, v in pairs(value) do
        table.insert(parts, "[" .. encode(k) .. "]=" .. encode(v))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
  end

  local function decode(str)
    local fn = load("return " .. str)
    if not fn then return nil end
    local ok, result = pcall(fn)
    if not ok then return nil end
    return result
  end

  return {
    serialize = encode,
    unserialize = decode,
  }
end

function FakeEnv.makeFs(store)
  store = store or {}
  local function open(path, mode)
    if mode == "r" then
      if not store[path] then return nil end
      local closed = false
      return {
        readAll = function()
          if closed then return nil end
          return store[path]
        end,
        close = function()
          closed = true
        end,
      }
    elseif mode == "w" then
      local buffer = ""
      local closed = false
      return {
        write = function(text)
          if closed then return end
          buffer = buffer .. (text or "")
        end,
        writeLine = function(text)
          if closed then return end
          buffer = buffer .. (text or "") .. "\n"
        end,
        close = function()
          if closed then return end
          store[path] = buffer
          closed = true
        end,
      }
    end
    return nil
  end

  return {
    store = store,
    exists = function(path)
      return store[path] ~= nil
    end,
    open = open,
    delete = function(path)
      store[path] = nil
    end,
  }
end

function FakeEnv.makeTextutils()
  local serializer = makeSerializer()
  return {
    serialize = serializer.serialize,
    unserialize = serializer.unserialize,
  }
end

local function makeTurtle(config)
  config = config or {}
  local fuel = config.fuel or 100000
  local fuelPerItem = config.fuelPerItem or 80
  local selected = 1
  local slots = {}
  for i = 1, 16 do
    local inventory = config.inventory or {}
    slots[i] = inventory[i] or 0
  end

  local function consumeFuel()
    if fuel == "unlimited" then return true end
    if fuel <= 0 then return false end
    fuel = fuel - 1
    return true
  end

  return {
    forward = function()
      return consumeFuel()
    end,
    back = function()
      return consumeFuel()
    end,
    up = function()
      return consumeFuel()
    end,
    down = function()
      return consumeFuel()
    end,
    turnRight = function()
      return true
    end,
    turnLeft = function()
      return true
    end,
    detect = function()
      return config.detectForward or false
    end,
    detectUp = function()
      return config.detectUp or false
    end,
    detectDown = function()
      return config.detectDown or false
    end,
    dig = function()
      return true
    end,
    digUp = function()
      return true
    end,
    digDown = function()
      return true
    end,
    attack = function()
      return false
    end,
    attackUp = function()
      return false
    end,
    attackDown = function()
      return false
    end,
    inspectUp = function()
      if config.hasChest then
        return true, { name = "minecraft:chest" }
      end
      return false
    end,
    dropUp = function()
      slots[selected] = 0
      return true
    end,
    select = function(slot)
      selected = slot
      return true
    end,
    getItemCount = function(slot)
      return slots[slot] or 0
    end,
    refuel = function(count)
      local available = slots[selected] or 0
      if count == 0 then
        return available > 0
      end
      if available <= 0 then return false end
      local consume = math.min(count, available)
      slots[selected] = available - consume
      if fuel ~= "unlimited" then
        fuel = fuel + consume * fuelPerItem
      end
      return true
    end,
    getFuelLevel = function()
      return fuel
    end,
  }
end

local function makeRednet()
  local broadcasts = {}
  return {
    broadcasts = broadcasts,
    open = function(side)
      broadcasts.openedSide = side
    end,
    broadcast = function(payload, protocol)
      table.insert(broadcasts, { payload = payload, protocol = protocol })
    end,
  }
end

function FakeEnv.new(config)
  config = config or {}
  local clock = 0
  local rednet = config.disableRednet and nil or makeRednet()
  local modemSide = config.modemSide
  local fsStore = config.fsStore or {}
  local fs = config.fs or FakeEnv.makeFs(fsStore)
  local env = {
    turtle = makeTurtle(config.turtle or {}),
    rednet = rednet,
    rs = {
      getSides = function()
        if modemSide then return { modemSide } end
        return {}
      end,
    },
    peripheral = {
      getType = function(side)
        if modemSide and side == modemSide then return "modem" end
        return nil
      end,
      call = function(side, method)
        if modemSide and side == modemSide and method == "isWireless" then return true end
        return nil
      end,
    },
    os = {
      epoch = function(_)
        return clock
      end,
      getComputerID = function()
        return config.computerID or 42
      end,
      getComputerLabel = function()
        return config.computerLabel
      end,
    },
    sleep = function(seconds)
      clock = clock + (seconds or 0) * 1000
    end,
    print = function() end,
    fs = fs,
    textutils = config.textutils or FakeEnv.makeTextutils(),
  }

  env.modemSide = modemSide
  env.clock = function()
    return clock
  end

  return env
end

-- Drawing/monitor simulators for dashboard tests
function FakeEnv.makeDrawingSurface(width, height)
  local ops = {}
  local surface = {
    getSize = function()
      return width, height
    end,
    clear = function(color)
      table.insert(ops, { op = "clear", color = color })
    end,
    fillRect = function(x1, y1, x2, y2, color)
      table.insert(ops, { op = "fill", x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = color })
    end,
    text = function(x, y, text, fg, bg)
      table.insert(ops, { op = "text", x = x, y = y, text = text, fg = fg, bg = bg })
    end,
    bar = function(x1, y1, x2, y2, pct, fg, bg)
      table.insert(ops, {
        op = "bar",
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        progress = pct,
        fg = fg,
        bg = bg,
      })
    end,
  }
  return surface, ops
end

function FakeEnv.makeMonitorAndPaintutils(width, height, ops)
  ops = ops or {}
  local bg, fg = nil, nil
  local cursor = { x = 1, y = 1 }
  local monitor = {
    getSize = function()
      return width, height
    end,
    getBackgroundColor = function()
      return bg
    end,
    setBackgroundColor = function(color)
      bg = color
      table.insert(ops, { op = "set_bg", color = color })
    end,
    getTextColor = function()
      return fg
    end,
    setTextColor = function(color)
      fg = color
      table.insert(ops, { op = "set_fg", color = color })
    end,
    clear = function()
      table.insert(ops, { op = "clear", bg = bg, fg = fg })
    end,
    setCursorPos = function(x, y)
      cursor.x = x
      cursor.y = y
      table.insert(ops, { op = "cursor", x = x, y = y })
    end,
    write = function(text)
      table.insert(ops, { op = "write", x = cursor.x, y = cursor.y, text = text, bg = bg, fg = fg })
      table.insert(ops, { op = "text", x = cursor.x, y = cursor.y, text = text, bg = bg, fg = fg })
    end,
  }

  local paint = {
    drawFilledBox = function(x1, y1, x2, y2, color)
      table.insert(ops, { op = "filled_box", x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = color })
    end,
  }

  return monitor, paint, ops
end

return FakeEnv
