-- vfs.lua

local File = require("types.file")
local Dir = require("types.dir")

local VFS = {}
VFS.__index = VFS

function VFS:new()
  local obj = {
    root = Dir:new("/"),
    cwd = {}
  }
  setmetatable(obj, self)
  return obj
end

local function splitPath(path)
  local parts = {}
  for part in string.gmatch(path, "[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

function VFS:resolve(path)
  local parts = splitPath(path)
  local node = self.root
  for i, part in ipairs(parts) do
    if node.type ~= "dir" then return nil, "Not a directory: " .. part end
    node = node:get(part)
    if not node then return nil, "Path not found: " .. part end
  end
  return node
end

function VFS:createFile(path, data)
  local parts = splitPath(path)
  local filename = table.remove(parts)
  local parent = self.root
  for _, part in ipairs(parts) do
    local next = parent:get(part)
    if not next then
      next = Dir:new(part)
      parent:add(part, next)
    elseif next.type ~= "dir" then
      return nil, "Path segment is not a directory: " .. part
    end
    parent = next
  end
  local file = File:new(filename, data)
  parent:add(filename, file)
  return file
end

function VFS:createDir(path)
  local parts = splitPath(path)
  local name = table.remove(parts)
  local parent = self.root
  for _, part in ipairs(parts) do
    local next = parent:get(part)
    if not next then
      next = Dir:new(part)
      parent:add(part, next)
    elseif next.type ~= "dir" then
      return nil, "Path segment is not a directory: " .. part
    end
    parent = next
  end
  local dir = Dir:new(name)
  parent:add(name, dir)
  return dir
end

function VFS:list(path)
  local node, err = self:resolve(path)
  if not node then return nil, err end
  if node.type ~= "dir" then return nil, "Not a directory" end
  return node:list()
end

function VFS:readFile(path)
  local node, err = self:resolve(path)
  if not node then return nil, err end
  if node.type ~= "file" then return nil, "Not a file" end
  return node:read()
end

function VFS:remove(path)
  local parts = splitPath(path)
  local name = table.remove(parts)
  local parent = self.root
  for _, part in ipairs(parts) do
    local next = parent:get(part)
    if not next or next.type ~= "dir" then return nil, "Invalid path" end
    parent = next
  end
  parent:remove(name)
  return true
end

return VFS
