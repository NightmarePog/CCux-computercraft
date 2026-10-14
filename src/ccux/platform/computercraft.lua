local Platform = {}

local function ensureDirectory(fs, path)
  if not fs.exists(path) then fs.makeDir(path) end
end

function Platform.new(host, dataRoot)
  host = host or _G
  local fs, term, osApi = assert(host.fs), assert(host.term), assert(host.os)
  dataRoot = dataRoot or '/.ccux/store'
  ensureDirectory(fs, '/.ccux')
  ensureDirectory(fs, dataRoot)

  local function path(key) return fs.combine(dataRoot, key) end
  local backend = {}
  function backend.read(key)
    local handle = fs.open(path(key), 'rb') or fs.open(path(key), 'r')
    if not handle then return nil end
    local value = handle.readAll(); handle.close(); return value
  end
  function backend.write(key, value)
    local handle = assert(fs.open(path(key), 'wb') or fs.open(path(key), 'w'))
    handle.write(value); handle.close()
  end
  function backend.remove(key) if fs.exists(path(key)) then fs.delete(path(key)) end end
  function backend.move(from, to)
    assert(not fs.exists(path(to)), 'destination exists')
    fs.move(path(from), path(to))
  end
  function backend.list() return fs.list(dataRoot) end

  local platform = {name = 'computercraft'}
  platform.clock = osApi.clock
  platform.wall = function()
    return osApi.epoch and osApi.epoch('utc') / 1000 or osApi.clock()
  end
  platform.poll = function(timeout)
    local timer
    if timeout ~= nil and timeout > 0 and osApi.startTimer then
      timer = osApi.startTimer(timeout)
    elseif timeout ~= nil and timeout <= 0 and osApi.queueEvent then
      osApi.queueEvent('__ccux_dispatch')
    end
    local event = {coroutine.yield()}
    if timer and event[1] ~= 'timer' and osApi.cancelTimer then osApi.cancelTimer(timer) end
    if (event[1] == 'timer' and event[2] == timer) or event[1] == '__ccux_dispatch' then return nil end
    if event[1] == 'key' and host.keys and host.keys.getName then event[2] = host.keys.getName(event[2]) end
    return (table.unpack or unpack)(event)
  end
  platform.write = function(value) term.write(value) end
  platform.flush = function() end
  platform.size = term.getSize
  platform.clear = term.clear
  platform.setCursor = term.setCursorPos
  platform.backspace = function()
    local x,y=term.getCursorPos()
    if x>1 then term.setCursorPos(x-1,y); term.write(' '); term.setCursorPos(x-1,y) end
  end
  platform.shutdown = function(reboot) if reboot then osApi.reboot() else osApi.shutdown() end end
  platform.enumerate = function(filter)
    local result = {}
    if not host.peripheral then return result end
    for _, name in ipairs(host.peripheral.getNames()) do
      local kind = host.peripheral.getType(name)
      if not filter or filter == kind then result[name] = kind end
    end
    return result
  end
  platform.invoke = function(address, method, ...) return host.peripheral.call(address, method, ...) end
  platform.readSystem = function(pathValue)
    local handle = fs.open(pathValue, 'r'); if not handle then return nil end
    local value = handle.readAll(); handle.close(); return value
  end
  return platform, backend
end

return Platform
