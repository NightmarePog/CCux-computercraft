local U=require('ccux.util')
local C=require('ccux.codec')
local defaults=require('ccux.config')
local V={}; V.__index=V
local root={uid=0,gid=0,groups={},cwd=1,umask=18}
V.rootCredentials=root
local function key(id) return 'm_'..id end
local function block(n,i) return 'b_'..n.id..'_'..n.generation..'_'..i end
function V.new(store,clock,config)
  local selected=config or defaults
  local self=setmetatable({store=store,clock=clock,config=selected,cache={},order=U.queue(),cacheSize=0,cacheLimit=selected.inodeCache,refs={}},V)
  local s=store:read('s_0')
  if s then self.super=C.unframe(s) else
    U.check(not store.readonly,'EROFS'); self.super={version=1,next=2}
    local now=clock(); local n={id=1,type='dir',uid=0,gid=0,mode=493,nlink=1,parent=1,entries={},size=0,ctime=now,mtime=now,generation=1}
    store:commit({s_0=C.frame(self.super),m_1=C.frame(n)})
  end
  U.check(self.super.version==1,'EINVAL'); self:get(1)
  return self
end
function V:setCacheLimit(limit)
  limit=math.max(1,math.floor(limit or 1)); self.cacheLimit=limit
  while self.cacheSize>limit do
    local old=U.pop(self.order); if not old then break end
    if self.cache[old] then self.cache[old]=nil; self.cacheSize=self.cacheSize-1 end
  end
end
function V:get(id)
  if self.cache[id] then return self.cache[id] end
  local raw=self.store:read(key(id)); U.check(raw,'ENOENT')
  local n=C.unframe(raw); U.check(n.id==id,'EIO')
  while self.cacheSize>=self.cacheLimit do local old=U.pop(self.order); if self.cache[old] then self.cache[old]=nil; self.cacheSize=self.cacheSize-1 end end
  self.cache[id]=n; U.push(self.order,id); self.cacheSize=self.cacheSize+1
  return n
