#!/bin/bash

# This Script creates a new snapshot in the source ZFS dataset and replicate source dataset into destination/backup dataset

function usage {
    echo "This script creates a new snapshot in the source ZFS and replicates it into destination/backup ZFS if there are changes from last snapshot"
        echo ""
        echo "usage: snapgration.sh  source destination [-w=time] [-r=retention]"
    echo "  -w      wait seconds in case another instance is running. 0 if not provided"
    echo "  -r      snapshot retention as per zfsnap. 1m (month) if not provided"
    exit 1
}


# Default options
WAIT="0"
RETENTION="1m"

# Positional arguments
SRC="$1"
DST="$2"

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

if [ $ARGV -ne 2 ]; then
    usage
fi

# Check if already running and wait
LOCK_FILE=/var/lock/snapgration.lock
exec 99>"$LOCK_FILE"
flock -w $WAIT 99
RC=$?
if [ "$RC" != 0 ]; then
    # Send message and exit
    echo "Already running script. Exiting"
    exit 1
fi

echo ""
echo "Selected options:"
echo "SRC = $SRC"
echo "DST = $DST"
echo "-w = $WAIT"
echo "-r = $RETENTION"
echo ""
echo "Starting ..."

# Do stuff

# Create a first snapshot and a full replication only if destination has no snapshot
existing_snapshots_dst=$(zfs list -H -t snapshot -o name -S creation -d1 "$DST")

if [ -z "$existing_snapshots_dst" ]; then
    # First replication
    echo "First replication"
    zfsnap snapshot -rv -a "$RETENTION" "$SRC"
    zfs send -R "$(zfs list -H -t snapshot -o name -S creation -d1 "$SRC" | head -1)" | zfs recv -Fu "$DST"
else
    # Incremental migration
    echo "Incremental replication"
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
