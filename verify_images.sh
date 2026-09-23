#!/bin/bash

# Script to verify RDR container images exist in Quay before creating release

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Verify that all required RDR container images exist in Quay.io for a release.

OPTIONS:
    -t, --tag TAG_NAME         Release tag name to verify (required, e.g., release-4.17)
    -a, --authfile FILE        Path to authentication file for skopeo (optional)
    --platform PLATFORM        Platform to check (default: auto, options: amd64, arm64, auto)
    -d, --debug                Show detailed diagnostic information for missing images
    -h, --help                 Show this help message

EXAMPLES:
    $0 -t release-4.17
    $0 --tag release-4.18
    $0 -t release-4.17 --debug
    $0 -t release-4.17 -a ~/.docker/config.json
    $0 -t release-4.17 --platform amd64

DESCRIPTION:
    This script verifies that all required container images exist in Quay
    with the specified release tag before you run create_rdr_release.sh.

    Platform checking:
      - auto (default): Uses linux/amd64, works on macOS arm64
      - amd64: Explicitly check linux/amd64 (x86_64) images
      - arm64: Explicitly check linux/arm64 images

REQUIREMENTS:
    - skopeo must be installed

EOF
    exit 1
}

# Parse command line arguments
RELEASE_TAG=""
AUTHFILE=""
PLATFORM="auto"
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            RELEASE_TAG="$2"
            shift 2
            ;;
        -a|--authfile)
            AUTHFILE="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate release tag
if [[ -z "$RELEASE_TAG" ]]; then
    print_error "Release tag is required!"
    usage
fi

# Check if skopeo is available
if ! command -v skopeo &> /dev/null; then
    print_error "skopeo is not installed or not in PATH"
    print_info "Install skopeo to verify images:"
    echo "  - macOS: brew install skopeo"
    echo "  - RHEL/Fedora: dnf install skopeo"
    echo "  - Ubuntu: apt install skopeo"
    exit 1
fi

# Check if yq is available (needed to read pinned digests from kustomize images: blocks)
if ! command -v yq &> /dev/null; then
    print_error "yq is not installed or not in PATH"
    print_info "Install yq (mikefarah/yq v4) to read pinned digests:"
    echo "  - macOS: brew install yq"
    echo "  - Linux: https://github.com/mikefarah/yq/#install"
    exit 1
fi

# Validate authfile if provided
if [[ -n "$AUTHFILE" ]]; then
    if [[ ! -f "$AUTHFILE" ]]; then
        print_error "Authentication file not found: $AUTHFILE"
        exit 1
    fi
fi

# Validate platform
if [[ "$PLATFORM" != "auto" && "$PLATFORM" != "amd64" && "$PLATFORM" != "arm64" ]]; then
    print_error "Invalid platform: $PLATFORM. Must be 'auto', 'amd64', or 'arm64'"
    exit 1
fi

# Build skopeo options based on platform
SKOPEO_OPTS=""

# Determine architecture override
if [[ "$PLATFORM" == "auto" ]]; then
    # Auto-detect: Use linux/amd64 as default for container images
    # This works well on macOS arm64 and avoids architecture mismatch errors
    SKOPEO_OPTS="--override-os linux --override-arch amd64"
    print_info "Platform: auto (using linux/amd64)"
elif [[ "$PLATFORM" == "amd64" ]]; then
    SKOPEO_OPTS="--override-os linux --override-arch amd64"
    print_info "Platform: linux/amd64"
elif [[ "$PLATFORM" == "arm64" ]]; then
    SKOPEO_OPTS="--override-os linux --override-arch arm64"
    print_info "Platform: linux/arm64"
fi

if [[ -n "$AUTHFILE" ]]; then
    SKOPEO_OPTS="$SKOPEO_OPTS --authfile $AUTHFILE"
fi

print_info "Verifying RDR Container Images for Release: $RELEASE_TAG"
echo ""

# Check if rdr/ directory exists
if [[ ! -d "rdr" ]]; then
    print_error "rdr/ directory not found! Please run this script from the repository root."
    exit 1
