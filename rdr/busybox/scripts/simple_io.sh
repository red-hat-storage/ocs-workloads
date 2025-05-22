#!/bin/sh

# Color codes for formatted output
Cyan='\033[0;36m'          
NC='\033[0m' # No Color

# Constants
MOUNT="/mnt/test"
HASHFILE="$MOUNT/hashfile"
KUBE_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"

# Variables to track previous state for time difference calculation
LAST_EPOCH_TIME=""
LAST_POD_NAME=""

# Trap to handle termination signals (SIGINT, SIGTERM, SIGHUP, SIGQUIT)
# This ensures that the cleanup function is called when the script receives
# these signals, allowing for graceful shutdown and data synchronization.
cleanup() {
    echo "Received termination signal! Syncing data and exiting..."
    sync # Ensure all buffered data is written to disk
    # Create a trap file to indicate cleanup was performed, useful for debugging
    touch "$MOUNT/trap_$(date +%s)"
    exit 1 # Exit with a non-zero status to indicate an abnormal termination
}

# Trap for common termination signals:
# SIGINT (Ctrl+C)
# SIGTERM (default signal sent by 'kill' or Kubernetes during graceful shutdown)
# SIGHUP (hangup, often sent when a controlling terminal closes)
# SIGQUIT (quit, similar to SIGINT but can produce a core dump)
trap cleanup SIGINT SIGTERM SIGHUP SIGQUIT

# Function to create a Kubernetes event
# Arguments: $1 = event_reason, $2 = event_message, $3 = event_type (Normal/Warning)
create_kubernetes_event() {
    local event_reason="$1"
    local event_message="$2"
    local event_type="$3"

    # Ensure POD_NAME and NAMESPACE are set before attempting to create an event
    if [ -z "$POD_NAME" ] || [ -z "$NAMESPACE" ]; then
        echo "Error: POD_NAME or NAMESPACE not set. Cannot create Kubernetes event."
        return 1
    fi

    # Check if Kubernetes API environment variables are set
    if [ -z "$KUBERNETES_SERVICE_HOST" ] || [ -z "$KUBERNETES_SERVICE_PORT" ]; then
        echo "Warning: Kubernetes API environment variables (KUBERNETES_SERVICE_HOST, KUBERNETES_SERVICE_PORT) not set. Cannot create event."
        return 1
    fi

    # Check if service account token exists
    if [ ! -f "$KUBE_TOKEN_PATH" ]; then
        echo "Warning: Kubernetes service account token not found at $KUBE_TOKEN_PATH. Cannot create event."
        return 1
    fi

    local KUBE_TOKEN=$(cat "$KUBE_TOKEN_PATH")
    local KUBE_API_SERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
    local CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # RFC3339 format for timestamps

    # Construct the JSON payload for the Kubernetes Event object
    # 'generateName' is used so Kubernetes automatically assigns a unique name.
    # 'involvedObject' links the event to the specific Pod.
    # 'source' indicates the component that generated the event.
    # 'firstTimestamp' and 'lastTimestamp' are required for events.
    local EVENT_JSON=$(cat <<EOF
{
  "apiVersion": "v1",
  "kind": "Event",
  "metadata": {
    "generateName": "data-writer-script-event-",
    "namespace": "$NAMESPACE"
  },
  "involvedObject": {
    "kind": "Pod",
    "namespace": "$NAMESPACE",
    "name": "$POD_NAME",
    "apiVersion": "v1"
  },
  "reason": "$event_reason",
  "message": "$event_message",
  "type": "$event_type",
  "source": {
    "component": "data-writer-script",
    "host": "$POD_NAME"
  },
  "firstTimestamp": "$CURRENT_TIMESTAMP",
  "lastTimestamp": "$CURRENT_TIMESTAMP",
  "count": 1
}
EOF
)

    echo "Attempting to create Kubernetes event: Reason='$event_reason', Message='$event_message'"

    # Send the POST request to the Kubernetes API server using wget
    # --post-data: Specifies the data to be sent in a POST request.
    # --header: Sets HTTP headers (Content-Type and Authorization).
    # --no-check-certificate: Disables SSL certificate validation. This is often
    #                         needed in Kubernetes for self-signed CAs when using wget,
    #                         as wget doesn't have a direct equivalent to curl's --cacert
    #                         for loading custom CA bundles for API calls.
    # -O /dev/null: Redirects the output to /dev/null to suppress verbose output.
    # -q: Quiet mode, suppresses wget's status messages.
    wget --post-data="$EVENT_JSON" \
         --header="Content-Type: application/json" \
         --header="Authorization: Bearer $KUBE_TOKEN" \
         --no-check-certificate \
         -O /dev/null \
         -q \
         "${KUBE_API_SERVER}/api/v1/namespaces/${NAMESPACE}/events"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to create Kubernetes event using wget. Check output for details or RBAC permissions."
    fi
}

