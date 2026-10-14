# CCux

CCux is an experimental Unix-like Lua operating system for CC: Tweaked and
OpenComputers. Both editions use the same process scheduler, syscall API,
permission-aware VFS, descriptors, pipes, program loader, and userspace. Small
platform adapters translate each mod's storage, terminal, events, devices, and
power controls.

The repository currently contains the kernel foundation and a bootable terminal
alpha. It is not yet POSIX conforming and should not be used for important data.

## Implemented foundation

- One cooperative dispatcher with process states, indexed event waits, timer
  heap, parent/child lifecycle, signals, zombies, and resource cleanup.
- Process-local globals, `package.loaded`, `require`, `load`, `loadfile`, and
  `dofile`, with VFS permission checks and bounded source caching.
- Native, CraftOS, and OpenOS runtime profiles. The compatibility profiles are
  intentionally incomplete but cannot access raw host APIs.
- Inode-based managed storage with modes, ownership, directories, links,
  chunked files, a checksummed metadata journal, and `fsck` support.
- File descriptors, descriptor inheritance, `dup`, bounded pipes, backpressure,
  EOF, and broken-pipe errors.
- Minimal PID 1, shell, and basic filesystem/text commands.
- CC: Tweaked UnBIOS entry and OpenComputers `/init.lua`/EEPROM entries.

See [the architecture](docs/architecture.md) and [current status](docs/status.md).

## Development

```sh
lua5.1 tests/run.lua
lua5.4 tests/run.lua
```

For Ocelot Desktop, keep its workspace outside version control and synchronize
CCux into a dedicated disk directory:

```sh
tools/sync-ocelot.sh ocelot/<ccux-disk-uuid>
```

The script backs up an existing `init.lua`. Do not point it at an OpenOS or
MineOS reference disk.

## Boot layout

Install this repository as `/ccux` on an OpenComputers boot disk and copy
`/ccux/boot/opencomputers.lua` to `/init.lua`. The EEPROM alternative is
`boot/opencomputers-eeprom.lua`.

On CC: Tweaked, install the repository as `/ccux`, place `bios.lua` at `/bios.lua`,
and run the attributed `unbios.lua` from startup. A development layout with
`boot/`, `src/`, and `rootfs/` at disk root also works.

`unbios.lua` retains its original MIT attribution to JackMacWindows. CCux uses
OpenOS and Phoenix as behavioral references; their code is not copied here.
