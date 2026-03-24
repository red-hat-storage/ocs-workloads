# RDR Release Management Guide

This guide explains the complete workflow for creating RDR releases, including tagging container images and updating YAML configurations.

## Overview

Creating a release involves two main steps:

1. **Tag Container Images** - Tag and push 7 container images to Quay.io
2. **Create Release Branch** - Create git branch and update YAML files

The repository provides three scripts to automate this process:
- `tag_images.sh` - Tag and push container images to Quay
- `verify_images.sh` - Verify images exist in Quay before release
- `create_rdr_release.sh` - Create git branch and update YAML files

## Prerequisites

- You must be in the repository root directory
- Git repository must be initialized
- `rdr/` directory must exist
- **IMPORTANT**: Container images must be tagged in Quay BEFORE creating the release branch
- You need push permissions to Quay repositories:
  - `quay.io/ocsci/*` (3 images)
  - `quay.io/prsurve/*` (5 images)
- **Authentication**: Login to Quay.io before running image tagging:
  ```bash
  # Login to Quay.io (credentials will be cached)
  skopeo login quay.io
  # OR
  docker login quay.io
  # OR
  podman login quay.io
  ```

## Quick Start - Complete Workflow

For a new release (e.g., `release-4.17`), follow these steps in order:

### Step 1: Tag Container Images in Quay

```bash
# Option A: Automatic (recommended)
./tag_images.sh -t release-4.17

# Option B: Dry-run first to preview
./tag_images.sh -t release-4.17 -d
./tag_images.sh -t release-4.17

# Option C: Use different method (docker/podman instead of skopeo)
./tag_images.sh -t release-4.17 -m docker
```

### Step 2: Verify Images Exist in Quay

```bash
./verify_images.sh -t release-4.17
```

### Step 3: Create Release Branch and Update YAML Files

```bash
# Preview what will change
./create_rdr_release.sh -b release-4.17 -d

# Create the release branch
./create_rdr_release.sh -b release-4.17

# Or create and push in one command
./create_rdr_release.sh -b release-4.17 -p
```

### Step 4: Test and Deploy

Deploy workloads from the release branch and verify everything works correctly.

---

## Detailed Usage

### Container Image Tagging (`tag_images.sh`)

This script **automatically detects and tags** all container images with `:latest` tag found in the `rdr/` directory. No manual updates needed when adding new images!

**Usage:**
```bash
./tag_images.sh -t RELEASE_TAG [-m METHOD] [-a AUTHFILE] [-d]
```

**Options:**
- `-t, --tag TAG_NAME` - Release tag (required, e.g., release-4.17)
- `-m, --method METHOD` - Tagging method: docker, podman, or skopeo (default: skopeo)
- `-a, --authfile FILE` - Path to authentication file for skopeo (optional)
- `--insecure-policy` - Skip signature verification for skopeo (use if you get trust policy errors)
- `-d, --dry-run` - Preview what would be done without making changes
- `-h, --help` - Show help message

**Examples:**
```bash
# Tag using skopeo (fastest, recommended)
./tag_images.sh -t release-4.17

# Tag using docker
./tag_images.sh -t release-4.17 -m docker

# Tag with custom auth file
./tag_images.sh -t release-4.17 -a ~/.docker/config.json

# Preview what would be tagged
./tag_images.sh -t release-4.17 -d
```

**Authentication:**
By default, skopeo uses cached credentials from `skopeo login quay.io`. You can optionally provide a custom authentication file:
```bash
# Using default cached credentials
skopeo login quay.io
./tag_images.sh -t release-4.17

# Using custom auth file
./tag_images.sh -t release-4.17 -a ~/.docker/config.json
./tag_images.sh -t release-4.17 -a ${XDG_RUNTIME_DIR}/containers/auth.json
```

**How Auto-Detection Works:**
- Scans all YAML files in `rdr/` directory
- Extracts container images with `:latest` tag
- Extracts VM containerDisk images with any version tag
- Detects current tag for each image (latest, 0.6.3, etc.)
- Excludes external images (e.g., `quay.io/prometheus/*`)
- Shows you the complete list before tagging

