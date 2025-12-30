-- OTA updater for super-excavate.
-- Downloads tracked files from a public GitHub repository and writes them
-- over the local copies.

local OTA = {}

local function readAll(handle)
  if handle.readAll then
    return handle.readAll()
  end
  local chunks = {}
  while true do
    local chunk = handle.readLine and handle.readLine()
    if not chunk then break end
    table.insert(chunks, chunk)
  end
  return table.concat(chunks, "\n")
end

function OTA.rawUrl(repo, branch, path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s", repo, branch or "main", path)
end

function OTA.download(url, httpApi)
  if not httpApi or not httpApi.get then
    return nil, "http API unavailable"
  end
  local resp = httpApi.get(url)
  if not resp then
    return nil, "no response"
  end
  if resp.getResponseCode and (resp.getResponseCode() < 200 or resp.getResponseCode() >= 300) then
    local code = resp.getResponseCode()
    resp.close()
    return nil, "http " .. tostring(code)
  end
  local body = readAll(resp)
  if resp.close then resp.close() end
  if not body then
    return nil, "empty body"
  end
  return body
end

function OTA.update(manifest, deps)
  deps = deps or {}
  local fs = deps.fs or _G.fs
  local httpApi = deps.http or _G.http

  if not manifest or not manifest.repo then
    return false, "manifest missing repo"
  end
  if not fs or not fs.open then
    return false, "fs API unavailable"
  end
  if not manifest.files or #manifest.files == 0 then
    return false, "manifest missing files"
  end

  local summary = {}
  for _, file in ipairs(manifest.files) do
    local url = OTA.rawUrl(manifest.repo, manifest.branch or "main", file)
    local body, err = OTA.download(url, httpApi)
    if not body then
      return false, string.format("failed to download %s: %s", file, err or "unknown error")
    end
    local handle = fs.open(file, "w")
    if not handle then
      return false, "could not open " .. file .. " for writing"
    end
    handle.write(body)
    handle.close()
    table.insert(summary, { file = file, bytes = #body, url = url })
  end

  return true, summary
end

return OTA
