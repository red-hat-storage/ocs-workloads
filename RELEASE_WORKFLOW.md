# RDR Release Workflow - Quick Reference

This document provides a quick reference for creating RDR releases.

## Files in This Repository

| File | Purpose |
|------|---------|
| `tag_images.sh` | Tag and push container images to Quay.io |
| `verify_images.sh` | Verify images exist in Quay before release |
| `create_rdr_release.sh` | Create git branch and update YAML files |
| `RDR_RELEASE_GUIDE.md` | Complete usage documentation |
| `IMAGE_TAGGING_GUIDE.md` | Detailed image tagging guide |

## Complete Release Process

### For Release 4.17 (Example)

```bash
# Step 1: Tag container images in Quay
./tag_images.sh -t release-4.17

# Step 2: Verify images exist
./verify_images.sh -t release-4.17

# Step 3: Preview YAML changes
./create_rdr_release.sh -b release-4.17 -d

# Step 4: Create release branch
./create_rdr_release.sh -b release-4.17 -p
```

## What Gets Updated

### Container Images (7 total)
- `quay.io/ocsci/rdr-ocs-workload:latest` → `:release-4.17`
- `quay.io/ocsci/filebrowser:latest` → `:release-4.17`
- `quay.io/prsurve/mongodb_rdr:latest` → `:release-4.17`
- `quay.io/prsurve/mongodb_data_write:latest` → `:release-4.17`
- `quay.io/prsurve/mysql:latest` → `:release-4.17`
- `quay.io/prsurve/mysql_data_write:latest` → `:release-4.17`
- `quay.io/prsurve/filebrowser_data_write:latest` → `:release-4.17`

### YAML Files (~70 files in rdr/ folder)
1. **Image tags**: `:latest` → `:release-4.17`
2. **ApplicationSet targetRevision**: `master` → `release-4.17`
3. **Subscription git-branch**: `master` → `release-4.17`
4. **GitHub raw URLs**: `/master/` → `/release-4.17/`

## Common Commands

### Tag Images
```bash
# Using skopeo (fastest, recommended)
./tag_images.sh -t release-4.17

# Using docker
./tag_images.sh -t release-4.17 -m docker

# Using podman
./tag_images.sh -t release-4.17 -m podman

# Dry-run mode
./tag_images.sh -t release-4.17 -d
```

### Verify Images
```bash
./verify_images.sh -t release-4.17
```

### Create Release Branch
```bash
# Preview changes
./create_rdr_release.sh -b release-4.17 -d

# Create branch locally
./create_rdr_release.sh -b release-4.17

# Create and push to remote
./create_rdr_release.sh -b release-4.17 -p
```

## Prerequisites

Before running these scripts, ensure you have:

1. **Git repository access**
   - Repository must be initialized
   - You must be in the repository root

2. **Quay.io push permissions**
   - Access to `quay.io/ocsci/*` repositories (2 images)
   - Access to `quay.io/prsurve/*` repositories (5 images)

3. **Required tools**
   - For image tagging: `skopeo` (recommended), `docker`, or `podman`
   - For image verification: `skopeo`

### Installing skopeo
```bash
# macOS
brew install skopeo

# RHEL/Fedora
sudo dnf install skopeo

# Ubuntu
sudo apt install skopeo
```

## Troubleshooting

### "Permission denied" when pushing images
- Ensure you're logged in to Quay: `docker login quay.io` or `podman login quay.io`
- Verify you have push permissions to the repositories

### "Image not found" during verification
- Images must be tagged and pushed to Quay before running `create_rdr_release.sh`
- Run `./tag_images.sh` first

### "Not in a git repository"
- Ensure you're in the repository root directory
- Run `git status` to verify

### "No files were updated"
- All YAML files may already be using the specified tag
- Check if the release branch already exists: `git branch -a`

## Best Practices

1. **Always use dry-run first** - Preview changes before applying
2. **Tag images first** - Container images MUST exist before updating YAML
3. **Verify before proceeding** - Use `verify_images.sh` to confirm
4. **Use semantic naming** - Follow the pattern `release-X.XX`
5. **Coordinate with team** - Ensure everyone is aware of the release

## Quick Help

```bash
# View help for any script
./tag_images.sh --help
./verify_images.sh --help
./create_rdr_release.sh --help
```

## Documentation

- **[RDR_RELEASE_GUIDE.md](RDR_RELEASE_GUIDE.md)** - Complete usage guide
- **[IMAGE_TAGGING_GUIDE.md](IMAGE_TAGGING_GUIDE.md)** - Detailed image tagging instructions

## Support

For issues or questions:
1. Check the documentation files listed above
2. Review the troubleshooting section
3. Contact your team lead
