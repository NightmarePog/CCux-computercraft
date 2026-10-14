local U = require('ccux.util')

local Scheduler = {}
Scheduler.__index = Scheduler
Scheduler.WAIT = {}

local syscallMarker = {}

local function removeWaiter(list, proc)
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == proc then table.remove(list, i) end
  end
end

function Scheduler.new(platform, config)
  return setmetatable({
    platform = platform,
    config = config,
    processes = {},
    ready = U.queue(),
    timers = {},
    eventWaiters = {},
    nextPid = 1,
    current = nil,
    living = 0,
    cycles = 0,
  }, Scheduler)
end

function Scheduler:syscalls()
  local function call(op, ...)
    return coroutine.yield(syscallMarker, op, ...)
  end
  local api = {}
  return setmetatable(api, {
    __index = function(_, op)
      local fn = function(...) return call(op, ...) end
      rawset(api, op, fn)
      return fn
    end,
    __newindex = function() error('syscall table is read-only', 2) end,
    __metatable = false,
  })
end

function Scheduler:eventRequest(name, transform)
  return U.pack(true, syscallMarker, 'wait_event', name or '*', transform)
end

function Scheduler:enqueue(proc, ...)
  if not proc or proc.state == 'zombie' or proc.state == 'stopped' then return end
  self:cancelWait(proc)
  proc.resume = U.pack(...)
  proc.state = 'ready'
  if not proc.queued then
    proc.queued = true
    U.push(self.ready, proc)
  end
end

function Scheduler:cancelWait(proc)
  local wait = proc.wait
  if not wait then return end
  if wait.kind == 'event' then removeWaiter(self.eventWaiters[wait.name], proc) end
  proc.wait = nil
end

function Scheduler:block(proc, state, wait)
  proc.state = state
  proc.wait = wait
end

function Scheduler:spawn(entry, options)
  options = options or {}
  U.check(type(entry) == 'function', 'EINVAL')
  U.check(self.living < self.config.maxProcesses, 'EAGAIN')
  local pid = self.nextPid
  self.nextPid = pid + 1
  local parent = options.parent
  local proc = {
    pid = pid,
    ppid = parent and parent.pid or 0,
    parent = parent,
    children = {},
    state = 'new',
    uid = options.uid or (parent and parent.uid) or 0,
    gid = options.gid or (parent and parent.gid) or 0,
    groups = U.copy(options.groups or (parent and parent.groups) or {}),
    cwd = options.cwd or (parent and parent.cwd) or 1,
    umask = options.umask or (parent and parent.umask) or 18,
    profile = options.profile or 'native',
    capabilities = U.copy(options.capabilities or (parent and parent.capabilities) or {}),
    envvars = U.copy(options.envvars or (parent and parent.envvars) or {}),
    fds = {},
    closeHandlers = {},
    name = options.name or ('process-' .. pid),
    onYield = options.onYield,
  }
  proc.co = coroutine.create(function()
    return entry(U.unpack(options.args or {}))
  end)
  self.processes[pid] = proc
  self.living = self.living + 1
  if parent then parent.children[pid] = true end
  self:enqueue(proc)
  return proc
end

