#!/bin/bash
#
# astroberry-image-build.sh
# Prepare vanilla system image for customization
# Invoked by: .github/workflows/astroberry-os-image.yml
# Runs: scripts/astroberry-image-sysmod.sh
# in chroot environment

set -e

# Check input args
if [ $# -lt 1 ]; then
    echo "Output image file missing!"
    echo "Usage ${0} IMAGE_FILE.img"
    exit 1
fi

OUTPUT_IMAGE="$1"

# Check if image exists
if [ ! -f "$OUTPUT_IMAGE" ]; then
    echo "$OUTPUT_IMAGE does not exist!"
    exit 2
fi

# Get and validate version from the image file name
ASTROBERRY_VERSION="$(echo $OUTPUT_IMAGE | cut -d_ -f2)"
if [[ ! "$ASTROBERRY_VERSION" =~ ^[0-9]\.([0-9]|[0-9][0-9])$ ]]; then
    echo "Wrong version format! Expected #.# or #.##, got $ASTROBERRY_VERSION"
    exit 3
fi

# Set working dir
WDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up loop device
LOOP_DEV=$(losetup -fP --show "$OUTPUT_IMAGE")

# Wait for partition
while [ ! -e "${LOOP_DEV}p2" ]; do
    sleep 3
done

# Check and grow root filesystem to maximum size
e2fsck -fy "${LOOP_DEV}p2"
parted "${LOOP_DEV}" resizepart 2 100%
resize2fs "${LOOP_DEV}p2"
sync

# Create root filesystem mount point
ROOTFS="/mnt/rootfs"
mkdir -p "$ROOTFS"

# Clean everything on exit
cleanup() {
    for dir in proc sys dev/pts dev; do
        if mountpoint -q "$ROOTFS/$dir"; then
            umount -l "$ROOTFS/$dir"
        fi
    done

    if mountpoint -q "$ROOTFS/boot/firmware"; then
        umount "$ROOTFS/boot/firmware"
    fi

    if mountpoint -q "$ROOTFS"; then
        umount "$ROOTFS"
    fi

    if [ -n "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV"
    fi

    rmdir "$ROOTFS"
}
trap cleanup EXIT

# Mount partitions
mount "${LOOP_DEV}p2" "$ROOTFS"
mount "${LOOP_DEV}p1" "$ROOTFS/boot/firmware"

# Prepare chroot environment
mount -t proc /proc "$ROOTFS/proc"
mount -t sysfs /sys "$ROOTFS/sys"
mount --rbind /dev "$ROOTFS/dev"
mount --rbind /dev/pts "$ROOTFS/dev/pts"

# Prepare build scripts
mkdir -p "$ROOTFS/tmp/astroberry-mods"
cp "$WDIR/astroberry-image-sysmod.sh" "$ROOTFS/tmp/astroberry-mods/"
cp "build/whl_astroberry-manager/dist/astroberry_manager-1.0-py3-none-any.whl" "$ROOTFS/tmp/astroberry-mods/"
chmod 755 "$ROOTFS/tmp/astroberry-mods/astroberry-image-sysmod.sh"

# Run system mods in chroot environment
chroot "$ROOTFS" /bin/bash -c "export ASTROBERRY_VERSION=$ASTROBERRY_VERSION && cd /tmp/astroberry-mods && ./astroberry-image-sysmod.sh"

# Remove build scripts
rm -rf "$ROOTFS/tmp/astroberry-mods"

# Unmount filesystems
for dir in proc sys dev/pts dev; do
    umount -l "$ROOTFS/$dir"
done
umount "$ROOTFS/boot/firmware"
umount "$ROOTFS"

# Check filesystem before shrinking
e2fsck -fy "${LOOP_DEV}p2"

# Shrink filesystem to minimum size
resize2fs -M "${LOOP_DEV}p2"

# Synchronize filesystem
sync