**Example Output:**
```
[INFO] Scanning rdr/ directory for container images...
[SUCCESS] Found 8 unique image(s) to tag

[INFO] Images to be tagged:
  - quay.io/ocsci/cirros-dd:0.6.3 → quay.io/ocsci/cirros-dd:release-4.17
  - quay.io/ocsci/filebrowser:latest → quay.io/ocsci/filebrowser:release-4.17
  - quay.io/ocsci/rdr-ocs-workload:latest → quay.io/ocsci/rdr-ocs-workload:release-4.17
  - quay.io/prsurve/filebrowser_data_write:latest → ...
  [and more...]
```

**Multi-Architecture Preservation:**
- ✅ **skopeo** (recommended): Uses `--all` flag to copy all architectures
- ✅ **docker/podman**: Preserves multi-arch manifests by default
- ✅ All architectures (amd64, arm64, etc.) are maintained in release tags

**Benefits:**
- ✅ Automatically stays synchronized with your workloads
- ✅ No script updates needed when adding new images
- ✅ Handles images with any tag (not just :latest)
- ✅ Preserves multi-architecture images
- ✅ Reduces manual maintenance

See [IMAGE_TAGGING_GUIDE.md](IMAGE_TAGGING_GUIDE.md) for detailed information.

---

### Image Verification (`verify_images.sh`)

This script verifies that all required container images exist in Quay with the specified release tag.

This script **automatically detects and verifies** that all container images exist in Quay.io before creating the release. It scans the same images found in the `rdr/` directory.

**Usage:**
```bash
./verify_images.sh -t RELEASE_TAG [OPTIONS]
```

**Options:**
- `-t, --tag TAG_NAME` - Release tag to verify (required)
- `-a, --authfile FILE` - Path to authentication file for skopeo (optional)
- `--platform PLATFORM` - Platform to check: auto (default), amd64, arm64
- `-d, --debug` - Show detailed diagnostic information for missing images
- `-h, --help` - Show help message

**Examples:**
```bash
# Basic verification
./verify_images.sh -t release-4.17

# Verify with debug information
./verify_images.sh -t release-4.17 --debug

# Verify specific platform (amd64/x86_64)
./verify_images.sh -t release-4.17 --platform amd64

# With custom auth file
./verify_images.sh -t release-4.17 -a ~/.docker/config.json
```

**Platform Support:**
- `auto` (default): Uses linux/amd64, works well on macOS with Apple Silicon
- `amd64`: Explicitly verify linux/amd64 (x86_64) images
- `arm64`: Explicitly verify linux/arm64 images

**Requirements:**
- `skopeo` must be installed
  - macOS: `brew install skopeo`
  - RHEL/Fedora: `dnf install skopeo`
  - Ubuntu: `apt install skopeo`

---

### Release Branch Creation (`create_rdr_release.sh`)

### Basic Usage

Create a release branch and update images:
```bash
./create_rdr_release.sh -b release-4.17
```

### Dry Run (Preview Changes)

See what would be changed without making any modifications:
```bash
./create_rdr_release.sh -b release-4.17 -d
```

### Create and Push to Remote

Create the release branch and immediately push to remote:
```bash
./create_rdr_release.sh -b release-4.17 -p
```

## Command Options

| Option | Short | Description |
|--------|-------|-------------|
| `--branch` | `-b` | Release branch name (required) |
| `--push` | `-p` | Push changes to remote repository |
| `--dry-run` | `-d` | Show what would be changed without making changes |
| `--help` | `-h` | Show help message |

## What Gets Updated

The script updates **five types of references** in all YAML files within the `rdr/` directory:

### 1. Container Image Tags

**Before:**
```yaml
image: quay.io/ocsci/rdr-ocs-workload:latest
```

**After (for branch `release-4.17`):**
```yaml
image: quay.io/ocsci/rdr-ocs-workload:release-4.17
```

### 1b. VM ContainerDisk Images

**Before:**
```yaml
url: docker://quay.io/ocsci/cirros-dd:0.6.3
```

