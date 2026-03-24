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
    -h, --help                 Show this help message

EXAMPLES:
    $0 -t release-4.17
    $0 --tag release-4.18

DESCRIPTION:
    This script verifies that all 7 required container images exist in Quay
    with the specified release tag before you run create_rdr_release.sh.

REQUIREMENTS:
    - skopeo must be installed

EOF
    exit 1
}

# Parse command line arguments
RELEASE_TAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            RELEASE_TAG="$2"
            shift 2
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

for image in "${images[@]}"; do
    full_image="${image}:${RELEASE_TAG}"

    if skopeo inspect docker://${full_image} &> /dev/null; then
        print_success "$full_image"
        ((success_count++))
    else
        print_error "$full_image (NOT FOUND)"
        missing_images+=("$full_image")
        ((failed_count++))
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
