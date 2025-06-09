local Link = {}
Link.__index = Link
-- TODO, perms and stuff like that
function Link:new(name, targetPath)
  local obj = {
    type = "link",
    name = name,
    target = targetPath,
    permissions = "lrwxrwxrwx",
    owner = "root",
    created = os.epoch("utc"),
    modified = os.epoch("utc")
  }
  setmetatable(obj, self)
  return obj
end

function Link:toTable()
  return {
    class = "link",
    name = self.name,
    target = self.target,
    permissions = self.permissions,
    owner = self.owner,
    created = self.created,
    modified = self.modified
  }
end

function Link.fromTable(tbl)
  local obj = Link:new(tbl.name, tbl.target)
  obj.permissions = tbl.permissions
  obj.owner = tbl.owner
  obj.created = tbl.created
  obj.modified = tbl.modified
  return obj
end

function Link:serialize()
  return {
    type = "link",
    name = self.name,
    target = self.targetPath
  }
end

function Link.deserialize(tbl)
  return Link:new(tbl.name, tbl.target)
end


return Link
