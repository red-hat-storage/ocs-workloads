#!/bin/bash

# Script to tag and push RDR container images for a release
# This script should be run BEFORE create_rdr_release.sh

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Tag and push RDR container images to Quay.io for a release.

OPTIONS:
    -t, --tag TAG_NAME         Release tag name (required, e.g., release-4.17)
    -m, --method METHOD        Tagging method: docker, podman, or skopeo (default: skopeo)
    -d, --dry-run              Show what would be done without making changes
    -h, --help                 Show this help message

EXAMPLES:
    $0 -t release-4.17
    $0 --tag release-4.17 --method docker
    $0 -t release-4.17 -d

DESCRIPTION:
    This script will tag and push all 7 required container images from :latest
    to your specified release tag.

    Images that will be tagged:
      - quay.io/ocsci/rdr-ocs-workload
      - quay.io/ocsci/filebrowser
      - quay.io/prsurve/mongodb_rdr
      - quay.io/prsurve/mongodb_data_write
      - quay.io/prsurve/mysql
      - quay.io/prsurve/mysql_data_write
      - quay.io/prsurve/filebrowser_data_write

NOTES:
    - Run this script BEFORE create_rdr_release.sh
    - Ensure you have push permissions to Quay repositories
    - Skopeo method is recommended (fastest, no local pull required)

EOF
    exit 1
}

# Parse command line arguments
RELEASE_TAG=""
METHOD="skopeo"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            RELEASE_TAG="$2"
            shift 2
            ;;
        -m|--method)
            METHOD="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
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

# Validate method
if [[ "$METHOD" != "docker" && "$METHOD" != "podman" && "$METHOD" != "skopeo" ]]; then
    print_error "Invalid method: $METHOD. Must be docker, podman, or skopeo"
    exit 1
fi

# Check if the tool is available
if ! command -v "$METHOD" &> /dev/null; then
    print_error "$METHOD is not installed or not in PATH"
    exit 1
fi

print_info "RDR Container Image Tagging Script"
print_info "Release Tag: $RELEASE_TAG"
print_info "Method: $METHOD"
echo ""

# List of images to tag (excluding external prometheus image)
declare -a images=(
    "quay.io/ocsci/rdr-ocs-workload"
    "quay.io/ocsci/filebrowser"
    "quay.io/prsurve/mongodb_rdr"
    "quay.io/prsurve/mongodb_data_write"
    "quay.io/prsurve/mysql"
    "quay.io/prsurve/mysql_data_write"
    "quay.io/prsurve/filebrowser_data_write"
)

total_images=${#images[@]}
print_info "Will tag $total_images container images"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE - No images will be tagged or pushed"
    echo ""
fi

# Process each image
success_count=0
failed_count=0
declare -a failed_images

for image in "${images[@]}"; do
    print_info "Processing: $image"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  Would tag: ${image}:latest → ${image}:${RELEASE_TAG}"
        echo "  Would push: ${image}:${RELEASE_TAG}"
        ((success_count++))
    else
        case "$METHOD" in
            skopeo)
                if skopeo copy \
                    docker://${image}:latest \
                    docker://${image}:${RELEASE_TAG} 2>&1; then
                    print_success "Tagged and pushed: ${image}:${RELEASE_TAG}"
                    ((success_count++))
                else
                    print_error "Failed to tag: ${image}"
                    failed_images+=("$image")
                    ((failed_count++))
                fi
                ;;
            docker|podman)
                # Pull, tag, and push
                if ${METHOD} pull ${image}:latest && \
                   ${METHOD} tag ${image}:latest ${image}:${RELEASE_TAG} && \
                   ${METHOD} push ${image}:${RELEASE_TAG}; then
                    print_success "Tagged and pushed: ${image}:${RELEASE_TAG}"
                    ((success_count++))
                else
                    print_error "Failed to tag: ${image}"
                    failed_images+=("$image")
                    ((failed_count++))
                fi
                ;;
        esac
    fi
    echo ""
done

# Print summary
echo ""
echo "=========================================="
print_info "Summary"
echo "=========================================="
echo "Total images: $total_images"
echo "Successfully tagged: $success_count"
echo "Failed: $failed_count"
echo ""

if [[ $failed_count -gt 0 ]]; then
    print_error "Failed to tag the following images:"
    for failed_image in "${failed_images[@]}"; do
        echo "  - $failed_image"
    done
    echo ""
    exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
    print_success "Dry run completed successfully!"
    print_info "Run without -d flag to actually tag and push images"
else
    print_success "All images tagged and pushed successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Verify images in Quay.io web interface"
    echo "  2. Run: ./create_rdr_release.sh -b $RELEASE_TAG"
fi

echo ""
