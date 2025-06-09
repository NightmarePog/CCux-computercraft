-- types/file.lua

local File = {}
File.__index = File

function File:new(name, content)
  local obj = {
    type = "file",
    name = name,
    permissions = "rw-r--r--",
    owner = "root",
    created = os.epoch("utc"),
    modified = os.epoch("utc"),
    content = content or ""
  }
  setmetatable(obj, self)
  return obj
end

function File:read()
  return self.content
end

function File:write(data)
  self.content = data
  self.modified = os.epoch("utc")
end

function File:append(data)
  self.content = self.content .. data
  self.modified = os.epoch("utc")
end

function File:toTable()
  return {
    class = "file",
    name = self.name,
    permissions = self.permissions,
    owner = self.owner,
    created = self.created,
    modified = self.modified,
    content = self.content
  }
end

function File.fromTable(tbl)
  local obj = File:new(tbl.name, tbl.content)
  obj.permissions = tbl.permissions
  obj.owner = tbl.owner
  obj.created = tbl.created
  obj.modified = tbl.modified
  return obj
end

function File:serialize()
  return {
    type = "file",
    name = self.name,
    data = self.data
  }
end

function File.deserialize(tbl)
  return File:new(tbl.name, tbl.data)
end


return File
