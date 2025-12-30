-- super-excavate installer and OTA bootstrap.
-- Download this file directly (e.g., with `wget`) and run `setup` to install or update.
--
-- Usage:
--   setup [--repo owner/name] [--branch main] [--startup]
--
-- Flags:
--   --repo owner/name   Override the GitHub repo to pull from (default: super-excavate/super-excavate).
--   --branch name       Override the branch/tag (default: main).
--   --startup           Install startup.lua that auto-resumes on boot.

local defaultManifest = {
  repo = "Laraakaa/super-excavate",
  branch = "main",
  files = {
    "version.lua",
    "setup.lua",
    "sexcavate.lua",
    "excavate.lua",
    "excavate_core.lua",
    "receiver.lua",
    "gold_dashboard.lua",
    "ota.lua",
    "ota_manifest.lua",
    "state_store.lua",
    "startup.lua",
  },
}

local function rawUrl(repo, branch, path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s", repo, branch or "main", path)
end

local function readAll(handle)
  if handle.readAll then return handle.readAll() end
  local parts = {}
  while true do
    local line = handle.readLine and handle.readLine()
    if not line then break end
    table.insert(parts, line)
  end
  return table.concat(parts, "\n")
end

local function assertHttp()
  if not http or not http.get then
    error("HTTP API is disabled. Enable http in ComputerCraft config to run setup.")
  end
end

local function download(url)
  local resp = http.get(url)
  if not resp then
    error("Failed to fetch " .. url)
  end
  if resp.getResponseCode and (resp.getResponseCode() < 200 or resp.getResponseCode() >= 300) then
    local code = resp.getResponseCode()
    resp.close()
    error("HTTP " .. tostring(code) .. " while fetching " .. url)
  end
  local body = readAll(resp)
  if resp.close then resp.close() end
  if not body then
    error("Empty response from " .. url)
  end
  return body
end

local function parseManifest(body)
  if not body then return nil, "empty manifest body" end
  local fn, err = load(body, "ota_manifest", "t", {})
  if not fn then
    return nil, "could not parse manifest: " .. tostring(err)
  end
  local ok, manifest = pcall(fn)
  if not ok then
    return nil, "manifest execution failed: " .. tostring(manifest)
  end
  if type(manifest) ~= "table" then
    return nil, "manifest is not a table"
  end
  return manifest
end

local function loadLocalManifest()
  if not fs or not fs.exists or not fs.exists("ota_manifest.lua") then return nil end
  local handle = fs.open("ota_manifest.lua", "r")
  if not handle then return nil end
  local body = readAll(handle)
  handle.close()
  return parseManifest(body)
end

local function writeFile(path, contents)
  if not fs or not fs.open then
    error("File system API unavailable; are you running in ComputerCraft?")
  end
  local handle = fs.open(path, "w")
  if not handle then
    error("Could not open " .. path .. " for writing")
  end
  handle.write(contents)
  handle.close()
end

local function persistManifest(manifest)
  local lines = {
    "return {",
    string.format("  repo = %q,", manifest.repo),
    string.format("  branch = %q,", manifest.branch or "main"),
    "  files = {",
  }
  for _, file in ipairs(manifest.files) do
    table.insert(lines, string.format("    %q,", file))
  end
  table.insert(lines, "  },")
  table.insert(lines, "}")
  writeFile("ota_manifest.lua", table.concat(lines, "\n") .. "\n")
end

local function installStartup()
  local content = [[
-- Auto-start hook for super-excavate installed via setup.lua.
if fs and fs.exists and fs.exists("sexcavate.lua") then
  if shell and shell.run then
    shell.run("sexcavate", "auto")
  elseif os and os.run then
    os.run(_ENV, "sexcavate", "auto")
  end
end
]]
  writeFile("startup.lua", content)
  print("[info] Installed startup.lua to auto-resume on boot.")
end

local function uniqueFiles(list)
  local seen, out = {}, {}
  for _, f in ipairs(list or {}) do
    if not seen[f] then
      seen[f] = true
      table.insert(out, f)
    end
  end
  return out
end

local function buildManifest(opts)
  local manifest = {
    repo = opts.repo or defaultManifest.repo,
    branch = opts.branch or defaultManifest.branch,
    files = defaultManifest.files,
  }

  local ok, remote = pcall(function()
    local body = download(rawUrl(manifest.repo, manifest.branch, "ota_manifest.lua"))
    return parseManifest(body)
  end)

  if ok and type(remote) == "table" then
    manifest.repo = remote.repo or manifest.repo
    manifest.branch = remote.branch or manifest.branch
    manifest.files = remote.files or manifest.files
  end

  manifest.files = uniqueFiles(manifest.files)

  local required = { "setup.lua", "ota_manifest.lua", "version.lua" }
  for _, f in ipairs(required) do
    local present = false
    for _, existing in ipairs(manifest.files) do
      if existing == f then
        present = true
        break
      end
    end
    if not present then table.insert(manifest.files, f) end
  end

  return manifest
end

local function removeStaleFiles(previous, manifest)
  if not previous or not previous.files then return end
  if not fs or not fs.delete or not fs.exists then return end
  local desired = {}
  for _, f in ipairs(manifest.files or {}) do
    desired[f] = true
  end
  for _, f in ipairs(previous.files) do
    if not desired[f] and fs.exists(f) then
      fs.delete(f)
      print("[info] Removed stale file: " .. f)
    end
  end
end

local function runSetup(opts)
  assertHttp()
  local previousManifest = loadLocalManifest()
  local manifest = buildManifest(opts)

  persistManifest(manifest)
  print(string.format("[info] Using repo %s on branch %s", manifest.repo, manifest.branch))

  local summary = {}
  for _, file in ipairs(manifest.files) do
    local url = rawUrl(manifest.repo, manifest.branch, file)
    local body = download(url)
    writeFile(file, body)
    table.insert(summary, { file = file, bytes = #body })
  end

  removeStaleFiles(previousManifest, manifest)

  print("[info] Downloaded files:")
  for _, entry in ipairs(summary) do
    print(string.format(" - %s (%d bytes)", entry.file, entry.bytes))
  end

  if opts.startup then
    installStartup()
  end
end

local function parseArgs(argList)
  local opts = {
    repo = nil,
    branch = nil,
    startup = false,
  }
  local i = 1
  while i <= #argList do
    local arg = argList[i]
    if arg == "--repo" and argList[i + 1] then
      opts.repo = argList[i + 1]
      i = i + 1
    elseif arg == "--branch" and argList[i + 1] then
      opts.branch = argList[i + 1]
      i = i + 1
    elseif arg == "--startup" then
      opts.startup = true
    else
      error("Unknown argument: " .. tostring(arg))
    end
    i = i + 1
  end
  return opts
end

local function main()
  local ok, opts = pcall(parseArgs, { ... })
  if not ok then
    print(opts)
    print("Usage: setup [--repo owner/name] [--branch main] [--startup]")
    return
  end

  local success, err = pcall(runSetup, opts)
  if not success then
    print("[error] " .. tostring(err))
  end
end

main()
