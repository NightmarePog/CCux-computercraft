-- Deterministic bounded backend and clock for tests and tmpfs.
local M={}
local unpackValues = table.unpack or unpack
function M.backend(limit, files)
  files=files or {}; local writes=0; local fail
  local function used() local n=0 for _,v in pairs(files) do n=n+#v end return n end
  local function fault() writes=writes+1; if fail and writes==fail then error('injected storage failure') end end
  return {
    files=files, read=function(k) return files[k] end,
    write=function(k,v) fault(); assert(used()-(files[k] and #files[k] or 0)+#v <= (limit or math.huge),'disk full'); files[k]=v end,
    remove=function(k) fault(); files[k]=nil end,
    move=function(a,b) fault(); assert(files[a] and not files[b],'invalid move'); files[b]=files[a]; files[a]=nil end,
    list=function() local r={} for k in pairs(files) do r[#r+1]=k end table.sort(r); return r end,
    used=used, failAt=function(n) writes=0; fail=n end,
  }
end
function M.new()
  local p={time=0,events={},output='',name='test',width=51,height=19}
  p.clock=function() return p.time end
  p.wall=function() return 1700000000+math.floor(p.time) end
  p.poll=function(timeout)
    if #p.events>0 then return unpackValues(table.remove(p.events,1)) end
    if timeout then p.time=p.time+timeout end
  end
  p.write=function(s) p.output=p.output..s end
  p.backspace=function() p.output=p.output:sub(1,-2) end
  p.flush=function() end
  p.size=function() return p.width,p.height end
  p.shutdown=function(reboot) p.halted=true; p.reboot=reboot end
  return p
end
return M
