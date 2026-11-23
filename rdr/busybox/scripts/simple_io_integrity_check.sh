#!/bin/sh
# =============================================================================
# DR I/O workload: verifier
#
# Checks everything the writer (simple_io.sh) committed and classifies problems:
#
#   DATA LOSS   (FAIL)  - a committed file is missing
#                       - a sequence gap in a manifest (committed entries gone)
#                       - data files exist but their manifest is gone
#                       - EXPECT_DATA=true but the volume holds no data at all
#   CORRUPTION  (FAIL)  - a committed file's content differs from its md5
#                       - a committed file exists but can't be read (I/O error)
#                       - garbage lines in the MIDDLE of a manifest
#   WARNING     (pass)  - torn last manifest line (normal after a crash)
#                       - uncommitted files (write in flight at crash time)
#                       - writer has no clean STOP as last event (crash or
#                         unplanned failover: some tail loss is expected
#                         within your RPO; compare last seq with pod logs)
#
# Also verifies the old-format $MOUNT/hashfile, if present. The writer keeps
# appending to it for ocs-ci compatibility; its lines that point into dr-io/
# are skipped here because the manifests already cover them.
#
# Environment:
#   CLUSTER_NAME     optional override; otherwise detected from the OpenShift API
#   MOUNT            volume mount path                    (default /mnt/test)
#   MD5_WORKERS      parallel md5sum workers              (default 2)
#   CONTAINER_VALUE  "init" when run as init container
#   EXPECT_DATA      true on the DR side: empty volume = total loss (default false)
#   FAIL_ON_ERROR    exit 1 on loss/corruption; true in an init container
#                    keeps the app from writing over the evidence (default true)
#   REPORT_DIR       where to save the report, "" to disable
#                    (default $MOUNT/dr-io/reports)
#   VERBOSE          true = print every per-file OK line  (default false)
#
# Exit codes: 0 = no loss/corruption, 1 = loss or corruption found,
#             2 = verification could not run.
# =============================================================================

MOUNT="${MOUNT:-/mnt/test}"
BASE="$MOUNT/dr-io"
LEGACY="$MOUNT/hashfile"
MD5_WORKERS="${MD5_WORKERS:-2}"
EXPECT_DATA="${EXPECT_DATA:-false}"
FAIL_ON_ERROR="${FAIL_ON_ERROR:-true}"
REPORT_DIR="${REPORT_DIR-$BASE/reports}"
VERBOSE="${VERBOSE:-false}"
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

case "$MD5_WORKERS" in
    ''|*[!0-9]*|0) echo "Invalid MD5_WORKERS='$MD5_WORKERS', using 2"; MD5_WORKERS=2 ;;
esac

# Work in local tmp, not on the volume under test
WORK=$(mktemp -d "${TMPDIR:-/tmp}/drverify.XXXXXX") || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT
trap 'exit 2' INT TERM

REPORT=""
if [ -n "$REPORT_DIR" ] && mkdir -p "$REPORT_DIR" 2>/dev/null; then
    REPORT="$REPORT_DIR/verify_$(date +%Y%m%dT%H%M%S)_$(hostname 2>/dev/null || echo unknown).log"
    : > "$REPORT" 2>/dev/null || REPORT=""
fi
say() {
    printf '%s\n' "$*"
    [ -n "$REPORT" ] && printf '%s\n' "$*" >> "$REPORT"
}

NOW=$(date +%s)
say "=== DR integrity check: $(date '+%Y-%m-%dT%H:%M:%S%z') host=$(hostname 2>/dev/null) cluster=$CLUSTER mode=${CONTAINER_VALUE:-main}"

: > "$WORK/all.list"
loss=0; corrupt=0; warn=0; writers=0; entries_total=0; newest=0

