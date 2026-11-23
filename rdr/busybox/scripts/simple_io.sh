#!/bin/sh
# =============================================================================
# DR I/O workload: writer
#
# Writes random data files to the volume under test and records each one in
# an ordered, checksummed manifest, so the verifier can later prove whether
# data was LOST or CORRUPTED (e.g. after a failover to the DR cluster).
#
# Durability ordering (this is what makes the verification meaningful):
#   1. generate data in local tmp and compute its md5 (the INTENDED content)
#   2. write the file to the volume with direct I/O + fsync, fsync its dir
#   3. read the file back (direct I/O) and compare with the intended md5
#   4. only then append "<md5>  <seq>_<epoch>.dat" to the manifest + fsync
# So any entry present in the manifest refers to a file that was fully
# durable before the entry was written. If storage replication preserves
# write order, a manifest entry on the DR side whose file is missing or
# different is real data loss / corruption, not a test artifact.
#
# Layout on the volume (per writer, so multiple pods never share a file):
#   $MOUNT/dr-io/<WRITER_ID>/manifest.md5    ordered commit log (md5sum format)
#   $MOUNT/dr-io/<WRITER_ID>/<seq>_<epoch>.dat  data files
#   $MOUNT/dr-io/<WRITER_ID>/events.log      START / STOP / error events
#   $MOUNT/dr-io/<WRITER_ID>/writer.log      detailed log
#
# Environment:
#   MOUNT          volume mount path                    (default /mnt/test)
#   WRITER_ID      stable writer name; use a StatefulSet so it survives
#                  failover (e.g. app-0)                (default hostname)
#   CLUSTER_NAME   optional override; otherwise detected from the
#                  OpenShift API (see detect_cluster below)
#   NODE_NAME      recorded in events (downward API)     (default unknown)
#   MAX_BLOCKS     max 4k blocks per file                (default 3)
#   MAX_SLEEP      max seconds between writes            (default 15)
#   MIN_FREE_MB    pause writing below this free space   (default 200)
#   VERIFY_TAIL    entries re-checked in the loop, 0=all (default 20)
#   LEGACY_HASHFILE  also append every commit to $MOUNT/hashfile with an
#                  absolute path, as the old script did. ocs-ci's
#                  validate_data_integrity() runs "md5sum -c /mnt/test/hashfile"
#                  inside the pod, so keep this on            (default true)
# =============================================================================

MOUNT="${MOUNT:-/mnt/test}"
NODE="${NODE_NAME:-unknown}"
POD="$(hostname 2>/dev/null || echo unknown)"
WRITER_ID="${WRITER_ID:-$POD}"
WRITER_ID=$(printf '%s' "$WRITER_ID" | tr -c 'A-Za-z0-9._-' '_')
MAX_BLOCKS="${MAX_BLOCKS:-3}"
MAX_SLEEP="${MAX_SLEEP:-15}"
MIN_FREE_MB="${MIN_FREE_MB:-200}"
VERIFY_TAIL="${VERIFY_TAIL:-20}"
LEGACY_HASHFILE="${LEGACY_HASHFILE:-true}"

BASE="$MOUNT/dr-io"
WDIR="$BASE/$WRITER_ID"
MANIFEST="$WDIR/manifest.md5"
HASHFILE="$MOUNT/hashfile"
EVENTS="$WDIR/events.log"
LOGFILE="$WDIR/writer.log"
export LC_ALL=C

# --- Cluster identity (OpenShift) --------------------------------------------
# Order:
#   1. CLUSTER_NAME env (explicit override)
#   2. Infrastructure "cluster" .status.infrastructureName  (e.g. ocp-dr-x7k2p)
#   3. ClusterVersion "version" .spec.clusterID             (UUID)
#   4. ca-<hash> of the cluster's service CA, read from the service account
#      mount: needs NO RBAC, unique per cluster, not human-readable, changes
#      only when the cluster's service CA is rotated
#   5. unknown
# 2 and 3 need the ClusterRole in dr-io-rbac.yaml; each call times out after 5s.
SA_DIR="${SA_DIR:-/var/run/secrets/kubernetes.io/serviceaccount}"
k8s_get() {
    api="${K8S_API:-https://kubernetes.default.svc}"
    [ -r "$SA_DIR/token" ] || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -sf --max-time 5 --cacert "$SA_DIR/ca.crt" \
            -H "Authorization: Bearer $(cat "$SA_DIR/token")" "$api$1"
    elif command -v python3 >/dev/null 2>&1; then
        # The rdr-ocs-workload image (Alpine) has python3 but no curl
        python3 -I -c 'import ssl, sys, urllib.request
ctx = ssl.create_default_context(cafile=sys.argv[3])
req = urllib.request.Request(sys.argv[1], headers={"Authorization": "Bearer " + open(sys.argv[2]).read().strip()})
sys.stdout.write(urllib.request.urlopen(req, timeout=5, context=ctx).read().decode())' \
            "$api$1" "$SA_DIR/token" "$SA_DIR/ca.crt"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 5 -O - --ca-certificate="$SA_DIR/ca.crt" \
            --header "Authorization: Bearer $(cat "$SA_DIR/token")" "$api$1"
    else
        return 1
    fi
}
json_field() { tr ',{}' '\n\n\n' | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -n 1; }
detect_cluster() {
    if [ -n "$CLUSTER_NAME" ]; then printf '%s' "$CLUSTER_NAME"; return; fi
    v=$(k8s_get /apis/config.openshift.io/v1/infrastructures/cluster 2>/dev/null | json_field infrastructureName)
    [ -z "$v" ] && v=$(k8s_get /apis/config.openshift.io/v1/clusterversions/version 2>/dev/null | json_field clusterID)
    if [ -z "$v" ]; then
        for ca in "$SA_DIR/service-ca.crt" "$SA_DIR/ca.crt"; do
            if [ -s "$ca" ]; then
                h=$(sha256sum < "$ca" 2>/dev/null | cut -c1-12)
                [ -n "$h" ] && { v="ca-$h"; break; }
            fi
        done
    fi
    printf '%s' "${v:-unknown}" | tr -c 'A-Za-z0-9._-' '_'
}
CLUSTER=$(detect_cluster)

