#!/bin/sh

# Color codes for formatted output
Cyan='\033[0;36m'
NC='\033[0m'

# Constants
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"
LOGFILE="$MOUNT/script.log"

# Simple logger: level, message...
log() {
    level=$1
    shift
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    # write to stdout and append to logfile (best-effort)
    printf "%s [%s] %s\n" "$ts" "$level" "$*" | tee -a "$LOGFILE"
}

# Trap to handle termination signals (SIGINT, SIGTERM)
cleanup() {
    log INFO "Received termination signal! Syncing data and exiting..."

    if [ -n "$SLEEP_PID" ] && kill -0 "$SLEEP_PID" 2>/dev/null; then
        log INFO "Killing background sleep (pid $SLEEP_PID)"
        kill "$SLEEP_PID" 2>/dev/null
    fi

    sync
    touch "$MOUNT/trap_$(date +%s)"
    log INFO "Exiting cleanly"
    exit 0
}

trap cleanup SIGINT SIGTERM

hostname=$(hostname -f 2>/dev/null || hostname)
node="${NODE_NAME:-unknown}"

# Main loop
while true; do
    file="$MOUNT/data_$(date +%s)_${hostname}_${node}"

    log INFO "Creating file with name: ${file}"

    # Write random data to file
    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct 2>>"$LOGFILE"
    dd_status=$?
    if [ "$dd_status" -ne 0 ]; then
        log ERROR "dd failed with status $dd_status; removing partial file $file"
        rm -f "$file"
        sync
        # short backoff before continuing loop
        sleep 1
        continue
    fi

    # Compute and store hash
    md5sum "$file" >> "$HASHFILE" 2>>"$LOGFILE" || log WARN "Failed to append hash for $file"
    sync

    # Random sleep with trap awareness
    sleep_time=$((RANDOM % 15 + 1))
    log INFO "Sleeping for $sleep_time seconds..."
    sleep "$sleep_time" &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
    SLEEP_PID=

    # Perform random integrity check
    if [ $((RANDOM % 2)) -eq 1 ]; then
        if md5sum -c --quiet "$HASHFILE"; then
            log INFO "Integrity check passed"
        else
            log WARN "Integrity check found problems (see md5sum output)"
        fi
    fi
done