**After (for branch `release-4.17`):**
```yaml
url: docker://quay.io/ocsci/cirros-dd:release-4.17
```

### 2. ApplicationSet Target Revision

**Before:**
```yaml
spec:
  template:
    spec:
      source:
        repoURL: https://github.com/red-hat-storage/ocs-workloads.git
        targetRevision: master
```

**After (for branch `release-4.17`):**
```yaml
spec:
  template:
    spec:
      source:
        repoURL: https://github.com/red-hat-storage/ocs-workloads.git
        targetRevision: release-4.17
```

### 3. Subscription Git Branch Annotations

**Before:**
```yaml
metadata:
  annotations:
    apps.open-cluster-management.io/git-branch: master
    apps.open-cluster-management.io/github-branch: master
```

**After (for branch `release-4.17`):**
```yaml
metadata:
  annotations:
    apps.open-cluster-management.io/git-branch: release-4.17
    apps.open-cluster-management.io/github-branch: release-4.17
```

### 4. GitHub Raw Content URLs

**Before:**
```yaml
value: ["wget https://raw.githubusercontent.com/red-hat-storage/ocs-workloads/master/rdr/busybox/scripts/kernel_untar.sh ..."]
```

**After (for branch `release-4.17`):**
```yaml
value: ["wget https://raw.githubusercontent.com/red-hat-storage/ocs-workloads/release-4.17/rdr/busybox/scripts/kernel_untar.sh ..."]
```

### Images Affected

The script updates tags for all images found in `rdr/` folder, including:
- `quay.io/ocsci/rdr-ocs-workload:latest`
- `quay.io/prsurve/mongodb_rdr:latest`
- `quay.io/prsurve/mysql:latest`
- `quay.io/prsurve/filebrowser_data_write:latest`
- `quay.io/ocsci/filebrowser:latest`
- `quay.io/prsurve/mongodb_data_write:latest`
- `quay.io/prsurve/mysql_data_write:latest`
- `quay.io/prometheus/busybox:latest`
- And any other images with `:latest` tag

## Workflow Examples

### Example 1: Create Release 4.17

```bash
# Step 1: Preview changes
./create_rdr_release.sh -b release-4.17 -d

# Step 2: Create branch and update images
./create_rdr_release.sh -b release-4.17

# Step 3: Review the changes
git diff

# Step 4: Push to remote (if you didn't use -p flag)
git push -u origin release-4.17
```

### Example 2: Quick Release and Push

```bash
# Create branch, update images, commit, and push in one command
./create_rdr_release.sh -b release-4.18 -p
```

### Example 3: Update Existing Branch

If the branch already exists locally, the script will ask if you want to:
- Switch to the existing branch
- Update the image tags
- Commit changes

## Script Output

The script provides colored output:
- 🔵 **BLUE [INFO]**: Informational messages
- 🟢 **GREEN [SUCCESS]**: Successful operations
- 🟡 **YELLOW [WARNING]**: Warnings (existing branches, uncommitted changes)
- 🔴 **RED [ERROR]**: Errors that stop execution

## Safety Features

1. **Uncommitted Changes Check**: Warns if you have uncommitted changes
2. **Existing Branch Check**: Asks for confirmation if branch already exists
3. **Dry Run Mode**: Preview changes before applying them
4. **Commit Confirmation**: Asks before committing changes
5. **Change Review**: Shows git diff before committing

## Troubleshooting

### "Not in a git repository"
- Make sure you're in the repository root directory
- Ensure the directory is a git repository (`git status` should work)

### "rdr/ directory not found"
- Navigate to the repository root where `rdr/` directory exists
- Run `ls rdr/` to verify the directory is present

### "No files were updated"
- All images may already be using the specified tag
- Verify that YAML files in `rdr/` contain `image:` fields with `:latest` tag

### Branch Already Exists Remotely
- If you need to recreate the branch:
  ```bash
  git branch -D release-4.17
  ./create_rdr_release.sh -b release-4.17
  ```

