
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