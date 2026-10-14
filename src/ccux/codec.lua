-- Length-prefixed, deterministic data encoding. Never executes stored data.
local M={}
local function encode(v, depth)
  assert(depth<32, 'record nesting limit')
  local t=type(v)
  if t=='string' then return 's'..#v..':'..v end
  if t=='number' then assert(v==v and math.abs(v)<2^53, 'invalid number'); local s=string.format('%.17g',v); return 'n'..#s..':'..s end
  if t=='boolean' then return v and 't' or 'f' end
  assert(t=='table', 'unsupported record type')
  local keys={} for k in pairs(v) do assert(type(k)=='string' or type(k)=='number'); keys[#keys+1]=k end
  table.sort(keys,function(a,b) return type(a)==type(b) and a<b or type(a)<type(b) end)
  local out={'d',tostring(#keys),':'}
  for _,k in ipairs(keys) do out[#out+1]=encode(k,depth+1); out[#out+1]=encode(v[k],depth+1) end
  return table.concat(out)
end
function M.encode(v) return encode(v,0) end
function M.decode(s, limit)
  assert(type(s)=='string' and #s<=(limit or 262144), 'record size limit')
  local i=1
  local function parse(depth)
    assert(depth<32,'record nesting limit')
    local t=s:sub(i,i); i=i+1
    if t=='t' then return true elseif t=='f' then return false end
    assert(t=='s' or t=='n' or t=='d','invalid record tag')
    local e=s:find(':',i,true); assert(e and e-i<10,'invalid record length')
    local raw=s:sub(i,e-1); assert(raw:match('^%d+$'),'invalid length')
    local n=tonumber(raw); i=e+1; assert(n<=#s,'record length overflow')
    if t=='d' then
      local v={} for _=1,n do local k=parse(depth+1); assert(type(k)=='string' or type(k)=='number','invalid key'); assert(v[k]==nil,'duplicate key'); v[k]=parse(depth+1) end
      return v
    end
    assert(i+n-1<=#s,'truncated record'); local v=s:sub(i,i+n-1); i=i+n
    if t=='n' then v=tonumber(v); assert(v and v==v and math.abs(v)<2^53,'invalid number') end
    return v
  end
  local v=parse(0); assert(i==#s+1,'trailing record data'); return v
end
function M.checksum(s)
  local a,b=1,0
  for i=1,#s do a=(a+s:byte(i))%65521; b=(b+a)%65521 end
  return string.format('%08x',b*65536+a)
end
function M.frame(v) local s=M.encode(v); return 'CCUX1\n'..M.checksum(s)..'\n'..s end
function M.unframe(s)
  assert(s:sub(1,6)=='CCUX1\n','unknown format')
  local body=s:sub(16); assert(s:sub(15,15)=='\n' and M.checksum(body)==s:sub(7,14),'checksum mismatch')
  return M.decode(body)
end
return M
