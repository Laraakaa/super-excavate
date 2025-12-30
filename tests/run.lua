local core = dofile("excavate_core.lua")
local FakeEnv = dofile("tests/fake_env.lua")
local GoldDashboard = dofile("gold_dashboard.lua")

local function assertEquals(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. string.format("Expected %s, got %s", tostring(expected), tostring(actual)))
  end
end

local function assertTrue(value, msg)
  if not value then
    error(msg or "Expected truthy value")
  end
end

local tests = {}

local function test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

test("completes quarry and returns home", function()
  local env = FakeEnv.new({ modemSide = "left" })
  local result = core.run(env, { 4, 3, 2 })
  assertTrue(result.completed, "run did not complete")
  assertEquals(result.cleared, 4 * 3 * 2)
  assertEquals(result.total, 4 * 3 * 2)
  assertEquals(result.position.x, 0)
  assertEquals(result.position.y, 0)
  assertEquals(result.position.z, 0)
  assertEquals(result.position.facing, 0)
end)

test("broadcasts key lifecycle states", function()
  local env = FakeEnv.new({ modemSide = "right" })
  core.run(env, { 2, 2, 1 })
  local states = {}
  for _, message in ipairs(env.rednet.broadcasts or {}) do
    table.insert(states, message.payload.state)
  end

  local function contains(target)
    for _, s in ipairs(states) do
      if s == target then return true end
    end
    return false
  end

  assertTrue(contains("ready"), "missing ready broadcast")
  assertTrue(contains("excavating"), "missing excavating broadcast")
  assertTrue(contains("done"), "missing done broadcast")
end)

test("fails fast when fuel is insufficient", function()
  local env = FakeEnv.new({
    modemSide = "left",
    turtle = {
      fuel = 5,
      fuelPerItem = 1,
      inventory = { [1] = 1 },
    },
  })

  local ok, err = pcall(function()
    core.run(env, { 10, 10, 1 })
  end)

  assertTrue(not ok, "expected failure due to fuel")
  assertTrue(tostring(err):find("Not enough fuel") ~= nil, "unexpected error: " .. tostring(err))
end)

test("gold dashboard lays out two columns for 2x2 monitors", function()
  local layout = GoldDashboard.layoutFor(64, 36)
  assertEquals(layout.columns, 2, "expected two columns")
  assertTrue(#layout.slots >= 4, "expected to fit at least four slots")
  assertTrue(layout.slots[2].x1 > layout.slots[1].x1, "second slot should be to the right of first")
end)

test("gold dashboard renders progress bars and headers", function()
  local monitor, paintutils, ops = FakeEnv.makeMonitorAndPaintutils(64, 36)
  local surface = GoldDashboard.makeSurface(monitor, { paintutils = paintutils })

  GoldDashboard.render(surface, {
    {
      label = "Miner-1",
      state = "excavating",
      progress = 0.5,
      detail = "Layer 1/2",
      fuel = 250,
    },
  }, {
    summary = { total = 1, active = 1, completed = 0 },
    updatedAgo = 3,
  })

  local sawBar, sawHeader, sawSurfaceBar = false, false, false
  for _, op in ipairs(ops) do
    if op.op == "bar" and op.progress == 0.5 then
      sawBar = true
    end
    if op.op == "filled_box" and (op.x2 - op.x1) >= 10 then
      sawSurfaceBar = true
    end
    if op.op == "text" and tostring(op.text or ""):find("Gold Dashboard") then
      sawHeader = true
    end
  end

  assertTrue(sawBar or sawSurfaceBar, "expected a progress bar to be drawn")
  assertTrue(sawHeader, "expected header text to be rendered")
end)

local function runAll()
  local passed = 0
  for _, entry in ipairs(tests) do
    local ok, err = pcall(entry.fn)
    if not ok then
      io.stderr:write(string.format("[FAIL] %s: %s\n", entry.name, err))
      os.exit(1)
    else
      print(string.format("[PASS] %s", entry.name))
      passed = passed + 1
    end
  end
  print(string.format("%d tests passed", passed))
end

runAll()