function Scheduler:addCloseHandler(proc, fn)
  proc.closeHandlers[#proc.closeHandlers + 1] = fn
end

function Scheduler:reap(parent, child)
  U.check(child and child.state == 'zombie', 'ECHILD')
  U.check(child.parent == parent or parent.uid == 0, 'ECHILD')
  if child.parent then child.parent.children[child.pid] = nil end
  self.processes[child.pid] = nil
  return child.pid, child.exitCode, child.exitReason
end

function Scheduler:finish(proc, code, reason)
  if proc.state == 'zombie' then return end
  self:cancelWait(proc)
  proc.state = 'zombie'
  proc.exitCode = tonumber(code) or 0
  proc.exitReason = reason
  self.living = self.living - 1
  for i = #proc.closeHandlers, 1, -1 do pcall(proc.closeHandlers[i]) end
  proc.closeHandlers = {}

  -- Reaping only needs identity and exit status. Release the program closure,
  -- globals, module graph, and pending resume values as soon as it exits.
  proc.co = nil
  proc.resume = nil
  proc.onYield = nil
  proc.luaEnv = nil
  proc.package = nil
  proc.require = nil
  proc.coroutines = nil
  proc.envvars = nil
  if self.onFinish then pcall(self.onFinish, proc) end

  local init = self.processes[1]
  for childPid in pairs(proc.children) do
    local child = self.processes[childPid]
    if child then
      child.parent = init ~= proc and init or nil
      child.ppid = child.parent and child.parent.pid or 0
      if child.parent then child.parent.children[childPid] = true end
    end
  end
  proc.children = {}

  local parent = proc.parent
  if parent and parent.state == 'waiting_child' and
      (parent.wait.pid == -1 or parent.wait.pid == proc.pid) then
    self:enqueue(parent, self:reap(parent, proc))
  elseif not parent then
    self.processes[proc.pid] = nil
  end
end

function Scheduler:waitpid(proc, pid)
  pid = pid or -1
  U.check(type(pid) == 'number' and pid == math.floor(pid), 'EINVAL')
  local hasChild = false
  for childPid in pairs(proc.children) do
    local child = self.processes[childPid]
    if child and (pid == -1 or pid == childPid) then
      hasChild = true
      if child.state == 'zombie' then return self:reap(proc, child) end
    end
  end
  U.check(hasChild, 'ECHILD')
  self:block(proc, 'waiting_child', {kind = 'child', pid = pid})
  return Scheduler.WAIT
end

function Scheduler:signal(sender, pid, signal)
  local target = self.processes[pid]
  U.check(target and target.state ~= 'zombie', 'ESRCH')
  U.check(sender.uid == 0 or sender.uid == target.uid, 'EPERM')
  signal = signal or 'TERM'
  if signal == 'CONT' then
    if target.state == 'stopped' then self:enqueue(target) end
  elseif signal == 'STOP' then
    self:cancelWait(target)
    target.state = 'stopped'
  elseif signal == 'KILL' or signal == 'TERM' or signal == 'INT' then
    self:finish(target, signal == 'KILL' and 137 or 128, signal)
  else
    U.check(false, 'EINVAL')
  end
  return true
end

function Scheduler:emit(name, ...)
  local args = U.pack(name, ...)
  local awakened = {}
  local function wake(list)
    if not list then return end
    for i = #list, 1, -1 do
      local proc = table.remove(list, i)
      if proc.state == 'waiting_event' and proc.wait and
          (proc.wait.name == name or proc.wait.name == '*') and not awakened[proc] then
        awakened[proc] = true
        if proc.wait.transform then
          self:enqueue(proc, proc.wait.transform(U.unpack(args)))
        else self:enqueue(proc, U.unpack(args)) end
      end
    end
  end
  wake(self.eventWaiters[name])
  wake(self.eventWaiters['*'])
end

function Scheduler:wakeTimers()
  local now = self.platform.clock()
  while self.timers[1] and self.timers[1].at <= now do
    local timer = U.heapPop(self.timers)
    if timer.proc.state == 'waiting_timer' and timer.proc.wait == timer then
      self:enqueue(timer.proc, true)
    end
  end
end

function Scheduler:nearestTimer()
  while self.timers[1] do
    local timer = self.timers[1]
    if timer.proc.state == 'waiting_timer' and timer.proc.wait == timer then
      return math.max(0, timer.at - self.platform.clock())
    end
    U.heapPop(self.timers)
  end
end

function Scheduler:complete(proc, ...)
  self:enqueue(proc, ...)
end

function Scheduler:handle(proc, yielded)
  if yielded[2] ~= syscallMarker then
    if proc.onYield then
      local request = proc.onYield(proc, yielded)
      if request then return self:handle(proc, request) end
    end
    self:finish(proc, 127, 'invalid yield')
    return
  end
  local op = yielded[3]
  if op == 'yield' then
    self:enqueue(proc, true)
  elseif op == 'sleep' then
    local delay = yielded[4] or 0
    U.check(type(delay) == 'number' and delay >= 0, 'EINVAL')
    if delay == 0 then self:enqueue(proc, true) else
      U.check(#self.timers < self.config.maxTimers, 'EAGAIN')
      local timer = {kind = 'timer', proc = proc, at = self.platform.clock() + delay}
      self:block(proc, 'waiting_timer', timer)
      U.heapPush(self.timers, timer)
    end
  elseif op == 'wait_event' then
    local name = yielded[4] or '*'
    U.check(type(name) == 'string', 'EINVAL')
    local wait = {kind = 'event', name = name, transform = yielded[5]}
    self:block(proc, 'waiting_event', wait)
    self.eventWaiters[name] = self.eventWaiters[name] or {}
    self.eventWaiters[name][#self.eventWaiters[name] + 1] = proc
  elseif op == 'waitpid' then
    local ok, a, b, c = pcall(self.waitpid, self, proc, yielded[4])
    if not ok then self:complete(proc, U.failure(a))
    elseif a ~= Scheduler.WAIT then self:complete(proc, a, b, c) end
  elseif op == 'kill' then
    local ok, a, b, c = pcall(self.signal, self, proc, yielded[4], yielded[5])
    if ok then self:complete(proc, a, b, c) else self:complete(proc, U.failure(a)) end
  elseif op == 'exit' then
    self:finish(proc, yielded[4], yielded[5])
  else
    local ok, a, b, c, d = pcall(self.dispatch, self, proc, op, U.unpack(yielded, 4, yielded.n))
    if not ok then self:complete(proc, U.failure(a))
    elseif a ~= Scheduler.WAIT then self:complete(proc, a, b, c, d) end
  end
end

function Scheduler:step()
  self:wakeTimers()
  local proc = U.pop(self.ready)
  if not proc then return false end
  proc.queued = false
  if proc.state ~= 'ready' then return true end
  if proc.pendingKill then self:finish(proc, 128, proc.pendingKill); return true end
  proc.state = 'running'
  self.current = proc
  local args = proc.resume or U.pack()
  proc.resume = nil
  local yielded = U.pack(coroutine.resume(proc.co, U.unpack(args, 1, args.n)))
  self.current = nil
  if not yielded[1] then
    local failure = yielded[2]
    self:finish(proc, 127, type(failure) == 'table' and
      (failure.message or failure.errno or tostring(failure)) or tostring(failure))
  elseif coroutine.status(proc.co) == 'dead' then
    self:finish(proc, type(yielded[2]) == 'number' and yielded[2] or 0, yielded[3])
  else
    local ok, err = pcall(self.handle, self, proc, yielded)
    if not ok then self:finish(proc, 127, type(err) == 'table' and err.errno or tostring(err)) end
  end
  return true
end

function Scheduler:poll(timeout)
  local event = U.pack(self.platform.poll(timeout))
  if event.n > 0 and event[1] ~= nil then
    if self.onEvent then self.onEvent(U.unpack(event, 1, event.n)) end
    self:emit(U.unpack(event, 1, event.n))
  end
end

function Scheduler:run(maxCycles)
  local cycles = 0
  while self.living > 0 and not self.platform.halted do
    self:wakeTimers()
    local ran = 0
    while ran < self.config.schedulerBatch and self:step() do ran = ran + 1 end
    if ran == self.config.schedulerBatch or self.ready.last >= self.ready.first then
      self:poll(0)
    else
      self:poll(self:nearestTimer())
    end
    cycles = cycles + 1
    self.cycles = self.cycles + 1
    if maxCycles and cycles >= maxCycles then break end
  end
  return self.living
end

function Scheduler:runReady(limit)
  local n = 0
  while (not limit or n < limit) and self:step() do n = n + 1 end
  return n
end

return Scheduler
