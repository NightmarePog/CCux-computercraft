local U=require('ccux.util')
local common=require('ccux.profile.common')
local rawCoroutine=coroutine
local M={}
local function parallelLibrary()
  local parallel={}
  local function run(waitAll,...)
    local functions={...}; local threads,filters,alive={},{},#functions
    for i,fn in ipairs(functions) do threads[i]=rawCoroutine.create(fn) end
    local function advance(i,event)
      local co=threads[i]; local result=U.pack(rawCoroutine.resume(co,U.unpack(event,1,event.n)))
      while true do
        if not result[1] then error(result[2],0) end
        if rawCoroutine.status(co)=='dead' then threads[i]=false; filters[i]=nil; alive=alive-1; return true end
        if result[2]==nil or type(result[2])=='string' then filters[i]=result[2]; return false end
        local response=U.pack(rawCoroutine.yield(U.unpack(result,2,result.n)))
        result=U.pack(rawCoroutine.resume(co,U.unpack(response,1,response.n)))
      end
    end
    local event=U.pack()
    while alive>0 do
      for i,co in ipairs(threads) do
        if co and (filters[i]==nil or event.n==0 or filters[i]==event[1]) and advance(i,event) and not waitAll then return i end
      end
      if alive>0 then event=U.pack(rawCoroutine.yield()) end
    end
  end
  function parallel.waitForAny(...) return run(false,...) end
  function parallel.waitForAll(...) return run(true,...) end
  return parallel
end
function M.install(runtime,proc,env)
  env.fs=common.filesystem(runtime,proc,'craftos')
  local sys=runtime.kernel.syscalls; local osApi={}
  function osApi.pullEventRaw(filter) return rawCoroutine.yield(filter) end
  function osApi.pullEvent(filter)
    local result=U.pack(osApi.pullEventRaw(filter)); if result[1]=='terminate' then error('Terminated',0) end
    return U.unpack(result,1,result.n)
  end
  osApi.sleep=sys.sleep; osApi.clock=sys.clock; osApi.epoch=function() return sys.time()*1000 end
  osApi.shutdown=function() return sys.shutdown(false) end; osApi.reboot=function() return sys.shutdown(true) end
  osApi.run=function(extra,path,...)
    local fn,err=env.loadfile(path,'t',setmetatable(extra or {},{__index=env})); if not fn then return false,err end
    return pcall(fn,...)
  end
  osApi.loadAPI=function(path)
    local apiEnv=setmetatable({},{__index=env}); apiEnv._ENV=apiEnv
    local fn,err=env.loadfile(path,'t',apiEnv); if not fn then return false,err end
    local ok,reason=pcall(fn); if not ok then return false,reason end
    local name=path:match('([^/]+)%.lua$') or path:match('([^/]+)$'); local exports={}
    for key,value in pairs(apiEnv) do if key~='_ENV' then exports[key]=value end end
    env[name]=exports; return true
  end
  osApi.unloadAPI=function(name) env[name]=nil end
  env.os=osApi
  env.term={write=function(value) runtime.kernel.platform.write(tostring(value)) end,getSize=runtime.kernel.platform.size,
    clear=runtime.kernel.platform.clear or function() end,setCursorPos=runtime.kernel.platform.setCursor or function() end}
  env.write=env.term.write; env.sleep=osApi.sleep; env.read=function() return env.io.stdin:read('*l') end
  env.shell={run=function(path,...)
      local fn,err=env.loadfile(path,'t',env); if not fn then return false,err end; return pcall(fn,...)
    end,dir=function() return runtime.kernel.vfs:getcwd(proc) end,
    setDir=function(path) return common.call(runtime.kernel.vfs.chdir,runtime.kernel.vfs,path,proc) end}
  env.parallel=parallelLibrary()
end
return M
