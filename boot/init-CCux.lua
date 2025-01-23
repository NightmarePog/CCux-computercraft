local function pull(tab, key)
  local func = tab[key]
  tab[key] = nil
  return func
end


local system = {
  _NAME = "CCux",
  _VERSION = {
    major = 0,
    minor = 1,
    patch = 0
  },
  queueEvent  = pull(os, "queueEvent"),
  startTimer  = pull(os, "startTimer"),
  cancelTimer = pull(os, "cancelTimer"),
  setAlarm    = pull(os, "setAlarm"),
  cancelAlarm = pull(os, "cancelAlarm"),
  getComputerID     = pull(os, "getComputerID"),
  computerID        = pull(os, "computerID"),
  getComputerLabel  = pull(os, "getComputerLabel"),
  computerLabel     = pull(os, "computerLabel"),
  setComputerLabel  = pull(os, "setComputerLabel"),
  day         = pull(os, "day"),
  epoch       = pull(os, "epoch"),
}

function loadfile(file)
    local handle, err = fs.open(file, "r")
    if not handle then
      return nil, err
    end
  
    local data = handle.readAll()
    handle.close()
  
    return load(data, "="..file, "t", _G)
end

function system.sleep(time, no_term)
  local id = system.startTimer(time)
  local thread = loadfile("CCux-computercraft/lib/modules/0.0.1-CCux/thread.lua").id()
  timer_filter[id] = thread

  repeat
    local _, tid = (no_term and system.pullEventRaw or system.pullEvent)("timer")
  until tid == id
end

local expect = loadfile("CCux-computercraft/lib/modules/0.0.1-CCux/rc-modules/expect.lua")()
local kernel_modules = "CCux-computercraft/lib/modules/0.0.1-CCux"
local loaded_modules = {
  system = system,
  stdio = nil
}
local module = {}
function module.initializeKernelModules()

end

-- IO

local stdio = {}

function stdio.print(string)
  local _, resY = term.getSize()
  local _, posY = term.getCursorPos()
  if posY == resY+1 then
    term.scroll(1)
  end
  term.write(string)
  term.setCursorPos(1,posY+1)
end

loaded_modules.stdio = stdio


return loaded_modules
