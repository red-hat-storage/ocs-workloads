#!/bin/sh

# Color codes for formatted output
Cyan='\033[0;36m'         
NC='\033[0m' # No Color

# Constants
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"

# Trap to handle termination signals (SIGINT, SIGTERM)
cleanup() {
    echo "Received termination signal! Syncing data and exiting..."
    sync
    touch "$MOUNT/trap_$(date +%s)"
    exit 1
}

trap cleanup SIGINT SIGTERM

# Main loop
while true; do
    hostname=$(hostname -f)
    file="$MOUNT/data_$(date +%s)_$hostname"
    
    printf "Creating file with name: ${Cyan}$file${NC}\n"

    # Write random data to file
    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct

    # Compute and store hash
    md5sum "$file" >> "$HASHFILE"
    sync

    # Random sleep with trap awareness
    sleep_time=$((RANDOM % 15 + 1))
    echo "Sleeping for $sleep_time seconds..."
    sleep "$sleep_time" &
    SLEEP_PID=$!
    wait "$SLEEP_PID"

    # Perform random integrity check
    if [ $((RANDOM % 2)) -eq 1 ]; then
        md5sum -c --quiet "$HASHFILE"
    fi
done
