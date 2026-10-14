local Kernel = require('ccux.kernel')
local Runtime = require('ccux.runtime')
local manifest = require('ccux.root_manifest')

return function(platform, backend, systemRoot)
  local kernel = Kernel.new(platform, backend)
  local runtime = Runtime.new(kernel)
  runtime:seedFromHost(manifest, systemRoot)
  local init = kernel:spawnProgram('/sbin/init.lua', {}, {
    uid=0, gid=0, profile='native', name='init', envvars={USER='root',HOME='/root',PATH='/bin:/sbin'}
  })
  assert(init.pid == 1, 'init must be PID 1')
  kernel:run()
end
