local posix=require('posix')
local info=posix.sysinfo()
local rows={}
for name,bytes in pairs(info.moduleMemory or {}) do rows[#rows+1]={name,bytes} end
table.sort(rows,function(a,b) return a[2]>b[2] end)
if #rows==0 then
  print('No boot profile. Run tools/profile-ocelot.sh on the disk, then reboot.')
  return 1
end
print('Approximate exclusive module allocation:')
local total=0
for _,row in ipairs(rows) do print(string.format('%7.1f KiB  %s',row[2]/1024,row[1])); total=total+row[2] end
print(string.format('%7.1f KiB  measured total',total/1024))
posix.sysinfo('clearProfile')
print('Profile data released.')
