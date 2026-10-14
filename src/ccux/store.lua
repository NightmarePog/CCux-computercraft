local codec=require('ccux.codec')
local U=require('ccux.util')
local Store={}; Store.__index=Store
-- Backend is a private flat key/value directory. Its functions throw on I/O failure.
function Store.new(backend)
  local self=setmetatable({backend=backend,readonly=false,transactions=0},Store)
  local pending=backend.read('pending')
  if pending and not backend.read('journal') then
    -- A staging write which was never published is not a committed transaction.
    backend.remove('pending')
  end
  local journal=backend.read('journal')
  if journal then
    local ok,err=pcall(function() self:apply(codec.unframe(journal)); backend.remove('journal') end)
    if not ok then self.readonly=true; self.recoveryError=tostring(err) end
  end
  return self
end
function Store:apply(changes)
  assert(type(changes)=='table','invalid journal')
  for k,v in pairs(changes) do
    assert(type(k)=='string' and k:match('^[mbs]_[%d_]+$'),'invalid storage key')
    assert(type(v)=='string' or v==false,'invalid storage value')
  end
  for k,v in pairs(changes) do if v==false then self.backend.remove(k) else self.backend.write(k,v) end end
end
function Store:commit(changes)
  U.check(not self.readonly,'EROFS')
  local ok,err=pcall(function()
    local record=codec.frame(changes)
    -- A fully written staging record is published before any home writes.
    self.backend.remove('pending')
    self.backend.write('pending',record)
    self.backend.move('pending','journal')
    self:apply(changes)
    self.backend.remove('journal')
  end)
  if not ok then self.readonly=true; error({errno='EIO',message=tostring(err)},0) end
  self.transactions=self.transactions+1
end
function Store:read(k) return self.backend.read(k) end
return Store
