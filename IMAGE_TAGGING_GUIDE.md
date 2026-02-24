# Container Image Tagging Guide for RDR Releases

Before creating a release branch with the `create_rdr_release.sh` script, you must ensure all container images are properly tagged and pushed to Quay.io with the release tag.

## Required Images to Tag

The following **8 container images** are used in the `rdr/` workloads and must be tagged with your release version:

### Images in quay.io/ocsci/ (2 images)

1. **quay.io/ocsci/rdr-ocs-workload**
   - Current: `quay.io/ocsci/rdr-ocs-workload:latest`
   - Release: `quay.io/ocsci/rdr-ocs-workload:release-4.17`
   - Used in: Busybox workloads
   - Files: Multiple busybox deployment YAML files

2. **quay.io/ocsci/filebrowser**
   - Current: `quay.io/ocsci/filebrowser:latest`
   - Release: `quay.io/ocsci/filebrowser:release-4.17`
   - Used in: File browser workload
   - Files: file-browser deployment files

### Images in quay.io/prsurve/ (5 images)

3. **quay.io/prsurve/mongodb_rdr**
   - Current: `quay.io/prsurve/mongodb_rdr:latest`
   - Release: `quay.io/prsurve/mongodb_rdr:release-4.17`
   - Used in: MongoDB workloads
   - Files: mongodb and mongodb-cephfs deployment files

4. **quay.io/prsurve/mongodb_data_write**
   - Current: `quay.io/prsurve/mongodb_data_write:latest`
   - Release: `quay.io/prsurve/mongodb_data_write:release-4.17`
   - Used in: MongoDB IO writer workloads
   - Files: mongodb io_writer files

5. **quay.io/prsurve/mysql**
   - Current: `quay.io/prsurve/mysql:latest`
   - Release: `quay.io/prsurve/mysql:release-4.17`
   - Used in: MySQL workloads
   - Files: mysql deployment files

6. **quay.io/prsurve/mysql_data_write**
   - Current: `quay.io/prsurve/mysql_data_write:latest`
   - Release: `quay.io/prsurve/mysql_data_write:release-4.17`
   - Used in: MySQL IO writer workloads
   - Files: mysql io_writer files

7. **quay.io/prsurve/filebrowser_data_write**
   - Current: `quay.io/prsurve/filebrowser_data_write:latest`
   - Release: `quay.io/prsurve/filebrowser_data_write:release-4.17`
   - Used in: File browser client workloads
   - Files: file-browser deployment files

### External Images (1 image - Optional)

8. **quay.io/prometheus/busybox**
   - Current: `quay.io/prometheus/busybox:latest`
   - Release: Not required (external image)
   - Note: This is an external Prometheus image. You don't need to tag this unless you want to pin a specific version.

---

## Important: Release Naming Convention

**All release tags MUST start with `release-`**

Examples:
- ✅ `release-4.17`
- ✅ `release-4.18`
- ✅ `release-5.0`
- ❌ `v4.17` (invalid)
- ❌ `4.17` (invalid)

This is enforced by the `tag_images.sh` script.

---

## Quick Reference Checklist

For release **release-4.17**, tag and push these images:

### Required Images (7 total)

- [ ] `quay.io/ocsci/rdr-ocs-workload:release-4.17`
- [ ] `quay.io/ocsci/filebrowser:release-4.17`
- [ ] `quay.io/prsurve/mongodb_rdr:release-4.17`
- [ ] `quay.io/prsurve/mongodb_data_write:release-4.17`
- [ ] `quay.io/prsurve/mysql:release-4.17`
- [ ] `quay.io/prsurve/mysql_data_write:release-4.17`
- [ ] `quay.io/prsurve/filebrowser_data_write:release-4.17`

---

## How to Tag and Push Images

### Method 1: Using Docker CLI

```bash
# Set your release version
RELEASE_TAG="release-4.17"

# For each image, pull latest, tag, and push
# Example for rdr-ocs-workload:

# 1. Pull the latest image
docker pull quay.io/ocsci/rdr-ocs-workload:latest

# 2. Tag it with the release version
docker tag quay.io/ocsci/rdr-ocs-workload:latest quay.io/ocsci/rdr-ocs-workload:${RELEASE_TAG}

# 3. Push the tagged image
docker push quay.io/ocsci/rdr-ocs-workload:${RELEASE_TAG}
```

### Method 2: Using Podman CLI

```bash
# Set your release version
RELEASE_TAG="release-4.17"

# For each image, pull latest, tag, and push
# Example for rdr-ocs-workload:

# 1. Pull the latest image
podman pull quay.io/ocsci/rdr-ocs-workload:latest

# 2. Tag it with the release version
podman tag quay.io/ocsci/rdr-ocs-workload:latest quay.io/ocsci/rdr-ocs-workload:${RELEASE_TAG}

# 3. Push the tagged image
podman push quay.io/ocsci/rdr-ocs-workload:${RELEASE_TAG}
```

### Method 3: Using Skopeo (No Local Pull Required)