end
function V:commit(nodes,extra)
  local changes=extra or {}
  for _,n in ipairs(nodes) do local raw=C.frame(n); U.check(#raw<=self.config.metadataBytes,'EFBIG'); changes[key(n.id)]=raw end
  self.store:commit(changes)
  for _,n in ipairs(nodes) do if self.cache[n.id] then self.cache[n.id]=n end end
end
function V:access(n,p,bit)
  if p.uid==0 then return true end
  local shift=0
  if p.uid==n.uid then shift=6 elseif p.gid==n.gid or (p.groups and p.groups[n.gid]) then shift=3 end
  return math.floor(n.mode/2^(shift+bit))%2==1
end
function V:permit(n,p,bit) U.check(self:access(n,p,bit),'EACCES') end
local function parts(path, config)
  U.check(type(path)=='string' and #path>0 and #path<=config.maxPath and not path:find('\0',1,true),'EINVAL')
  local r={} for s in path:gmatch('[^/]+') do U.check(#s<=config.maxName,'ENAMETOOLONG'); r[#r+1]=s end return r
end
function V:resolve(path,p,nofollow)
  p=p or root
  local todo=parts(path,self.config); local id=path:sub(1,1)=='/' and 1 or (p.cwd or 1); local i,links=1,0
  while i<=#todo do
    local dir=self:get(id); U.check(dir.type=='dir','ENOTDIR'); self:permit(dir,p,0)
    local name=todo[i]
    if name=='..' then id=dir.parent
    elseif name~='.' then
      local child=dir.entries[name]; U.check(child,'ENOENT'); local n=self:get(child)
      if n.type=='link' and (i<#todo or not nofollow or path:sub(-1)=='/') then
        links=links+1; U.check(links<=self.config.symlinkLimit,'ELOOP')
        local nextParts=parts(n.target,self.config); for j=i+1,#todo do nextParts[#nextParts+1]=todo[j] end
        todo=nextParts; i=0; if n.target:sub(1,1)=='/' then id=1 end
      else id=child end
    end
    i=i+1
  end
  local n=self:get(id); if path:sub(-1)=='/' then U.check(n.type=='dir','ENOTDIR') end
  return n
end
function V:parent(path,p)
  local list=parts(path,self.config); local name=table.remove(list)
  U.check(name and name~='.' and name~='..','EINVAL')
  local prefix=(path:sub(1,1)=='/' and '/' or '')..table.concat(list,'/')
  local dir=self:resolve(prefix=='' and '.' or prefix,p)
  U.check(dir.type=='dir','ENOTDIR'); self:permit(dir,p,0); self:permit(dir,p,1)
  return U.clone(dir),name
end
function V:create(path,p,kind,mode,target)
  local dir,name=self:parent(path,p); U.check(not dir.entries[name],'EEXIST')
  local id=self.super.next; local now=self.clock()
  local n={id=id,type=kind,uid=p.uid,gid=p.gid,mode=U.mode(mode or (kind=='dir' and 511 or 438),p.umask or 18),nlink=1,parent=dir.id,size=0,generation=1,mtime=now,ctime=now}
  if kind=='dir' then n.entries={} elseif kind=='link' then U.check(type(target)=='string' and #target>0,'EINVAL'); parts(target,self.config); n.target=target; n.size=#target end
  dir.entries[name]=id; dir.mtime=now
  local super=U.copy(self.super); super.next=id+1
  self:commit({dir,n},{s_0=C.frame(super)}); self.super=super
  return n
end
function V:stat(path,p,nofollow)
  local n= self:resolve(path,p,nofollow)
  return {ino=n.id,type=n.type,uid=n.uid,gid=n.gid,mode=n.mode,nlink=n.nlink,size=n.size,mtime=n.mtime,ctime=n.ctime,dev=1}
end
function V:list(path,p)
  local n=self:resolve(path,p); U.check(n.type=='dir','ENOTDIR'); self:permit(n,p,2)
  local r={} for k in pairs(n.entries) do r[#r+1]=k end table.sort(r); return r
end
function V:readlink(path,p)
  local n=self:resolve(path,p,true); U.check(n.type=='link','EINVAL'); return n.target
end
function V:chdir(path,p)
  local n=self:resolve(path,p); U.check(n.type=='dir','ENOTDIR'); self:permit(n,p,0); p.cwd=n.id; return true
end
function V:sticky(dir,n,p)
  U.check(math.floor(dir.mode/512)%2==0 or p.uid==0 or p.uid==dir.uid or p.uid==n.uid,'EPERM')
end
function V:unlink(path,p,isdir)
  local dir,name=self:parent(path,p); local id=dir.entries[name]; U.check(id,'ENOENT')
  local n=U.clone(self:get(id)); self:sticky(dir,n,p)
  if isdir then U.check(n.type=='dir','ENOTDIR'); U.check(next(n.entries)==nil,'ENOTEMPTY'); U.check(not self.refs[id],'EBUSY') else U.check(n.type~='dir','EISDIR') end
  dir.entries[name]=nil; dir.mtime=self.clock(); n.nlink=n.nlink-1
  self:commit({dir,n}); self:collect(id)
  return true
end
function V:collect(id)
  local n=self:get(id)
  if n.nlink~=0 or self.refs[id] then return end
  -- Unreachable objects are swept by fsck/maintenance; unlink stays bounded.
end
function V:link(old,new,p)
  local n=U.clone(self:resolve(old,p,true)); U.check(n.type~='dir','EPERM')
  U.check(p.uid==0 or p.uid==n.uid,'EPERM')
  local d,name=self:parent(new,p); U.check(not d.entries[name],'EEXIST'); d.entries[name]=n.id; n.nlink=n.nlink+1
  self:commit({d,n}); return true
end
function V:rename(old,new,p)
  local a,an=self:parent(old,p); local b,bn=self:parent(new,p)
  local id=a.entries[an]; U.check(id,'ENOENT'); local n=U.clone(self:get(id)); self:sticky(a,n,p)
  if a.id==b.id then b=a end
  if b.entries[bn]==id then return true end
  if n.type=='dir' then local x=b; while true do U.check(x.id~=id,'EINVAL'); if x.id==1 then break end; x=self:get(x.parent) end end
  local nodes={a}; if a.id~=b.id then nodes[#nodes+1]=b end
  if b.entries[bn] then
    local victim=U.clone(self:get(b.entries[bn])); self:sticky(b,victim,p)
    U.check((victim.type=='dir')==(n.type=='dir'),victim.type=='dir' and 'EISDIR' or 'ENOTDIR')
    if victim.type=='dir' then U.check(next(victim.entries)==nil,'ENOTEMPTY'); U.check(not self.refs[victim.id],'EBUSY') end
    victim.nlink=victim.nlink-1; nodes[#nodes+1]=victim
  end
  a.entries[an]=nil; b.entries[bn]=id; n.parent=b.id; n.ctime=self.clock(); nodes[#nodes+1]=n
  self:commit(nodes); return true
end
function V:chmod(path,p,mode)
  U.check(U.integer(mode) and mode>=0 and mode<=1023,'EINVAL')
  local n=U.clone(self:resolve(path,p)); U.check(p.uid==0 or p.uid==n.uid,'EPERM'); n.mode=mode; n.ctime=self.clock(); self:commit({n}); return true
end
function V:chown(path,p,uid,gid)
  U.check(p.uid==0,'EPERM'); U.check(U.integer(uid) and uid>=0 and U.integer(gid) and gid>=0,'EINVAL')
  local n=U.clone(self:resolve(path,p)); n.uid=uid; n.gid=gid; n.ctime=self.clock(); self:commit({n}); return true
end
function V:open(path,p,flags,mode)
  flags=flags or 'r'; U.check(type(flags)=='string' and ({r=true,w=true,a=true,['r+']=true,['w+']=true,['a+']=true,wx=true,['wx+']=true})[flags],'EINVAL')
  local ok,n=pcall(self.resolve,self,path,p)
  if not ok then
    if type(n)=='table' and n.errno=='ENOENT' and flags:sub(1,1)~='r' then n=self:create(path,p,'file',mode)
    else error(n,0) end
  elseif flags:find('x',1,true) then U.check(false,'EEXIST') end
  U.check(n.type=='file' or n.type=='fifo','EISDIR')
  local read=flags:sub(1,1)=='r' or flags:find('+',1,true)~=nil
  local write=flags:sub(1,1)~='r' or flags:find('+',1,true)~=nil
  if read then self:permit(n,p,2) end; if write then self:permit(n,p,1) end
  if flags:sub(1,1)=='w' and n.type=='file' then
    n=U.clone(n); n.size=0; n.generation=n.generation+1; n.mtime=self.clock(); self:commit({n})
  end
  self.refs[n.id]=(self.refs[n.id] or 0)+1
  return {kind=n.type,ino=n.id,offset=0,readable=read,writable=write,append=flags:sub(1,1)=='a',refs=1}
end
function V:close(h)
  self.refs[h.ino]=self.refs[h.ino]-1; if self.refs[h.ino]==0 then self.refs[h.ino]=nil end; self:collect(h.ino)
end
function V:read(h,count)
  U.check(h.readable,'EBADF'); U.check(U.integer(count) and count>=0,'EINVAL')
  local n=self:get(h.ino); count=math.min(count,self.config.chunk,n.size-h.offset)
  if count<=0 then return '' end
  local out={}; local remaining=count
  while remaining>0 do
    local i=math.floor(h.offset/self.config.chunk); local off=h.offset%self.config.chunk
    local take=math.min(remaining,self.config.chunk-off)
    local data=self.store:read(block(n,i)) or ''; data=data..string.rep('\0',math.max(0,off+take-#data))
    out[#out+1]=data:sub(off+1,off+take); h.offset=h.offset+take; remaining=remaining-take
  end
  return table.concat(out)
end
function V:write(h,data)
  U.check(h.writable,'EBADF'); U.check(type(data)=='string','EINVAL')
  local n=U.clone(self:get(h.ino)); local pos=h.append and n.size or h.offset
  U.check(pos+#data<=self.config.maxFile,'EFBIG'); U.check(#data<=self.config.chunk,'EINVAL')
  local changes={}; local done=0
  while done<#data do
    local i=math.floor(pos/self.config.chunk); local off=pos%self.config.chunk; local take=math.min(#data-done,self.config.chunk-off)
    local k=block(n,i); local old=self.store:read(k) or ''; old=old..string.rep('\0',math.max(0,off-#old))
    changes[k]=old:sub(1,off)..data:sub(done+1,done+take)..old:sub(off+take+1)
    done=done+take; pos=pos+take
  end
  n.size=math.max(n.size,pos); n.mtime=self.clock(); self:commit({n},changes); h.offset=pos; return done
end
function V:seek(h,whence,offset)
  U.check(h.kind=='file','ESPIPE'); U.check(U.integer(offset),'EINVAL')
  local base=({set=0,cur=h.offset,['end']=self:get(h.ino).size})[whence]; U.check(base~=nil and base+offset>=0 and base+offset<=self.config.maxFile,'EINVAL')
  h.offset=base+offset; return h.offset
end
function V:getcwd(p)
  local id=p.cwd or 1; local r={}
  while id~=1 do
    local n=self:get(id); local parent=self:get(n.parent); local found
    for name,child in pairs(parent.entries) do if child==id then found=name; break end end
    U.check(found,'ENOENT'); table.insert(r,1,found); id=parent.id
  end
  return '/'..table.concat(r,'/')
end
function V:fsck(sweep)
  local counts={[1]=1}; local reachable={}; local errors={}
  local function walk(id,ancestors)
    if ancestors[id] then errors[#errors+1]='directory cycle at '..id; return end
    local ok,n=pcall(self.get,self,id); if not ok then errors[#errors+1]='missing/corrupt inode '..id; return end
    if reachable[id] then return end; reachable[id]=n
    if n.type=='dir' then local nextAnc=U.copy(ancestors); nextAnc[id]=true; for _,child in pairs(n.entries) do counts[child]=(counts[child] or 0)+1; walk(child,nextAnc) end end
  end
  walk(1,{})
  for id,n in pairs(reachable) do if n.nlink~=(counts[id] or 0) then errors[#errors+1]='link count mismatch '..id end end
  if sweep and #errors==0 and not self.store.readonly then
    for _,k in ipairs(self.store.backend.list()) do
      local id,gen,index=k:match('^b_(%d+)_(%d+)_(%d+)$'); local mid=k:match('^m_(%d+)$')
      local remove=false
      if id then local n=reachable[tonumber(id)]; remove=not self.refs[tonumber(id)] and (not n or n.generation~=tonumber(gen) or tonumber(index)*self.config.chunk>=n.size)
      elseif mid then remove=not reachable[tonumber(mid)] and not self.refs[tonumber(mid)] end
      if remove then self.store.backend.remove(k) end
    end
  end
  return errors
end
return V
