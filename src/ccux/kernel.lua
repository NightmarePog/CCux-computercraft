local U = require('ccux.util')
local Store = require('ccux.store')
local VFS = require('ccux.vfs')
local Scheduler = require('ccux.scheduler')
local Loader = require('ccux.loader')
local defaults = require('ccux.config')

local Kernel = {}
Kernel.__index = Kernel
local validFd

function Kernel.new(platform, backend, config)
  config = config or defaults
  local store = Store.new(backend)
  local self = setmetatable({
    platform = platform,
    config = config,
    store = store,
    vfs = VFS.new(store, platform.wall or platform.clock, config),
  }, Kernel)
  self.scheduler = Scheduler.new(platform, config)
  self.loader = Loader.new(self.vfs, config)
  self.syscalls = self.scheduler:syscalls()
  self.scheduler.dispatch = function(_, proc, op, ...)
    return self:dispatch(proc, op, ...)
  end
  self.tty = {buffer = '', edit = '', waiters = {}}
  self.scheduler.onEvent = function(name, ...)
    self:onHostEvent(name, ...)
  end
  self.scheduler.onFinish = function() self:maintainMemory() end
  self:maintainMemory()
  return self
end

function Kernel:maintainMemory()
  local limit = self.config.moduleSourceCache
  local inodeLimit = self.config.inodeCache
  if self.platform.freeMemory and self.platform.totalMemory then
    local free, total = self.platform.freeMemory(), self.platform.totalMemory()
    if type(free) == 'number' and type(total) == 'number' and total > 0 then
      local ratio = free / total
      if ratio < 0.25 then limit = 0; inodeLimit = math.min(4, inodeLimit)
      elseif ratio < 0.5 then limit = math.min(2, limit); inodeLimit = math.min(8, inodeLimit) end
    end
  end
  self.loader:setCacheLimit(limit)
  self.vfs:setCacheLimit(inodeLimit)
  if type(collectgarbage) == 'function' then
    if limit == 0 then collectgarbage('collect') else collectgarbage('step', 32) end
  end
end

function Kernel:allocateFd(proc, description, requested)
  local fd = requested
  if fd == nil then
    fd = 0
    while proc.fds[fd] do fd = fd + 1 end
  end
  U.check(U.integer(fd) and fd >= 0 and fd < self.config.maxDescriptors, 'EMFILE')
  if proc.fds[fd] then self:closeFd(proc, fd) end
  proc.fds[fd] = description
  description.refs = description.refs + 1
  return fd
end

function Kernel:closeDescription(description)
  description.refs = description.refs - 1
  if description.refs > 0 then return end
  if description.kind == 'file' then
    self.vfs:close(description.handle)
  elseif description.kind == 'pipe' then
    local pipe = description.pipe
    if description.readable then pipe.readers = pipe.readers - 1 end
    if description.writable then pipe.writers = pipe.writers - 1 end
    self:wakePipe(pipe)
  elseif description.close then
    description.close(description)
  end
end

function Kernel:closeFd(proc, fd)
  local description = proc.fds[fd]
  U.check(description, 'EBADF')
  proc.fds[fd] = nil
  self:closeDescription(description)
  return true
end

