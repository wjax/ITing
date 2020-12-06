#!/bin/bash

# Copyright (c) 2016 Erick Turnquist <jhujhiti@adjectivism.org>
# Adapted to Linux by Jesus Alvarez wjaxxx@gmail.com

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Usage:
# with-zfs-snapshots <mountpoint> <zpool>[ <zpool>...] -- <command>

# This script will run the supplied command on a recursive snapshot of the supplied zpools.  Snapshots will be taken of each
# filesystem on <zpool>s and those snapshots will be nullfs-mounted rooted at <mountpoint>. The script will then cd to that
# directory (*not* chroot) and run the supplied command. Mounts and snapshots are cleaned up afterwards.

# N.B. Don't put spaces or pipes (|) in your filesystem names or paths. Bad things will probably happen.

# This was written and tested on FreeBSD 10.2. I use a 132-column wide terminal. Deal with it.

# 1)  Snapshot the pools
# 2)  Set holds on the snapshots. This both protects the snapshots while we work with them and makes it easier to identify the
#     filesystems we want for the next step.
# 3)  Find the filesystems with a mountpoint set.
# 4)  Sort the identified filesystems by depth of the mount, shallow first.
# 5)  Bind mount the filesystems in that order.
# 6)  Move into the mountpoint directory.
# 7)  Run the supplied command.
# 8)  Unmount the filesystems in the reverse order.
# 9)  Release the holds.
# 10) Destroy the snapshots.


cleanup() {
    set +e
    cd ${savepwd}
    [ $mounted ] && umount -R "$mountpoint"
    [ $zfs_hold ] && zfs release -r "${snapname}" "${snapshot}"
    [ $zfs_snapshot ] && zfs destroy -r "${snapshot}"
    [ ! "$(ls -A $mountpoint)" ] && rm -rf "$mountpoint"
}

# Setup things
savepwd="${PWD}"

# Mount point argument
mountpoint="$1"
if [ ! -d $mountpoint ]
then
    >&2 echo "${mountpoint} doesn't exist."
    exit 1
fi
shift

# Pool argument
pool="$1"
shift


# Prepare mountpoint
NEW_UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
mountpoint="$mountpoint/$NEW_UUID"
mkdir "$mountpoint"

# Snapshot name
snapname=backup-$(date -u +%s)
# Pool/snapshot
snapshot="${pool}@${snapname}"

set -e
trap cleanup INT TERM EXIT

# Perform snapshot
zfs_snapshot=1
zfs snapshot -r "${snapshot}"

# Hold this snapshot
zfs hold -r "${snapname}" "${snapshot}"
zfs_hold=1

# List all snapshots recursively
allsnaps=$(zfs holds -Hr "${snapshot}" | awk '{ print $1; }')

# Mount snapshots

for snap in $allsnaps
do
   mounted=1
   relativepath=${snap%@*}
   relativepath=${relativepath#"$pool"}
   itemmountpoint=$(echo ${mountpoint}/${relativepath} | tr -s /)
   mount -t zfs,ro "$snap" "$itemmountpoint"
done

#Execute command
cd "${mountpoint}"
#echo $(pwd)
eval "$@"

# Clean and umount
#cleanup
