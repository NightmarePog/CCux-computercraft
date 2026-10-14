package.path = './src/?.lua;./src/?/init.lua;' .. package.path

local Memory = require('ccux.platform.memory')
local Kernel = require('ccux.kernel')
local Runtime = require('ccux.runtime')
local Store = require('ccux.store')
local VFS = require('ccux.vfs')

local tests, passed = {}, 0
local function test(name, fn) tests[#tests + 1] = {name, fn} end
local function equal(actual, expected, message)
  if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2) end
end
local function truthy(value, message) if not value then error(message or 'expected truthy value', 2) end end

local function system(files, config)
  local platform = Memory.new()
  local backend = Memory.backend(4 * 1024 * 1024)
  local kernel = Kernel.new(platform, backend, config)
  local runtime = Runtime.new(kernel)
  runtime:seed(files or {})
  return kernel, runtime, platform, backend
end

test('codec-backed store recovers a published transaction', function()
  local backend = Memory.backend(1024 * 1024)
  local store = Store.new(backend)
  store:commit({m_1='one'})
  backend.files.journal = backend.files.journal or nil
  equal(store:read('m_1'), 'one')
end)

test('store replays a transaction interrupted after journal publication', function()
  local backend = Memory.backend(1024 * 1024)
  local store = Store.new(backend)
  backend.failAt(4)
  local ok = pcall(store.commit, store, {m_9='recovered'})
  truthy(not ok and backend.files.journal, 'published journal should survive failure')
  backend.failAt(nil)
  local recovered = Store.new(backend)
  equal(recovered:read('m_9'),'recovered')
  truthy(not backend.files.journal, 'journal should be removed after replay')
end)

test('VFS streams data, enforces permissions, and preserves hard links', function()
  local platform = Memory.new()
  local store = Store.new(Memory.backend(1024 * 1024))
  local vfs = VFS.new(store, platform.wall, require('ccux.config'))
  local root = {uid=0,gid=0,groups={},cwd=1,umask=18}
  vfs:create('/home',root,'dir',493)
  vfs:create('/home/private',root,'file',384)
  local handle = vfs:open('/home/private',root,'w')
  equal(vfs:write(handle,'secret'),6); vfs:close(handle)
  vfs:link('/home/private','/home/alias',root)
  equal(vfs:stat('/home/alias',root).nlink,2)
  local user = {uid=1000,gid=1000,groups={},cwd=1,umask=18}
  local ok, err = pcall(vfs.open,vfs,'/home/private',user,'r')
  truthy(not ok and type(err)=='table' and err.errno=='EACCES','permission denial expected')
  vfs:unlink('/home/private',root,false)
  local linked = vfs:open('/home/alias',root,'r')
  equal(vfs:read(linked,4096),'secret'); vfs:close(linked)
end)

test('scheduler runs one dispatcher and clears current process after errors', function()
  local kernel = system({
    ['/bin/good.lua']="local p=require('posix'); p.write(1,'good\\n')",
    ['/bin/bad.lua']="error('boom')",
  })
  kernel:spawnProgram('/bin/bad.lua',{}, {uid=1000,gid=1000})
  kernel:spawnProgram('/bin/good.lua',{}, {uid=1000,gid=1000})
  kernel:run(50)
  equal(kernel.scheduler.current,nil)
  truthy(kernel.platform.output:find('good',1,true))
  equal(kernel.scheduler.living,0)
end)

test('zombie processes release their runtime environment before reaping', function()
  local kernel = system({['/bin/done.lua']="local value=require('posix'); return 0"})
  local parent=kernel:spawnProgram('/bin/done.lua',{}, {uid=1000,gid=1000})
  local child=kernel:spawnProgram('/bin/done.lua',{}, {parent=parent,uid=1000,gid=1000})
  kernel:run(30)
  equal(child.state,'zombie')
  equal(child.co,nil); equal(child.luaEnv,nil); equal(child.package,nil)
end)

test('loader source cache adapts to reported free memory', function()
  local kernel = system()
  kernel.platform.totalMemory=function() return 1000 end
  kernel.platform.freeMemory=function() return 200 end
  kernel:maintainMemory(); equal(kernel.loader.cacheLimit,0); equal(kernel.vfs.cacheLimit,4)
  kernel.platform.freeMemory=function() return 400 end
  kernel:maintainMemory(); equal(kernel.loader.cacheLimit,2); equal(kernel.vfs.cacheLimit,8)
  kernel.platform.freeMemory=function() return 800 end
  kernel:maintainMemory(); equal(kernel.loader.cacheLimit,kernel.config.moduleSourceCache)
  equal(kernel.vfs.cacheLimit,kernel.config.inodeCache)
end)

