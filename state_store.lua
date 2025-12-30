-- Simple persisted state helper for ComputerCraft-style environments.
-- Provides serialize/deserialize helpers that fall back to Lua's `load`
-- when `textutils` is not available.

local function makeSerializer(env)
  env = env or _G
  local tu = env.textutils or _G.textutils

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
    local fn, err = load("return " .. str)
    if not fn then return nil, err end
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    return result
  end

  local function serialize(tbl)
    if tu and tu.serialize then
      return tu.serialize(tbl)
    end
    return encode(tbl)
  end

  local function unserialize(str)
    if tu and tu.unserialize then
      return tu.unserialize(str)
    end
    return decode(str)
  end

  return {
    serialize = serialize,
    unserialize = unserialize,
  }
end

local function new(path, env)
  env = env or _G
  local fs = env.fs or _G.fs
  local serializer = makeSerializer(env)

  local function save(tbl)
    if not fs or not fs.open then
      return false, "fs API unavailable"
    end
    local handle = fs.open(path, "w")
    if not handle then
      return false, "failed to open " .. tostring(path)
    end
    handle.write(serializer.serialize(tbl))
    handle.close()
    return true
  end

  local function load()
    if not fs or not fs.exists or not fs.open then
      return nil, "fs API unavailable"
    end
    if not fs.exists(path) then
      return nil, "missing"
    end
    local handle = fs.open(path, "r")
    if not handle then
      return nil, "failed to read " .. tostring(path)
    end
    local contents = handle.readAll()
    handle.close()
    if not contents or contents == "" then return nil, "empty" end
    local ok, decoded = pcall(serializer.unserialize, contents)
    if not ok then
      return nil, decoded
    end
    return decoded
  end

  local function clear()
    if fs and fs.delete then
      fs.delete(path)
    end
  end

  return {
    save = save,
    load = load,
    clear = clear,
    exists = function()
      return fs and fs.exists and fs.exists(path)
    end,
    path = path,
  }
end

return {
  new = new,
  serializer = makeSerializer,
}
