-- super-excavate dashboard listener
-- Run this on any ComputerCraft computer with a wireless modem attached.
-- Displays status broadcasts tagged with "super_excavate".
-- Default: text table on the computer screen.
-- Gold monitor mode: uses the drawing API for a rich, 2x2-optimized display.

local goldDashboard = dofile("gold_dashboard.lua")

local originalTerm = term.current()
local monitor = peripheral.find("monitor")
local renderMode = "text"
local drawingSurface

if monitor and monitor.isColor and monitor.isColor() then
  monitor.setTextScale(0.5)
  term.redirect(monitor)
  renderMode = "gold_monitor"
  drawingSurface = goldDashboard.makeSurface(monitor, { paintutils = paintutils })
elseif monitor then
  monitor.setTextScale(0.5)
  term.redirect(monitor)
end

local colorsAvailable = term.isColor and term.isColor()
local width, height = term.getSize()

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
local lastHeaderTick = os.epoch("utc")

local function clampText(text, len)
  text = tostring(text or "")
  if #text > len then
    return text:sub(1, len)
  end
  return text .. string.rep(" ", len - #text)
end

local function formatProgress(entry)
  if not entry.total or entry.total == 0 then return "?" end
  local pct = math.floor((entry.cleared or 0) / entry.total * 1000) / 10
  return string.format("%s%%", pct)
end

local function formatFuel(entry)
  if not entry.fuel then return "?" end
  if entry.fuel == "unlimited" then return "∞" end
  return tostring(entry.fuel)
end

local function formatPos(entry)
  if not entry.position then return "?" end
  local p = entry.position
  return string.format("%d,%d,%d", p.x or 0, p.y or 0, p.z or 0)
end

local function formatHeading(entry)
  return tostring(entry.heading or "?")
end

local function formatDistance(entry)
  if not entry.distance_from_home then return "?" end
  return tostring(entry.distance_from_home)
end

local function sortedEntries()
  local list = {}
  for _, entry in pairs(known) do
    table.insert(list, entry)
  end
  table.sort(list, function(a, b)
    local la = tostring(a.label or a.id or "")
    local lb = tostring(b.label or b.id or "")
    if la == lb then
      return (a.id or 0) < (b.id or 0)
    end
    return la:lower() < lb:lower()
  end)
  return list
end

local function drawHeader(summary)
  term.setCursorPos(1, 1)
  if colorsAvailable then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.cyan)
  end
  term.clearLine()
  term.write(clampText("Super Excavate Dashboard", width))

  term.setCursorPos(1, 2)
  if colorsAvailable then term.setTextColor(colors.lightGray) end
  term.clearLine()
  term.write(clampText(summary, width))

  term.setCursorPos(1, 3)
  if colorsAvailable then
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
  end
  local headers = {
    { label = "ID", len = 3 },
    { label = "Label", len = 9 },
    { label = "State", len = 8 },
    { label = "Prog", len = 6 },
    { label = "Fuel", len = 5 },
    { label = "Pos", len = 10 },
    { label = "Head", len = 5 },
    { label = "Dist", len = 5 },
    { label = "Age", len = 5 },
  }

  local detailWidth = width - (3 + 1 + 9 + 1 + 8 + 1 + 6 + 1 + 5 + 1 + 10 + 1 + 5 + 1 + 5 + 1 + 5)
  if detailWidth > 0 then
    table.insert(headers, { label = "Detail", len = detailWidth })
  end

  local lineParts = {}
  for index, h in ipairs(headers) do
    table.insert(lineParts, clampText(h.label, h.len))
    if index < #headers then table.insert(lineParts, " ") end
  end
  term.write(table.concat(lineParts))
  if colorsAvailable then term.setBackgroundColor(colors.black) end
end

