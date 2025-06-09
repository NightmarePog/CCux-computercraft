local logger = {}

local logPath = "/debug.log"  -- můžeš přepsat podle potřeby

function logger.log(msg)
  local h = fs.open(logPath, "a")
  if h then
    h.writeLine("[" .. os.clock() .. "] " .. tostring(msg))
    h.close()
  end
end

function logger.clear()
  if fs.exists(logPath) then fs.delete(logPath) end
end

return logger