# Classify every manifest line. Prints the valid entries (with full path)
# to listfile, bad line numbers to badfile, and a stats line on stdout:
#   entries first_seq last_seq last_epoch gaps mid_bad torn gapdesc...
# legacy=1: old hashfile format (absolute paths, no sequence numbers).
analyze() {
    tr '\000' '\001' < "$1" | awk -v dir="$2" -v listfile="$3" -v badfile="$4" -v legacy="$5" -v skip="$BASE/" '
    {
        valid = (length($1) == 32 && $1 !~ /[^0-9a-f]/ && substr($0, 33, 2) == "  ")
        if (valid && !legacy) valid = (NF == 2 && $2 ~ /^[0-9]+_[0-9]+\.dat$/)
        if (valid && legacy)  valid = (NF >= 2)
        if (!valid) { pending++; print NR >> badfile; next }
        mid_bad += pending; pending = 0
        n++
        if (legacy) {
            # Entries for dr-io/ files are already checked via their manifest
            if (index(substr($0, 35), skip) == 1) { n--; next }
            print $0 >> listfile; next
        }
        split($2, a, "_"); s = a[1] + 0; t = a[2]; sub(/\.dat$/, "", t)
        if (n == 1) first = s
        else if (s != prev + 1) {
            gaps++
            if (s > prev + 1) gd = gd sprintf(" %d-%d", prev + 1, s - 1)
            else gd = gd sprintf(" out-of-order@%d", s)
        }
        prev = s; last_t = t
        print $1 "  " dir "/" $2 >> listfile
    }
    END {
        if (!legacy && n > 0 && first != 1) { gaps++; gd = sprintf(" 1-%d", first - 1) gd }
        if (gd == "") gd = " -"
        printf "%d %d %d %d %d %d %d%s\n", n, first + 0, prev + 0, last_t + 0, gaps + 0, mid_bad + 0, pending + 0, gd
    }'
}

