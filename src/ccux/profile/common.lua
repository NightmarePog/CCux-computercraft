local U=require('ccux.util')
local M={}
local function call(fn,...)
  local result=U.pack(pcall(fn,...))
  if not result[1] then
    local err=result[2]; error(type(err)=='table' and (err.message or err.errno) or tostring(err),3)
  end
  return U.unpack(result,2,result.n)
end
function M.file(runtime,proc,path,mode,style)
  local vfs=runtime.kernel.vfs; local handle=call(vfs.open,vfs,path,proc,mode or 'r'); local closed=false
  local object={}
  local function check() if closed then error('file is closed',3) end end
  local function close() if not closed then closed=true; vfs:close(handle) end; return true end
  runtime.kernel.scheduler:addCloseHandler(proc,close)
  function object.close() return close() end
  function object.read(first,second)
    local count=first==object and second or first; check(); count=count or runtime.kernel.config.chunk
    local value=call(vfs.read,vfs,handle,count); return value=='' and nil or value
  end
  function object.write(first,second)
    local data=first==object and second or first; check(); call(vfs.write,vfs,handle,tostring(data)); return true
  end
  function object.seek(first,second,third)
    local whence,offset=first,second; if first==object then whence,offset=second,third end
    check(); return call(vfs.seek,vfs,handle,whence or 'cur',offset or 0)
  end
  function object.readAll()
    check(); local out={}
    while true do local value=vfs:read(handle,runtime.kernel.config.chunk); if value=='' then break end; out[#out+1]=value end
    return table.concat(out)
  end
  function object.readLine()
    check(); local out={}
    while true do
      local value=vfs:read(handle,1)
      if value=='' then return #out>0 and table.concat(out) or nil end
      if value=='\n' then return table.concat(out) end
      out[#out+1]=value
    end
  end
  function object.writeLine(first,second) object.write(tostring(first==object and second or first)..'\n') end
  return style=='openos' and setmetatable(object,{__index=object}) or object
end
function M.filesystem(runtime,proc,style)
  local vfs=runtime.kernel.vfs; local fs={}
  local function attempt(fn,...)
    local result=U.pack(pcall(fn,...)); if result[1] then return U.unpack(result,2,result.n) end
    local err=result[2]; return nil,type(err)=='table' and (err.message or err.errno) or tostring(err)
  end
  function fs.open(path,mode) return attempt(M.file,runtime,proc,path,mode,style) end
  function fs.exists(path) return pcall(vfs.stat,vfs,path,proc) end
  function fs.isDirectory(path) local ok,stat=pcall(vfs.stat,vfs,path,proc); return ok and stat.type=='dir' end
  fs.isDir=fs.isDirectory
  function fs.list(path) return attempt(vfs.list,vfs,path,proc) end
  function fs.makeDirectory(path) return attempt(vfs.create,vfs,path,proc,'dir',511) end
  fs.makeDir=fs.makeDirectory
  function fs.remove(path) local ok=pcall(vfs.unlink,vfs,path,proc,false); if ok then return true end; return attempt(vfs.unlink,vfs,path,proc,true) end
  fs.delete=fs.remove
  function fs.rename(old,new) return attempt(vfs.rename,vfs,old,new,proc) end
  fs.move=fs.rename
  function fs.size(path) local stat,reason=attempt(vfs.stat,vfs,path,proc); return stat and stat.size or nil,reason end
  fs.getSize=fs.size
  function fs.lastModified(path) local stat,reason=attempt(vfs.stat,vfs,path,proc); return stat and stat.mtime or nil,reason end
  function fs.attributes(path) return attempt(vfs.stat,vfs,path,proc) end
  function fs.concat(a,b) return a:sub(-1)=='/' and a..b or a..'/'..b end
  fs.combine=fs.concat
  return fs
end
function M.components(runtime,proc)
  local facade={}
  function facade.list(filter)
    local devices=runtime.kernel.platform.enumerate and runtime.kernel.platform.enumerate(filter) or {}; local visible={}
    for address,kind in pairs(devices) do
      if runtime:hasCapability(proc,'component:*') or runtime:hasCapability(proc,'component:'..kind) then visible[address]=kind end
    end
    local key; return function() key=next(visible,key); if key then return key,visible[key] end end
  end
  function facade.invoke(address,method,...)
    local devices=runtime.kernel.platform.enumerate and runtime.kernel.platform.enumerate() or {}; local kind=devices[address]
    if not kind then return nil,'no such component' end
    if not (runtime:hasCapability(proc,'component:*') or runtime:hasCapability(proc,'component:'..kind)) then return nil,'permission denied' end
    if not runtime.kernel.platform.invoke then return nil,'unsupported component operation' end
    return runtime.kernel.platform.invoke(address,method,...)
  end
  function facade.proxy(address)
    local proxy={address=address}
    return setmetatable(proxy,{__index=function(_,method) return function(...)
      if select(1,...)==proxy then return facade.invoke(address,method,select(2,...)) end
      return facade.invoke(address,method,...)
    end end})
  end
  return facade
end
M.call=call
return M
