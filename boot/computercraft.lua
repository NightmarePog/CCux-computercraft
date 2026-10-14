local host = _G
local systemRoot = fs.exists('/ccux/src/ccux/kernel.lua') and '/ccux' or ''
local cache = {}

local function hostRequire(name)
  if cache[name] ~= nil then return cache[name] end
  assert(name:match('^ccux[%.%w_%-]*$'), 'invalid boot module')
  local path = systemRoot .. '/src/' .. name:gsub('%.','/') .. '.lua'
  local handle = assert(fs.open(path,'r'), 'missing boot module: '..path)
  local source=handle.readAll(); handle.close()
  local env=setmetatable({require=hostRequire},{__index=host}); env._G=env
  local fn,reason=load(source,'='..path,'t',env)
  if not fn and loadstring then fn,reason=loadstring(source,'='..path); if fn and setfenv then setfenv(fn,env) end end
  assert(fn,reason)
  cache[name]=true
  local value=fn(); if value~=nil then cache[name]=value end
  return cache[name]
end

local Platform=hostRequire('ccux.platform.computercraft')
local platform,backend=Platform.new(host,'/.ccux/store')
return hostRequire('ccux.start')(platform,backend,systemRoot)