function Kernel:closeAll(proc)
  local fds = {}
  for fd in pairs(proc.fds) do fds[#fds + 1] = fd end
  for _, fd in ipairs(fds) do pcall(self.closeFd, self, proc, fd) end
end

function Kernel:terminalDescriptions()
  local input = {kind = 'tty', refs = 0, readable = true, writable = false, tty = self.tty}
  local output = {kind = 'tty', refs = 0, readable = false, writable = true, tty = self.tty}
  return input, output
end

function Kernel:wakeTty()
  while #self.tty.buffer > 0 do
    local wait = table.remove(self.tty.waiters, 1)
    while wait and (wait.proc.state ~= 'waiting_fd' or wait.proc.wait ~= wait) do
      wait = table.remove(self.tty.waiters, 1)
    end
    if not wait then return end
    local amount = math.min(wait.count, #self.tty.buffer, self.config.chunk)
    local value = self.tty.buffer:sub(1, amount)
    self.tty.buffer = self.tty.buffer:sub(amount + 1)
    self.scheduler:complete(wait.proc, value)
  end
end

local function dropLastCharacter(value)
  local at = #value
  while at > 1 do
    local byte = value:byte(at)
    if not byte or byte < 128 or byte >= 192 then break end
    at = at - 1
  end
  return value:sub(1, at - 1)
end

function Kernel:ttyText(value)
  value = value:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('\0', '')
  local at = 1
  while at <= #value do
    local newline = value:find('\n', at, true)
    local part = value:sub(at, newline and newline - 1 or #value)
    local available = self.config.eventBytes - #self.tty.edit
    if available > 0 and #part > 0 then
      part = part:sub(1, available)
      self.tty.edit = self.tty.edit .. part
      self.platform.write(part)
    end
    if newline then
      self.tty.buffer = self.tty.buffer .. self.tty.edit .. '\n'
      self.tty.edit = ''
      self.platform.write('\n')
      self:wakeTty()
      at = newline + 1
    else break end
  end
end

function Kernel:onHostEvent(name, ...)
  if name == 'backspace' or (name == 'key' and (...) == 'backspace') then
    if #self.tty.edit > 0 then
      self.tty.edit = dropLastCharacter(self.tty.edit)
      if self.platform.backspace then self.platform.backspace() else self.platform.write('\b \b') end
    end
    return
  end
  local value
  if name == 'char' or name == 'paste' then value = (...)
  elseif name == 'enter' or (name == 'key' and (...) == 'enter') then value = '\n' end
  if type(value) == 'string' then self:ttyText(value) end
end

function Kernel:inheritDescriptors(proc, parent)
  if parent then
    for fd, description in pairs(parent.fds) do
      if not description.closeOnExec then self:allocateFd(proc, description, fd) end
    end
  else
    local input, output = self:terminalDescriptions()
    self:allocateFd(proc, input, 0)
    self:allocateFd(proc, output, 1)
    self:allocateFd(proc, output, 2)
  end
  self.scheduler:addCloseHandler(proc, function() self:closeAll(proc) end)
end

function Kernel:spawn(entry, options)
  options = options or {}
  local proc = self.scheduler:spawn(entry, options)
  self:inheritDescriptors(proc, options.parent)
  return proc
end

function Kernel:spawnProgram(path, args, options)
  options = options or {}
  self:maintainMemory()
  local proc
  proc = self:spawn(function()
    return self.runtime:runProgram(proc, path, args or {})
  end, options)
  return proc
end

function Kernel:validateDescriptorActions(parent, actions)
  actions = actions or {}
  U.check(actions.fds == nil or type(actions.fds) == 'table', 'EINVAL')
  U.check(actions.closeOthers == nil or type(actions.closeOthers) == 'boolean', 'EINVAL')
  for target, source in pairs(actions.fds or {}) do
    U.check(U.integer(target) and target >= 0 and target < self.config.maxDescriptors, 'EINVAL')
    validFd(parent, source)
  end
  return actions
end

function Kernel:configureChildDescriptors(parent, child, actions)
  actions = self:validateDescriptorActions(parent, actions)
  local mappings = actions.fds or {}
  for target, source in pairs(mappings) do
    local description = validFd(parent, source)
    if child.fds[target] ~= description then self:allocateFd(child, description, target) end
  end
  if actions.closeOthers then
    local keep = {}; for target in pairs(mappings) do keep[target] = true end
    keep[0] = mappings[0] ~= nil; keep[1] = mappings[1] ~= nil; keep[2] = mappings[2] ~= nil
    local close = {}; for fd in pairs(child.fds) do if not keep[fd] then close[#close+1] = fd end end
    for _, fd in ipairs(close) do self:closeFd(child, fd) end
  end
end

validFd = function(proc, fd)
  U.check(U.integer(fd) and proc.fds[fd], 'EBADF')
  return proc.fds[fd]
end

function Kernel:blockPipe(proc, pipe, kind, data)
  local wait = {proc = proc, pipe = pipe, kind = kind, data = data}
  local list = kind == 'read' and pipe.readWaiters or pipe.writeWaiters
  list[#list + 1] = wait
  self.scheduler:block(proc, 'waiting_fd', wait)
  return Scheduler.WAIT
end

function Kernel:pipeRead(proc, description, count, mayBlock)
  local pipe = description.pipe
  U.check(description.readable, 'EBADF')
  U.check(U.integer(count) and count >= 0, 'EINVAL')
  if count == 0 then return '' end
  if #pipe.buffer > 0 then
    local amount = math.min(count, #pipe.buffer, self.config.chunk)
    local result = pipe.buffer:sub(1, amount)
    pipe.buffer = pipe.buffer:sub(amount + 1)
    self:wakePipe(pipe)
    return result
  end
  if pipe.writers == 0 then return '' end
  if not mayBlock then return nil, 'EAGAIN', 'would block' end
  return self:blockPipe(proc, pipe, 'read', count)
end

function Kernel:pipeWrite(proc, description, data, mayBlock)
  local pipe = description.pipe
  U.check(description.writable, 'EBADF')
  U.check(type(data) == 'string', 'EINVAL')
  if #data == 0 then return 0 end
  if pipe.readers == 0 then return nil, 'EPIPE', 'broken pipe' end
  local available = pipe.capacity - #pipe.buffer
  if available > 0 then
    local amount = math.min(#data, available, self.config.chunk)
    pipe.buffer = pipe.buffer .. data:sub(1, amount)
    self:wakePipe(pipe)
    return amount
  end
  if not mayBlock then return nil, 'EAGAIN', 'would block' end
  return self:blockPipe(proc, pipe, 'write', data)
end

function Kernel:wakePipe(pipe)
  local progress = true
  while progress do
    progress = false
    local read = table.remove(pipe.readWaiters, 1)
    while read and (read.proc.state ~= 'waiting_fd' or read.proc.wait ~= read) do
      read = table.remove(pipe.readWaiters, 1)
    end
    if read and (#pipe.buffer > 0 or pipe.writers == 0) then
      local value = self:pipeRead(read.proc, {pipe = pipe, readable = true}, read.data, false)
      self.scheduler:complete(read.proc, value)
      progress = true
    elseif read then table.insert(pipe.readWaiters, 1, read) end

    local write = table.remove(pipe.writeWaiters, 1)
    while write and (write.proc.state ~= 'waiting_fd' or write.proc.wait ~= write) do
      write = table.remove(pipe.writeWaiters, 1)
    end
    if write and (pipe.readers == 0 or #pipe.buffer < pipe.capacity) then
      local a, b, c = self:pipeWrite(write.proc, {pipe = pipe, writable = true}, write.data, false)
      self.scheduler:complete(write.proc, a, b, c)
      progress = true
    elseif write then table.insert(pipe.writeWaiters, 1, write) end
  end
end

function Kernel:dispatch(proc, op, ...)
  if op == 'getpid' then return proc.pid
  elseif op == 'getppid' then return proc.ppid
  elseif op == 'getuid' then return proc.uid
  elseif op == 'getgid' then return proc.gid
  elseif op == 'getcwd' then return self.vfs:getcwd(proc)
  elseif op == 'chdir' then return self.vfs:chdir((...), proc)
  elseif op == 'umask' then
    local mask = (...); U.check(U.integer(mask) and mask >= 0 and mask <= 511, 'EINVAL')
    local old = proc.umask; proc.umask = mask; return old
  elseif op == 'open' then
    local path, flags, mode = ...
    local handle = self.vfs:open(path, proc, flags, mode)
    return self:allocateFd(proc, {kind = 'file', refs = 0, handle = handle,
      readable = handle.readable, writable = handle.writable})
  elseif op == 'close' then return self:closeFd(proc, (...))
  elseif op == 'read' then
    local fd, count = ...; local description = validFd(proc, fd)
    if description.kind == 'file' then return self.vfs:read(description.handle, count)
    elseif description.kind == 'pipe' then return self:pipeRead(proc, description, count, true)
    elseif description.kind == 'tty' and description.readable then
      U.check(U.integer(count) and count >= 0, 'EINVAL')
      if count == 0 then return '' end
      if #self.tty.buffer > 0 then
        local amount = math.min(count, #self.tty.buffer, self.config.chunk)
        local value = self.tty.buffer:sub(1, amount)
        self.tty.buffer = self.tty.buffer:sub(amount + 1)
        return value
      end
      local wait = {proc = proc, kind = 'tty', count = count}
      self.tty.waiters[#self.tty.waiters + 1] = wait
      self.scheduler:block(proc, 'waiting_fd', wait)
      return Scheduler.WAIT
    end
    U.check(false, 'EBADF')
  elseif op == 'write' then
    local fd, data = ...; local description = validFd(proc, fd)
    U.check(description.writable, 'EBADF')
    if description.kind == 'file' then return self.vfs:write(description.handle, data)
    elseif description.kind == 'pipe' then return self:pipeWrite(proc, description, data, true)
    elseif description.kind == 'tty' then self.platform.write(data); return #data end
    U.check(false, 'EBADF')
  elseif op == 'seek' then
    local fd, whence, offset = ...; local description = validFd(proc, fd)
    U.check(description.kind == 'file', 'ESPIPE'); return self.vfs:seek(description.handle, whence, offset)
  elseif op == 'dup' or op == 'dup2' then
    local old, requested = ...; local description = validFd(proc, old)
    return self:allocateFd(proc, description, op == 'dup2' and requested or nil)
  elseif op == 'pipe' then
    local pipe = {buffer = '', capacity = self.config.pipeBytes, readers = 1, writers = 1,
      readWaiters = {}, writeWaiters = {}}
    local read = {kind = 'pipe', refs = 0, pipe = pipe, readable = true, writable = false}
    local write = {kind = 'pipe', refs = 0, pipe = pipe, readable = false, writable = true}
    return self:allocateFd(proc, read), self:allocateFd(proc, write)
  elseif op == 'stat' then return self.vfs:stat((...), proc)
  elseif op == 'lstat' then return self.vfs:stat((...), proc, true)
  elseif op == 'list' then return self.vfs:list((...), proc)
  elseif op == 'mkdir' then local path, mode = ...; self.vfs:create(path, proc, 'dir', mode); return true
  elseif op == 'unlink' then return self.vfs:unlink((...), proc, false)
  elseif op == 'rmdir' then return self.vfs:unlink((...), proc, true)
  elseif op == 'rename' then local old, new = ...; return self.vfs:rename(old, new, proc)
  elseif op == 'link' then local old, new = ...; return self.vfs:link(old, new, proc)
  elseif op == 'symlink' then local target, path = ...; self.vfs:create(path, proc, 'link', 511, target); return true
  elseif op == 'readlink' then return self.vfs:readlink((...), proc)
  elseif op == 'chmod' then local path, mode = ...; return self.vfs:chmod(path, proc, mode)
  elseif op == 'chown' then local path, uid, gid = ...; return self.vfs:chown(path, proc, uid, gid)
  elseif op == 'spawn' then
    local path, args, actions = ...
    U.check(type(path) == 'string' and type(args or {}) == 'table', 'EINVAL')
    U.check(actions == nil or type(actions) == 'table', 'EINVAL')
    actions = self:validateDescriptorActions(proc, actions)
    local child=self:spawnProgram(path, args or {}, {parent=proc,profile=proc.profile,
      uid=proc.uid,gid=proc.gid,groups=proc.groups,capabilities=proc.capabilities,
      cwd=proc.cwd,umask=proc.umask,envvars=proc.envvars})
    self:configureChildDescriptors(proc,child,actions)
    return child.pid
  elseif op == 'exec' then
    local path, args = ...
    return self.runtime:exec(proc, path, args or {})
  elseif op == 'clock' then return self.platform.clock()
  elseif op == 'time' then return (self.platform.wall or self.platform.clock)()
  elseif op == 'sysinfo' then
    local request = (...)
    local total = self.platform.totalMemory and self.platform.totalMemory() or nil
    local free = self.platform.freeMemory and self.platform.freeMemory() or nil
    local result = {
      memoryTotal=total, memoryFree=free,
      memoryUsed=total and free and total-free or nil,
      luaKiB=type(collectgarbage)=='function' and collectgarbage('count') or nil,
      processes=self.scheduler.living,
      sourceCacheEntries=self.loader.sourceCount,
      sourceCacheBytes=self.loader.sourceBytes,
      sourceCacheLimit=self.loader.cacheLimit,
      inodeCacheEntries=self.vfs.cacheSize,
      inodeCacheLimit=self.vfs.cacheLimit,
      transactions=self.store.transactions,
      moduleMemory=self.platform.memoryProfile,
    }
    if request=='clearProfile' then
      U.check(proc.uid==0,'EPERM'); self.platform.memoryProfile=nil; result.moduleMemory=nil
    end
    return result
  elseif op == 'shutdown' then
    U.check(proc.uid == 0, 'EPERM'); self.platform.shutdown((...)); return true
  end
  U.check(false, 'ENOSYS')
end

function Kernel:run(maxCycles) return self.scheduler:run(maxCycles) end

return Kernel
