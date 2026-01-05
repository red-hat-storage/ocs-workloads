#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
IMAGE="quay.io/ocsci/cirros-dd"
VERSION="0.6.3"
BASE_URL="https://download.cirros-cloud.net/${VERSION}"

# CirrOS-supported disk images
declare -A ARCH_MAP=(
  [amd64]="cirros-0.6.3-x86_64-disk.img linux/amd64"
  [arm64]="cirros-0.6.3-aarch64-disk.img linux/arm64"
  [arm]="cirros-0.6.3-arm-disk.img linux/arm/v7"
  [ppc64le]="cirros-0.6.3-ppc64le-disk.img linux/ppc64le"
)

# ================= CLEANUP =================
cleanup() {
  sudo umount /mnt 2>/dev/null || true
  sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true
}
trap cleanup EXIT

# ================= PREP =================
sudo modprobe nbd max_part=8

# ================= BUILD LOOP =================
for ARCH in "${!ARCH_MAP[@]}"; do
  read -r DISK PLATFORM <<< "${ARCH_MAP[$ARCH]}"
  OCI_ARCH="${PLATFORM#linux/}"

  echo "▶ Building for ${ARCH} (${PLATFORM})"

  # ---------- Download disk ----------
  curl -fL -O "${BASE_URL}/${DISK}"

  # ---------- Inject init script ----------
  sudo qemu-nbd --connect=/dev/nbd0 "$DISK"
  sleep 2
  sudo mount /dev/nbd0p1 /mnt

  sudo mkdir -p /mnt/usr/local/bin
  sudo cp io_dd_verify.sh /mnt/usr/local/bin/io_dd_verify.sh
  sudo chmod +x /mnt/usr/local/bin/io_dd_verify.sh

  # Create rc.local (BusyBox init)
  sudo mkdir -p /mnt/etc
  sudo sh -c 'cat > /mnt/etc/rc.local <<EOF
#!/bin/sh
/usr/local/bin/io_dd_verify.sh &
EOF'
  sudo chmod +x /mnt/etc/rc.local

  sudo umount /mnt
  sudo qemu-nbd --disconnect /dev/nbd0

  # ---------- Build containerDisk image (Buildah) ----------
  CTR=$(buildah from --arch "${OCI_ARCH}" scratch)
  buildah copy "${CTR}" "${DISK}" /disk/disk.qcow2
  buildah config \
    --label org.opencontainers.image.title="CirrOS dd integrity VM" \
    --label org.opencontainers.image.version="${VERSION}" \
    --label org.opencontainers.image.arch="${ARCH}" \
    "${CTR}"

  buildah commit "${CTR}" "${IMAGE}:${VERSION}-${ARCH}"
  buildah rm "${CTR}"

  # ---------- Push per-arch image ----------
  buildah push "${IMAGE}:${VERSION}-${ARCH}"

  rm -f "${DISK}"
done

# ================= MANIFEST =================
echo "▶ Creating multi-arch manifest"

buildah manifest create "${IMAGE}:${VERSION}" || true

for ARCH in "${!ARCH_MAP[@]}"; do
  buildah manifest add \
    "${IMAGE}:${VERSION}" \
    "docker://${IMAGE}:${VERSION}-${ARCH}"
done

buildah manifest push --all \
  "${IMAGE}:${VERSION}" \
  "docker://${IMAGE}:${VERSION}"

echo "✅ Multi-arch image published: ${IMAGE}:${VERSION}"