log() {
    level=$1; shift
    printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$WRITER_ID" "$*" \
        | tee -a "$LOGFILE"
}

# fsync specific paths; fall back to a global sync if unsupported
fsync_path() { sync "$@" 2>/dev/null || sync; }

event() {
    printf '%s %s cluster=%s node=%s pod=%s %s\n' "$(date +%s)" "$1" "$CLUSTER" "$NODE" "$POD" "$2" \
        >> "$EVENTS"
    fsync_path "$EVENTS"
}

# Portable random 0..65535 ($RANDOM is not available in POSIX sh / dash)
rand() { od -An -N2 -tu2 /dev/urandom | tr -d ' \n'; }

md5_of() { md5sum | cut -d' ' -f1; }

is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
for v in MAX_BLOCKS MAX_SLEEP MIN_FREE_MB VERIFY_TAIL; do
    eval "val=\$$v"
    is_uint "$val" || { echo "Invalid $v='$val'"; exit 2; }
done
[ "$MAX_BLOCKS" -ge 1 ] || MAX_BLOCKS=1
[ "$MAX_SLEEP" -ge 1 ] || MAX_SLEEP=1

mkdir -p "$WDIR" || { echo "Cannot create $WDIR"; exit 2; }
fsync_path "$BASE" "$MOUNT"

SRC=$(mktemp "${TMPDIR:-/tmp}/drio_src.XXXXXX") || { echo "mktemp failed"; exit 2; }
SLEEP_PID=

cleanup() {
    log INFO "Received termination signal, syncing and exiting"
    if [ -n "$SLEEP_PID" ] && kill -0 "$SLEEP_PID" 2>/dev/null; then
        kill "$SLEEP_PID" 2>/dev/null
    fi
    rm -f "$SRC"
    sync
    # STOP is written last: if it is the last event on the DR copy, every
    # commit made by this run reached the DR side.
    event STOP "clean last_seq=$seq"
    log INFO "Exiting cleanly (last_seq=$seq)"
    exit 0
}
trap cleanup INT TERM