fi

# Auto-detect all images from rdr/ directory
print_info "Scanning rdr/ directory for container images..."

# Build the pinned image -> digest map (source of truth), from:
#   - kustomize images: blocks (name|sha256:...)
#   - digest-pinned VM url: fields (name@sha256:... -> name|sha256:...)
# This works on master (newTag: latest) and on release branches (newTag: release-X),
# since we read .digest regardless of the tag.
digest_tmp=$(mktemp)
trap 'rm -f "$digest_tmp"' EXIT
{
    find rdr -name kustomization.yaml -print0 2>/dev/null | while IFS= read -r -d '' f; do
        yq eval '.images[]? | .name + "|" + .digest' "$f" 2>/dev/null
    done
    grep -rh "url:.*docker://" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null | \
        sed 's/.*docker:\/\///g' | sed 's/[[:space:]]*#.*//g' | sed "s/'//g" | sed 's/"//g' | \
        grep '@sha256:' | sed -E 's/@(sha256:[0-9a-f]+)$/|\1/'
} | grep -v "^$" | grep -v "quay.io/prometheus" | sort -u > "$digest_tmp"

# Names for the existence check
declare -a images
while IFS='|' read -r name _; do
    [[ -n "$name" ]] && images+=("$name")
done < <(cut -d'|' -f1 "$digest_tmp" | sort -u)

