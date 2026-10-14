local common=require('ccux.profile.common')
local rawCoroutine=coroutine
local M={}
function M.install(runtime,proc,env)
  proc.package.loaded.filesystem=common.filesystem(runtime,proc,'openos')
  proc.package.loaded.component=common.components(runtime,proc)
  local sys=runtime.kernel.syscalls
  proc.package.loaded.computer={uptime=sys.clock,pullSignal=function() return rawCoroutine.yield() end,shutdown=sys.shutdown}
  proc.package.loaded.unicode=env.utf8 or {len=string.len,sub=string.sub,char=string.char}
  local event={}
  function event.pull(first,second) return rawCoroutine.yield(type(first)=='string' and first or second) end
  event.push=function(name,...) runtime.kernel.scheduler:emit(name,...); return true end
  proc.package.loaded.event=event
  proc.package.loaded.process={info=function() return {pid=proc.pid,parent=proc.ppid,data={vars=proc.envvars}} end}
  env.os=env.os or {}
  env.os.getenv=function(name) return name and proc.envvars[name] or proc.envvars end
  env.os.setenv=function(name,value) proc.envvars[name]=value and tostring(value) or nil; return value end
  env.os.sleep=sys.sleep
end
return M
