local posix = require('posix')

print('CCux kernel API ' .. tostring(posix.version))
while true do
  local pid, code, message = posix.spawn('/bin/sh.lua', {})
  if not pid then print('init: cannot start shell: ' .. tostring(message or code)); posix.sleep(1)
  else
    posix.waitpid(pid)
    print('shell exited; restarting')
  end
end
