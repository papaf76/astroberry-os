#!/bin/bash
#
# astroberry-image-build.sh
# Prepare vanilla system image for customization (amd64 variant)
# Invoked by: .github/workflows/astroberry-os-image-amd64.yml
# Runs: scripts/astroberry-image-sysmod.sh
# in chroot environment

set -e

# Check input args
if [ $# -lt 1 ]; then
    echo "Output archive file missing!"
    echo "Usage ${0} ARCHIVE_FILE.tgz"
    exit 1
fi

OUTPUT_ARCHIVE="$1"

# Get and validate version from the image file name
ASTROBERRY_VERSION="$(echo $OUTPUT_ARCHIVE | cut -d_ -f2)"
if [[ ! "$ASTROBERRY_VERSION" =~ ^[0-9]\.([0-9]|[0-9][0-9])$ ]]; then
    echo "Wrong version format! Expected #.# or #.##, got $ASTROBERRY_VERSION"
    exit 3
fi

# Set working dir
WDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Create the initial debootstrap
debootstrap --arch amd64 trixie "$ROOTFS" http://deb.debian.org/debian/

# Prepare chroot environment
mount -t proc /proc "$ROOTFS/proc"
mount -t sysfs /sys "$ROOTFS/sys"
mount --rbind /dev "$ROOTFS/dev"
mount --rbind /dev/pts "$ROOTFS/dev/pts"

# Prepare build scripts
mkdir -p "$ROOTFS/tmp/astroberry-mods"
cp "$WDIR/../scripts/astroberry-image-sysmod.sh" "$ROOTFS/tmp/astroberry-mods/astroberry-image-sysmod.sh"
ASTROBERRYFILE=$(ls build/whl_astroberry-manager/dist/astroberry_manager*.whl | head -1)
cp "$ASTROBERRYFILE" "$ROOTFS/tmp/astroberry-mods"
chmod 755 "$ROOTFS/tmp/astroberry-mods/astroberry-image-sysmod.sh"

# Install requirements into the chroot
chroot "$ROOTFS" /bin/bash -c "apt-get install -y curl gpg" 

# Run system mods in chroot environment
chroot "$ROOTFS" /bin/bash -c "export ASTROBERRY_VERSION=$ASTROBERRY_VERSION && \
  cd /tmp/astroberry-mods && ./astroberry-archive-sysmod.sh"
#chroot "$ROOTFS" /bin/bash -c "apt-get clean"

# Remove build scripts
rm -rf "$ROOTFS/tmp/astroberry-mods"

# Unmount filesystems
for dir in proc sys dev/pts dev; do
    umount -l "$ROOTFS/$dir"
done

# Synchronize filesystem
sync

# Create archive
tar --zstd -cvf $OUTPUT_ARCHIVE -C $ROOTFS .

# Clean ROOTFS
rm -rf $ROOTFS

# Create ISO
if [ -e "rootfs" ]; then rm -rf rootfs; fi
mkdir rootfs
          
debootstrap --variant=minbase --include=fdisk,gdisk,parted,tar,gzip,udev,kmod,dosfstools,pv,zstd \
  trixie rootfs http://deb.debian.org/debian/

chroot rootfs apt-get update
chroot rootfs apt-get install -y --no-install-recommends linux-image-generic firmware-linux-nonfree \
  intel-microcode intel-media-va-driver-nonfree va-driver-all haveged
chroot rootfs apt-get clean

cp -v $WDIR/iso-installer/init.sh rootfs/init
chmod +x rootfs/init

mkdir -p iso/installer
cp -v $WDIR/iso-installer/deploy.sh iso/installer
chmod +x iso/installer/deploy.sh
cp -v $OUTPUT_ARCHIVE iso/installer/

mkdir -p iso/boot/grub
cp -v rootfs/boot/vmlinuz iso/boot/vmlinuz
(cd rootfs && find . | cpio -H newc -o | gzip > ../iso/boot/initrd.img)
          
cp -v $WDIR/iso-installer/grub.cfg iso/boot/grub

# Secure boot support
mkdir -p "iso/EFI/BOOT"
cp iso/boot/grub/grub.cfg "iso/EFI/BOOT/grub.cfg"
cp iso/boot/grub/grub.cfg "iso/grub.cfg"
cp /usr/lib/shim/shimx64.efi.signed "iso/EFI/BOOT/BOOTX64.EFI"
cp /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed "iso/EFI/BOOT/grubx64.efi"
cp /usr/lib/shim/mmx64.efi "iso/EFI/BOOT/"
if [ -e "efiboot.img" ]; then rm -rf efiboot.img; fi
truncate -s 8M efiboot.img
mkfs.vfat -F12 -n "EFI_BOOT" efiboot.img
mmd -i efiboot.img ::/EFI
mmd -i efiboot.img ::/EFI/BOOT
mcopy -i efiboot.img iso/EFI/BOOT/* ::/EFI/BOOT/
mcopy -i efiboot.img iso/boot/grub/grub.cfg ::/grub.cfg

ISOFILE=$(basename "$OUTPUT_ARCHIVE").iso
xorriso -as mkisofs -r -V astroberrycd -o $ISOFILE \
  -J -joliet-long -no-emul-boot -e efiboot.img \
  -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
  iso efiboot.img

ls -al $ISOFILE