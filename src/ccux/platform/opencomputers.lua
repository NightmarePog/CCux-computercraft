local Platform = {}

function Platform.new(host, dataRoot)
  host = host or _G
  local component, computer = assert(host.component), assert(host.computer)
  local address = assert(computer.getBootAddress(), 'no boot filesystem')
  local fs = component.proxy(address)
  dataRoot = dataRoot or '/.ccux/store'
  if not fs.exists('/.ccux') then assert(fs.makeDirectory('/.ccux')) end
  if not fs.exists(dataRoot) then assert(fs.makeDirectory(dataRoot)) end
  local function path(key) return dataRoot .. '/' .. key end

  local backend = {}
  function backend.read(key)
    local handle = fs.open(path(key), 'r'); if not handle then return nil end
    local chunks = {}
    while true do local value = fs.read(handle, 4096); if not value then break end; chunks[#chunks+1] = value end
    fs.close(handle); return table.concat(chunks)
  end
  function backend.write(key, value)
    if fs.exists(path(key)) then assert(fs.remove(path(key))) end
    local handle = assert(fs.open(path(key), 'w'))
    local at = 1
    while at <= #value do local chunk=value:sub(at,at+4095); assert(fs.write(handle,chunk)); at=at+#chunk end
    fs.close(handle)
  end
  function backend.remove(key) if fs.exists(path(key)) then assert(fs.remove(path(key))) end end
  function backend.move(from, to)
    assert(not fs.exists(path(to)), 'destination exists')
    assert(fs.rename(path(from), path(to)))
  end
  function backend.list()
    local values = fs.list(dataRoot); local result = {}
    for _, value in ipairs(values) do result[#result+1] = value:gsub('/$','') end
    return result
  end

  local platform = {name = 'opencomputers'}
  platform.clock = computer.uptime
  platform.freeMemory = computer.freeMemory
  platform.totalMemory = computer.totalMemory
  platform.wall = function() return computer.uptime() end
  platform.poll = function(timeout)
    local event = {computer.pullSignal(timeout)}
    local name = event[1]
    if name == 'key_down' then
      local character, code, player = event[3], event[4], event[5]
      if code == 28 then return 'key', 'enter', code, player end
      if code == 14 then return 'key', 'backspace', code, player end
      local characterFromCode = host.unicode and host.unicode.char or
        (host.utf8 and host.utf8.char) or string.char
      if character and character > 0 then return 'char', characterFromCode(character), code, player end
      return 'key', code, player
    elseif name == 'key_up' then return 'key_up', event[4], event[5]
    elseif name == 'clipboard' then return 'paste', event[3], event[4]
    elseif name == 'screen_resized' then return 'term_resize', event[2]
    end
    return (table.unpack or unpack)(event)
  end
  local gpuAddress = component.list('gpu')()
  local screenAddress = component.list('screen')()
  local gpu = gpuAddress and component.proxy(gpuAddress)
  if gpu and screenAddress and not gpu.getScreen() then gpu.bind(screenAddress) end
  platform.write = function(value)
    if not gpu then return end
    local x,y = gpu.getResolution()
    local cx,cy = platform.cursorX or 1, platform.cursorY or 1
    for part, newline in tostring(value):gmatch('([^\n]*)(\n?)') do
      if #part > 0 then gpu.set(cx,cy,part); cx=math.min(x+1,cx+#part) end
      if newline == '\n' then cx=1; cy=cy+1; if cy>y then gpu.copy(1,2,x,y-1,0,-1); gpu.fill(1,y,x,1,' '); cy=y end end
    end
    platform.cursorX,platform.cursorY=cx,cy
  end
  platform.flush = function() end
  platform.size = function() if gpu then return gpu.getResolution() end return 0,0 end
  platform.clear = function() if gpu then local w,h=gpu.getResolution(); gpu.fill(1,1,w,h,' '); platform.cursorX,platform.cursorY=1,1 end end
  platform.setCursor = function(x,y) platform.cursorX,platform.cursorY=x,y end
  platform.backspace = function()
    if not gpu then return end
    local cx,cy=platform.cursorX or 1,platform.cursorY or 1
    if cx>1 then cx=cx-1; gpu.set(cx,cy,' '); platform.cursorX=cx end
  end
  platform.shutdown = computer.shutdown
  platform.enumerate = function(filter)
    local result = {}; for addr, kind in component.list(filter) do result[addr]=kind end; return result
  end
  platform.invoke = component.invoke
  platform.readSystem = function(pathValue)
    local handle = fs.open(pathValue, 'r'); if not handle then return nil end
    local chunks = {}; while true do local value=fs.read(handle,4096); if not value then break end; chunks[#chunks+1]=value end
    fs.close(handle); return table.concat(chunks)
  end
  return platform, backend
end

return Platform
