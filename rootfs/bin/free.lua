local info=require('posix').sysinfo()
local function kib(value) return value and string.format('%.1f',value/1024) or '?' end
print('memory KiB: total '..kib(info.memoryTotal)..'  used '..kib(info.memoryUsed)..'  free '..kib(info.memoryFree))
print('lua heap KiB: '..(info.luaKiB and string.format('%.1f',info.luaKiB) or '?'))
print('processes: '..info.processes)
print('source cache: '..info.sourceCacheEntries..'/'..info.sourceCacheLimit..' entries, '..info.sourceCacheBytes..' bytes')
print('inode cache: '..info.inodeCacheEntries..'/'..info.inodeCacheLimit..' entries')
