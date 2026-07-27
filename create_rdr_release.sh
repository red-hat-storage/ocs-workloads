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
    -c, --check                Run preflight checks only (verify prerequisites)
    -h, --help                 Show this help message

EXAMPLES:
    $0 -b release-4.17
    $0 --branch release-4.17 --push
    $0 -b release-4.17 -d
    $0 -b release-4.17 -c

DESCRIPTION:
    This script will:
    1. Create a new git branch with the specified name
    2. Update all image tags in rdr/ folder from ':latest' to ':BRANCH_NAME'
       (excluding external images like quay.io/prometheus/*)
    3. Commit the changes
    4. Optionally push to remote

EOF
    exit 1
}

# Parse command line arguments
BRANCH_NAME=""
PUSH_TO_REMOTE=false
DRY_RUN=false
PREFLIGHT=false

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
        -c|--check)
            PREFLIGHT=true
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

# Check quay.io login
check_quay_login() {
    local container_cli=""
    if command -v podman &>/dev/null; then
        container_cli="podman"
    elif command -v docker &>/dev/null; then
        container_cli="docker"
    else
        print_warning "Neither podman nor docker found. Cannot verify quay.io login."
        read -p "Do you want to continue anyway? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted by user."
            exit 0
        fi
        return
    fi

    print_info "Checking quay.io login using $container_cli..."
    if $container_cli login --get-login quay.io &>/dev/null; then
        local user
        user=$($container_cli login --get-login quay.io 2>/dev/null)
        print_success "Logged into quay.io as: $user"
    else
        print_warning "Not logged into quay.io via $container_cli."
        print_info "Run '$container_cli login quay.io' to authenticate."
        read -p "Do you want to continue anyway? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted by user."
            exit 0
        fi
    fi
}

run_preflight() {
    local branch=$1
    local pass=0 fail=0 warn=0

    echo ""
    print_info "=== Preflight Checks ==="
    echo ""

    # 1. Required CLI tools
    local missing_tools=()
    for tool in git sed find grep; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}[PASS]${NC} Required CLI tools (git, sed, find, grep)"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} Required CLI tools — missing: ${missing_tools[*]}"
        fail=$((fail + 1))
    fi

    # 2. Git repository
    if git rev-parse --git-dir &>/dev/null; then
        echo -e "  ${GREEN}[PASS]${NC} Inside a git repository"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} Not inside a git repository"
        fail=$((fail + 1))
    fi

    # 3. rdr/ directory exists
    if [[ -d "rdr" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} rdr/ directory exists"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} rdr/ directory not found (run from repo root)"
        fail=$((fail + 1))
    fi

    # 4. On master/main branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" == "master" || "$current_branch" == "main" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} On branch: $current_branch"
        pass=$((pass + 1))
    else
        echo -e "  ${YELLOW}[WARN]${NC} Not on master/main (current: $current_branch)"
        warn=$((warn + 1))
    fi

    # 5. Remote reachable
    if git ls-remote origin HEAD &>/dev/null; then
        echo -e "  ${GREEN}[PASS]${NC} Remote 'origin' is reachable"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} Cannot reach remote 'origin'"
        fail=$((fail + 1))
    fi

    # 6. Branch doesn't already exist (local + remote)
    local branch_exists_local=0 branch_exists_remote=0
    if git rev-parse --verify "$branch" &>/dev/null; then
        branch_exists_local=1
    fi
    if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
        branch_exists_remote=1
    fi
    if [[ "$branch_exists_local" -eq 0 && "$branch_exists_remote" -eq 0 ]]; then
        echo -e "  ${GREEN}[PASS]${NC} Branch '$branch' does not exist (local or remote)"
        pass=$((pass + 1))
    else
        local where=""
        [[ "$branch_exists_local" -eq 1 ]] && where="local"
        [[ "$branch_exists_remote" -eq 1 ]] && where="${where:+$where + }remote"
        echo -e "  ${RED}[FAIL]${NC} Branch '$branch' already exists ($where)"
        fail=$((fail + 1))
    fi

    # 7. Container CLI available
    local container_cli=""
    if command -v podman &>/dev/null; then
        container_cli="podman"
    elif command -v docker &>/dev/null; then
        container_cli="docker"
    fi
    if [[ -n "$container_cli" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} Container CLI available: $container_cli"
        pass=$((pass + 1))
    else
        echo -e "  ${YELLOW}[WARN]${NC} No container CLI (podman/docker) found — skipping login check"
        warn=$((warn + 1))
    fi

    # 8. quay.io login
    if [[ -n "$container_cli" ]]; then
        if $container_cli login --get-login quay.io &>/dev/null; then
            local user
            user=$($container_cli login --get-login quay.io 2>/dev/null)
            echo -e "  ${GREEN}[PASS]${NC} Logged into quay.io as: $user"
            pass=$((pass + 1))
        else
            echo -e "  ${RED}[FAIL]${NC} Not logged into quay.io (run: $container_cli login quay.io)"
            fail=$((fail + 1))
        fi
    else
        echo -e "  ${YELLOW}[WARN]${NC} quay.io login — skipped (no container CLI)"
        warn=$((warn + 1))
    fi

    # 9. skopeo available
    local has_skopeo=0
    if command -v skopeo &>/dev/null; then
        echo -e "  ${GREEN}[PASS]${NC} skopeo is available"
        pass=$((pass + 1))
        has_skopeo=1
    else
        echo -e "  ${YELLOW}[WARN]${NC} skopeo not found"
        warn=$((warn + 1))
    fi

    # 10. Verify source images exist on quay.io
    if [[ "$has_skopeo" -eq 1 ]]; then
        echo ""
        print_info "Verifying source images exist on quay.io..."
        local all_images
        all_images=$(
            {
                grep -rh "image:.*:latest" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null
                grep -rh "value:.*:latest" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null
            } | grep -v "quay.io/prometheus" | grep -v "^\s*#" \
              | sed -E "s/.*(image|value):[[:space:]]*//" \
              | sed "s/['\"]//g" \
              | sort -u
        )
        local vm_imgs
        vm_imgs=$(
            grep -rh "url:.*docker://" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null \
              | grep -v "^\s*#" \
              | sed -E "s/.*url:[[:space:]]*//" \
              | sed "s/['\"]//g" | sed "s|docker://||" \
              | sort -u
        )
        local combined
        combined=$(echo -e "${all_images}\n${vm_imgs}" | grep -v "^$" | sort -u)

        if [[ -n "$combined" ]]; then
            local img_pass=0 img_fail=0
            while IFS= read -r img; do
                if skopeo inspect "docker://${img}" &>/dev/null; then
                    echo -e "  ${GREEN}[PASS]${NC} Image exists: $img"
                    img_pass=$((img_pass + 1))
                else
                    echo -e "  ${RED}[FAIL]${NC} Image NOT found: $img"
                    img_fail=$((img_fail + 1))
                fi
            done <<< "$combined"
            pass=$((pass + img_pass))
            fail=$((fail + img_fail))
        else
            echo -e "  ${YELLOW}[WARN]${NC} No images found in rdr/ YAML files"
            warn=$((warn + 1))
        fi
    else
        echo -e "  ${YELLOW}[WARN]${NC} Image existence check — skipped (skopeo not found)"
        warn=$((warn + 1))
    fi

    # Summary
    echo ""
    print_info "=== Preflight Summary ==="
    echo -e "  ${GREEN}PASS: $pass${NC}  ${RED}FAIL: $fail${NC}  ${YELLOW}WARN: $warn${NC}"
    echo ""

    if [[ "$fail" -gt 0 ]]; then
        print_error "Preflight checks failed. Fix the issues above before running the release."
        return 1
    else
        print_success "All preflight checks passed!"
        return 0
    fi
}