test('sysinfo reports bounded kernel memory consumers', function()
  local kernel = system({
    ['/bin/info.lua']=[[local i=require('posix').sysinfo(); assert(i.processes==1); assert(i.sourceCacheBytes>=0); assert(i.inodeCacheEntries>=1)]],
  })
  kernel:spawnProgram('/bin/info.lua',{}, {uid=1000,gid=1000})
  kernel:run(30); equal(kernel.scheduler.living,0)
end)

test('terminal input is canonical, echoed, and supports backspace', function()
  local kernel = system({
    ['/bin/readline.lua']=[[local line=io.read('*l'); io.write('[',line,']')]],
  })
  local proc=kernel:spawnProgram('/bin/readline.lua',{}, {uid=1000,gid=1000})
  kernel.scheduler:runReady(10)
  kernel:onHostEvent('char','a'); kernel:onHostEvent('char','b')
  kernel:onHostEvent('key','backspace'); kernel:onHostEvent('char','c')
  equal(proc.state,'waiting_fd','canonical input must wait for a complete line')
  kernel:onHostEvent('key','enter'); kernel:run(30)
  equal(kernel.platform.output,'ac\n[ac]')
end)

test('module state is isolated per process and cached inside one process', function()
  local kernel = system({
    ['/lib/counter.lua']='return {value=0}',
    ['/bin/module.lua']=[[local p=require('posix')
local a=require('counter'); a.value=a.value+1
local b=require('counter'); p.write(1,tostring(b.value)..'\n')]],
  })
  kernel:spawnProgram('/bin/module.lua',{}, {uid=1000,gid=1000})
  kernel:spawnProgram('/bin/module.lua',{}, {uid=1000,gid=1000})
  kernel:run(100)
  equal(kernel.platform.output,'1\n1\n')
end)

test('standard library views share functions but isolate assignments', function()
  local kernel = system({
    ['/bin/library.lua']=[[local p=require('posix'); math.localValue=p.getpid(); p.yield(); p.write(1,tostring(math.localValue)..':'..tostring(type(math.abs))) ]],
  })
  kernel:spawnProgram('/bin/library.lua',{}, {uid=1000,gid=1000})
  kernel:spawnProgram('/bin/library.lua',{}, {uid=1000,gid=1000})
  kernel:run(50)
  truthy(kernel.platform.output:find('1:function',1,true))
  truthy(kernel.platform.output:find('2:function',1,true))
end)

test('require obeys VFS read permission', function()
  local kernel = system({
    ['/lib/private.lua']='return true',
    ['/bin/denied.lua']="require('private')",
  })
  local root={uid=0,gid=0,groups={},cwd=1,umask=18}
  kernel.vfs:chmod('/lib/private.lua',root,384)
  local proc=kernel:spawnProgram('/bin/denied.lua',{}, {uid=1000,gid=1000})
  kernel:run(30)
  equal(proc.state,'zombie')
  truthy(tostring(proc.exitReason):find('EACCES',1,true))
end)

