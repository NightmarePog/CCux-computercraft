local U = require('ccux.util')

local Loader = {}
Loader.__index = Loader

local nativeLoad = load
local nativeLoadstring = loadstring
local nativeSetfenv = setfenv

local function compile(source, name, mode, env)
  if mode and mode ~= 't' and mode ~= 'bt' then return nil, 'binary chunks are disabled' end
  if source:byte(1) == 27 then return nil, 'binary chunks are disabled' end
  if _VERSION == 'Lua 5.1' and nativeLoadstring then
    local fn, err = nativeLoadstring(source, name)
    if fn and nativeSetfenv then nativeSetfenv(fn, env) end
    return fn, err
  end
  return nativeLoad(source, name, 't', env)
end

function Loader.new(vfs, config)
  return setmetatable({
    vfs = vfs,
    config = config,
    preloads = {native = {}, craftos = {}, openos = {}},
    sourceCache = {},
    sourceOrder = U.queue(),
    sourceCount = 0,
    sourceBytes = 0,
    cacheLimit = config.moduleSourceCache,
    librarySources = setmetatable({}, {__mode='k'}),
  }, Loader)
end

function Loader:setCacheLimit(limit)
  limit = math.max(0, math.floor(limit or 0))
  self.cacheLimit = limit
  while self.sourceCount > limit do
    local old = U.pop(self.sourceOrder)
    if not old then break end
    if self.sourceCache[old] then
      self.sourceBytes = self.sourceBytes - #self.sourceCache[old]
      self.sourceCache[old] = nil
      self.sourceCount = self.sourceCount - 1
    end
  end
end

function Loader:register(profile, name, factory)
  U.check(self.preloads[profile] and type(name) == 'string' and type(factory) == 'function', 'EINVAL')
  self.preloads[profile][name] = factory
end

