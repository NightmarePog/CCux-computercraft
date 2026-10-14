#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "usage: $0 <ocelot-ccux-disk-directory>" >&2
  exit 2
fi

target=$1
if [ -e "$target/init.lua" ] && [ ! -e "$target/init.lua.ccux-backup" ]; then
  cp "$target/init.lua" "$target/init.lua.ccux-backup"
fi
mkdir -p "$target/ccux"

copy_tree() {
  source_root=$1
  destination_root=$2
  find "$source_root" -type d | while IFS= read -r directory; do
    relative=${directory#"$source_root"}
    mkdir -p "$destination_root$relative"
  done
  find "$source_root" -type f | while IFS= read -r source; do
    relative=${source#"$source_root"/}
    destination="$destination_root/$relative"
    cp "$source" "$destination.ccux-new"
    mv -f "$destination.ccux-new" "$destination"
  done
}

copy_tree src "$target/ccux/src"
copy_tree rootfs "$target/ccux/rootfs"
copy_tree boot "$target/ccux/boot"
cp boot/opencomputers.lua "$target/init.lua.ccux-new"
mv -f "$target/init.lua.ccux-new" "$target/init.lua"
echo "CCux synchronized to $target"
