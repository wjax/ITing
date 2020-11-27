#!/bin/bash

#This script creates a clone from latest ZFS Snapshot and borg-back-up a given path inside

usage () {
    echo "This script creates a clone from latest ZFS Snapshot and borg-back-up a given path inside"
        echo ""
        echo "usage: cloneborging.sh zfs_dataset clone_destination borg_repo [-p=borg_password] [-i=folder] [-r=d,w,m] [-w=60]"
    echo "  zfs_dataset     	ZFS dataset to clone last snapshot and backup"
	echo "	clone_destination   Clone mnt point relative to pool"
	echo "	borg_repo			Borg Repo path"
	echo "  -p     				password of the borg repo"
    echo "  -i     				include folder"
	echo "  -w     				wait seconds to previous script to finish"
	echo "  -r     				retention, day, week, month"
    exit 1
}

get_mountpoint () {
	local mtn_line=$(zfs get mountpointzfs get -H -o "value"  mountpoint $1)
	return $"mnt_line"
}


# Default options
WAIT="0"
BORG_RETENTION_DAYS="7"
BORG_RETENTION_WEEKS="4"
BORG_RETENTION_MONTHS="3"
PASSWORD=""
INCLUDE_FOLDERS=""

# Positional arguments
SRC="$1"
DST="$2"
BORG="$3"

# Number arguments
ARGV=$#

# Parse arguments
for i in "$@"
do
case $i in
    -w=*|--wait=*)
    WAIT="${i#*=}"
    let "ARGV-=1"
    shift # past argument=value
    ;;
    -r=*|--retention=*)
    RETENTION="${i#*=}"
    let "ARGV-=1"
    shift # past argument=value
    ;;
    *)
          # unknown option
    ;;
esac
done

if [ $ARGV -ne 3 ]; then
    usage
fi

# Check if already running and wait
LOCK_FILE=/var/lock/cloneborging.lock
exec 99>"$LOCK_FILE"
flock -w $WAIT 99
RC=$?
if [ "$RC" != 0 ]; then
    # Send message and exit
    echo "Already running script. Exiting"
    exit 1
fi
#-------------------------------------

echo ""
echo "Selected options:"
echo "ZFS Source = $SRC"
echo "Clone Mnt point = $DST"
echo "-w = $WAIT"
echo "-r = $BORG_RETENTION_DAYS, $BORG_RETENTION_WEEKS, $BORG_RETENTION_MONTHS"
echo "-i = $INCLUDE_FOLDERS"
echo "Starting ..."

# Do stuff

# Create a first snapshot and a full replication only if destination has no snapshot
last_snapshot=$(zfs list -H -t snapshot -o name -S creation -d1 "$SRC" | head -1)

if [ -z "$last_snapshots" ]; then
    # First replication
    echo "No Snapshots available. Exiting"
    exit 1
else
    # Clone
    echo "Clone snapshot"
	pool=${last_snapshot%%/*}
	zfs clone $last_snapshot $pool$DST
	if [ $? -eq 0 ]; then
		echo "Clone created and ready"
		mnt_point=get_mountpoint 
	else
		echo "Problem creating clone. Exiting"
		exit 1
	fi
    # Get name of last snapshot in destination dataset
    last_snapshot_in_destination=$(zfs list -H -t snapshot -o name -S creation -d1 "$DST" | head -1)
    # Transform name to source dataset snapshot name
    last_replicated_snapshot_in_source="$SRC"@${last_snapshot_in_destination#*@}
    zfsnap snapshot -rv -a "$RETENTION" "$SRC"
    latest_snapshot=$(zfs list -H -t snapshot -o name -S creation -d1 "$SRC" | head -1)
    diff_snapshots=$(zfs diff "$last_replicated_snapshot_in_source" "$latest_snapshot")
    if [ -n "$diff_snapshots" ]; then
       echo "Changes exists. Replicate"
       zfs send -RI "$last_replicated_snapshot_in_source" "$latest_snapshot" | zfs recv -Fu "$DST"
    else
       echo "No changes detected. No need to replicate"
    fi
    zfsnap destroy -rv "$SRC"
fi
