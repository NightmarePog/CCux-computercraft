local posix=require('posix'); local failed=false
for _,path in ipairs({...}) do local ok,code,msg=posix.mkdir(path,493); if not ok then failed=true; io.stderr:write('mkdir: ',path,': ',tostring(msg or code),'\n') end end
return failed and 1 or 0
