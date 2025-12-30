-- Gold monitor dashboard renderer for super-excavate.
-- Uses simple drawing primitives (filled rectangles, text, and bars) to build
-- a colorful, monitor-optimized display. Designed for 2x2 advanced/gold
-- monitors running at text scale 0.5, but adapts to other sizes.

local palette = _G.colors or {
  white = 1,
  orange = 2,
  magenta = 4,
  lightBlue = 8,
  yellow = 16,
  lime = 32,
  pink = 64,
  gray = 128,
  lightGray = 256,
  cyan = 512,
  purple = 1024,
  blue = 2048,
  brown = 4096,
  green = 8192,
  red = 16384,
  black = 32768,
}

local GoldDashboard = {}

local function clampText(text, width)
  text = tostring(text or "")
  if #text <= width then return text end
  return text:sub(1, width)
end

function GoldDashboard.stateColor(state)
  if state == "error" then return palette.red end
  if state == "unloading" then return palette.orange end
  if state == "done" then return palette.lime end
  if state == "excavating" then return palette.green end
  if state == "ready" then return palette.cyan end
  return palette.lightGray
end

function GoldDashboard.layoutFor(width, height)
  local padding = 2
  local columns = 2
  local cardHeight = 9
  local availableHeight = math.max(height - 4, cardHeight)
  local rows = math.max(1, math.floor((availableHeight + 1) / (cardHeight + 1)))
  local cardWidth = math.max(12, math.floor((width - padding * (columns + 1)) / columns))
  local slots = {}
  local maxItems = columns * rows
  for i = 1, maxItems do
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    local x1 = padding + col * (cardWidth + padding)
    local y1 = 4 + row * (cardHeight + 1)
    table.insert(slots, {
      x1 = x1,
      y1 = y1,
      x2 = x1 + cardWidth - 1,
      y2 = y1 + cardHeight - 1,
      width = cardWidth,
      height = cardHeight,
    })
  end

  return {
    slots = slots,
    maxItems = maxItems,
    cardWidth = cardWidth,
    cardHeight = cardHeight,
    columns = columns,
    rows = rows,
    padding = padding,
  }
end

function GoldDashboard.makeSurface(target, deps)
  deps = deps or {}
  local paint = deps.paintutils or paintutils
  local surf = {}

  function surf:getSize()
    if target.getSize then
      return target.getSize()
    end
    return 0, 0
  end

  function surf:clear(bg)
    if target.setBackgroundColor and bg then
      target.setBackgroundColor(bg)
    end
    if target.clear then target.clear() end
  end

  function surf:fillRect(x1, y1, x2, y2, color)
    local prevBg = target.getBackgroundColor and target.getBackgroundColor()
    if target.setBackgroundColor and color then target.setBackgroundColor(color) end
    if paint and paint.drawFilledBox then
      paint.drawFilledBox(x1, y1, x2, y2, color)
    else
      local width = math.max(0, x2 - x1 + 1)
      for y = y1, y2 do
        if target.setCursorPos then target.setCursorPos(x1, y) end
        if target.write then target.write(string.rep(" ", width)) end
      end
    end
    if target.setBackgroundColor and prevBg then
      target.setBackgroundColor(prevBg)
    end
  end

  function surf:text(x, y, text, fg, bg)
    local prevBg = target.getBackgroundColor and target.getBackgroundColor()
    local prevFg = target.getTextColor and target.getTextColor()
    if target.setBackgroundColor and bg then target.setBackgroundColor(bg) end
    if target.setTextColor and fg then target.setTextColor(fg) end
    if target.setCursorPos then target.setCursorPos(x, y) end
    if target.write then target.write(text) end
    if target.setBackgroundColor and prevBg then target.setBackgroundColor(prevBg) end
    if target.setTextColor and prevFg then target.setTextColor(prevFg) end
  end

  function surf:bar(x1, y1, x2, y2, progress, fg, bg)
    progress = math.max(0, math.min(1, progress or 0))
    self:fillRect(x1, y1, x2, y2, bg)
    local totalWidth = math.max(0, x2 - x1)
    local filled = math.floor(totalWidth * progress + 0.5)
    if filled > 0 then
      self:fillRect(x1, y1, x1 + filled, y2, fg)
    end
  end

  return surf
end

local function drawHeader(surface, width, summary, updatedAgo)
  surface:fillRect(1, 1, width, 3, palette.gray)
  surface:text(2, 2, "Super Excavate // Gold Dashboard", palette.white, palette.gray)
  local detail = string.format(
    "Turtles %d | Active %d | Done %d | Updated %ss ago",
    summary.total or 0,
    summary.active or 0,
    summary.completed or 0,
    math.floor(updatedAgo or 0)
  )
  surface:text(2, 3, clampText(detail, width - 2), palette.lightGray, palette.gray)
end

local function drawCard(surface, entry, slot)
  surface:fillRect(slot.x1, slot.y1, slot.x2, slot.y2, palette.black)
  surface:fillRect(slot.x1, slot.y1, slot.x2, slot.y1 + 1, palette.gray)
  local accent = GoldDashboard.stateColor(entry.state)
  surface:fillRect(slot.x1, slot.y1, slot.x1, slot.y2, accent)

  local header = clampText(entry.label or entry.id or "Turtle", slot.width - 3)
  surface:text(slot.x1 + 2, slot.y1, header, palette.white, palette.gray)

  local stateLabel = clampText(tostring(entry.state or "?"), slot.width - 3)
  surface:text(slot.x1 + 2, slot.y1 + 1, stateLabel, accent, palette.gray)

  local detail = clampText(entry.detail or "Waiting for updates…", slot.width - 2)
  surface:text(slot.x1 + 1, slot.y1 + 3, detail, palette.lightGray, palette.black)

  local progress = entry.progress or 0
  local pct = math.floor(progress * 100 + 0.5)
  local progressLabel = clampText(string.format("%3d%%", pct), slot.width - 2)
  surface:text(slot.x1 + 1, slot.y2 - 1, progressLabel, palette.white, palette.black)
  surface:bar(slot.x1 + 1, slot.y2 - 2, slot.x2 - 1, slot.y2 - 2, progress, accent, palette.gray)

  local fuelLabel = clampText("Fuel " .. tostring(entry.fuel or "?"), slot.width - 2)
  surface:text(slot.x1 + 1, slot.y2, fuelLabel, palette.yellow, palette.black)
end

function GoldDashboard.render(surface, entries, opts)
  opts = opts or {}
  local summary = opts.summary or { total = #entries, active = #entries, completed = 0 }
  local updatedAgo = opts.updatedAgo or 0
  local width, height = surface:getSize()
  surface:clear(palette.black)
  drawHeader(surface, width, summary, updatedAgo)

  local layout = GoldDashboard.layoutFor(width, height)
  for index, entry in ipairs(entries) do
    if index > layout.maxItems then break end
    drawCard(surface, entry, layout.slots[index])
  end
end

return GoldDashboard
