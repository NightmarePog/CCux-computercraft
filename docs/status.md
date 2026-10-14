# Alpha status and compatibility

## Native API

`require("posix")` provides process identity, environment variables,
spawn/exec/wait, cooperative signals, clocks, filesystem operations, descriptor
I/O, duplication, pipes, sleeps, and shutdown. Operational failures return
`nil, errno, message`.

Missing POSIX areas include `fork`, process groups, full terminal control,
`poll`, sockets, named FIFOs, mounts, account databases, and most optional
interfaces. CCux does not claim formal POSIX conformance.

## CraftOS profile

Available now: process-local `fs`, `term`, basic `shell`, input, filtered events,
`parallel`, `os.run`, `os.loadAPI`, clocks, sleep, and power calls. Device,
HTTP, rednet, settings, complete shell semantics, windows, and the full ROM API
remain pending.

Nested `parallel` coroutines can relay a blocking syscall through their owning
process. Concurrent waits of different kinds inside one `parallel` group are a
known limit until the kernel gains multi-wait support.

## OpenOS profile

Available now: process-local `package`, `filesystem`, `io`, `event`, `process`,
`computer`, `component`, environment variables, and a Unicode fallback. Raw
components are capability-filtered. Full OpenOS threads, event timers, buffered
terminal behavior, shell libraries, robot APIs, and networking remain pending.

Compatibility means tested API behavior, not that every existing program runs.