### "Cannot use 'master' or 'main' as release branch name"
- You tried to use a reserved branch name
- `master` and `main` are reserved for main development branches
- Use a semantic release name instead: `release-4.17`, `release-4.18`, etc.

### "Cannot use 'latest' as release branch/tag name"
- You tried to use `latest` as a release name
- `latest` is the tag being replaced, not a valid release identifier
- Use a semantic version name: `release-4.17`, `release-4.18`, etc.

### "Branch/Tag name must start with 'release-'"
- You used a name that doesn't start with `release-`
- Examples: `v4.17`, `4.17`, `stable-2024`
- **Solution**: Add `release-` prefix: `release-4.17`, `release-4.18`, etc.
- This is a strict requirement to maintain consistency

### "Error loading trust policy" (Skopeo)
- **Error**: `FATA[0000] Error loading trust policy: invalid policy in...`
- **Cause**: Skopeo requires a trust policy file for signature verification
- **Solution**: Use the `--insecure-policy` flag to skip signature verification:
  ```bash
  ./tag_images.sh -t release-4.17 --insecure-policy
  ```
- **Note**: This is safe for trusted registries like Quay.io
- **Alternative**: Create a proper policy.json file (see `man containers-policy.json`)

## Best Practices

1. **Always use dry-run first**: `./create_rdr_release.sh -b BRANCH_NAME -d`
2. **Use semantic branch names**: `release-4.17`, `release-4.18`, etc.
3. **Commit your work first**: Ensure you have no uncommitted changes before running
4. **Review before pushing**: Use `git diff` to review changes before pushing to remote
5. **Coordinate with team**: Ensure your container images are built and pushed with the correct tag before creating the release branch

## Important Restrictions

To prevent common mistakes, the scripts **strictly validate** release names:

**📋 Naming Requirements:**
- ✅ **MUST** start with `release-`
- ✅ Follow the pattern: `release-X.XX` or `release-X.X`

**❌ Invalid names (will be rejected):**
- `master` or `main` - Reserved for main development branches
- `latest` - Reserved as the tag being replaced
- `v4.17` - Doesn't start with "release-"
- `stable-2024` - Doesn't start with "release-"
- `4.17` - Doesn't start with "release-"

**✅ Valid release names:**
- `release-4.17` ✓
- `release-4.18` ✓
- `release-5.0` ✓
- `release-4.17.1` ✓

**Example of validation:**
```bash
# Invalid: doesn't start with "release-"
$ ./create_rdr_release.sh -b v4.17
[ERROR] Branch name must start with 'release-'
[INFO] Current value: v4.17
[INFO] Valid examples: release-4.17, release-4.18, release-5.0, etc.

# Invalid: reserved name
$ ./create_rdr_release.sh -b latest
[ERROR] Cannot use 'latest' as release branch name!
[INFO] 'latest' is the tag being replaced, not a valid release name.
[INFO] Use a semantic release name like: release-4.17, release-4.18, etc.

# Valid: starts with "release-"
$ ./create_rdr_release.sh -b release-4.17
[INFO] Starting RDR release process for branch: release-4.17
✓ Validation passed
```

## Summary of Changes

When you run the script with branch `release-4.17`, it will:

1. ✅ Update all container image tags from `:latest` → `:release-4.17`
2. ✅ Update all VM containerDisk image tags (any version) → `:release-4.17`
3. ✅ Update all ApplicationSet `targetRevision: master` → `targetRevision: release-4.17`
4. ✅ Update all Subscription git branch annotations from `master` → `release-4.17`
5. ✅ Update all GitHub raw URLs from `/master/` → `/release-4.17/`

This ensures that:
- Your container workloads use the correct versioned container images
- Your VM workloads use the correct versioned containerDisk images
- ArgoCD ApplicationSets pull from the correct Git branch
- ACM Subscriptions pull from the correct Git branch
- Scripts downloaded from GitHub come from the correct branch

## Additional Notes

- The script only affects files in the `rdr/` directory
- It preserves the directory structure and file formatting
- Works on both macOS and Linux
- All changes are tracked in git, so you can easily revert if needed
- The script is safe to run multiple times (idempotent)
