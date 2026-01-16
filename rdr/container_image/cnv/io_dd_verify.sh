#!/bin/sh
#
# Continuous dd I/O with integrity verification across VM restarts
# Designed for CirrOS (BusyBox init)
#

MOUNT="/run_io"
HASHFILE="$MOUNT/checksums.md5"
LOGFILE="$MOUNT/script.log"

mkdir -p "$MOUNT"

log() {
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    printf "%s [INFO] %s\n" "$ts" "$*" | tee -a "$LOGFILE"
}

cleanup() {
    log "Received termination signal, syncing and exiting"
    sync
    exit 0
}

trap cleanup SIGINT SIGTERM

hostname=$(hostname 2>/dev/null || echo unknown)

log "===== VM boot detected ====="
log "Hostname: $hostname"

if [ -f "$HASHFILE" ]; then
    log "Verifying existing data"
    if md5sum -c "$HASHFILE" >>"$LOGFILE" 2>&1; then
        log "Integrity check PASSED"
    else
        log "Integrity check FAILED"
    fi
else
    log "No checksum file found, starting fresh"
fi

while true; do
    file="$MOUNT/data_$(date +%s)_${hostname}"

    log "Writing file: $file"

    dd if=/dev/urandom of="$file" \
       bs=4k \
       count=$((RANDOM % 8 + 1)) \
       oflag=direct \
       >>"$LOGFILE" 2>&1

    rc=$?
    if [ "$rc" -ne 0 ]; then
        log "dd failed (rc=$rc), removing partial file"
        rm -f "$file"
        sync
        sleep 1
        continue
    fi

    md5sum "$file" >>"$HASHFILE" 2>>"$LOGFILE"
    sync

    sleep $((RANDOM % 10 + 1))
done
