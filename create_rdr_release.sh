#!/bin/bash

# Script to create a release branch and update RDR workload images
# This script only affects the rdr/ folder

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

Create a release branch and update RDR workload image tags.

OPTIONS:
    -b, --branch BRANCH_NAME    Release branch name (required)
    -p, --push                  Push changes to remote repository
    -d, --dry-run              Show what would be changed without making changes
    -h, --help                 Show this help message

EXAMPLES:
    $0 -b release-4.17
    $0 --branch release-4.17 --push
    $0 -b release-4.17 -d

DESCRIPTION:
    This script will:
    1. Create a new git branch with the specified name
    2. Update all image tags in rdr/ folder from ':latest' to ':BRANCH_NAME'
    3. Commit the changes
    4. Optionally push to remote

EOF
    exit 1
}

# Parse command line arguments
BRANCH_NAME=""
PUSH_TO_REMOTE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        -p|--push)
            PUSH_TO_REMOTE=true
            shift
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

# Validate branch name
if [[ -z "$BRANCH_NAME" ]]; then
    print_error "Branch name is required!"
    usage
fi

# Prevent using reserved names
if [[ "$BRANCH_NAME" == "master" || "$BRANCH_NAME" == "main" ]]; then
    print_error "Cannot use 'master' or 'main' as release branch name!"
    print_info "These are reserved for the main development branches."
    print_info "Use a release branch name like: release-4.17, release-4.18, etc."
    exit 1
fi

if [[ "$BRANCH_NAME" == "latest" ]]; then
    print_error "Cannot use 'latest' as release branch name!"
    print_info "'latest' is the tag being replaced, not a valid release name."
    print_info "Use a semantic release name like: release-4.17, release-4.18, etc."
    exit 1
fi

# Enforce that branch name must start with "release-"
if [[ ! "$BRANCH_NAME" =~ ^release- ]]; then
    print_error "Branch name must start with 'release-'"
    print_info "Current value: $BRANCH_NAME"
    print_info "Valid examples: release-4.17, release-4.18, release-5.0, etc."
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository!"
    exit 1
fi

# Check if rdr/ directory exists
if [[ ! -d "rdr" ]]; then
    print_error "rdr/ directory not found! Please run this script from the repository root."
    exit 1
fi

print_info "Starting RDR release process for branch: $BRANCH_NAME"
echo ""

# Check for uncommitted changes
if [[ -n $(git status -s) ]]; then
    print_warning "You have uncommitted changes:"
    git status -s
    echo ""
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Aborted by user."
        exit 0
    fi
fi

# Function to update image tags and branch references in a file
update_file() {
    local file=$1
    local branch=$2
    local dry_run=$3

    # Check for image tags
    local has_image_tags=0
    if grep -q "image:.*:latest" "$file" 2>/dev/null; then
        has_image_tags=1
    fi

    # Check for targetRevision: master
    local has_target_revision=0
    if grep -q "targetRevision: master" "$file" 2>/dev/null; then
        has_target_revision=1
    fi

    # Check for git-branch: master or github-branch: master
    local has_git_branch=0
    if grep -q -E "git-branch: master|github-branch: master" "$file" 2>/dev/null; then
        has_git_branch=1
    fi

    # Check for GitHub raw URLs with master branch
    local has_github_url=0
    if grep -q "raw.githubusercontent.com/red-hat-storage/ocs-workloads/master" "$file" 2>/dev/null; then
        has_github_url=1
    fi

    # Skip if no changes needed
    if [[ "$has_image_tags" -eq 0 && "$has_target_revision" -eq 0 && "$has_git_branch" -eq 0 && "$has_github_url" -eq 0 ]]; then
        return 1
    fi

    print_info "Updating: $file"

    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN - Would update:"

        # Show image tag changes
        if [[ "$has_image_tags" -eq 1 ]]; then
            echo "  Image tags:"
            grep "image:.*:latest" "$file" | sed "s/image:/  /" | while read -r line; do
                echo "    OLD: $line"
                echo "    NEW: ${line/:latest/:${branch}}"
            done
        fi

        # Show targetRevision changes
        if [[ "$has_target_revision" -eq 1 ]]; then
            echo "  Target Revision:"
            grep "targetRevision: master" "$file" | while read -r line; do
                echo "    OLD: $line"
                echo "    NEW: ${line/master/${branch}}"
            done
        fi

        # Show git-branch changes
        if [[ "$has_git_branch" -eq 1 ]]; then
            echo "  Git Branch:"
            grep -E "git-branch: master|github-branch: master" "$file" | while read -r line; do
                echo "    OLD: $line"
                echo "    NEW: ${line/master/${branch}}"
            done
        fi

        # Show GitHub URL changes
        if [[ "$has_github_url" -eq 1 ]]; then
            echo "  GitHub URLs:"
            grep "raw.githubusercontent.com/red-hat-storage/ocs-workloads/master" "$file" | while read -r line; do
                echo "    OLD: ...ocs-workloads/master/..."
                echo "    NEW: ...ocs-workloads/${branch}/..."
            done
        fi
    else
        # Apply changes based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed requires '' after -i
            [[ "$has_image_tags" -eq 1 ]] && sed -i '' "s/:latest/:${branch}/g" "$file"
            [[ "$has_target_revision" -eq 1 ]] && sed -i '' "s/targetRevision: master/targetRevision: ${branch}/g" "$file"
            [[ "$has_git_branch" -eq 1 ]] && sed -i '' "s/\(git-branch: \)master/\1${branch}/g; s/\(github-branch: \)master/\1${branch}/g" "$file"
            [[ "$has_github_url" -eq 1 ]] && sed -i '' "s|raw.githubusercontent.com/red-hat-storage/ocs-workloads/master|raw.githubusercontent.com/red-hat-storage/ocs-workloads/${branch}|g" "$file"
        else
            # Linux sed doesn't need '' after -i
            [[ "$has_image_tags" -eq 1 ]] && sed -i "s/:latest/:${branch}/g" "$file"
            [[ "$has_target_revision" -eq 1 ]] && sed -i "s/targetRevision: master/targetRevision: ${branch}/g" "$file"
            [[ "$has_git_branch" -eq 1 ]] && sed -i "s/\(git-branch: \)master/\1${branch}/g; s/\(github-branch: \)master/\1${branch}/g" "$file"
            [[ "$has_github_url" -eq 1 ]] && sed -i "s|raw.githubusercontent.com/red-hat-storage/ocs-workloads/master|raw.githubusercontent.com/red-hat-storage/ocs-workloads/${branch}|g" "$file"
        fi
        print_success "Updated: $file"
    fi
    return 0
}

