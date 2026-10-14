local posix=require('posix')
local paths={...}
if #paths==0 then
  while true do local data=posix.read(0,4096); if not data or data=='' then break end; posix.write(1,data) end
end
for _,path in ipairs(paths) do
  local fd,code,msg=posix.open(path,'r')
  if not fd then io.stderr:write('cat: ',path,': ',tostring(msg or code),'\n')
  else
    while true do local data=posix.read(fd,4096); if not data or data=='' then break end; io.write(data) end
    posix.close(fd)
  end
end
