local posix = require('posix')

local function words(line)
  local result, current, quote, escaped = {}, {}, nil, false
  local function finish() if #current > 0 then result[#result+1]=table.concat(current); current={} end end
  local i=1
  while i<=#line do
    local c=line:sub(i,i)
    if escaped then current[#current+1]=c; escaped=false
    elseif c=='\\' and quote~="'" then escaped=true
    elseif quote then if c==quote then quote=nil else current[#current+1]=c end
    elseif c=='"' or c=="'" then quote=c
    elseif c:match('%s') then finish()
    elseif c=='|' or c=='<' or c=='>' or c==';' then
      finish()
      if c=='>' and line:sub(i+1,i+1)=='>' then result[#result+1]='>>'; i=i+1
      else result[#result+1]=c end
    else current[#current+1]=c end
    i=i+1
  end
  if quote or escaped then return nil,'unfinished quote or escape' end
  finish(); return result
end

local function runPipeline(tokens)
  local commands={{args={},redirs={}}}; local command=commands[1]; local i=1
  while i<=#tokens do
    local token=tokens[i]
    if token=='|' then
      if #command.args==0 then return 2,'empty pipeline command' end
      command={args={},redirs={}}; commands[#commands+1]=command
    elseif token=='<' or token=='>' or token=='>>' then
      i=i+1; if not tokens[i] then return 2,'missing redirection target' end
      command.redirs[#command.redirs+1]={token,tokens[i]}
    elseif token==';' then return 2,'command lists are not implemented yet'
    else command.args[#command.args+1]=token end
    i=i+1
  end
  if #command.args==0 then return 2,'empty command' end

  local pipes,children,temporary={},{},{}
  local resourcesOpen=true
  local function closeResources()
    if not resourcesOpen then return end
    resourcesOpen=false
    for _,pair in ipairs(pipes) do
      if pair[1] then posix.close(pair[1]) end
      if pair[2] then posix.close(pair[2]) end
    end
    for _,fd in ipairs(temporary) do posix.close(fd) end
  end
  local function abort(code,message)
    closeResources()
    for _,pid in ipairs(children) do posix.kill(pid,'KILL') end
    for _,pid in ipairs(children) do posix.waitpid(pid) end
    return code,message
  end
  for n=1,#commands-1 do
    local r,w,reason=posix.pipe()
    if not r then return abort(1,tostring(reason or w)) end
    pipes[n]={r,w}
  end
  for n,item in ipairs(commands) do
    local map={[0]=n>1 and pipes[n-1][1] or 0,[1]=n<#commands and pipes[n][2] or 1,[2]=2}
    for _,redirect in ipairs(item.redirs) do
      local fd,code,msg=posix.open(redirect[2],redirect[1]=='<' and 'r' or redirect[1]=='>>' and 'a' or 'w')
      if not fd then return abort(1,tostring(msg or code)) end
      temporary[#temporary+1]=fd; map[redirect[1]=='<' and 0 or 1]=fd
    end
    local name=table.remove(item.args,1)
    local path=name:find('/',1,true) and name or '/bin/'..name..'.lua'
    local pid,code,msg=posix.spawn(path,item.args,{fds=map,closeOthers=true})
    if not pid then return abort(1,tostring(msg or code)) end
    children[#children+1]=pid
  end
  closeResources()
  local status=0
  for _,pid in ipairs(children) do local _,code=posix.waitpid(pid); if code and code~=0 then status=code end end
  return status
end

while true do
  io.write((posix.getenv('USER') or 'root') .. '@ccux:' .. posix.getcwd() .. '$ ')
  local line=io.read('*l'); if not line then return 0 end
  local argv,reason=words(line)
  if not argv then print('sh: '..reason)
  elseif argv[1]=='exit' then return tonumber(argv[2]) or 0
  elseif argv[1]=='cd' then local ok,code,msg=posix.chdir(argv[2] or '/'); if not ok then print('cd: '..tostring(msg or code)) end
  elseif argv[1] then
    local _,reason=runPipeline(argv); if reason then print('sh: '..reason) end
  end
end