# If dry run, just show what would be changed
if [[ "$DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE - No changes will be made"
    echo ""

    print_info "Searching for YAML files with ':latest' tag in rdr/ directory..."
    echo ""

    updated_count=0
    while IFS= read -r -d '' file; do
        if update_file "$file" "$BRANCH_NAME" "true"; then
            ((updated_count++))
            echo ""
        fi
    done < <(find rdr -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)

    echo ""
    print_info "Total files that would be updated: $updated_count"
    print_info "Run without -d flag to apply changes"
    exit 0
fi

# Check if branch already exists locally
if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
    print_warning "Branch '$BRANCH_NAME' already exists locally."
    read -p "Do you want to switch to it and update images? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Aborted by user."
        exit 0
    fi
    git checkout "$BRANCH_NAME"
else
    # Create new branch
    print_info "Creating new branch: $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME"
    print_success "Branch created and checked out"
fi

echo ""
print_info "Updating image tags in rdr/ directory..."
echo ""

# Find all YAML files in rdr/ directory and update them
updated_count=0
while IFS= read -r -d '' file; do
    if update_file "$file" "$BRANCH_NAME" "false"; then
        ((updated_count++))
    fi
done < <(find rdr -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)

echo ""
if [[ $updated_count -eq 0 ]]; then
    print_warning "No files were updated. All images may already be using the correct tag."
    exit 0
fi

print_success "Updated $updated_count file(s)"
echo ""

# Show git diff
print_info "Changes made:"
git diff rdr/

echo ""
read -p "Do you want to commit these changes? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Changes not committed. You can review and commit manually."
    exit 0
fi

# Commit changes
print_info "Committing changes..."
git add rdr/
git commit -m "Update RDR workload images to use $BRANCH_NAME tag

- Updated all image tags from :latest to :$BRANCH_NAME
- Only affects rdr/ directory
- Automated update via create_rdr_release.sh"

print_success "Changes committed"

# Push to remote if requested
if [[ "$PUSH_TO_REMOTE" == "true" ]]; then
    echo ""
    print_info "Pushing branch to remote..."

    if git push -u origin "$BRANCH_NAME"; then
        print_success "Branch pushed to remote successfully"
    else
        print_error "Failed to push to remote"
        exit 1
    fi
fi

echo ""
print_success "Release branch '$BRANCH_NAME' created successfully!"
echo ""
print_info "Summary:"
echo "  - Branch: $BRANCH_NAME"
echo "  - Files updated: $updated_count"
echo "  - Changes committed: Yes"
echo "  - Pushed to remote: $PUSH_TO_REMOTE"
echo ""

if [[ "$PUSH_TO_REMOTE" == "false" ]]; then
    print_info "To push this branch to remote, run:"
    echo "  git push -u origin $BRANCH_NAME"
fi

print_success "Done!"
