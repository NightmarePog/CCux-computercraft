local U=require('ccux.util')
local Scheduler=require('ccux.scheduler')
local Runtime={}; Runtime.__index=Runtime
local rawCoroutine=coroutine

local function readonly(source)
  return setmetatable({},{__index=source,__newindex=function() error('read-only API',2) end,__metatable=false})
end

function Runtime.new(kernel)
  local self=setmetatable({kernel=kernel,loader=kernel.loader},Runtime)
  kernel.runtime=self
  for _,profile in ipairs({'native','craftos','openos'}) do
    self.loader:register(profile,'posix',function(proc) return self:posixModule(proc) end)
  end
  return self
end

function Runtime:hasCapability(proc,capability)
  return proc.uid==0 or proc.capabilities['*'] or proc.capabilities[capability]
end

function Runtime:coroutineLibrary(proc)
  local owned=setmetatable({},{__mode='k'}); proc.coroutines=owned
  local library={}
  function library.create(fn) local co=rawCoroutine.create(fn); owned[co]=true; return co end
  function library.resume(co,...)
    if not owned[co] then return false,'cannot resume a coroutine owned by another process' end
    return rawCoroutine.resume(co,...)
  end
  function library.status(co)
    if not owned[co] and co~=rawCoroutine.running() then return 'dead' end
    return rawCoroutine.status(co)
  end
  function library.running() return rawCoroutine.running() end
  function library.yield(...) return rawCoroutine.yield(...) end
  function library.wrap(fn)
    local co=library.create(fn)
    return function(...)
      local result=U.pack(library.resume(co,...)); if not result[1] then error(result[2],2) end
      return U.unpack(result,2,result.n)
    end
  end
  if rawCoroutine.isyieldable then library.isyieldable=rawCoroutine.isyieldable end
  return library
end

function Runtime:posixModule(proc)
  local sys=self.kernel.syscalls; local posix={version=1}
  local names={'getpid','getppid','getuid','getgid','getcwd','chdir','umask','open','close',
    'read','write','seek','dup','dup2','pipe','stat','lstat','list','mkdir','unlink','rmdir',
    'rename','link','symlink','readlink','chmod','chown','spawn','exec','waitpid','kill',
    'sleep','yield','clock','time','sysinfo','exit','shutdown'}
  for _,name in ipairs(names) do posix[name]=sys[name] end
  posix.errno=readonly({EACCES='EACCES',ENOENT='ENOENT',EINVAL='EINVAL',EPIPE='EPIPE'})
  posix.getenv=function(name) return proc.envvars[name] end
  posix.setenv=function(name,value)
    if type(name)~='string' then return nil,'EINVAL','invalid environment name' end
    proc.envvars[name]=value==nil and nil or tostring(value); return true
  end
  return readonly(posix)
end

local File={}
local FileMeta={__index=File,__metatable=false}
local function opened(file) if file._closed then error('attempt to use a closed file',2) end end
function File:close()
  opened(self); local ok,code,message=self._posix.close(self._fd); self._closed=true; return ok,message or code
end
function File:flush() opened(self); return true end
function File:seek(whence,offset)
  opened(self); return self._posix.seek(self._fd,whence or 'cur',offset or 0)
end
function File:write(...)
    opened(self); local posix,chunkSize=self._posix,self._chunk
    for i=1,select('#',...) do
      local data=tostring(select(i,...)); local at=1
      while at<=#data do
        local count,code,message=posix.write(self._fd,data:sub(at,at+chunkSize-1))
        if not count then return nil,message or code end
        at=at+count
      end
    end
    return self
