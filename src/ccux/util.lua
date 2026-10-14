local M = {}
M.unpack = table.unpack or unpack
function M.pack(...) return {n=select('#', ...), ...} end
function M.copy(t) local r={} for k,v in pairs(t or {}) do r[k]=v end return r end
function M.clone(t)
  if type(t) ~= 'table' then return t end
  local r={} for k,v in pairs(t) do r[k]=M.clone(v) end return r
end
function M.err(code, message) return nil, code, message or code end
function M.check(ok, code) if not ok then error({errno=code}, 0) end end
function M.failure(value)
  if type(value) == 'table' and value.errno then
    return nil, value.errno, value.message or value.errno
  end
  return nil, 'EIO', tostring(value)
end
function M.integer(n) return type(n)=='number' and n==math.floor(n) and math.abs(n)<2^53 end
function M.queue() return {first=1,last=0} end
function M.push(q,v) q.last=q.last+1; q[q.last]=v end
function M.pop(q)
  if q.first>q.last then return end
  local v=q[q.first]; q[q.first]=nil; q.first=q.first+1
  if q.first>q.last then q.first=1; q.last=0 end
  return v
end
function M.heapPush(h,v)
  local i=#h+1
  while i>1 do local p=math.floor(i/2); if h[p].at<=v.at then break end; h[i]=h[p]; i=p end
  h[i]=v
end
function M.heapPop(h)
  local v=h[1]; local tail=table.remove(h)
  if #h>0 then
    local i=1
    while i*2<=#h do
      local c=i*2; if c<#h and h[c+1].at<h[c].at then c=c+1 end
      if tail.at<=h[c].at then break end; h[i]=h[c]; i=c
    end
    h[i]=tail
  end
  return v
end
function M.mode(mode, mask)
  local r=0
  for i=0,8 do local b=2^i; if math.floor(mode/b)%2==1 and math.floor(mask/b)%2==0 then r=r+b end end
  return r
end
return M
