#!/bin/bash
#
# astroberry-image-open.sh
# Open image system for inspection or manual modification.
# Runs chroot environment on root file system of the image.
#

set -e

# Check input args
if [ $# -lt 1 ]; then
    echo "Missing output image!"
    echo "Usage ${0} IMAGE_FILE.img [rw]"
    exit 1
fi

OUTPUT_IMAGE="$1"

# Mount rw only if requested
if [ -n $2 ] && [ "$2" == "rw" ]; then
    MOUNT_OPTIONS="rw"
else
    MOUNT_OPTIONS="ro"
fi

# Check if image file exists
if [ ! -f "$OUTPUT_IMAGE" ]; then
    echo "$OUTPUT_IMAGE file does not exist"
    exit 2
fi

# Set up loop device
LOOP_DEV=$(losetup -fP --show "$OUTPUT_IMAGE")

# Wait for partition
while [ ! -e "${LOOP_DEV}p2" ]; do
    sleep 3
done

# Create mount points
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

# Run chroot
chroot "$ROOTFS" /bin/bash
