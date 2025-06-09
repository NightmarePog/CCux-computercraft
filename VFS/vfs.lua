-- Load logger.lua
local lf = fs.open("/VFS/logger.lua", "r")
local lsrc = lf.readAll()
lf.close()
local LoggerLoader, err = load(lsrc, "/logger.lua", "t", _ENV)
if not LoggerLoader then error("Logger load error: " .. err) end
local Logger = LoggerLoader()

-- 📦 Load File module
local f1 = fs.open("/VFS/types/file.lua", "r")
local src1 = f1.readAll()
f1.close()
Logger.log("Loaded file.lua source")
local FileLoader, err1 = load(src1, "/VFS/types/file.lua", "t", _ENV)
if not FileLoader then error("Load error: " .. err1) end
Logger.log("Compiled file.lua")
local File = FileLoader()

-- 📦 Load Dir module
local f2 = fs.open("/VFS/types/dir.lua", "r")
local src2 = f2.readAll()
f2.close()
Logger.log("Loaded dir.lua source")
local DirLoader, err2 = load(src2, "/VFS/types/dir.lua", "t", _ENV)
if not DirLoader then error("Load error: " .. err2) end
Logger.log("Compiled dir.lua")
local Dir = DirLoader()

-- 🔧 Serialization utils (replaces textutils.serialize/unserialize)
local function escapeString(str)
  return string.format("%q", str)
end

local function basicSerialize(tbl)
  local function recurse(t)
    local out = "{"
    for k, v in pairs(t) do
      local key = type(k) == "string" and "[" .. escapeString(k) .. "]" or "[" .. tostring(k) .. "]"
      local value
      if type(v) == "table" then
        value = recurse(v)
      elseif type(v) == "string" then
        value = escapeString(v)
      else
        value = tostring(v)
      end
      out = out .. key .. "=" .. value .. ","
    end
    return out .. "}"
  end
  return recurse(tbl)
end

local function basicUnserialize(str)
  local func, err = load("return " .. str, "unserialize", "t", {})
  if not func then return nil, err end
  local ok, result = pcall(func)
  if not ok then return nil, result end
  return result
end

-- 🗂️ VFS implementation
Logger.log("Initializing VFS class...")
local VFS = {}
VFS.__index = VFS

function VFS:new()
  Logger.log("Creating new VFS instance")
  local obj = {
    root = Dir:new("/"),
    cwd = {}
  }
  setmetatable(obj, self)
  return obj
end