# Run preflight checks if requested
if [[ "$PREFLIGHT" == "true" ]]; then
    run_preflight "$BRANCH_NAME"
    exit $?
fi

if [[ "$DRY_RUN" == "false" ]]; then
    check_quay_login
    echo ""
fi

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

    # Check for image tags (excluding prometheus images)
    local has_image_tags=0
    if grep "image:.*:latest" "$file" 2>/dev/null | grep -qv "quay.io/prometheus"; then
        has_image_tags=1
    fi

    # Check for kustomize patch value: image references (excluding prometheus)
    local has_kustomize_images=0
    if grep "value:.*:latest" "$file" 2>/dev/null | grep -qv "quay.io/prometheus"; then
        has_kustomize_images=1
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

    # Check for VM containerDisk images (url: docker://)
    local has_vm_images=0
    if grep -q "url:.*docker://" "$file" 2>/dev/null; then
        has_vm_images=1
    fi

    # Warn about non-master branch references in git-branch/github-branch annotations
    if grep -q -E "git-branch:|github-branch:" "$file" 2>/dev/null; then
        local non_master_branches
        non_master_branches=$(grep -E "git-branch:|github-branch:" "$file" | grep -v "master" | grep -v "^\s*#")
        if [[ -n "$non_master_branches" ]]; then
            print_warning "Skipping non-master branch reference in $file:"
            echo "$non_master_branches" | while read -r line; do
                echo "    $line"
            done
        fi
    fi

    # Skip if no changes needed
    if [[ "$has_image_tags" -eq 0 && "$has_kustomize_images" -eq 0 && "$has_target_revision" -eq 0 && "$has_git_branch" -eq 0 && "$has_github_url" -eq 0 && "$has_vm_images" -eq 0 ]]; then
        return 1
    fi

    print_info "Updating: $file"

    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN - Would update:"

        # Show image tag changes (excluding prometheus images)
        if [[ "$has_image_tags" -eq 1 ]]; then
            echo "  Image tags:"
            grep "image:.*:latest" "$file" | grep -v "quay.io/prometheus" | sed "s/image:/  /" | while read -r line; do
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

        # Show kustomize patch value: image changes (excluding prometheus)
        if [[ "$has_kustomize_images" -eq 1 ]]; then
            echo "  Kustomize patch images:"
            grep "value:.*:latest" "$file" | grep -v "quay.io/prometheus" | while read -r line; do
                echo "    OLD: $line"
                echo "    NEW: ${line/:latest/:${branch}}"
            done
        fi

        # Show VM containerDisk image changes (excluding prometheus)
        if [[ "$has_vm_images" -eq 1 ]]; then
            echo "  VM Images (containerDisk):"
            grep "url:.*docker://" "$file" | while read -r line; do
                local old_url=$(echo "$line" | sed 's/.*url:[[:space:]]*//g' | sed "s/'//g" | sed 's/"//g')
                local new_url=$(echo "$old_url" | sed "s/\(.*\):[^:]*$/\1:${branch}/")
                echo "    OLD: $old_url"
                echo "    NEW: $new_url"
            done
        fi
    else
        # Apply changes based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed requires '' after -i
            [[ "$has_image_tags" -eq 1 ]] && sed -i '' "/quay.io\/prometheus/!s/:latest/:${branch}/g" "$file"
            [[ "$has_kustomize_images" -eq 1 ]] && sed -i '' "/quay.io\/prometheus/!s/:latest/:${branch}/g" "$file"
            [[ "$has_target_revision" -eq 1 ]] && sed -i '' "s/targetRevision: master/targetRevision: ${branch}/g" "$file"
            [[ "$has_git_branch" -eq 1 ]] && sed -i '' "s/\(git-branch: \)master/\1${branch}/g; s/\(github-branch: \)master/\1${branch}/g" "$file"
            [[ "$has_github_url" -eq 1 ]] && sed -i '' "s|raw.githubusercontent.com/red-hat-storage/ocs-workloads/master|raw.githubusercontent.com/red-hat-storage/ocs-workloads/${branch}|g" "$file"
            [[ "$has_vm_images" -eq 1 ]] && sed -i '' "s|\(url:.*docker://[^:]*\):[^'\"[:space:]]*|\1:${branch}|g" "$file"
        else
            # Linux sed doesn't need '' after -i
            [[ "$has_image_tags" -eq 1 ]] && sed -i "/quay.io\/prometheus/!s/:latest/:${branch}/g" "$file"
            [[ "$has_kustomize_images" -eq 1 ]] && sed -i "/quay.io\/prometheus/!s/:latest/:${branch}/g" "$file"
            [[ "$has_target_revision" -eq 1 ]] && sed -i "s/targetRevision: master/targetRevision: ${branch}/g" "$file"
            [[ "$has_git_branch" -eq 1 ]] && sed -i "s/\(git-branch: \)master/\1${branch}/g; s/\(github-branch: \)master/\1${branch}/g" "$file"
            [[ "$has_github_url" -eq 1 ]] && sed -i "s|raw.githubusercontent.com/red-hat-storage/ocs-workloads/master|raw.githubusercontent.com/red-hat-storage/ocs-workloads/${branch}|g" "$file"
            [[ "$has_vm_images" -eq 1 ]] && sed -i "s|\(url:.*docker://[^:]*\):[^'\"[:space:]]*|\1:${branch}|g" "$file"
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
            updated_count=$((updated_count + 1))
            echo ""
        fi
    done < <(find rdr -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)

    # Image update summary
    echo ""
    print_info "=== Image Update Summary ==="
    echo ""

    print_success "Images that WILL be retagged to :${BRANCH_NAME}:"
    updated_images=$(
        {
            grep -rh "image:.*:latest" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null
            grep -rh "value:.*:latest" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null
        } | grep -v "quay.io/prometheus" | grep -v "^\s*#" \
          | sed -E "s/.*(image|value):[[:space:]]*//" \
          | sed "s/['\"]//g" \
          | sort -u
    )
    vm_images=$(
        grep -rh "url:.*docker://" rdr/ --include="*.yaml" --include="*.yml" 2>/dev/null \
          | grep -v "^\s*#" \
          | sed -E "s/.*url:[[:space:]]*//" \
          | sed "s/['\"]//g" | sed "s|docker://||" \
          | sort -u
    )
    if [[ -n "$updated_images" ]]; then
        echo "$updated_images" | while read -r img; do
            echo "    ${img} → ${img/:latest/:${BRANCH_NAME}}"
        done
    fi
    if [[ -n "$vm_images" ]]; then
        echo "$vm_images" | while read -r img; do
            new_img=$(echo "$img" | sed "s/\(.*\):[^:]*$/\1:${BRANCH_NAME}/")
            echo "    ${img} → ${new_img}"
        done
    fi
    if [[ -z "$updated_images" && -z "$vm_images" ]]; then
        echo "    (none)"
    fi

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
        updated_count=$((updated_count + 1))
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
