-- Copy this file to /init.lua, or invoke it from an EEPROM loader.
local host = _G
local component,computer=assert(host.component),assert(host.computer)
local bootAddress=assert(computer.getBootAddress(),'no boot filesystem')
local bootfs=component.proxy(bootAddress)
local systemRoot=bootfs.exists('/ccux/src/ccux/kernel.lua') and '/ccux' or ''
local cache={}
local profileMarker='/.ccux-profile-next-boot'
local memoryProfile=bootfs.exists(profileMarker) and {} or nil
if memoryProfile then bootfs.remove(profileMarker) end
local profileStack={}

local function read(path)
  local handle=assert(bootfs.open(path,'r'),'missing boot module: '..path)
  local chunks={}
  while true do local value=bootfs.read(handle,4096); if not value then break end; chunks[#chunks+1]=value end
  bootfs.close(handle); return table.concat(chunks)
end
local function hostRequire(name)
  if cache[name]~=nil then return cache[name] end
  assert(name:match('^ccux[%.%w_%-]*$'),'invalid boot module')
  local path=systemRoot..'/src/'..name:gsub('%.','/')..'.lua'
  local env=setmetatable({require=hostRequire},{__index=host}); env._G=env
  local fn,reason=load(read(path),'='..path,'t',env); assert(fn,reason)
  local frame
  if memoryProfile then
    frame={before=computer.freeMemory(),children=0}; profileStack[#profileStack+1]=frame
  end
  cache[name]=true
  local ok,value=pcall(fn)
  if memoryProfile then
    local delta=frame.before-computer.freeMemory(); profileStack[#profileStack]=nil
    memoryProfile[name]=(memoryProfile[name] or 0)+delta-frame.children
    local parent=profileStack[#profileStack]; if parent then parent.children=parent.children+delta end
  end
  if not ok then cache[name]=nil; error(value,0) end
  if value~=nil then cache[name]=value end
  return cache[name]
end

local Platform=hostRequire('ccux.platform.opencomputers')
local platform,backend=Platform.new(host,'/.ccux/store')
platform.memoryProfile=memoryProfile
return hostRequire('ccux.start')(platform,backend,systemRoot)
