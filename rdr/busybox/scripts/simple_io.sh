# #!/bin/sh

# # Color codes for formatted output
# Cyan='\033[0;36m'
# Yellow='\033[1;33m'
# NC='\033[0m' # No Color

# # Constants
# MOUNT="/mnt/test"
# HASHFILE="$MOUNT/hashfile"
# PYTHON_EVENT_SCRIPT="/mnt/test/create_event.py"

# # Get initial pod name and namespace from environment
# LAST_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"
# NAMESPACE="${KUBERNETES_NAMESPACE:-default}"

# # Trap to handle termination signals (SIGINT, SIGTERM)
# cleanup() {
#     echo "Received termination signal! Syncing data and exiting..."
#     sync
#     touch "$MOUNT/trap_$(date +%s)"
#     exit 1
# }

# trap cleanup SIGINT SIGTERM

# # Main loop
# while true; do
#     CURRENT_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"
#     timestamp=$(date +%s)
#     file="$MOUNT/${CURRENT_PODNAME}_${NAMESPACE}_${timestamp}"

#     printf "Creating file with name: ${Cyan}$file${NC}\n"

#     # Write random data to file
#     dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct

#     # Compute and store hash
#     md5sum "$file" >> "$HASHFILE"
#     sync

#     # If pod name has changed, emit event
#     if [ "$CURRENT_PODNAME" != "$LAST_PODNAME" ]; then
#         echo "${Yellow}Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME${NC}"

#         last_file=$(ls "$MOUNT"/${LAST_PODNAME}_${NAMESPACE}_* 2>/dev/null | sort | tail -n 1)
#         current_file="$file"

#         if [ -n "$last_file" ]; then
#             old_ts=$(echo "$last_file" | awk -F'_' '{print $3}')
#             new_ts=$(echo "$current_file" | awk -F'_' '{print $3}')
#             timediff=$((new_ts - old_ts))

#             echo "${Yellow}Time difference between last and current pod file: ${timediff} seconds${NC}"

#             # Get pod UID
#             pod_uid=$(kubectl get pod "$CURRENT_PODNAME" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' 2>/dev/null)

#             if [ -n "$pod_uid" ]; then
#                 echo "Calling Python script to create event..."
#                 echo "Running Python event script:"
#                 echo python3 "$PYTHON_EVENT_SCRIPT" "$CURRENT_PODNAME" "$pod_uid" "$NAMESPACE" "$LAST_PODNAME" "$timediff"

#                 /mnt/test/venv/bin/python3 "$PYTHON_EVENT_SCRIPT" "$CURRENT_PODNAME" "$pod_uid" "$NAMESPACE" "$LAST_PODNAME" "$timediff"
#             else
#                 echo "Failed to get pod UID for $CURRENT_PODNAME"
#             fi
#         fi

#         LAST_PODNAME="$CURRENT_PODNAME"
#     fi

#     # Random sleep with trap awareness
#     sleep_time=$((RANDOM % 15 + 1))
#     echo "Sleeping for $sleep_time seconds..."
#     sleep "$sleep_time" &
#     SLEEP_PID=$!
#     wait "$SLEEP_PID"

#     # Random integrity check
#     if [ $((RANDOM % 2)) -eq 1 ]; then
#         md5sum -c --quiet "$HASHFILE"
#     fi
# done


#!/bin/sh

# Color codes for formatted output
Cyan='\033[0;36m'
Yellow='\033[1;33m'
NC='\033[0m' # No Color

# Constants
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"
LAST_PODFILE="$MOUNT/last_podname"

# Load last pod name from file if exists, else use env/default
if [ -f "$LAST_PODFILE" ]; then
    LAST_PODNAME=$(cat "$LAST_PODFILE")
else
    LAST_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"
fi

NAMESPACE="${KUBERNETES_NAMESPACE:-default}"

# Trap to handle termination signals (SIGINT, SIGTERM)
cleanup() {
    echo "Received termination signal! Syncing data and exiting..."
    sync
    touch "$MOUNT/trap_$(date +%s)"
    exit 1
}

trap cleanup SIGINT SIGTERM

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

            # Get pod UID for involvedObject
            pod_uid=$(kubectl get pod "$CURRENT_PODNAME" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')

            # Unique event name (cannot use generateName with kubectl create -f)
            event_name="pod-switch-$(date +%s)"

            echo "Creating event $event_name for pod $CURRENT_PODNAME in $NAMESPACE"

            kubectl create -f - <<EOF 2>&1 | tee /tmp/kubectl_event.log
apiVersion: v1
kind: Event
metadata:
  name: $event_name
  namespace: $NAMESPACE
involvedObject:
  kind: Pod
  namespace: $NAMESPACE
  name: $CURRENT_PODNAME
  apiVersion: v1
  uid: $pod_uid
reason: PodNameChange
message: Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME. Time diff: ${timediff}s.
type: Normal
source:
  component: pod-monitor-script
firstTimestamp: "$(date -Iseconds)"
lastTimestamp: "$(date -Iseconds)"
count: 1
EOF

            # Check if event creation failed
            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                echo "Event creation failed:"
                cat /tmp/kubectl_event.log
            fi
        fi

        # Update LAST_PODNAME and save to file
        LAST_PODNAME="$CURRENT_PODNAME"
        echo "$LAST_PODNAME" > "$LAST_PODFILE"
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
