function loadfile(file)
    local handle, err = fs.open(file, "r")
    if not handle then
      return nil, err
    end
  
    local data = handle.readAll()
    handle.close()
  
    return load(data, "="..file, "t", _G)
end

local expect = loadfile("/rc/modules/main/cc/expect.lua")()
local kernel_modules = "/lib/modules/0.0.1-CCux"
local loaded_modules = {}
local module = {}
function module.initializeKernelModules()

end

function printBootLog(msg, status)

end

while true do
end


return loaded_modules
