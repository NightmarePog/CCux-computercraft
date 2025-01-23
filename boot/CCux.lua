term.setCursorPos(1,1)
function loadfile(file)
    local handle, err = fs.open(file, "r")
    if not handle then
      return nil, err
    end
  
    local data = handle.readAll()
    handle.close()
  
    return load(data, "="..file, "t", _G)
end

local runinit = loadfile("/CCux-computercraft/boot/init-CCux.lua")()

local n = 1
while true do
    n = n+1
    runinit.stdio.print("test")
end
