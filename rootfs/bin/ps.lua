-- /proc process files are planned; this utility identifies the current process now.
local posix=require('posix')
print('PID PPID UID COMMAND')
print(posix.getpid(),posix.getppid(),posix.getuid(),'ps')
