#!/bin/sh

# === Color Codes ===
Cyan='\033[0;36m'
Yellow='\033[1;33m'
Red='\033[0;31m'
NC='\033[0m' # No Color

# === Constants ===
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"
LAST_PODFILE="$MOUNT/last_podname"
NAMESPACE="${KUBERNETES_NAMESPACE:-default}"
CURRENT_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"

# === Load last known pod name ===
if [ -f "$LAST_PODFILE" ]; then
    LAST_PODNAME=$(cat "$LAST_PODFILE")
else
    LAST_PODNAME="$CURRENT_PODNAME"
fi

# === Signal Handling ===
cleanup() {
    echo "${Yellow}Termination signal received. Syncing data...${NC}"
    sync
    touch "$MOUNT/trap_$(date +%s)"
    exit 0
}
trap cleanup SIGINT SIGTERM

# === Main Loop ===
while true; do
    CURRENT_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"
    timestamp=$(date +%s)
    file="$MOUNT/${CURRENT_PODNAME}_${NAMESPACE}_${timestamp}"

    printf "Creating file: ${Cyan}%s${NC}\n" "$file"
    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct

    md5sum "$file" >> "$HASHFILE"
    sync

    if [ "$CURRENT_PODNAME" != "$LAST_PODNAME" ]; then
        echo "${Yellow}Detected pod switch: $LAST_PODNAME ➝ $CURRENT_PODNAME${NC}"

        last_file=$(ls "$MOUNT"/${LAST_PODNAME}_${NAMESPACE}_* 2>/dev/null | sort | tail -n 1)
        old_ts=$(echo "$last_file" | awk -F'_' '{print $3}')
        new_ts="$timestamp"
        timediff=$((new_ts - old_ts))

        echo "${Yellow}Time since last pod: ${timediff} seconds${NC}"

        pod_uid=$(kubectl get pod "$CURRENT_PODNAME" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' 2>/dev/null)
        if [ -z "$pod_uid" ]; then
            echo "${Red}Error: Could not fetch pod UID for $CURRENT_PODNAME${NC}"
        else
            event_name="pod-switch-$(date +%s)"
            echo "Creating event: $event_name"

            cat <<EOF | kubectl apply -f - | tee /tmp/kubectl_event.log
apiVersion: v1
kind: Event
metadata:
  name: "$event_name"
  namespace: "$NAMESPACE"
involvedObject:
  kind: Pod
  namespace: "$NAMESPACE"
  name: "$CURRENT_PODNAME"
  apiVersion: v1
  uid: "$pod_uid"
reason: PodNameChange
message: "Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME. Time diff: ${timediff}s."
type: Normal
source:
  component: pod-monitor-script
firstTimestamp: "$(date -Iseconds)"
lastTimestamp: "$(date -Iseconds)"
count: 1
EOF
        fi

        LAST_PODNAME="$CURRENT_PODNAME"
        if echo "$LAST_PODNAME" > "$LAST_PODFILE"; then
            echo "✅ Saved LAST_PODNAME to $LAST_PODFILE"
        else
            echo "❌ Failed to write LAST_PODNAME to $LAST_PODFILE"
            ls -ld "$MOUNT" "$LAST_PODFILE"
        fi
    else
        echo "❌ Skipped iff check"
    fi

    # Sleep with interrupt support
    sleep_time=$((RANDOM % 15 + 1))
    echo "Sleeping for $sleep_time seconds..."
    sleep "$sleep_time" & SLEEP_PID=$!
    wait "$SLEEP_PID"

    # Optional integrity check
    if [ $((RANDOM % 2)) -eq 1 ]; then
        echo "Verifying file integrity..."
        md5sum -c --quiet "$HASHFILE" || echo "${Red}Warning: File hash mismatch detected!${NC}"
    fi
done
