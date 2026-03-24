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

# Extract all unique images, excluding external images
# Handles both "image:" fields and "url: docker://" fields
declare -a images
while IFS= read -r image; do
    images+=("$image")
done < <(
    {
        # Pattern 1: image: with :latest tag
        grep -rh "image:.*:latest" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null | \
        sed 's/.*image:[[:space:]]*//g' | \
        sed 's/:latest//g'

        # Pattern 2: url: docker:// with any tag (for VM images)
        grep -rh "url:.*docker://" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null | \
        sed 's/.*docker:\/\///g' | \
        sed 's/\(.*\):[^:]*$/\1/'  # Remove tag
    } | \
    sed 's/[[:space:]]*#.*//g' | \
    sed "s/'//g" | \
    sed 's/"//g' | \
    grep -v "^$" | \
    grep -v "quay.io/prometheus" | \
    sort -u
)

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

for image in "${images[@]}"; do
    full_image="${image}:${RELEASE_TAG}"

    if skopeo inspect $SKOPEO_OPTS docker://${full_image} &> /dev/null; then
        print_success "$full_image"
        ((success_count++))
    else
        print_error "$full_image (NOT FOUND)"
        missing_images+=("$full_image")
        ((failed_count++))

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
print_info "Verification Summary"
echo "=========================================="
echo "Total images checked: $total_images"
echo "Found: $success_count"
echo "Missing: $failed_count"
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

print_success "All required images exist in Quay!"
echo ""
print_info "You can now proceed with creating the release branch:"
echo "  ./create_rdr_release.sh -b $RELEASE_TAG"
echo ""