total_images=${#images[@]}

if [[ $total_images -eq 0 ]]; then
    print_warning "No container images found in rdr/ directory"
    print_info "Nothing to verify"
    exit 0
fi

print_info "Checking $total_images container image(s)..."
echo ""

# Verify each image
success_count=0
failed_count=0
declare -a missing_images
declare -a missing_details
declare -a verified_report
declare -a not_verified_report

for image in "${images[@]}"; do
    full_image="${image}:${RELEASE_TAG}"

    if skopeo inspect $SKOPEO_OPTS docker://${full_image} &> /dev/null; then
        print_success "$full_image"
        success_count=$((success_count + 1))
        verified_report+=("${full_image}|FOUND")
    else
        print_error "$full_image (NOT FOUND)"
        missing_images+=("$full_image")
        failed_count=$((failed_count + 1))
        not_verified_report+=("${full_image}|NOT FOUND")

        # Collect debug information if debug mode is enabled
        if [[ "$DEBUG" == "true" ]]; then
            # Check what tags are in YAML files first
            yaml_current_tags=$(grep -rh "${image}:" rdr/ 2>/dev/null | \
                               sed 's|.*'"${image}"':||g' | \
                               sed 's/[[:space:]]*#.*//g' | \
                               sed "s/'//g" | sed 's/"//g' | \
                               grep -v "^$" | sort -u | head -1)

            # Check if any source image exists
            source_exists="unknown"
            if [[ -n "$yaml_current_tags" ]] && skopeo inspect $SKOPEO_OPTS "docker://${image}:${yaml_current_tags}" &> /dev/null; then
                source_exists="$yaml_current_tags"
            elif skopeo inspect $SKOPEO_OPTS "docker://${image}:latest" &> /dev/null; then
                source_exists="latest"
            elif skopeo inspect $SKOPEO_OPTS "docker://${image}:main" &> /dev/null; then
                source_exists="main"
            fi

            missing_details+=("${full_image}|${source_exists}")
        fi
    fi
done

# Print summary
echo ""
echo "=========================================="
print_info "Verification Report"
echo "=========================================="
echo ""
printf "  %-55s %s\n" "IMAGE" "STATUS"
printf "  %-55s %s\n" "-----" "------"

if [[ ${#verified_report[@]} -gt 0 ]]; then
    for entry in "${verified_report[@]}"; do
        IFS='|' read -r img status <<< "$entry"
        printf "  ${GREEN}%-55s %s${NC}\n" "$img" "$status"
    done
fi

if [[ ${#not_verified_report[@]} -gt 0 ]]; then
    for entry in "${not_verified_report[@]}"; do
        IFS='|' read -r img status <<< "$entry"
        printf "  ${RED}%-55s %s${NC}\n" "$img" "$status"
    done
fi

echo ""
echo "  Total: $total_images | Found: $success_count | Missing: $failed_count"
echo ""

if [[ $failed_count -gt 0 ]]; then
    print_error "The following images are missing in Quay:"
    for missing_image in "${missing_images[@]}"; do
        echo "  - $missing_image"
    done
    echo ""

    # Show detailed diagnostics in debug mode
    if [[ "$DEBUG" == "true" ]]; then
        echo "=========================================="
        print_info "Diagnostic Information (Debug Mode)"
        echo "=========================================="
        echo ""

        for detail in "${missing_details[@]}"; do
            IFS='|' read -r img src_tag <<< "$detail"
            image_name=$(echo "$img" | sed "s/:${RELEASE_TAG}//")

            echo "Image: $image_name"
            echo "  Missing tag: $RELEASE_TAG"

            # Check if source tag exists
            if [[ "$src_tag" != "unknown" ]]; then
                echo "  ✓ Source exists: :$src_tag"
                echo "  → Action: Run tag_images.sh to copy :$src_tag to :$RELEASE_TAG"
            else
                echo "  ✗ No :latest or :main tag found"
                echo "  → Possible issues:"
                echo "    1. Source image doesn't exist at all"
                echo "    2. Source has a different tag (check YAML files)"
                echo "    3. No read permission for this image"
            fi

            # Check what tags YAML files expect
            echo "  Checking YAML files for expected source tag..."
            # Use | as delimiter to avoid conflicts with / in image names
            yaml_tags=$(grep -rh "${image_name}:" rdr/ 2>/dev/null | \
                       sed 's|.*'"${image_name}"':||g' | \
                       sed 's/[[:space:]]*#.*//g' | \
                       sed "s/'//g" | sed 's/"//g' | \
                       grep -v "^$" | sort -u)

            if [[ -n "$yaml_tags" ]]; then
                echo "  YAML files reference these tags:"
                yaml_has_release_tag=false
                yaml_has_source_tag=false

                while IFS= read -r tag; do
                    echo "    - :$tag"
                    # Test if this tag exists
                    if skopeo inspect $SKOPEO_OPTS "docker://${image_name}:${tag}" &> /dev/null; then
                        echo "      [EXISTS in Quay]"
                        if [[ "$tag" != "$RELEASE_TAG" ]]; then
                            yaml_has_source_tag=true
                        fi
                    else
                        echo "      [NOT FOUND in Quay]"
                    fi

                    if [[ "$tag" == "$RELEASE_TAG" ]]; then
                        yaml_has_release_tag=true
                    fi
                done <<< "$yaml_tags"

                # Detect circular problem: YAML already updated but images not tagged
                if [[ "$yaml_has_release_tag" == "true" ]] && [[ "$yaml_has_source_tag" == "false" ]]; then
                    echo ""
                    print_warning "  ⚠️  CIRCULAR DEPENDENCY DETECTED!"
                    echo "  Your YAML files already reference :$RELEASE_TAG"
                    echo "  But this tag doesn't exist in Quay yet."
                    echo ""
                    echo "  This happened because you ran create_rdr_release.sh before tagging images."
                    echo ""
                    echo "  Solutions:"
                    echo "    1. Check out master branch to get YAML files with :latest tags:"
                    echo "       git checkout master"
                    echo "       ./tag_images.sh -t $RELEASE_TAG --insecure-policy"
                    echo "       git checkout $RELEASE_TAG"
                    echo ""
                    echo "    2. Or manually tag from a known working tag in Quay:"
                    echo "       skopeo copy --all --insecure-policy \\"
                    echo "         docker://${image_name}:<source-tag> \\"
                    echo "         docker://${image_name}:$RELEASE_TAG"
                fi
            fi

            # Test authentication using the source tag if found
            echo "  Testing authentication..."
            test_tag="latest"
            if [[ "$src_tag" != "unknown" ]]; then
                test_tag="$src_tag"
            fi

            if skopeo inspect $SKOPEO_OPTS "docker://${image_name}:${test_tag}" &> /dev/null; then
                echo "    ✓ Can read from this repository (tested with :${test_tag})"
            else
                # Try to get more specific error
                auth_test=$(skopeo inspect $SKOPEO_OPTS "docker://${image_name}:${test_tag}" 2>&1 || true)
                if echo "$auth_test" | grep -qi "unauthorized\|forbidden\|denied"; then
                    echo "    ✗ Authentication/Permission issue"
                    echo "    → Try: skopeo login quay.io"
                elif echo "$auth_test" | grep -qi "not found\|manifest unknown"; then
                    echo "    ✗ Image/tag :${test_tag} doesn't exist in registry"
                else
                    echo "    ✗ Cannot access repository (see error below)"
                    echo "$auth_test" | head -2 | sed 's/^/      /'
                fi
            fi
            echo ""
        done

        echo "=========================================="
        print_info "Troubleshooting Steps"
        echo "=========================================="
        echo ""
        echo "1. Check if you're authenticated:"
        echo "   skopeo login quay.io"
        echo ""
        echo "2. Verify source images exist:"
        echo "   skopeo inspect docker://<image>:latest"
        echo ""
        echo "3. Try tagging manually to test permissions:"
        echo "   skopeo copy --insecure-policy \\"
        echo "     docker://<image>:latest \\"
        echo "     docker://<image>:test-push"
        echo ""
        echo "4. If tagging works, run the automated script:"
        echo "   ./tag_images.sh -t $RELEASE_TAG --insecure-policy"
        echo ""
    else
        print_info "For detailed diagnostics, run with --debug flag:"
        echo "  ./verify_images.sh -t $RELEASE_TAG --debug"
        echo ""
    fi

    print_warning "You must tag and push these images before creating the release branch!"
    print_info "Run: ./tag_images.sh -t $RELEASE_TAG"
    echo ""
    exit 1
fi

# --- Digest equality check: :RELEASE_TAG must resolve to the pinned digest ---
# The pinned digest (from kustomize images: blocks and digest-pinned VM url: fields)
# is what master tested. This guards against :release-X pointing at a different build.
echo ""
echo "=========================================="
print_info "Digest Equality Check"
echo "=========================================="
echo ""

# --raw digest must be computed WITHOUT --override-arch so we compare the
# manifest-list (index) digest, matching how the pins were resolved.
# Reuses the name|digest map ($digest_tmp) built during detection above.
RAW_OPTS=""
[[ -n "$AUTHFILE" ]] && RAW_OPTS="--authfile $AUTHFILE"

digest_mismatch=0
digest_checked=0
while IFS='|' read -r name want; do
    [[ -z "$name" || -z "$want" ]] && continue
    digest_checked=$((digest_checked + 1))
    got="sha256:$(skopeo inspect --raw $RAW_OPTS "docker://${name}:${RELEASE_TAG}" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    if [[ "$got" == "$want" ]]; then
        print_success "${name}:${RELEASE_TAG} matches pinned ${want}"
    else
        print_error "${name}:${RELEASE_TAG} digest mismatch"
        echo "    pinned: $want"
        echo "    actual: $got"
        digest_mismatch=1
    fi
done < "$digest_tmp"

echo ""
if [[ "$digest_mismatch" -eq 1 ]]; then
    print_error "One or more :${RELEASE_TAG} tags do not match the pinned digest!"
    print_info "Re-run tagging from the pinned digests: ./tag_images.sh -t $RELEASE_TAG"
    echo ""
    exit 1
fi
print_success "All $digest_checked release tag(s) resolve to the pinned digest"

echo ""
print_success "All required images exist in Quay!"
echo ""
print_info "You can now proceed with creating the release branch:"
echo "  ./create_rdr_release.sh -b $RELEASE_TAG"
echo ""
