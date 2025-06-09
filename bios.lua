local f = fs.open("/VFS/test.lua", "r")
local src = f.readAll()
f.close()

local fn, err = load(src, "/VFS/test.lua", "t", _ENV)
if not fn then
  error("Load error: " .. err)
end

fn()
