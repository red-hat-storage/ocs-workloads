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
    -a, --authfile FILE        Path to authentication file for skopeo (optional)
    -d, --dry-run              Show what would be done without making changes
    -h, --help                 Show this help message

EXAMPLES:
    $0 -t release-4.17
    $0 --tag release-4.17 --method docker
    $0 -t release-4.17 -a ~/.docker/config.json
    $0 -t release-4.17 -d

DESCRIPTION:
    This script automatically detects and tags all container images found in the
    rdr/ directory. It handles both:
      - Container images with :latest tag
      - VM containerDisk images with any version tag (e.g., :0.6.3)

    The script preserves multi-architecture manifests using:
      - skopeo: Uses --all flag to explicitly copy all architectures
      - docker/podman: Preserves multi-arch by default

    Auto-detected images (example):
      - quay.io/ocsci/rdr-ocs-workload:latest → :release-4.17
      - quay.io/ocsci/filebrowser:latest → :release-4.17
      - quay.io/ocsci/cirros-dd:0.6.3 → :release-4.17 (VM image)
      - quay.io/prsurve/mongodb_rdr:latest → :release-4.17
      - And more...

NOTES:
    - Run this script BEFORE create_rdr_release.sh
    - Ensure you have push permissions to Quay repositories
    - Skopeo method is recommended (fastest, no local pull required)
    - Multi-arch images are fully preserved with all architectures

AUTHENTICATION:
    By default, skopeo uses cached credentials from previous logins:
      skopeo login quay.io

    You can also specify a custom auth file:
      $0 -t release-4.17 -a ~/.docker/config.json
      $0 -t release-4.17 -a \${XDG_RUNTIME_DIR}/containers/auth.json

EOF
    exit 1
}

# Parse command line arguments
RELEASE_TAG=""
METHOD="skopeo"
AUTHFILE=""
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
        -a|--authfile)
            AUTHFILE="$2"
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

# Prevent using reserved names
if [[ "$RELEASE_TAG" == "latest" ]]; then
    print_error "Cannot use 'latest' as release tag!"
    print_info "'latest' is the tag being replaced, not a valid release name."
    print_info "Use a semantic release tag like: release-4.17, release-4.18, etc."
    exit 1
fi

if [[ "$RELEASE_TAG" == "master" || "$RELEASE_TAG" == "main" ]]; then
    print_error "Cannot use 'master' or 'main' as release tag!"
    print_info "These are reserved for main development branches."
    print_info "Use a release tag name like: release-4.17, release-4.18, etc."
    exit 1
fi

# Enforce that release tag must start with "release-"
if [[ ! "$RELEASE_TAG" =~ ^release- ]]; then
    print_error "Release tag must start with 'release-'"
    print_info "Current value: $RELEASE_TAG"
    print_info "Valid examples: release-4.17, release-4.18, release-5.0, etc."
    exit 1
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

# Validate authfile if provided
if [[ -n "$AUTHFILE" ]]; then
    if [[ ! -f "$AUTHFILE" ]]; then
        print_error "Authentication file not found: $AUTHFILE"
        exit 1
    fi
    if [[ "$METHOD" != "skopeo" ]]; then
        print_warning "Authentication file is only supported with skopeo method"
        print_info "Ignoring --authfile option"
        AUTHFILE=""
    fi
fi

print_info "RDR Container Image Tagging Script"
print_info "Release Tag: $RELEASE_TAG"
print_info "Method: $METHOD"
if [[ -n "$AUTHFILE" ]]; then
    print_info "Auth File: $AUTHFILE"
fi
echo ""

# Check if rdr/ directory exists
if [[ ! -d "rdr" ]]; then
    print_error "rdr/ directory not found! Please run this script from the repository root."
    exit 1
fi

# Auto-detect all images from rdr/ directory
print_info "Scanning rdr/ directory for container images..."

# Use parallel arrays for bash 3.x compatibility
declare -a image_names
declare -a image_current_tags

# Temporary file to collect all images with their current tags
temp_file=$(mktemp)
trap 'rm -f "$temp_file"' EXIT

# Pattern 1: Extract images with :latest tag (container images)
grep -rh "image:.*:latest" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null | \
    sed 's/.*image:[[:space:]]*//g' | \
    sed 's/[[:space:]]*#.*//g' | \
    sed "s/'//g" | \
    sed 's/"//g' | \
    grep -v "^$" | \
    grep -v "quay.io/prometheus" | \
    sort -u | \
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        image=$(echo "$line" | sed 's/:latest$//')
        echo "${image}|latest" >> "$temp_file"
    fi
done

# Pattern 2: Extract VM images with any tag (containerDisk images)
grep -rh "url:.*docker://" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null | \
    grep -v "quay.io/prometheus" | \
    sort -u | \
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        # Extract full image with tag: quay.io/ocsci/cirros-dd:0.6.3
        full_image=$(echo "$line" | sed 's/.*docker:\/\///g' | sed 's/[[:space:]]*#.*//g' | sed "s/'//g" | sed 's/"//g')
        # Extract image without tag: quay.io/ocsci/cirros-dd
        image=$(echo "$full_image" | sed 's/:[^:]*$//')
        # Extract current tag: 0.6.3
        current_tag=$(echo "$full_image" | sed 's/.*://')

        # Check if image already exists in temp file
        if ! grep -q "^${image}|" "$temp_file" 2>/dev/null; then
            echo "${image}|${current_tag}" >> "$temp_file"
        fi
    fi
done

# Read unique images into parallel arrays (avoid subshell by using process substitution correctly)
while IFS='|' read -r img_name img_tag; do
    image_names+=("$img_name")
    image_current_tags+=("$img_tag")
done < <(sort -u "$temp_file" 2>/dev/null)

total_images=${#image_names[@]}

if [[ $total_images -eq 0 ]]; then
    print_warning "No container images found in rdr/ directory"
    print_info "This might mean:"
    echo "  - All images are already tagged with a specific version"
    echo "  - There are no YAML files with container images"
    echo "  - You're not in the repository root directory"
    exit 0
fi

print_success "Found $total_images unique image(s) to tag"
echo ""

# Show the images that will be tagged
print_info "Images to be tagged:"
for ((i=0; i<${#image_names[@]}; i++)); do
    echo "  - ${image_names[$i]}:${image_current_tags[$i]} → ${image_names[$i]}:${RELEASE_TAG}"
done
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE - No images will be tagged or pushed"
    echo ""
fi

# Process each image
success_count=0
failed_count=0
declare -a failed_images

for ((i=0; i<${#image_names[@]}; i++)); do
    image="${image_names[$i]}"
    current_tag="${image_current_tags[$i]}"
    print_info "Processing: $image"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  Would tag: ${image}:${current_tag} → ${image}:${RELEASE_TAG}"
        echo "  Would push: ${image}:${RELEASE_TAG}"
        ((success_count++))
    else
        case "$METHOD" in
            skopeo)
                # Use --all flag to explicitly preserve multi-arch manifests
                # This ensures all architectures (amd64, arm64, etc.) are copied

                # Build skopeo command with optional authfile
                skopeo_opts="--all"
                if [[ -n "$AUTHFILE" ]]; then
                    skopeo_opts="$skopeo_opts --authfile $AUTHFILE"
                fi

                if skopeo copy $skopeo_opts \
                    docker://${image}:${current_tag} \
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
                # Note: docker/podman preserve multi-arch manifests by default when pulling
                # The manifest list is maintained across tag and push operations
                if ${METHOD} pull ${image}:${current_tag} && \
                   ${METHOD} tag ${image}:${current_tag} ${image}:${RELEASE_TAG} && \
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
