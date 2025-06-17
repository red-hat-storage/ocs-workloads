#!/bin/sh

# === Color codes for output ===
Cyan='\033[0;36m'
Yellow='\033[1;33m'
NC='\033[0m' # No Color

# === Constants ===
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"
LAST_PODFILE="$MOUNT/last_podname"
NAMESPACE="${KUBERNETES_NAMESPACE:-default}"
CURRENT_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"

# === Save CURRENT_PODNAME at script start ===
echo "$CURRENT_PODNAME" > "$LAST_PODFILE"
echo "📁 Saved initial pod name to $LAST_PODFILE: $CURRENT_PODNAME"

# === Load LAST_PODNAME ===
LAST_PODNAME=$(cat "$LAST_PODFILE" | tr -d '\n' | xargs)

# === Trap to handle termination signals (SIGINT, SIGTERM) ===
cleanup() {
    echo "🛑 Received termination signal! Syncing data and exiting..."
    sync
    touch "$MOUNT/trap_$(date +%s)"
    exit 1
}
trap cleanup SIGINT SIGTERM

# === Main loop ===
while true; do
    CURRENT_PODNAME="${KUBERNETES_POD_NAME:-unknownpod}"
    timestamp=$(date +%s)
    file="$MOUNT/${CURRENT_PODNAME}_${NAMESPACE}_${timestamp}"

    printf "📄 Creating file: ${Cyan}$file${NC}\n"
    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct

    md5sum "$file" >> "$HASHFILE"
    sync

    echo "🔁 Comparing pod names: CURRENT='$CURRENT_PODNAME' | LAST='$LAST_PODNAME'"
    if [ "$CURRENT_PODNAME" != "$LAST_PODNAME" ]; then
        echo "${Yellow}⚠️ Pod name changed from $LAST_PODNAME to $CURRENT_PODNAME${NC}"

        last_file=$(ls "$MOUNT"/${LAST_PODNAME}_${NAMESPACE}_* 2>/dev/null | sort | tail -n 1)
        current_file="$file"

        if [ -n "$last_file" ]; then
            old_ts=$(echo "$last_file" | awk -F'_' '{print $3}')
            new_ts=$(echo "$current_file" | awk -F'_' '{print $3}')
            timediff=$((new_ts - old_ts))

            echo "${Yellow}⏱️ Time diff: ${timediff} seconds${NC}"

            pod_uid=$(kubectl get pod "$CURRENT_PODNAME" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' 2>/dev/null)

            if [ -n "$pod_uid" ]; then
                event_name="pod-switch-$(date +%s)"
                echo "📢 Creating event '$event_name' for pod '$CURRENT_PODNAME'"

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

                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    echo "❌ Event creation failed:"
                    cat /tmp/kubectl_event.log
                fi
            else
                echo "❌ Failed to retrieve pod UID for $CURRENT_PODNAME"
            fi
        fi

        # === Update LAST_PODNAME file ===
        LAST_PODNAME="$CURRENT_PODNAME"
        if echo "$LAST_PODNAME" > "$LAST_PODFILE"; then
            echo "✅ Updated $LAST_PODFILE with pod name: $LAST_PODNAME"
        else
            echo "❌ Failed to write to $LAST_PODFILE"
        fi
    fi

    sleep_time=$((RANDOM % 15 + 1))
    echo "😴 Sleeping for $sleep_time seconds..."
    sleep "$sleep_time" &
    wait $!

    if [ $((RANDOM % 2)) -eq 1 ]; then
        echo "🔍 Running random hash check..."
        md5sum -c --quiet "$HASHFILE"
    fi
done
