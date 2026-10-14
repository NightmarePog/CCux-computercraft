#!/bin/sh
set -eu
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "usage: $0 <ocelot-ccux-disk-directory>" >&2
  exit 2
fi
marker="$1/.ccux-profile-next-boot"
printf '%s\n' enabled > "$marker.ccux-new"
mv -f "$marker.ccux-new" "$marker"
echo "Memory profiling enabled for the next CCux boot"
