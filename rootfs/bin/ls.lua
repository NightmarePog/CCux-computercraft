local posix=require('posix')
local path=(...) or '.'
local names,code,msg=posix.list(path)
if not names then io.stderr:write('ls: ',tostring(msg or code),'\n'); return 1 end
for _,name in ipairs(names) do print(name) end