# --- Repair a torn tail left by a crash --------------------------------------
# A crash during an append can leave a partial line or NUL bytes at the end.
# Appending after it would bury the garbage mid-file (which the verifier
# rightly reports as corruption), so cut it off and keep it as evidence.
# Garbage in the MIDDLE of a file is never touched.
#   $1 = file, $2 = 0 for a manifest, 1 for the legacy hashfile
repair_tail() {
    f=$1; [ -s "$f" ] || return 0
    total_lines=$(wc -l < "$f")
    last_valid=$(tr '\000' '\001' < "$f" | awk -v legacy="$2" '
        { ok = (length($1) == 32 && $1 !~ /[^0-9a-f]/ && substr($0, 33, 2) == "  ")
          if (ok && !legacy) ok = (NF == 2 && $2 ~ /^[0-9]+_[0-9]+\.dat$/)
          if (ok && legacy)  ok = (NF >= 2)
          if (ok) lv = NR }
        END { print lv + 0 }')
    has_nl=$(tail -c 1 "$f" | wc -l)
    physical=$total_lines; [ "$has_nl" -eq 0 ] && physical=$((total_lines + 1))
    if [ "$last_valid" -lt "$physical" ]; then
        ts=$(date +%s)
        saved="$WDIR/torn_tail_$(basename "$f")_$ts.bin"
        tail -n +"$((last_valid + 1))" "$f" > "$saved"
        head -n "$last_valid" "$f" > "$f.tmp"
        fsync_path "$f.tmp"
        mv "$f.tmp" "$f"
        fsync_path "$(dirname "$f")"
        log WARN "$f had a torn tail after line $last_valid; saved to $saved"
        event TORN_TAIL_REPAIRED "file=$(basename "$f") kept_lines=$last_valid saved=$(basename "$saved")"
    elif [ "$has_nl" -eq 0 ]; then
        printf '\n' >> "$f"
        fsync_path "$f"
    fi
}
repair_tail "$MANIFEST" 0
[ "$LEGACY_HASHFILE" = "true" ] && repair_tail "$HASHFILE" 1

# --- Continue the sequence from the last committed entry ---------------------
seq=0
if [ -s "$MANIFEST" ]; then
    seq=$(tail -n 1 "$MANIFEST" | awk '{ split($2, a, "_"); print a[1] + 0 }')
fi

# --- Probe direct I/O support (busybox dd, tmpfs, some FUSE fs lack it) ------
OUT_DIRECT="oflag=direct"; IN_DIRECT="iflag=direct"
probe="$WDIR/.direct_probe"
if ! dd if=/dev/zero of="$probe" bs=4k count=1 oflag=direct 2>/dev/null; then
    OUT_DIRECT=""; log WARN "oflag=direct not supported, using buffered writes + fsync"
fi
if ! dd if="$probe" of=/dev/null bs=4k iflag=direct 2>/dev/null; then
    IN_DIRECT=""; log WARN "iflag=direct not supported, read-back may come from page cache"
fi
rm -f "$probe"

event START "last_seq=$seq direct_write=${OUT_DIRECT:-no} direct_read=${IN_DIRECT:-no}"
log INFO "Writer started: cluster=$CLUSTER node=$NODE dir=$WDIR resuming after seq=$seq"

low_space=0
while true; do
    # --- Free-space guard: don't let ENOSPC create partial-state noise --------
    free_kb=$(df -Pk "$MOUNT" 2>/dev/null | awk 'NR==2 { print $4 }')
    if is_uint "$free_kb" && [ "$free_kb" -lt $((MIN_FREE_MB * 1024)) ]; then
        if [ "$low_space" -eq 0 ]; then
            log WARN "Free space ${free_kb}KB below ${MIN_FREE_MB}MB, pausing writes"
            event LOW_SPACE "free_kb=$free_kb"
            low_space=1
        fi
        sleep 30 & SLEEP_PID=$!; wait "$SLEEP_PID"; SLEEP_PID=
        continue
    fi
    low_space=0

    next=$((seq + 1))
    name=$(printf '%010d_%s.dat' "$next" "$(date +%s)")
    file="$WDIR/$name"
    count=$(( $(rand) % MAX_BLOCKS + 1 ))

    # 1. intended content + hash
    if ! dd if=/dev/urandom of="$SRC" bs=4k count="$count" 2>/dev/null; then
        log ERROR "Could not generate source data"; sleep 1; continue
    fi
    src_md5=$(md5_of < "$SRC")

    # 2. durable write to the volume under test
    if ! dd if="$SRC" of="$file" bs=4k $OUT_DIRECT conv=fsync 2>>"$LOGFILE"; then
        log ERROR "Write failed for $name; removing partial file"
        rm -f "$file"; fsync_path "$WDIR"
        event WRITE_FAILED "seq=$next"
        sleep 1; continue
    fi
    fsync_path "$WDIR"

    # 3. read-back verification (catches corruption on the write path)
    rb_md5=$(dd if="$file" bs=4k $IN_DIRECT 2>/dev/null | md5_of)
    if [ "$rb_md5" != "$src_md5" ]; then
        log ERROR "READ-BACK MISMATCH seq=$next file=$name expected=$src_md5 got=$rb_md5"
        event CORRUPT_ON_WRITE "seq=$next file=$name expected=$src_md5 got=$rb_md5"
        # Still commit the INTENDED hash so the verifier also flags this file.
    fi

    # 4. commit
    if printf '%s  %s\n' "$src_md5" "$name" >> "$MANIFEST"; then
        fsync_path "$MANIFEST"
        seq=$next
        if [ "$LEGACY_HASHFILE" = "true" ]; then
            printf '%s  %s\n' "$src_md5" "$file" >> "$HASHFILE" && fsync_path "$HASHFILE" \
                || log WARN "Failed to append $name to legacy hashfile"
        fi
        # Also goes to pod logs: an external record of what was committed on
        # the primary, to compare with the DR side's last seq (RPO in records).
        log INFO "COMMIT seq=$seq file=$name blocks=$count md5=$src_md5"
    else
        log ERROR "Manifest append failed for $name"
        event COMMIT_FAILED "seq=$next file=$name"
        sleep 1; continue
    fi

    sleep_time=$(( $(rand) % MAX_SLEEP + 1 ))
    sleep "$sleep_time" & SLEEP_PID=$!
    wait "$SLEEP_PID"
    SLEEP_PID=

    # Light in-loop check of recent entries (full check = verifier script)
    if [ $(( $(rand) % 2 )) -eq 1 ]; then
        if [ "$VERIFY_TAIL" -eq 0 ]; then n=$(wc -l < "$MANIFEST"); else n=$VERIFY_TAIL; fi
        if ( cd "$WDIR" && tail -n "$n" manifest.md5 | md5sum -c --quiet - ) >>"$LOGFILE" 2>&1; then
            log INFO "Recent-entry check passed (last $n entries)"
        else
            log ERROR "Recent-entry check FAILED (see $LOGFILE)"
            event VERIFY_FAILED "scope=last_$n"
        fi
    fi
done