local function splitPath(path)
  Logger.log("Splitting path: " .. path)
  local parts = {}
  for part in string.gmatch(path, "[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

function VFS:resolve(path)
  Logger.log("Resolving path: " .. path)
  local parts = splitPath(path)
  local node = self.root
  for i, part in ipairs(parts) do
    if node.type ~= "dir" then
      Logger.log("Resolve failed: Not a directory - " .. part)
      return nil, "Not a directory: " .. part
    end
    node = node:get(part)
    if not node then
      Logger.log("Resolve failed: Path not found - " .. part)
      return nil, "Path not found: " .. part
    end
  end
  Logger.log("Resolved path successfully: " .. path)
  return node
end

function VFS:createFile(path, data)
  Logger.log("Creating file at: " .. path)
  local parts = splitPath(path)
  local filename = table.remove(parts)
  local parent = self.root
  for _, part in ipairs(parts) do
    local next = parent:get(part)
    if not next then
      Logger.log("Creating intermediate directory: " .. part)
      next = Dir:new(part)
      parent:add(part, next)
    elseif next.type ~= "dir" then
      Logger.log("Failed to create file, not a dir: " .. part)
      return nil, "Path segment is not a directory: " .. part
    end
    parent = next
  end
  local file = File:new(filename, data)
  parent:add(filename, file)
  Logger.log("File created: " .. path)
  return file
end

function VFS:createDir(path)
  Logger.log("Creating directory at: " .. path)
  local parts = splitPath(path)
  local name = table.remove(parts)
  local parent = self.root
  for _, part in ipairs(parts) do
    local next = parent:get(part)
    if not next then
      Logger.log("Creating intermediate directory: " .. part)
      next = Dir:new(part)
      parent:add(part, next)
    elseif next.type ~= "dir" then
      Logger.log("Failed to create directory, not a dir: " .. part)
      return nil, "Path segment is not a directory: " .. part
    end
    parent = next
  end
  local dir = Dir:new(name)
  parent:add(name, dir)
  Logger.log("Directory created: " .. path)
  return dir
end

function VFS:list(path)
  Logger.log("Listing directory: " .. path)
  local node, err = self:resolve(path)
  if not node then
    Logger.log("List failed: " .. err)
    return nil, err
  end
  if node.type ~= "dir" then
    Logger.log("List failed: Not a directory")
    return nil, "Not a directory"
  end
  Logger.log("Directory listed: " .. path)
  return node:list()
end

function VFS:readFile(path)
  Logger.log("Reading file: " .. path)
  local node, err = self:resolve(path)
  if not node then
    Logger.log("Read failed: " .. err)
    return nil, err
  end
  if node.type ~= "file" then
    Logger.log("Read failed: Not a file")
    return nil, "Not a file"
  end
  Logger.log("File read successfully: " .. path)
  return node:read()
end

function VFS:remove(path)
  Logger.log("Removing: " .. path)
  local parts = splitPath(path)
  local name = table.remove(parts)
  local parent = self.root
  for _, part in ipairs(parts) do
    local next = parent:get(part)
    if not next or next.type ~= "dir" then
      Logger.log("Remove failed: Invalid path - " .. part)
      return nil, "Invalid path"
    end
    parent = next
  end
  parent:remove(name)
  Logger.log("Removed: " .. path)
  return true
end

Logger.log("VFS module fully loaded")

-- 📦 Utility: Serialize Dir structure
local function serializeNode(node)
  if node.type == "file" then
    return { type = "file", name = node.name, data = node.data }
  elseif node.type == "dir" then
    local children = {}
    for name, child in pairs(node.children) do
      children[name] = serializeNode(child)
    end
    return { type = "dir", name = node.name, children = children }
  end
end

local function deserializeNode(tbl, Dir, File)
  if tbl.type == "file" then
    return File:new(tbl.name, tbl.data)
  elseif tbl.type == "dir" then
    local dir = Dir:new(tbl.name)
    for name, child in pairs(tbl.children) do
      dir:add(name, deserializeNode(child, Dir, File))
    end
    return dir
  end
end

-- 💾 Save snapshot to file
function VFS:saveSnapshot(snapshotDir)
  snapshotDir = snapshotDir or "/snapshots"
  fs.makeDir(snapshotDir)

  local files = fs.list(snapshotDir)
  table.sort(files)
  while #files > 9 do
    fs.delete(fs.combine(snapshotDir, files[1]))
    table.remove(files, 1)
  end

  local data = basicSerialize(serializeNode(self.root))
  local name = "snapshot_" .. os.epoch("utc") .. ".vfs"
  local path = fs.combine(snapshotDir, name)
  local f = fs.open(path, "w")
  f.write(data)
  f.close()
end

-- 🔁 Load latest snapshot
function VFS.loadLatestSnapshot(snapshotDir)
  snapshotDir = snapshotDir or "/snapshots"
  if not fs.exists(snapshotDir) then return nil end

  local files = fs.list(snapshotDir)
  table.sort(files, function(a, b) return a > b end)

  for _, filename in ipairs(files) do
    if filename:match("%.vfs$") then
      local f = fs.open(fs.combine(snapshotDir, filename), "r")
      local data = f.readAll()
      f.close()

      local parsed, err = basicUnserialize(data)
      if parsed then
        local vfs = VFS:new()
        vfs.root = deserializeNode(parsed, Dir, File)
        return vfs
      end
    end
  end

  return nil
end

return VFS