test('pipes apply backpressure and deliver EOF', function()
  local kernel = system({
    ['/bin/pipe.lua']=[[local p=require('posix')
local r,w=p.pipe()
local child=p.spawn('/bin/writer.lua',{tostring(w),tostring(r)})
p.close(w)
local all={}
while true do local value=p.read(r,4); if value=='' then break end; all[#all+1]=value end
p.write(1,table.concat(all)..'\n'); p.close(r); p.waitpid(child)]],
    ['/bin/writer.lua']=[[local p=require('posix'); local w,r=...; w=tonumber(w); r=tonumber(r)
p.close(r); local data='abcdefghij'; local at=1
while at<=#data do local n=p.write(w,data:sub(at)); at=at+n end
p.close(w)]],
  })
  kernel.config.pipeBytes=4
  kernel:spawnProgram('/bin/pipe.lua',{}, {uid=1000,gid=1000})
  kernel:run(200)
  equal(kernel.platform.output,'abcdefghij\n')
end)

test('CraftOS profile translates filtered coroutine yields', function()
  local kernel = system({
    ['/bin/craft.lua']=[[local event,value=os.pullEvent('custom'); print(event,value)]],
  })
  kernel:spawnProgram('/bin/craft.lua',{}, {profile='craftos',uid=1000,gid=1000})
  kernel.scheduler:runReady(3)
  kernel.scheduler:emit('ignored',1)
  kernel.scheduler:emit('custom',42)
  kernel:run(30)
  equal(kernel.platform.output,'custom\t42\n')
end)

test('CraftOS parallel relays blocking syscalls from child coroutines', function()
  local kernel = system({
    ['/bin/parallel.lua']=[[parallel.waitForAll(function() sleep(2); write('timer') end)]],
  })
  kernel:spawnProgram('/bin/parallel.lua',{}, {profile='craftos',uid=1000,gid=1000})
  kernel:run(100)
  equal(kernel.platform.output,'timer')
end)

test('failed require does not poison the process module cache', function()
  local kernel = system({
    ['/lib/fails.lua']="error('module failure')",
    ['/bin/retry.lua']=[[local p=require('posix')
local a=pcall(require,'fails'); local b=pcall(require,'fails')
p.write(1,tostring(a)..':'..tostring(b))]],
  })
  kernel:spawnProgram('/bin/retry.lua',{}, {uid=1000,gid=1000})
  kernel:run(50)
  equal(kernel.platform.output,'false:false')
end)

test('spawn cannot elevate credentials through user options', function()
  local kernel = system({
    ['/bin/parent.lua']=[[local p=require('posix'); local child=p.spawn('/bin/identity.lua',{}, {uid=0,capabilities={['*']=true}}); p.waitpid(child)]],
    ['/bin/identity.lua']=[[local p=require('posix'); p.write(1,tostring(p.getuid()))]],
  })
  kernel:spawnProgram('/bin/parent.lua',{}, {uid=1000,gid=1000})
  kernel:run(60)
  equal(kernel.platform.output,'1000')
end)

test('invalid spawn descriptor actions do not leave a runnable child', function()
  local kernel = system({
    ['/bin/parent.lua']=[[local p=require('posix')
local child,code=p.spawn('/bin/side-effect.lua',{}, {fds={[1]=99},closeOthers=true})
p.write(1,tostring(child)..':'..tostring(code))]],
    ['/bin/side-effect.lua']=[[require('posix').write(1,'BAD')]],
  })
  kernel:spawnProgram('/bin/parent.lua',{}, {uid=1000,gid=1000})
  kernel:run(60)
  equal(kernel.platform.output,'nil:EBADF')
end)

test('seeded shell reads terminal input and starts a command', function()
  local files = {}
  for target, sourcePath in pairs(require('ccux.root_manifest')) do
    local handle = assert(io.open(sourcePath, 'r')); files[target] = handle:read('*a'); handle:close()
  end
  local kernel = system(files)
  kernel.platform.events[#kernel.platform.events+1] = {'paste','echo hello\nexit\n'}
  kernel:spawnProgram('/bin/sh.lua',{}, {uid=0,gid=0,envvars={USER='root'}})
  kernel:run(300)
  truthy(kernel.platform.output:find('hello\n',1,true),'shell did not run echo')
  equal(kernel.scheduler.living,0)
end)

test('shell pipelines close inherited pipe ends and redirect output', function()
  local files = {}
  for target, sourcePath in pairs(require('ccux.root_manifest')) do
    local handle = assert(io.open(sourcePath, 'r')); files[target] = handle:read('*a'); handle:close()
  end
  files['/bin/upper.lua'] = [[local p=require('posix')
while true do
  local value=p.read(0,64)
  if value=='' then break end
  local at=1
  while at<=#value do at=at+p.write(1,value:sub(at):upper()) end
end]]
  local kernel = system(files)
  kernel.platform.events[#kernel.platform.events+1] = {'paste','echo hello | upper > /tmp/result\ncat /tmp/result\nexit\n'}
  kernel:spawnProgram('/bin/sh.lua',{}, {uid=0,gid=0,envvars={USER='root'}})
  kernel:run(600)
  truthy(kernel.platform.output:find('HELLO\n',1,true),'pipeline output was not redirected and read back')
  equal(kernel.scheduler.living,0)
end)

test('OpenOS profile uses process-local filesystem handles', function()
  local kernel = system({
    ['/bin/openos.lua']=[[local fs=require('filesystem'); local p=require('posix')
local out=assert(fs.open('/tmp/oc','w')); out:write('ocelot'); out:close()
local input=assert(fs.open('/tmp/oc','r')); p.write(1,input:read(64)); input:close()]],
  })
  kernel:spawnProgram('/bin/openos.lua',{}, {profile='openos',uid=1000,gid=1000})
  kernel:run(60)
  equal(kernel.platform.output,'ocelot')
end)

test('sleeping processes wake by deadline without ready-queue polling', function()
  local kernel = system({
    ['/bin/timer.lua']=[[local p=require('posix'); p.sleep(2); p.write(1,tostring(p.clock()))]],
  })
  kernel:spawnProgram('/bin/timer.lua',{}, {uid=1000,gid=1000})
  kernel:run(30)
  equal(kernel.platform.output,'2')
end)

for _, item in ipairs(tests) do
  local ok, reason = pcall(item[2])
  if ok then
    passed = passed + 1
    io.write('ok - ', item[1], '\n')
  else
    io.stderr:write('not ok - ', item[1], ': ', tostring(reason), '\n')
  end
end

io.write(string.format('%d/%d tests passed\n', passed, #tests))
if passed ~= #tests then os.exit(1) end
