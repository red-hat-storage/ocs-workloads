#!/bin/bash

# Color codes
Cyan='\033[0;36m'
Yellow='\033[1;33m'
NC='\033[0m'

# Constants
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"
LAST_PODFILE="$MOUNT/last_podname"

# Load ServiceAccount values
TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
CA_CERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
NAMESPACE_FILE="/var/run/secrets/kubernetes.io/serviceaccount/namespace"

# Read namespace
NAMESPACE=$(cat "$NAMESPACE_FILE")
API_SERVER="https://kubernetes.default.svc"

# Get current pod name
CURRENT_PODNAME=$(hostname)

# Load last pod name from file if it exists
if [ -f "$LAST_PODFILE" ]; then
    LAST_PODNAME=$(cat "$LAST_PODFILE")
else
    LAST_PODNAME="$CURRENT_PODNAME"
fi

# Trap to handle termination
cleanup() {
    echo "Received termination signal! Syncing data and exiting..."
    sync
    touch "$MOUNT/trap_$(date +%s)"
    exit 1
}
trap cleanup SIGINT SIGTERM

# Function to create event via Kubernetes API
create_event_directly() {
    local token
    token=$(cat "$TOKEN_FILE")

    local event_json
    event_json=$(cat <<EOF
{
  "apiVersion": "v1",
  "kind": "Event",
  "metadata": {
    "name": "$event_name",
    "namespace": "$NAMESPACE"
  },
  "involvedObject": {
    "kind": "Pod",
    "namespace": "$NAMESPACE",
    "name": "$CURRENT_PODNAME",
    "apiVersion": "v1",
    "uid": "$pod_uid"
  },
  "reason": "PodNameChange",
  "message": "Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME. Time diff: ${timediff}s.",
  "type": "Normal",
  "source": {
    "component": "pod-monitor-script"
  },
  "firstTimestamp": "$first_ts",
  "lastTimestamp": "$last_ts",
  "count": 1
}
EOF
    )

    echo "$event_json" > "$MOUNT/event_${event_name}.json"

    curl -sSk --cacert "$CA_CERT" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -X POST \
      -d @"$MOUNT/event_${event_name}.json" \
      "$API_SERVER/api/v1/namespaces/$NAMESPACE/events"
}

# Main loop
while true; do
    CURRENT_PODNAME=$(hostname)
    timestamp=$(date +%s)
    file="$MOUNT/${CURRENT_PODNAME}_${NAMESPACE}_${timestamp}"

    printf "Creating file with name: ${Cyan}$file${NC}\n"

    # Write data
    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct

    # Hash
    md5sum "$file" >> "$HASHFILE"
    sync

    # Pod name changed?
    if [ "$CURRENT_PODNAME" != "$LAST_PODNAME" ]; then
        echo "${Yellow}Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME${NC}"

        last_file=$(ls "$MOUNT"/${LAST_PODNAME}_${NAMESPACE}_* 2>/dev/null | sort | tail -n 1)
        current_file="$file"

        if [ -n "$last_file" ]; then
            old_ts=$(echo "$last_file" | awk -F'_' '{print $3}')
            new_ts=$(echo "$current_file" | awk -F'_' '{print $3}')
            timediff=$((new_ts - old_ts))

            echo "${Yellow}Time difference between last and current pod file: ${timediff} seconds${NC}"

            # Get pod UID using Kubernetes API
            token=$(cat "$TOKEN_FILE")
            pod_uid=$(curl -sSk --cacert "$CA_CERT" \
    -H "Authorization: Bearer $token" \
    "$API_SERVER/api/v1/namespaces/$NAMESPACE/pods/$CURRENT_PODNAME" \
    | grep -o '"uid": *"[^"]*"' | head -n1 | sed 's/.*"uid": *"\([^"]*\)".*/\1/')
            event_name="pod-switch-$(date +%s)"
            first_ts=$(date -Iseconds)
            last_ts="$first_ts"

            echo "Creating event $event_name for pod $CURRENT_PODNAME"
            create_event_directly
        fi

        # Save new pod name
        LAST_PODNAME="$CURRENT_PODNAME"
        echo "$LAST_PODNAME" > "$LAST_PODFILE"
    fi

    # Sleep
    sleep_time=$((RANDOM % 15 + 1))
    echo "Sleeping for $sleep_time seconds..."
    sleep "$sleep_time" & wait $!

    # Random hash check
    if [ $((RANDOM % 2)) -eq 1 ]; then
        md5sum -c --quiet "$HASHFILE"
    fi
done
