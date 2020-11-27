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

tmpfile=$(mktemp)
savepwd=${PWD}

mountpoint=$1
shift
pools=
for it in $@
do
    [ ${it} == '--' ] && break
    pools="${pools} ${it}"
    shift
done

if [ "$1" == '--' ]
then
    shift
else
    >&2 echo "Supply me a command to run. I will cd to the root of the mount before running it."
    exit 1
fi
snapname=backup-$(date -u +%s)

if [ ! -d $mountpoint ]
then
    >&2 echo "${mountpoint} doesn't exist."
    exit 1
fi

poolsnaps=
for pool in $pools
do
    poolsnaps="${poolsnaps} ${pool}@${snapname}"
done


cleanup() {
    set +e
    cd ${savepwd}
    if [ $mounted ]
    then
        for path in $(tac <<< $mountorder)
        do
                if [ -d ${path}/.zfs ]
                then
                        path=$(echo ${path} | tr -s /)
                        relativepath=${path#"$basepath"}
                        itemmountpoint=$(echo ${mountpoint}/${relativepath} | tr -s /)

#                       echo "umount ${itemmountpoint}"
                        umount $(echo ${itemmountpoint} | tr -s /)
                fi
        done
    fi
    [ $zfs_hold ] && zfs release -r ${snapname} ${poolsnaps}
    if [ $zfs_snapshot ]
    then
        for snap in ${poolsnaps}
        do
            zfs destroy -r ${snap}
        done
    fi
    [ -f $tmpfile ] && rm $tmpfile
}


set -e
trap cleanup INT TERM EXIT

zfs_snapshot=1
for snap in ${poolsnaps}
do
    zfs snapshot -r ${snap}
done

zfs hold -r ${snapname} ${poolsnaps}
zfs_hold=1

# find snapshots that are of mounted filesystems only
allsnaps=$(zfs holds -Hr ${poolsnaps} | awk '{ print $1; }')
cat <<EOF | sed -e "s/@${snapname}\$//g" | xargs zfs list -Hpo name,mountpoint | awk '$2 != "none" { print $0; }' > ${tmpfile}
${allsnaps}
EOF

# order the mounts.
# we need to mount things shallow-first
mountorder=$(while read name path
do
    if [ ${path} != '/' ]
    then
        echo "${name}|${path}|$(echo "${path}" | tr -dc / | wc -c)"
    else
        echo "${name}|${path}|0"
    fi
done < ${tmpfile} | sort -n -t\| -k3 -k2 | awk -F\| '{ print $2; }')

rm ${tmpfile}

#echo "${mountorder}"
#IFS=0 read -r -a arraymountpoints <<< "${mountorder}"
basepath=$(echo "${mountorder}" | cut -d$'\n' -f1)
#echo ${mountorder%%"\n"}

for path in ${mountorder}
do
    mounted=1
    path=$(echo ${path} | tr -s /)
    relativepath=${path#"$basepath"}
    itemmountpoint=$(echo ${mountpoint}/${relativepath} | tr -s /)
    if [ -d "${path}/.zfs" ]
    then
#       [ ! -d "${subpath}" ] && mkdir "${subpath}"
#       echo "mount ${itemmountpoint}"
        mount -o ro,bind $(echo "${path}/.zfs/snapshot/${snapname}" | tr -s /) "${itemmountpoint}"
    else
        # silently do nothing
        echo "this path is unmounted, presumably because the canmount property is set to no"
    fi
done

cd ${mountpoint}

"$@"
