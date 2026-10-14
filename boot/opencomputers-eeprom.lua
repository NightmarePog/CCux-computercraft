-- Minimal EEPROM loader. It loads /ccux/boot/opencomputers.lua, falling back to
-- /boot/opencomputers.lua for development disks.
local address,invoke=computer.getBootAddress(),component.invoke
local function try(path)
  local handle=invoke(address,'open',path,'r'); if not handle then return end
  local chunks={}; while true do local value=invoke(address,'read',handle,4096); if not value then break end; chunks[#chunks+1]=value end
  invoke(address,'close',handle)
  local fn,reason=load(table.concat(chunks),'='..path,'t',_G); assert(fn,reason); return fn()
end
return try('/ccux/boot/opencomputers.lua') or try('/boot/opencomputers.lua') or error('CCux boot files missing')
