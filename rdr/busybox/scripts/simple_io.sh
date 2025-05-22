#!/bin/sh

# Color codes for formatted output
Cyan='\033[0;36m'
Yellow='\033[1;33m'
NC='\033[0m' # No Color

# Constants
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"

# Get initial pod name and namespace from environment
LAST_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"
NAMESPACE="${KUBERNETES_NAMESPACE:-default}"

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
    CURRENT_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"
    timestamp=$(date +%s)
    file="$MOUNT/${CURRENT_PODNAME}_${NAMESPACE}_${timestamp}"

    printf "Creating file with name: ${Cyan}$file${NC}\n"

    # Write random data to file
    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct

    # Compute and store hash
    md5sum "$file" >> "$HASHFILE"
    sync

    # If pod name has changed, calculate time difference and emit event
    if [ "$CURRENT_PODNAME" != "$LAST_PODNAME" ]; then
        echo "${Yellow}Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME${NC}"

        last_file=$(ls "$MOUNT"/${LAST_PODNAME}_${NAMESPACE}_* 2>/dev/null | sort | tail -n 1)
        current_file="$file"

        if [ -n "$last_file" ]; then
            old_ts=$(echo "$last_file" | awk -F'_' '{print $3}')
            new_ts=$(echo "$current_file" | awk -F'_' '{print $3}')
            timediff=$((new_ts - old_ts))

            echo "${Yellow}Time difference between last and current pod file: ${timediff} seconds${NC}"

            # Create Kubernetes event
            kubectl create -f - <<EOF
apiVersion: v1
kind: Event
metadata:
  generateName: pod-switch-
  namespace: $NAMESPACE
involvedObject:
  kind: Pod
  namespace: $NAMESPACE
  name: $CURRENT_PODNAME
  apiVersion: v1
reason: PodNameChange
message: Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME. Time diff: ${timediff}s.
type: Normal
source:
  component: pod-monitor-script
firstTimestamp: "$(date -Iseconds)"
lastTimestamp: "$(date -Iseconds)"
count: 1
EOF
        fi

        LAST_PODNAME="$CURRENT_PODNAME"
    fi

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
