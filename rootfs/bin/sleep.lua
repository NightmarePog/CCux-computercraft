local posix=require('posix'); local seconds=tonumber((...))
if not seconds or seconds<0 then io.stderr:write('sleep: invalid duration\n'); return 1 end
posix.sleep(seconds)