# --- Per-writer manifests -----------------------------------------------------
if [ -d "$BASE" ]; then
    for wdir in "$BASE"/*; do
        [ -d "$wdir" ] || continue
        w=$(basename "$wdir")
        [ "$w" = "reports" ] && continue
        writers=$((writers + 1))
        m="$wdir/manifest.md5"
        ndat=$(ls "$wdir" | grep -c '\.dat$')

        if [ ! -f "$m" ]; then
            if [ "$ndat" -gt 0 ]; then
                say "[$w] DATA LOSS: manifest.md5 missing but $ndat data files present"
                loss=$((loss + 1))
            else
                say "[$w] no manifest and no data files (writer never committed)"
            fi
            continue
        fi

        : > "$WORK/bad.$writers"
        read n first last last_t gaps midbad torn gapdesc <<EOF
$(analyze "$m" "$wdir" "$WORK/all.list" "$WORK/bad.$writers" 0)
EOF
        entries_total=$((entries_total + n))
        [ "$last_t" -gt "$newest" ] && newest=$last_t

        last_ev=$(tail -n 1 "$wdir/events.log" 2>/dev/null)
        case "$last_ev" in
            *" STOP "*) stop_state="clean STOP" ;;
            "")         stop_state="no events.log" ;;
            *)          stop_state="NO clean stop (crash/unplanned failover)" ;;
        esac

        # Uncommitted files: on disk but not in the manifest
        orphans=$(ls "$wdir" | grep '\.dat$' | awk 'FILENAME == ARGV[1] { c[$2] = 1; next } !($0 in c)' "$m" - | wc -l)

        if [ "$n" -gt 0 ]; then
            say "[$w] entries=$n seq=$first..$last last_commit=$(date -d "@$last_t" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "$last_t") last_event: $stop_state"
        else
            say "[$w] entries=0 last_event: $stop_state"
        fi
        case "$stop_state" in NO*) warn=$((warn + 1)) ;; esac

        if [ "$gaps" -gt 0 ]; then
            say "[$w] DATA LOSS: $gaps sequence gap(s), missing seq: $gapdesc"
            loss=$((loss + gaps))
        fi
        if [ "$midbad" -gt 0 ]; then
            say "[$w] CORRUPTION: $midbad garbage line(s) inside manifest (lines: $(head -n "$midbad" "$WORK/bad.$writers" | tr '\n' ' '))"
            corrupt=$((corrupt + midbad))
        fi
        if [ "$torn" -gt 0 ]; then
            say "[$w] WARNING: torn last manifest line ($torn line(s)), expected after a crash"
            warn=$((warn + 1))
        fi
        if [ "$orphans" -gt 0 ]; then
            say "[$w] WARNING: $orphans uncommitted data file(s) (in-flight writes, not counted as loss)"
            warn=$((warn + 1))
        fi
    done
fi

# --- Old-format hashfile ------------------------------------------------------
if [ -f "$LEGACY" ]; then
    : > "$WORK/bad.legacy"
    read n first last last_t gaps midbad torn gapdesc <<EOF
$(analyze "$LEGACY" "" "$WORK/all.list" "$WORK/bad.legacy" 1)
EOF
    entries_total=$((entries_total + n))
    say "[legacy hashfile] entries=$n (lines for dr-io/ files are checked via their manifests)"
    if [ "$midbad" -gt 0 ]; then
        say "[legacy hashfile] CORRUPTION: $midbad garbage line(s) inside hashfile"
        corrupt=$((corrupt + midbad))
    fi
    [ "$torn" -gt 0 ] && { say "[legacy hashfile] WARNING: torn last line"; warn=$((warn + 1)); }
fi

# --- Nothing to verify --------------------------------------------------------
if [ "$entries_total" -eq 0 ] && [ "$loss" -eq 0 ] && [ "$corrupt" -eq 0 ]; then
    if [ "$EXPECT_DATA" = "true" ]; then
        say "DATA LOSS: EXPECT_DATA=true but no committed data found under $MOUNT"
        loss=1
    else
        say "No committed data found (fresh volume), nothing to verify"
        say "RESULT: PASS"
        exit 0
    fi
fi

# --- Verify all committed files in parallel -----------------------------------
mismatch=0; missing=0; unreadable=0; ok=0
if [ "$entries_total" -gt 0 ]; then
    chunk_size=$(( (entries_total + MD5_WORKERS - 1) / MD5_WORKERS ))
    [ "$chunk_size" -lt 1 ] && chunk_size=1
    split -l "$chunk_size" "$WORK/all.list" "$WORK/chunk_" || { say "split failed"; exit 2; }

    pids=""
    for chunk in "$WORK"/chunk_*; do
        [ -f "$chunk" ] || continue
        md5sum -c "$chunk" > "$chunk.out" 2> "$chunk.err" &
        pids="$pids $!"
    done
    for pid in $pids; do wait "$pid"; done   # result is taken from the output below

    cat "$WORK"/chunk_*.out > "$WORK/result.out" 2>/dev/null
    cat "$WORK"/chunk_*.err > "$WORK/result.err" 2>/dev/null
    ok=$(grep -c ': OK$' "$WORK/result.out")
    mismatch=$(grep -c ': FAILED$' "$WORK/result.out")
    openfail=$(grep -c ': FAILED open or read$' "$WORK/result.out")
    missing=$(grep -c 'No such file or directory' "$WORK/result.err")
    unreadable=$((openfail - missing))
    [ "$unreadable" -lt 0 ] && unreadable=0

    # Every entry must be accounted for, or md5sum itself misbehaved
    accounted=$((ok + mismatch + openfail))
    if [ "$accounted" -ne "$entries_total" ]; then
        say "ERROR: md5sum reported $accounted results for $entries_total entries; verification incomplete"
        sed 's/^/  /' "$WORK/result.err" | head -n 20 | while IFS= read -r l; do say "$l"; done
        exit 2
    fi

    loss=$((loss + missing))
    corrupt=$((corrupt + mismatch + unreadable))

    say "Files verified: $entries_total  OK=$ok  checksum_mismatch=$mismatch  missing=$missing  unreadable=$unreadable"
    if [ $((mismatch + openfail)) -gt 0 ]; then
        say "Failed files (first 50):"
        grep -v ': OK$' "$WORK/result.out" | head -n 50 | while IFS= read -r l; do say "  $l"; done
    fi
    [ "$VERBOSE" = "true" ] && cat "$WORK/result.out"
    [ -n "$REPORT" ] && { echo "--- full md5sum output ---"; cat "$WORK/result.out"; } >> "$REPORT"
fi

if [ "$newest" -gt 0 ]; then
    say "Newest committed write: $(date -d "@$newest" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "$newest") ($((NOW - newest))s before this check; upper bound on RPO if run right after failover)"
fi

# --- Verdict ------------------------------------------------------------------
if [ "$loss" -gt 0 ] || [ "$corrupt" -gt 0 ]; then
    say "RESULT: FAIL  data_loss=$loss  corruption=$corrupt  warnings=$warn"
    [ -n "$REPORT" ] && say "Report: $REPORT"
    [ "$FAIL_ON_ERROR" = "true" ] && exit 1
    exit 0
fi
say "RESULT: PASS  warnings=$warn"
[ -n "$REPORT" ] && say "Report: $REPORT"
exit 0
