#!/bin/sh
HASHFILE=/mnt/test/hashfile
# Number of parallel md5sum workers.
# Capped at 4 by default — nproc reports the node's full CPU count which is
# unsafe to use directly (no limits set = could be 32/64 core node, and you'd
# starve other pods or get OOM-killed). Override explicitly in your pod spec
# once you know your actual CPU allocation:
#   env:
#     - name: MD5_WORKERS
#       value: "2"
MD5_WORKERS="${MD5_WORKERS:-2}"
 
if [ -f "$HASHFILE" ]; then
    echo "Found hashfile"
else
    echo "Hashfile not found, can't continue with integrity check"
    if [ "$CONTAINER_VALUE" = "init" ]; then
        exit 0
    else
        exit 1
    fi
fi
 
# Shard HASHFILE across MD5_WORKERS workers and run md5sum -c in parallel
total=$(wc -l < "$HASHFILE")
chunk_size=$(( (total + MD5_WORKERS - 1) / MD5_WORKERS ))
chunk_size=$(( chunk_size < 1 ? 1 : chunk_size ))
tmp_dir=$(mktemp -d /mnt/test/.verify_XXXXXX)
split -l "$chunk_size" "$HASHFILE" "$tmp_dir/chunk_"
 
fail=0
for chunk in "$tmp_dir"/chunk_*; do
    if [ "$CONTAINER_VALUE" = "init" ]; then
        md5sum -c "$chunk" &
    else
        md5sum -c --quiet "$chunk" &
    fi
done
# Wait for all background workers and collect failures
for job in $(jobs -p); do
    wait "$job" || fail=1
done
 
rm -rf "$tmp_dir"
 
if [ "$fail" -ne 0 ]; then
    echo "Error"
else
    echo "Integrity check Passed"
fi
exit "$fail"
 