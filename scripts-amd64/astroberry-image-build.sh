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
sed -i 's/main$/main contrib non-free-firmware non-free/' "$ROOTFS/etc/apt/sources.list"
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y --no-install-recommends linux-image-generic firmware-linux-nonfree \
  intel-microcode va-driver-all haveged zstd
# Install required dependencies outside standard debian
wget --quiet -O $ROOTFS/tmp/astrodmx-capture.deb \
  "https://www.astrodmx-capture.org.uk/downloads/astrodmx/current/linux-x86_64/astrodmx-capture_2.16.4_amd64.deb"
wget --quiet -O $ROOTFS/tmp/astap.deb \
  "https://downloads.sourceforge.net/project/astap-program/linux_installer/astap_amd64.deb?ts=gAAAAABp5ciU7OE0noIjB1qTTFRlNckXUW1TEo9G_9Kv8mN05c4kNFgvP4meqm7hWwbuHz6iV3NuwNiTg0S5gJ3HNmQmfPQ14A%3D%3D&r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fastap-program%2Ffiles%2Flinux_installer%2Fastap_amd64.deb%2Fdownload"
wget --quiet -O $ROOTFS/tmp/ccdciel.deb \
  "https://downloads.sourceforge.net/project/ccdciel/ccdciel_0.9.93/ccdciel_0.9.93-3961_amd64.deb?ts=gAAAAABp5cjXzCBrGpk_xGycEUGEF-pi_AHManlSmHxcQl6hmvASGsv46nJUDVqYjW_sl3byXg803yMT1hc0e5igMO1ZJRswyg%3D%3D&r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fccdciel%2Ffiles%2Fccdciel_0.9.93%2Fccdciel_0.9.93-3961_amd64.deb%2Fdownload"
wget --quiet -O $ROOTFS/tmp/libpasastro.deb \
  "https://downloads.sourceforge.net/project/libpasastro/version_1.4.2/libpasastro_1.4.2-54_amd64.deb?ts=gAAAAABp5d-utQ8rEB-mcYu-QEoLLbW-lQFC7Jbrtw4FwsdPGILP9DbKSw8UzkVRRzP-UMNk44Go8AsLvsB5vO4PUrwuNqmHoQ%3D%3D&r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Flibpasastro%2Ffiles%2Fversion_1.4.2%2Flibpasastro_1.4.2-54_amd64.deb%2Fdownload"
chroot "$ROOTFS" apt install -y /tmp/astrodmx-capture.deb /tmp/astap.deb /tmp/ccdciel.deb /tmp/libpasastro.deb
rm -f $ROOTFS/tmp/astrodmx-capture.deb $ROOTFS/tmp/astap.deb $ROOTFS/tmp/ccdciel.deb $ROOTFS/tmp/libpasastro.deb
chroot "$ROOTFS" apt-get install -y curl gpg
chroot "$ROOTFS" bash -c 'curl -s --compressed "https://riblee.github.io/ppa/KEY.gpg" | gpg --dearmor -o /etc/apt/trusted.gpg.d/firecapture.gpg'
echo "deb [signed-by=/etc/apt/trusted.gpg.d/firecapture.gpg] https://riblee.github.io/ppa ./" > $ROOTFS/etc/apt/sources.list.d/firecapture.list
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y firecapture
chroot "$ROOTFS" apt-get clean

# Prepare chroot environment
mount -t proc /proc "$ROOTFS/proc"
mount -t sysfs /sys "$ROOTFS/sys"
mount --rbind /dev "$ROOTFS/dev"
mount --rbind /dev/pts "$ROOTFS/dev/pts"

# Prepare build scripts
mkdir -p "$ROOTFS/tmp/astroberry-mods"
cp "$WDIR/../scripts/astroberry-image-sysmod-fabiorepo.sh" "$ROOTFS/tmp/astroberry-mods/astroberry-image-sysmod.sh"
ASTROBERRYFILE=$(ls build/whl_astroberry-manager/dist/astroberry_manager*.whl | head -1)
cp "$ASTROBERRYFILE" "$ROOTFS/tmp/astroberry-mods"
chmod 755 "$ROOTFS/tmp/astroberry-mods/astroberry-image-sysmod.sh"

# Install requirements into the chroot
chroot "$ROOTFS" /bin/bash -c "apt-get install -y curl gpg" 

# Run system mods in chroot environment
chroot "$ROOTFS" /bin/bash -c "export ASTROBERRY_VERSION=$ASTROBERRY_VERSION && \
  cd /tmp/astroberry-mods && ./astroberry-image-sysmod.sh"
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
chroot rootfs apt-get install -y --no-install-recommends linux-image-generic
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