```bash
# Set your release version
RELEASE_TAG="release-4.17"

# Copy directly from :latest to :release tag without pulling locally
skopeo copy \
  docker://quay.io/ocsci/rdr-ocs-workload:latest \
  docker://quay.io/ocsci/rdr-ocs-workload:${RELEASE_TAG}
```

---

## Automated Tagging Script

Here's a helper script to tag all images at once:

### Using Docker:

```bash
#!/bin/bash
RELEASE_TAG="release-4.17"

# List of images to tag (excluding external prometheus image)
images=(
  "quay.io/ocsci/rdr-ocs-workload"
  "quay.io/ocsci/filebrowser"
  "quay.io/prsurve/mongodb_rdr"
  "quay.io/prsurve/mongodb_data_write"
  "quay.io/prsurve/mysql"
  "quay.io/prsurve/mysql_data_write"
  "quay.io/prsurve/filebrowser_data_write"
)

for image in "${images[@]}"; do
  echo "Processing: $image"
  docker pull ${image}:latest
  docker tag ${image}:latest ${image}:${RELEASE_TAG}
  docker push ${image}:${RELEASE_TAG}
  echo "✓ Tagged and pushed: ${image}:${RELEASE_TAG}"
  echo ""
done

echo "All images tagged successfully!"
```

### Using Skopeo (Faster - No Local Pull):

```bash
#!/bin/bash
RELEASE_TAG="release-4.17"

# List of images to tag (excluding external prometheus image)
images=(
  "quay.io/ocsci/rdr-ocs-workload"
  "quay.io/ocsci/filebrowser"
  "quay.io/prsurve/mongodb_rdr"
  "quay.io/prsurve/mongodb_data_write"
  "quay.io/prsurve/mysql"
  "quay.io/prsurve/mysql_data_write"
  "quay.io/prsurve/filebrowser_data_write"
)

for image in "${images[@]}"; do
  echo "Processing: $image"
  skopeo copy \
    docker://${image}:latest \
    docker://${image}:${RELEASE_TAG}
  echo "✓ Tagged and pushed: ${image}:${RELEASE_TAG}"
  echo ""
done

echo "All images tagged successfully!"
```

---

## Verification

After tagging all images, verify they exist in Quay:

```bash
RELEASE_TAG="release-4.17"

# Verify each image exists
skopeo inspect docker://quay.io/ocsci/rdr-ocs-workload:${RELEASE_TAG}
skopeo inspect docker://quay.io/ocsci/filebrowser:${RELEASE_TAG}
skopeo inspect docker://quay.io/prsurve/mongodb_rdr:${RELEASE_TAG}
skopeo inspect docker://quay.io/prsurve/mongodb_data_write:${RELEASE_TAG}
skopeo inspect docker://quay.io/prsurve/mysql:${RELEASE_TAG}
skopeo inspect docker://quay.io/prsurve/mysql_data_write:${RELEASE_TAG}
skopeo inspect docker://quay.io/prsurve/filebrowser_data_write:${RELEASE_TAG}
```

Or check manually in Quay.io web interface:
- https://quay.io/repository/ocsci/rdr-ocs-workload?tab=tags
- https://quay.io/repository/ocsci/filebrowser?tab=tags
- https://quay.io/repository/prsurve/mongodb_rdr?tab=tags
- https://quay.io/repository/prsurve/mongodb_data_write?tab=tags
- https://quay.io/repository/prsurve/mysql?tab=tags
- https://quay.io/repository/prsurve/mysql_data_write?tab=tags
- https://quay.io/repository/prsurve/filebrowser_data_write?tab=tags

---

## Complete Release Workflow

Follow these steps in order:

1. **Build and Tag Container Images** (This Guide)
   ```bash
   # Tag all 7 required images in Quay with the release version
   ./tag_images.sh  # Using the automated script above
   ```

2. **Verify Images Exist**
   ```bash
   # Verify all images are available in Quay
   skopeo inspect docker://quay.io/ocsci/rdr-ocs-workload:release-4.17
   # ... repeat for all images
   ```

3. **Create Release Branch** (Use `create_rdr_release.sh`)
   ```bash
   # Preview changes
   ./create_rdr_release.sh -b release-4.17 -d

   # Create release branch and update YAML files
   ./create_rdr_release.sh -b release-4.17 -p
   ```

4. **Test Deployment**
   - Deploy workloads from the new release branch
   - Verify they use the correct image tags
   - Ensure all functionality works as expected

---

## Important Notes

- **Timing**: Always tag and push container images to Quay BEFORE running the `create_rdr_release.sh` script
- **Permissions**: Ensure you have push permissions to the Quay repositories
- **External Images**: The `quay.io/prometheus/busybox:latest` image is external and doesn't need to be tagged
- **Verification**: Always verify images exist in Quay before updating YAML files
- **Consistency**: Use the exact same release tag for all images and the git branch

---

## Image Source Repositories

If you need to rebuild images from source:

- **rdr-ocs-workload**: Check your team's repository for build instructions
- **mongodb_rdr**: Check your team's repository for build instructions
- **mysql**: Check your team's repository for build instructions
- **filebrowser**: Check your team's repository for build instructions
- **data_write containers**: Check your team's repository for build instructions

Contact your team lead if you're unsure about image build processes.
