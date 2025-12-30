-- super-excavate launcher with OTA updates and resume support.
-- Usage:
--   sexcavate <length> <width> [depth]
--   sexcavate resume
--   sexcavate auto                (update then resume if a save exists)
--   sexcavate update [--repo owner/name] [--branch main] [--quiet]
--   sexcavate install-startup

local core = dofile("excavate_core.lua")
local ota = dofile("ota.lua")
local stateStore = dofile("state_store.lua")

local STATE_PATH = ".sexcavate_state"
local MANIFEST_PATH = "ota_manifest.lua"
local trackedFiles = {
  "sexcavate.lua",
  "excavate.lua",
  "excavate_core.lua",
  "receiver.lua",
  "gold_dashboard.lua",
  "ota.lua",
  "ota_manifest.lua",
  "state_store.lua",
  "startup.lua",
}

local function usage()
  print("Usage:")
  print("  sexcavate <length> <width> [depth]")
  print("  sexcavate resume")
  print("  sexcavate auto")
  print("  sexcavate update [--repo owner/name] [--branch main] [--quiet]")
  print("  sexcavate install-startup")
end

local function loadManifest()
  if fs and fs.exists and fs.exists(MANIFEST_PATH) then
    local ok, manifest = pcall(dofile, MANIFEST_PATH)
    if ok and type(manifest) == "table" and manifest.repo then
      return manifest
    end
  end
  return {
    repo = "super-excavate/super-excavate",
    branch = "main",
    files = trackedFiles,
  }
end

local function persistManifest(manifest)
  local serializer = stateStore.serializer(_G)
  local encoded = serializer.serialize(manifest)
  local handle = fs and fs.open and fs.open(MANIFEST_PATH, "w")
  if handle then
    handle.write("return " .. encoded)
    handle.close()
  end
end

local function runUpdate(args)
  local manifest = loadManifest()
  local opts = { quiet = false }

  local i = 2
  while i <= #args do
    local arg = args[i]
    if arg == "--repo" and args[i + 1] then
      manifest.repo = args[i + 1]
      opts.repoChanged = true
      i = i + 1
    elseif arg == "--branch" and args[i + 1] then
      manifest.branch = args[i + 1]
      opts.repoChanged = true
      i = i + 1
    elseif arg == "--quiet" then
      opts.quiet = true
    end
    i = i + 1
  end

  if not http or not http.get then
    print("[warn] http API is disabled; enable in ComputerCraft config to update.")
    return
  end

  local ok, result = ota.update(manifest, { fs = fs, http = http })
  if not ok then
    print("[warn] Update failed: " .. tostring(result))
    return
  end

  if opts.repoChanged then
    persistManifest(manifest)
  end

  if not opts.quiet then
    print("[info] Updated files:")
    for _, entry in ipairs(result) do
      print(string.format(" - %s (%d bytes)", entry.file, entry.bytes or 0))
    end
  end
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

local function installStartup()
  if fs and fs.exists and fs.exists("startup.lua") then
    print("[info] startup.lua already exists; replacing with sexcavate autostart.")
  end

  local handle = fs and fs.open and fs.open("startup.lua", "w")
  if not handle then
    error("Could not write startup.lua")
  end
  handle.write([[
if fs and fs.exists and fs.exists("sexcavate.lua") then
  if shell and shell.run then
    shell.run("sexcavate", "auto")
  elseif os and os.run then
    os.run(_ENV, "sexcavate", "auto")
  end
end
]])
  handle.close()
  print("[info] startup.lua installed. The turtle will auto-resume on reboot.")
end

local function handleAuto(args)
  local shouldUpdate = true
  for _, a in ipairs(args) do
    if a == "--no-update" then
      shouldUpdate = false
    end
  end

  if shouldUpdate then
    runUpdate({ "update", "--quiet" })
  end

  if fs and fs.exists and fs.exists(STATE_PATH) then
    resumeJob()
  else
    print("[info] No saved state; nothing to auto-resume.")
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
  elseif command == "update" then
    runUpdate(args)
  elseif command == "auto" then
    handleAuto(args)
  elseif command == "install-startup" then
    installStartup()
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
