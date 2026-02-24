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
  - `quay.io/ocsci/*` (2 images)
  - `quay.io/prsurve/*` (5 images)

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

This script tags and pushes all 7 required container images to Quay.io.

**Usage:**
```bash
./tag_images.sh -t RELEASE_TAG [-m METHOD] [-d]
```

**Options:**
- `-t, --tag TAG_NAME` - Release tag (required, e.g., release-4.17)
- `-m, --method METHOD` - Tagging method: docker, podman, or skopeo (default: skopeo)
- `-d, --dry-run` - Preview what would be done without making changes
- `-h, --help` - Show help message

**Examples:**
```bash
# Tag using skopeo (fastest, recommended)
./tag_images.sh -t release-4.17

# Tag using docker
./tag_images.sh -t release-4.17 -m docker

# Preview what would be tagged
./tag_images.sh -t release-4.17 -d
```

**Images Tagged:**
- `quay.io/ocsci/rdr-ocs-workload:release-4.17`
- `quay.io/ocsci/filebrowser:release-4.17`
- `quay.io/prsurve/mongodb_rdr:release-4.17`
- `quay.io/prsurve/mongodb_data_write:release-4.17`
- `quay.io/prsurve/mysql:release-4.17`
- `quay.io/prsurve/mysql_data_write:release-4.17`
- `quay.io/prsurve/filebrowser_data_write:release-4.17`

See [IMAGE_TAGGING_GUIDE.md](IMAGE_TAGGING_GUIDE.md) for detailed information about manual tagging.

---

### Image Verification (`verify_images.sh`)

This script verifies that all required images exist in Quay.io before creating the release.

**Usage:**
```bash
./verify_images.sh -t RELEASE_TAG
```

**Options:**
- `-t, --tag TAG_NAME` - Release tag to verify (required)
- `-h, --help` - Show help message

**Example:**
```bash
./verify_images.sh -t release-4.17
```

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

The script updates **four types of references** in all YAML files within the `rdr/` directory:

### 1. Container Image Tags

**Before:**
```yaml
image: quay.io/ocsci/rdr-ocs-workload:latest
```

**After (for branch `release-4.17`):**
```yaml
image: quay.io/ocsci/rdr-ocs-workload:release-4.17
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

## Best Practices

1. **Always use dry-run first**: `./create_rdr_release.sh -b BRANCH_NAME -d`
2. **Use semantic branch names**: `release-4.17`, `release-4.18`, etc.
3. **Commit your work first**: Ensure you have no uncommitted changes before running
4. **Review before pushing**: Use `git diff` to review changes before pushing to remote
5. **Coordinate with team**: Ensure your container images are built and pushed with the correct tag before creating the release branch

## Summary of Changes

When you run the script with branch `release-4.17`, it will:

1. ✅ Update all container image tags from `:latest` → `:release-4.17`
2. ✅ Update all ApplicationSet `targetRevision: master` → `targetRevision: release-4.17`
3. ✅ Update all Subscription git branch annotations from `master` → `release-4.17`
4. ✅ Update all GitHub raw URLs from `/master/` → `/release-4.17/`

This ensures that:
- Your workloads use the correct versioned container images
- ArgoCD ApplicationSets pull from the correct Git branch
- ACM Subscriptions pull from the correct Git branch
- Scripts downloaded from GitHub come from the correct branch

## Additional Notes

- The script only affects files in the `rdr/` directory
- It preserves the directory structure and file formatting
- Works on both macOS and Linux
- All changes are tracked in git, so you can easily revert if needed
- The script is safe to run multiple times (idempotent)
