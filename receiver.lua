-- super-excavate dashboard listener
-- Run this on any ComputerCraft computer with a wireless modem attached.
-- Displays status broadcasts tagged with "super_excavate".

local modemSide
for _, side in ipairs(rs.getSides()) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
    modemSide = side
    break
  end
end

if not modemSide then
  error("No wireless modem found. Attach a wireless modem to any side.")
end

rednet.open(modemSide)

local known = {}

local function formatProgress(entry)
  if not entry.total or entry.total == 0 then return "?" end
  local pct = math.floor((entry.cleared or 0) / entry.total * 1000) / 10
  return string.format("%s%%", pct)
end

local function draw()
  term.clear()
  term.setCursorPos(1, 1)
  print("Super Excavate Dashboard")
  print("ID  Label       State      Prog Fuel Age")
  print(string.rep("-", 44))

  for id, entry in pairs(known) do
    local label = tostring(entry.label or "(no label)")
    if #label > 10 then
      label = label:sub(1, 10)
    end
    local state = tostring(entry.state or "?")
    if #state > 9 then
      state = state:sub(1, 9)
    end
    local progress = formatProgress(entry)
    local fuel = tostring(entry.fuel or "?")
    if #fuel > 5 then fuel = fuel:sub(1, 5) end
    local age = "?"
    if entry.timestamp then
      age = string.format("%ds", math.floor((os.epoch("utc") - entry.timestamp) / 1000))
    end
    if #age > 5 then
      age = age:sub(1, 5)
    end

    print(string.format("%-3s %-10s %-9s %5s %5s %5s", id, label, state, progress, fuel, age))
  end
end

local function handleMessage(id, msg)
  if type(msg) ~= "table" then return end
  known[id] = msg
  known[id].id = id
  known[id].label = msg.label or msg.id or id
end

local function main()
  draw()
  local timer = os.startTimer(5)
  while true do
    local event, sender, message, protocol = os.pullEvent()
    if event == "rednet_message" and protocol == "super_excavate" then
      handleMessage(sender, message)
      draw()
    elseif event == "timer" and sender == timer then
      draw()
      timer = os.startTimer(5)
    end
  end
end

main()
