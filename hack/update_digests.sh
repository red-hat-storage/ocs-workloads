#!/usr/bin/env bash
#
# update_digests.sh — resolve and pin container image digests for RDR workloads.
#
# Every kustomization.yaml under rdr/ that owns resources carries an `images:`
# transformer block of the form:
#
#   images:
#   - name: quay.io/ocsci/rdr-ocs-workload
#     newTag: latest                 # the tag the digest is resolved from
#     digest: sha256:<64-hex>        # the immutable manifest-list digest (pin)
#
# This script re-resolves each `newTag` to its current manifest-list (index)
# digest via skopeo and writes it into the `digest:` field. In --check mode it
# does not modify anything; it exits non-zero if any pin is stale, so CI can
# fail a PR whose digests drifted from what `newTag` currently points at.
#
# The manifest-list digest is computed as:
#     skopeo inspect --raw docker://NAME:TAG | sha256sum
# WITHOUT --override-arch, so we pin the multi-arch index (matching how the
# release scripts copy images with `skopeo copy --all`).
#
# Requirements: skopeo, yq (mikefarah/yq v4), sha256sum (coreutils).
#
# Usage:
#   hack/update_digests.sh            # resolve and write digests in place
#   hack/update_digests.sh --check    # verify pins are current (no writes)
#   hack/update_digests.sh -a FILE    # use a skopeo auth file
#
set -euo pipefail

CHECK=false
AUTHFILE=""
ROOT_DIR="rdr"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Resolve and pin container image digests in rdr/ kustomization images: blocks.

OPTIONS:
    -c, --check          Verify pins are current; do not write. Exit 1 on drift.
    -a, --authfile FILE  skopeo auth file (default: cached skopeo login creds)
    -r, --root DIR       Root directory to scan (default: rdr)
    -h, --help           Show this help

EXAMPLES:
    $0                   # update all digests in place
    $0 --check           # CI mode: fail if any digest is stale
    $0 -a ~/.docker/config.json
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--check) CHECK=true; shift ;;
        -a|--authfile) AUTHFILE="$2"; shift 2 ;;
        -r|--root) ROOT_DIR="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

# --- Tool checks -------------------------------------------------------------
for tool in skopeo yq sha256sum; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: required tool '$tool' is not installed or not in PATH" >&2
        exit 1
    fi
done

if [[ -n "$AUTHFILE" && ! -f "$AUTHFILE" ]]; then
    echo "ERROR: auth file not found: $AUTHFILE" >&2
    exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
    echo "ERROR: root directory '$ROOT_DIR' not found (run from repo root)" >&2
    exit 1
fi

RAW_OPTS=()
[[ -n "$AUTHFILE" ]] && RAW_OPTS+=(--authfile "$AUTHFILE")

# Resolve the manifest-list (index) digest for a name:tag reference.
resolve_digest() {
    local ref="$1" raw sum
    # Capture the raw manifest first so we can distinguish a real failure
    # (skopeo error / empty output) from a valid response. Hashing straight from
    # a failed pipe would yield sha256("") = e3b0c442..., a bogus but non-empty
    # "digest" that must never be written as a pin.
    raw=$(skopeo inspect --raw "${RAW_OPTS[@]}" "docker://${ref}" 2>/dev/null) || return 1
    [[ -z "$raw" ]] && return 1
    sum=$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)
    [[ -n "$sum" ]] && echo "sha256:${sum}"
}

updated=0
stale=0
checked=0

# Iterate every kustomization file that declares an images: block.
while IFS= read -r -d '' kfile; do
    count=$(yq eval '.images | length' "$kfile" 2>/dev/null || echo 0)
    [[ -z "$count" || "$count" == "null" || "$count" -eq 0 ]] && continue

    for ((i=0; i<count; i++)); do
        name=$(yq eval ".images[$i].name" "$kfile")
        tag=$(yq eval ".images[$i].newTag // \"latest\"" "$kfile")
        current=$(yq eval ".images[$i].digest // \"\"" "$kfile")

        # Skip external images we do not own / pin.
        case "$name" in
            quay.io/prometheus/*) continue ;;
        esac

        checked=$((checked + 1))
        resolved=$(resolve_digest "${name}:${tag}") || true

        if [[ -z "$resolved" ]]; then
            echo "WARN: could not resolve ${name}:${tag} (skipping)" >&2
            continue
        fi

        if [[ "$resolved" == "$current" ]]; then
            echo "ok    ${name}:${tag} -> ${resolved} ($kfile)"
            continue
        fi

        if [[ "$CHECK" == "true" ]]; then
            echo "STALE ${name}:${tag}" >&2
            echo "        pinned:   ${current:-<none>}" >&2
            echo "        current:  ${resolved}" >&2
            echo "        file:     ${kfile}" >&2
            stale=$((stale + 1))
        else
            yq eval -i ".images[$i].digest = \"${resolved}\"" "$kfile"
            echo "update ${name}:${tag} ${current:-<none>} -> ${resolved} ($kfile)"
            updated=$((updated + 1))
        fi
    done
done < <(find "$ROOT_DIR" -name kustomization.yaml -print0 2>/dev/null)

echo ""
echo "Checked $checked image pin(s)."

if [[ "$CHECK" == "true" ]]; then
    if [[ "$stale" -gt 0 ]]; then
        echo "FAIL: $stale digest pin(s) are stale. Run hack/update_digests.sh to refresh." >&2
        exit 1
    fi
    echo "All digest pins are current."
else
    echo "Updated $updated digest pin(s)."
fi