end
function File:read(format)
    opened(self); local posix,chunkSize=self._posix,self._chunk; format=format or '*l'
    if type(format)=='number' then return posix.read(self._fd,format) end
    if format=='*a' then
      local out={}
      while true do
        local data,code,message=posix.read(self._fd,chunkSize)
        if not data then return nil,message or code end
        if data=='' then break end
        out[#out+1]=data
      end
      return table.concat(out)
    elseif format=='*l' or format=='*L' then
      local out={}
      while true do
        local data,code,message=posix.read(self._fd,1)
        if not data then return nil,message or code end
        if data=='' then return #out>0 and table.concat(out) or nil end
        if data=='\n' then return table.concat(out)..(format=='*L' and '\n' or '') end
        out[#out+1]=data
      end
    end
    return nil,'unsupported read format'
end
function File:lines() return function() return self:read('*l') end end

function Runtime:fileObject(posix,fd)
  return setmetatable({_fd=fd,_closed=false,_posix=posix,_chunk=self.kernel.config.chunk},FileMeta)
end

function Runtime:installCommon(proc,env)
  local coroutineLibrary=self:coroutineLibrary(proc)
  env.coroutine=coroutineLibrary; proc.package.loaded.coroutine=coroutineLibrary
  local posix=proc.require('posix'); local io={}
  io.stdin,io.stdout,io.stderr=self:fileObject(posix,0),self:fileObject(posix,1),self:fileObject(posix,2)
  function io.open(path,mode)
    local fd,code,message=posix.open(path,mode or 'r'); if not fd then return nil,message or code end
    return self:fileObject(posix,fd)
  end
  function io.write(...) return io.stdout:write(...) end
  function io.read(...) return io.stdin:read(...) end
  function io.lines(path)
    local file,reason=io.open(path,'r'); if not file then error(reason,2) end
    return function() local line=file:read('*l'); if line==nil then file:close() end; return line end
  end
  function io.type(value)
    if type(value)~='table' or value._fd==nil then return nil end
    return value._closed and 'closed file' or 'file'
  end
  env.io=io; proc.package.loaded.io=io
  env.print=function(...)
    local values={}; for i=1,select('#',...) do values[i]=tostring(select(i,...)) end
    io.stdout:write(table.concat(values,'\t'),'\n')
  end
end

function Runtime:buildEnvironment(proc)
  local env=self.loader:baseEnvironment(proc)
  self.loader:installPackage(proc,proc.profile)
  self:installCommon(proc,env)
  if proc.profile~='native' then require('ccux.profile.'..proc.profile).install(self,proc,env) end
  if proc.profile=='craftos' or proc.profile=='openos' then
    proc.onYield=function(_,yielded)
      local filter=yielded[2]
      if filter~=nil and type(filter)~='string' then return nil end
      if proc.profile=='openos' then
        local canonical=({key_down='key',key_up='key_up',clipboard='paste',touch='touch',screen_resized='term_resize'})[filter] or filter or '*'
        local reverse={key='key_down',key_up='key_up',paste='clipboard',touch='touch',term_resize='screen_resized'}
        return self.kernel.scheduler:eventRequest(canonical,function(name,...) return reverse[name] or name,... end)
      end
      return self.kernel.scheduler:eventRequest(filter or '*')
    end
  else proc.onYield=nil end
  return env
end

function Runtime:loadProgram(proc,path)
  local env=self:buildEnvironment(proc); local fn,err=self.loader:loadfile(proc,path,'t',env)
  if not fn then error(err,0) end
  return fn
end
function Runtime:runProgram(proc,path,args)
  return self:loadProgram(proc,path)(U.unpack(args,1,args.n or #args))
end
function Runtime:exec(proc,path,args)
  for fd,description in pairs(proc.fds) do if description.closeOnExec then self.kernel:closeFd(proc,fd) end end
  proc.package,proc.luaEnv,proc.require,proc.coroutines=nil,nil,nil,nil
  proc.name=path; proc.co=rawCoroutine.create(function() return self:runProgram(proc,path,args) end)
  self.kernel.scheduler:enqueue(proc); return Scheduler.WAIT
end

function Runtime:seed(files,onlyMissing)
  local credentials={uid=0,gid=0,groups={},cwd=1,umask=0}
  local dirs={{'/bin',493},{'/sbin',493},{'/lib',493},{'/usr',493},{'/usr/lib',493},{'/home',493},{'/tmp',1023},{'/etc',493},{'/var',493}}
  for _,item in ipairs(dirs) do
    if not pcall(self.kernel.vfs.stat,self.kernel.vfs,item[1],credentials) then self.kernel.vfs:create(item[1],credentials,'dir',item[2]) end
  end
  for path,source in pairs(files or {}) do
    local exists=pcall(self.kernel.vfs.stat,self.kernel.vfs,path,credentials)
    if not (onlyMissing and exists) then
      local handle=self.kernel.vfs:open(path,credentials,'w',493); local at=1
      while at<=#source do local chunk=source:sub(at,at+self.kernel.config.chunk-1); self.kernel.vfs:write(handle,chunk); at=at+#chunk end
      self.kernel.vfs:close(handle)
    end
  end
end
function Runtime:seedFromHost(manifest,prefix)
  local credentials={uid=0,gid=0,groups={},cwd=1,umask=0}
  self:seed({},true)
  for target,sourcePath in pairs(manifest) do
    if not pcall(self.kernel.vfs.stat,self.kernel.vfs,target,credentials) then
      local source=self.kernel.platform.readSystem(prefix..'/'..sourcePath)
      if source then self:seed({[target]=source},true) end
    end
  end
end

return Runtime
