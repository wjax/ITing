#!/bin/sh

# This Script creates a new snapshot in the source ZFS dataset and replicate source dataset into destination/backup dataset

if [ $# -ne 3 ]; then
    echo "Usage: snapgration.sh SRC_Dataset DST_Dataset retention"
    return 1
fi

src_dataset="$1"
dst_dataset="$2"
snapshot_retention="$3"

# Create a first snapshot and a full replication only if destination is snapshot empty
existing_snapshots_dst=$(zfs list -H -t snapshot -o name -S creation -d1 "$dst_dataset")

if [ -z "$existing_snapshots_dst" ]; then
    # First replication
    echo "First replication"
    zfsnap snapshot -rv -a "$snapshot_retention" "$src_dataset"
    zfs send -R "$(zfs list -H -t snapshot -o name -S creation -d1 "$src_dataset" | head -1)" | zfs recv -Fu "$dst_dataset"
else
    # Incremental migration
    echo "Incremental replication"
    # Get name of last snapshot in destination dataset
    last_snapshot_in_destination=$(zfs list -H -t snapshot -o name -S creation -d1 "$dst_dataset" | head -1)
    # Transform name to source dataset snapshot name
    last_replicated_snapshot_in_source="$src_dataset"@${last_snapshot_in_destination#*@}
    zfsnap snapshot -rv -a "$snapshot_retention" "$src_dataset"
    latest_snapshot=$(zfs list -H -t snapshot -o name -S creation -d1 "$src_dataset" | head -1)
    zfs send -RI "$last_replicated_snapshot_in_source" "$latest_snapshot" | zfs recv -Fu "$dst_dataset"
    zfsnap destroy -rv "$src_dataset"
fi
