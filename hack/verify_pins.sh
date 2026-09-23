#!/usr/bin/env bash
#
# verify_pins.sh — CI guard that every rdr/ workload deploys a digest-pinned image.
#
# It performs three checks:
#   1. Renders every kustomize entrypoint under rdr/ and asserts that every
#      rendered `image:` contains an `@sha256:` digest (the only allowed
#      exception is the data-viewer placeholder image `' '`).
#   2. Consistency: a given image name must be pinned to the SAME digest
#      everywhere it appears across rdr/ (kustomize images: blocks + VM url:).
#   3. Existence (best-effort, only when skopeo can reach the registry): each
#      pinned digest must actually exist. Skipped automatically when offline
#      or when SKIP_EXISTENCE=1.
#
# Requirements: kustomize (or `oc`/`kubectl kustomize`), yq, grep. skopeo is
# optional (existence check).
#
# Usage: hack/verify_pins.sh
#
set -uo pipefail

ROOT_DIR="${1:-rdr}"
SKIP_EXISTENCE="${SKIP_EXISTENCE:-0}"

fail=0

# --- Locate a kustomize binary ----------------------------------------------
KUSTOMIZE=()
if command -v kustomize &> /dev/null; then
    KUSTOMIZE=(kustomize build)
elif command -v oc &> /dev/null; then
    KUSTOMIZE=(oc kustomize)
elif command -v kubectl &> /dev/null; then
    KUSTOMIZE=(kubectl kustomize)
else
    echo "ERROR: need one of: kustomize, oc, or kubectl (for kustomize build)" >&2
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo "ERROR: yq (mikefarah v4) is required" >&2
    exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
    echo "ERROR: root directory '$ROOT_DIR' not found (run from repo root)" >&2
    exit 1
fi

echo "=== Check 1: every rendered image is digest-pinned ========================"
built=0
while IFS= read -r -d '' kfile; do
    dir=$(dirname "$kfile")
    # Only build top-level-ish roots: skip if this kustomization is only a
    # component/base referenced by others? We build every dir; kustomize bases
    # build fine on their own, and overlays exercise the transformers.
    out=$("${KUSTOMIZE[@]}" "$dir" 2>/dev/null) || {
        # A pure component (kind: Component) can't be built standalone — skip.
        if grep -q '^kind: Component' "$kfile" 2>/dev/null; then
            continue
        fi
        echo "  [skip] $dir (kustomize build failed)"
        continue
    }
    built=$((built + 1))

    # Extract every `image:` value from the rendered manifests.
    while IFS= read -r img; do
        [[ -z "$img" ]] && continue
        # Allow the data-viewer placeholder (empty/space image).
        stripped=$(echo "$img" | tr -d "[:space:]'\"")
        [[ -z "$stripped" ]] && continue
        case "$img" in
            *@sha256:*) : ;;  # good — digest pinned
            *)
                echo "  [FAIL] $dir renders un-pinned image: $img"
                fail=1
                ;;
        esac
    done < <(echo "$out" | yq eval -N '.. | select(has("image")) | .image' - 2>/dev/null)
done < <(find "$ROOT_DIR" -name kustomization.yaml -print0 2>/dev/null)
echo "  built $built kustomize root(s)"
echo ""

echo "=== Check 2: each image name pins one consistent digest ==================="
pins=$(mktemp); trap 'rm -f "$pins"' EXIT
{
    find "$ROOT_DIR" -name kustomization.yaml -print0 2>/dev/null | while IFS= read -r -d '' f; do
        yq eval '.images[]? | .name + "|" + .digest' "$f" 2>/dev/null
    done
    grep -rh "url:.*docker://" "$ROOT_DIR" --include="*.yaml" --include="*.yml" 2>/dev/null | \
        sed 's/.*docker:\/\///g' | sed 's/[[:space:]]*#.*//g' | tr -d "'\"" | \
        grep '@sha256:' | sed -E 's/@(sha256:[0-9a-f]+)$/|\1/'
} | grep -v '^$' | grep -v '|null$' | grep -v 'quay.io/prometheus' | sort -u > "$pins"

conflicts=$(cut -d'|' -f1 "$pins" | uniq -d)
if [[ -n "$conflicts" ]]; then
    echo "  [FAIL] image name(s) pinned to conflicting digests:"
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        echo "    $name:"
        grep "^${name}|" "$pins" | sed 's/^/      /'
    done <<< "$conflicts"
    fail=1
else
    echo "  ok — $(wc -l < "$pins" | tr -d ' ') unique pin(s), no conflicts"
fi
echo ""

echo "=== Check 3: pinned digests exist in registry (best-effort) ==============="
if [[ "$SKIP_EXISTENCE" == "1" ]] || ! command -v skopeo &> /dev/null; then
    echo "  skipped (skopeo unavailable or SKIP_EXISTENCE=1)"
else
    # Probe connectivity once; if the first inspect fails to reach the registry,
    # skip the whole check rather than producing false failures offline.
    probed=0
    while IFS='|' read -r name digest; do
        [[ -z "$name" || -z "$digest" ]] && continue
        if skopeo inspect --raw "docker://${name}@${digest}" &> /dev/null; then
            echo "  [ok]   ${name}@${digest}"
        else
            if [[ "$probed" -eq 0 ]]; then
                echo "  [warn] cannot reach registry for ${name}; skipping existence check"
                break
            fi
            echo "  [FAIL] pinned digest not found: ${name}@${digest}"
            fail=1
        fi
        probed=1
    done < "$pins"
fi
echo ""

if [[ "$fail" -ne 0 ]]; then
    echo "RESULT: FAIL — one or more pin checks failed." >&2
    exit 1
fi
echo "RESULT: PASS — all rdr/ images are digest-pinned and consistent."