local function drawRows(entries, startRow)
  local maxRows = height - startRow + 1
  local detailWidth = width - (3 + 1 + 9 + 1 + 8 + 1 + 6 + 1 + 5 + 1 + 10 + 1 + 5 + 1 + 5 + 1 + 5)
  local overLimit = #entries - maxRows
  if overLimit > 0 then
    maxRows = maxRows - 1
  end

  for i = 1, maxRows do
    local entry = entries[i]
    term.setCursorPos(1, startRow + i - 1)
    term.clearLine()

    if entry then
      local ageSeconds = "?"
      if entry.timestamp then
        ageSeconds = math.floor((os.epoch("utc") - entry.timestamp) / 1000)
      end

      local ageLabel = tostring(ageSeconds) .. "s"
      local stateLabel = tostring(entry.state or "?")
      local stateColor = colorsAvailable and colors.white
      if colorsAvailable then
        if stateLabel == "error" then
          stateColor = colors.red
        elseif stateLabel == "unloading" then
          stateColor = colors.orange
        elseif stateLabel == "done" then
          stateColor = colors.green
        elseif stateLabel == "excavating" then
          stateColor = colors.lime
        elseif stateLabel == "ready" then
          stateColor = colors.cyan
        end
      end

      local columns = {
        clampText(entry.id or "?", 3),
        clampText(entry.label or "(no label)", 9),
        clampText(stateLabel, 8),
        clampText(formatProgress(entry), 6),
        clampText(formatFuel(entry), 5),
        clampText(formatPos(entry), 10),
        clampText(ageLabel, 5),
      }

      if detailWidth > 0 then
        table.insert(columns, clampText(entry.detail or "", detailWidth))
      end

      local row = table.concat(columns, " ")

      if colorsAvailable then
        if type(ageSeconds) == "number" and ageSeconds > 20 then
          term.setTextColor(colors.lightGray)
        else
          term.setTextColor(colors.white)
        end
      end

      if colorsAvailable then
        -- Apply state color specifically to the state column
        local preState = table.concat(columns, " ", 1, 2)
        term.write(preState .. " ")
        term.setTextColor(stateColor)
        term.write(columns[3])
        term.setTextColor(colorsAvailable and colors.white or term.getTextColor())
        term.write(" " .. table.concat(columns, " ", 4))
      else
        term.write(row)
      end
    end
  end

  if overLimit and overLimit > 0 then
    term.setCursorPos(1, startRow + maxRows)
    if colorsAvailable then term.setTextColor(colors.lightGray) end
    term.clearLine()
    term.write(clampText("…" .. overLimit .. " more", width))
  end
end

local function drawGold(entries)
  if not drawingSurface then return draw() end
  local active, completed = 0, 0
  for _, entry in ipairs(entries) do
    if entry.state == "done" then
      completed = completed + 1
    else
      active = active + 1
    end
  end

  goldDashboard.render(drawingSurface, entries, {
    summary = {
      total = #entries,
      active = active,
      completed = completed,
    },
    updatedAgo = (os.epoch("utc") - lastHeaderTick) / 1000,
  })
  lastHeaderTick = os.epoch("utc")
end

local function draw()
  width, height = term.getSize()
  if renderMode == "gold_monitor" then
    drawGold(sortedEntries())
    return
  end
  if colorsAvailable then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
  end
  term.clear()

  local entries = sortedEntries()
  local active = 0
  local completed = 0
  for _, entry in ipairs(entries) do
    if entry.state == "done" then
      completed = completed + 1
    else
      active = active + 1
    end
  end
  local summary = string.format("Turtles: %d | Active: %d | Done: %d | Updated: %ss ago", #entries, active, completed, math.floor((os.epoch("utc") - lastHeaderTick) / 1000))
  drawHeader(summary)
  drawRows(entries, 4)
  lastHeaderTick = os.epoch("utc")
end

local function handleMessage(id, msg)
  if type(msg) ~= "table" then return end
  known[id] = msg
  known[id].id = id
  known[id].label = msg.label or msg.id or id
  draw()
end

local function main()
  draw()
  local timer = os.startTimer(1)
  while true do
    local event, sender, message, protocol = os.pullEvent()
    if event == "rednet_message" and protocol == "super_excavate" then
      handleMessage(sender, message)
    elseif event == "timer" and sender == timer then
      draw()
      timer = os.startTimer(1)
    end
  end
end

main()
