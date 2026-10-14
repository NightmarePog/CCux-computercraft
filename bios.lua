-- CCux entry point, invoked after the attributed UnBIOS takeover.
local candidates = {'/ccux/boot/computercraft.lua', '/boot/computercraft.lua'}
for _, path in ipairs(candidates) do
  local handle = fs.open(path, 'r')
  if handle then
    local source = handle.readAll(); handle.close()
    local fn, reason = load(source, '=' .. path, 't', _G)
    if not fn and loadstring then fn, reason = loadstring(source, '=' .. path); if fn and setfenv then setfenv(fn, _G) end end
    assert(fn, reason); return fn()
  end
end
error('CCux boot files are missing', 0)