function Loader:readSource(proc, path)
  local stat = self.vfs:stat(path, proc, true)
  U.check(stat.type == 'file', 'EISDIR')
  U.check(stat.size <= self.config.maxSource, 'EFBIG')
  -- Opening is required even on a cache hit: this rechecks current credentials.
  local handle = self.vfs:open(path, proc, 'r')
  local cacheKey = stat.ino .. ':' .. stat.mtime .. ':' .. stat.size
  local cached = self.sourceCache[cacheKey]
  if cached then self.vfs:close(handle); return cached, stat end
  local chunks = {}
  local ok, err = pcall(function()
    while true do
      local chunk = self.vfs:read(handle, self.config.chunk)
      if chunk == '' then break end
      chunks[#chunks + 1] = chunk
    end
  end)
  self.vfs:close(handle)
  if not ok then error(err, 0) end
  local source = table.concat(chunks)
  if self.cacheLimit == 0 or #source > self.config.moduleSourceCacheBytes then return source, stat end
  while self.sourceCount >= self.cacheLimit or
      self.sourceBytes + #source > self.config.moduleSourceCacheBytes do
    local old = U.pop(self.sourceOrder)
    if old and self.sourceCache[old] then
      self.sourceBytes = self.sourceBytes - #self.sourceCache[old]
      self.sourceCache[old] = nil
      self.sourceCount = self.sourceCount - 1
    end
  end
  self.sourceCache[cacheKey] = source
  self.sourceBytes = self.sourceBytes + #source
  U.push(self.sourceOrder, cacheKey)
  self.sourceCount = self.sourceCount + 1
  return source, stat
end

function Loader:loadfile(proc, path, mode, env)
  local source = self:readSource(proc, path)
  return compile(source, '=' .. path, mode or 't', env or proc.luaEnv)
end

function Loader:baseEnvironment(proc)
  local function libraryView(source)
    if not source then return nil end
    local proxy=setmetatable({}, {
      __index=source,
      __pairs=function() return pairs(source) end,
      __metatable=false,
    })
    self.librarySources[proxy]=source
    return proxy
  end
  local function userPairs(value)
    local source=self.librarySources[value]
    if source then return pairs(source) end
    return pairs(value)
  end
  local function userNext(value, key)
    local source=self.librarySources[value]
    return next(source or value, key)
  end
  local env = {
    assert = assert,
    error = error,
    ipairs = ipairs,
    next = userNext,
    pairs = userPairs,
    pcall = pcall,
    rawequal = rawequal,
    rawget = rawget,
    rawset = rawset,
    select = select,
    setmetatable = setmetatable,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    xpcall = xpcall,
    math = libraryView(math),
    string = libraryView(string),
    table = libraryView(table),
    bit32 = libraryView(bit32),
    utf8 = libraryView(utf8),
    _VERSION = _VERSION,
  }
  env.unpack = env.table.unpack or unpack
  env.table.unpack = env.table.unpack or unpack
  env.table.pack = env.table.pack or U.pack
  env.getmetatable = function(value)
    if type(value) ~= 'table' then return nil end
    local mt = getmetatable(value)
    if type(mt) == 'table' and mt.__metatable ~= nil then return mt.__metatable end
    return mt
  end
  env._G = env
  proc.luaEnv = env
  return env
end

local function validateModuleName(name)
  U.check(type(name) == 'string' and #name > 0 and #name <= 255, 'EINVAL')
  U.check(not name:find('/', 1, true) and not name:find('\\', 1, true), 'EINVAL')
  U.check(name:match('^[%w_%.%-]+$') and not name:match('^%.') and
    not name:match('%.$') and not name:match('%.%.'), 'EINVAL')
end

function Loader:installPackage(proc, profile, options)
  options = options or {}
  local env = proc.luaEnv or self:baseEnvironment(proc)
  local loaded, loading = {}, {}
  local package = {
    config = '/\n;\n?\n!\n-\n',
    path = options.path or '/lib/?.lua;/usr/lib/?.lua;/lib/?/init.lua;/usr/lib/?/init.lua',
    loaded = loaded,
    preload = {},
    searchers = {},
  }
  local profilePreloads = self.preloads[profile] or self.preloads.native
  for name, factory in pairs(profilePreloads) do package.preload[name] = factory end
  if profile ~= 'native' then
    for name, factory in pairs(self.preloads.native) do
      if package.preload[name] == nil then package.preload[name] = factory end
    end
  end

  function package.searchpath(name, path)
    validateModuleName(name)
    local modulePath = name:gsub('%.', '/')
    local errors = {}
    for template in path:gmatch('[^;]+') do
      local candidate = template:gsub('%?', modulePath)
      local ok, stat = pcall(self.vfs.stat, self.vfs, candidate, proc, true)
      if ok and stat.type == 'file' then return candidate end
      errors[#errors + 1] = "no file '" .. candidate .. "'"
    end
    return nil, table.concat(errors, '\n\t')
  end

  package.searchers[1] = function(name)
    local factory = package.preload[name]
    if factory then return function() return factory(proc, env) end, ':preload:' .. name end
    return "no field package.preload['" .. name .. "']"
  end
  package.searchers[2] = function(name)
    local path, reason = package.searchpath(name, package.path)
    if not path then return reason end
    local fn, err = self:loadfile(proc, path, 't', env)
    if not fn then error("error loading module '" .. name .. "' from '" .. path .. "': " .. err, 0) end
    local stat = self.vfs:stat(path, proc, true)
    return fn, path, stat.ino
  end

  local function requireModule(name)
    validateModuleName(name)
    if loaded[name] ~= nil then return loaded[name] end
    U.check(not loading[name], 'ELOOP')
    local loaderFn, loaderArg, inode
    local failures = {}
    for _, searcher in ipairs(package.searchers) do
      local candidate, arg, ino = searcher(name)
      if type(candidate) == 'function' then loaderFn, loaderArg, inode = candidate, arg, ino; break end
      failures[#failures + 1] = tostring(candidate)
    end
    if not loaderFn then error("module '" .. name .. "' not found:\n\t" .. table.concat(failures, '\n\t'), 2) end
    local canonical = inode and ('@inode:' .. inode) or loaderArg
    if canonical and loaded[canonical] ~= nil then loaded[name] = loaded[canonical]; return loaded[name] end
    U.check(not loading[canonical or name], 'ELOOP')
    loading[name], loading[canonical or name] = true, true
    local ok, result = pcall(loaderFn, loaderArg or name)
    loading[name], loading[canonical or name] = nil, nil
    if not ok then error(result, 2) end
    if result == nil then result = true end
    loaded[name] = result
    if canonical then loaded[canonical] = result end
    return result
  end

  function package.delay(target, initializer)
    U.check(type(target) == 'table' and type(initializer) == 'function', 'EINVAL')
    local mt = getmetatable(target) or {}
    local previous = mt.__index
    mt.__index = function(tableValue, key)
      mt.__index = previous
      initializer(tableValue)
      local value = rawget(tableValue, key)
      if value ~= nil then return value end
      if type(previous) == 'function' then return previous(tableValue, key) end
      return previous and previous[key]
    end
    setmetatable(target, mt)
    return target
  end

  local function userLoad(source, name, mode, targetEnv)
    U.check(type(source) == 'string', 'EINVAL')
    U.check(#source <= self.config.maxSource, 'EFBIG')
    return compile(source, name or '=(load)', mode or 't', targetEnv or env)
  end
  local function userLoadfile(path, mode, targetEnv)
    U.check(type(path) == 'string', 'EINVAL')
    return self:loadfile(proc, path, mode or 't', targetEnv or env)
  end

  env.package = package
  env.require = requireModule
  env.load = userLoad
  env.loadstring = function(source, name) return userLoad(source, name, 't', env) end
  env.loadfile = userLoadfile
  env.dofile = function(path)
    local fn, err = userLoadfile(path, 't', env)
    if not fn then error(err, 2) end
    return fn()
  end
  loaded._G, loaded.package = env, package
  loaded.math, loaded.string, loaded.table = env.math, env.string, env.table
  if env.bit32 then loaded.bit32 = env.bit32 end
  if env.utf8 then loaded.utf8 = env.utf8 end
  proc.package = package
  proc.require = requireModule
  return env
end

return Loader
