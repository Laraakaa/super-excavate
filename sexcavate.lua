-- super-excavate launcher with resume support.
-- Usage:
--   sexcavate <length> <width> [depth]
--   sexcavate resume
--   sexcavate auto                (resume if a save exists)

local core = dofile("excavate_core.lua")
local stateStore = dofile("state_store.lua")

local STATE_PATH = ".sexcavate_state"

local function usage()
  print("Usage:")
  print("  sexcavate <length> <width> [depth]")
  print("  sexcavate resume")
  print("  sexcavate auto")
end

local function loadState()
  local store = stateStore.new(STATE_PATH, _G)
  local state = store.load()
  return store, state
end

local function startJob(length, width, depth)
  local store = stateStore.new(STATE_PATH, _G)
  store.clear()
  local ok, result = pcall(function()
    return core.run(_G, { length, width, depth }, { state = store })
  end)
  if not ok then
    print("[error] " .. tostring(result))
    return
  end
  return result
end

local function resumeJob()
  local store, state = loadState()
  if not state then
    print("[info] No saved job found to resume.")
    return
  end
  local ok, result = pcall(function()
    return core.run(_G, {}, { state = store, resumeState = state })
  end)
  if not ok then
    print("[error] Resume failed: " .. tostring(result))
    return
  end
  return result
end

local function handleAuto()
  if fs and fs.exists and fs.exists(STATE_PATH) then
    resumeJob()
  else
    print("[info] No saved state; nothing to resume automatically.")
  end
end

local function dispatch(args)
  if #args == 0 then
    usage()
    return
  end

  local command = args[1]
  if command == "resume" then
    resumeJob()
  elseif command == "auto" then
    handleAuto()
  else
    local length = tonumber(command)
    local width = tonumber(args[2])
    local depth = tonumber(args[3]) or 1
    if not length or not width then
      usage()
      return
    end
    startJob(length, width, depth)
  end
end

dispatch({ ... })