# Main loop
while true; do
    # Get current epoch time for the file being created
    CURRENT_EPOCH_TIME=$(date +%s)

    # Get pod name: Prioritize KUBERNETES_POD_NAME, then HOSTNAME, then hostname command
    # In a typical Kubernetes environment, HOSTNAME usually corresponds to the pod name.
    POD_NAME="${KUBERNETES_POD_NAME:-${HOSTNAME:-$(hostname)}}"
    
    # Get namespace: Prioritize KUBERNETES_NAMESPACE, then MY_POD_NAMESPACE, then default
    NAMESPACE="${KUBERNETES_NAMESPACE:-${MY_POD_NAMESPACE:-"default"}}"
    
    # Generate the file name in the format: podname_namespace_epoctime
    file="$MOUNT/${POD_NAME}_${NAMESPACE}_${CURRENT_EPOCH_TIME}"
    
    printf "Creating file with name: ${Cyan}$file${NC}\n"

    # --- START: Temporary Test Event for Debugging ---
    # This event will be created in every loop iteration to confirm event creation is working.
    create_kubernetes_event "ScriptHeartbeat" \
                            "Data writer script is active in pod ${POD_NAME}." \
                            "Normal"
    # --- END: Temporary Test Event for Debugging ---

    # Calculate and show time difference if previous epoch time is available
    if [ -n "$LAST_EPOCH_TIME" ]; then
        TIME_DIFFERENCE=$((CURRENT_EPOCH_TIME - LAST_EPOCH_TIME))
        echo "Time difference since last file creation: ${TIME_DIFFERENCE} seconds"
        
        # Check if POD_NAME has changed since the last iteration
        if [ "$POD_NAME" != "$LAST_POD_NAME" ]; then
            echo "Note: POD_NAME changed from '${LAST_POD_NAME}' to '${POD_NAME}'."
            # Create a Kubernetes event for POD_NAME change
            create_kubernetes_event "PodNameChanged" \
                                    "POD_NAME changed from '${LAST_POD_NAME}' to '${POD_NAME}'." \
                                    "Normal"
        fi
    fi

    # Write random data to file
    # bs=4k count=$((RANDOM % 3 + 1)) will create files of 4KB, 8KB, or 12KB
    dd if=/dev/urandom of="$file" bs=4k count=$((RANDOM % 3 + 1)) oflag=direct

    # Compute and store hash
    md5sum "$file" >> "$HASHFILE"
    sync # Ensure data is written to disk

    # Update last epoch time and pod name for the next iteration
    LAST_EPOCH_TIME="$CURRENT_EPOCH_TIME"
    LAST_POD_NAME="$POD_NAME"

    # Random sleep with trap awareness
    sleep_time=$((RANDOM % 15 + 1)) # Sleep for 1 to 15 seconds
    echo "Sleeping for $sleep_time seconds..."
    
    # Use 'sleep' in the background and 'wait' to allow the trap to interrupt it
    # This allows the cleanup trap to still function if a termination signal is received during sleep.
    sleep "$sleep_time" &
    SLEEP_PID=$!
    wait "$SLEEP_PID"

    # Perform random integrity check
    if [ $((RANDOM % 2)) -eq 1 ]; then
        echo "Performing integrity check..."
        md5sum -c --quiet "$HASHFILE"
        if [ $? -ne 0 ]; then # Check the exit status of the md5sum command
            echo "Integrity check failed! Some files might be corrupted."
            # Create a warning event for integrity check failure
            create_kubernetes_event "IntegrityCheckFailed" \
                                    "Data integrity check failed for files in $MOUNT." \
                                    "Warning"
        else
            echo "Integrity check passed."
        fi
    fi
done