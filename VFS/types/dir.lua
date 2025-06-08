
local Dir = {}
Dir.__index = Dir

function Dir:new(name)
  local obj = {
    type = "dir",
    name = name,
    permissions = "rwxr-xr-x",
    owner = "root",
    created = os.epoch("utc"),
    modified = os.epoch("utc"),
    contents = {}
  }
  setmetatable(obj, self)
  return obj
end

function Dir:add(name, node)
  self.contents[name] = node
  self.modified = os.epoch("utc")
end

function Dir:get(name)
  return self.contents[name]
end

function Dir:remove(name)
  self.contents[name] = nil
  self.modified = os.epoch("utc")
end

function Dir:list()
  local list = {}
  for name in pairs(self.contents) do
    table.insert(list, name)
  end
  return list
end

function Dir:toTable()
  return {
    class = "dir",
    name = self.name,
    permissions = self.permissions,
    owner = self.owner,
    created = self.created,
    modified = self.modified,
    contents = {} -- naplní VFS
  }
end

function Dir.fromTable(tbl)
  local obj = Dir:new(tbl.name)
  obj.permissions = tbl.permissions
  obj.owner = tbl.owner
  obj.created = tbl.created
  obj.modified = tbl.modified
  return obj
end

return Dir
