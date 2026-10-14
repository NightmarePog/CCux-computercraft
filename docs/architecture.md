# Runtime architecture

CCux has one shared kernel and two platform adapters. Application code never
receives the captured ComputerCraft or OpenComputers globals.

```text
native / CraftOS / OpenOS program profiles
                  |
       process-local module loaders
                  |
       syscall and compatibility facades
                  |
 scheduler -- descriptors -- VFS -- permissions
                  |
    CC:T adapter / OpenComputers adapter
```

## Scheduling

Only `ccux.scheduler` resumes process coroutines. Runnable processes live in a
FIFO queue; event, descriptor, child, and timer waits are indexed separately.
The dispatcher runs a bounded batch and then polls the host, preventing a
continuous runnable workload from starving input.

Scheduling is cooperative. A process runs until it invokes a syscall or yields
through its compatibility runtime. Access boundaries apply when the kernel
regains control, but this cannot contain an infinite loop or arbitrary Lua
memory exhaustion.

## Loading and authority

Kernel modules use the boot loader and are unavailable to userspace. Every user
process receives a fresh environment, package table, module cache, cycle set,
and compatibility profile. Module paths resolve through the VFS and source must
be readable by the process. `exec` discards the old environment and cache.

Loading a module never grants permission. Sensitive APIs are process-bound
facades and check credentials or capabilities for each operation. Source may be
cached by inode/version after permission checking; mutable module return tables
remain process-local.

Exited processes release their coroutine, globals, and module graph before they
wait as zombies to be reaped. On OpenComputers, the source cache adapts to
reported free memory: at most four entries/64 KiB normally, two entries below
50% free, and disabled below 25% free. Collection runs only at process creation
and exit boundaries. The inode cache similarly contracts from sixteen entries
to eight or four under memory pressure.

Syscall functions and file-object methods are shared instead of regenerated per
process or descriptor. Standard Lua libraries use protected process-local views
over shared function tables, avoiding repeated copies while keeping assignments
inside the process that made them.

OpenComputers can perform a one-shot differential module scan when the boot
disk contains `/.ccux-profile-next-boot`. `memstat` reports the approximate
exclusive allocation and then releases the profile table. Measurements include
allocator and garbage-collection noise and are intended for ranking modules.

## Storage

The VFS stores versioned inode metadata and fixed-size content blocks in a
private flat backend. Namespace and metadata changes use a checksummed journal.
An interrupted published transaction is replayed during mount; an unreadable
journal makes the store read-only.

Host administrators and direct edits to backing files remain outside the OS
security boundary.
