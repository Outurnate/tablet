#!/bin/bash
#qemu
#bindfs
#wget

MAKEOPTS=-j12

mount-qcow2()
{
    if (( $# != 2 )); then
	echo mount-qcow2 [img] [mount]
	exit 1
    fi
    IMG=$1
    MOUNT=$2
    echo Loading nbd kernel module...
    sudo modprobe nbd max_part=16

    echo Mounting image...
    sudo qemu-nbd -c /dev/nbd0 $IMG

    echo Setting up disk...
    sudo fdisk -u /dev/nbd0 <<EOF
o
n
p
1

+100M
t
c
n
p
2


w
EOF

    echo Creating filesystems...
    sudo mkfs.vfat /dev/nbd0p1
    sudo mkfs.ext4 /dev/nbd0p2

    echo Mounting partitions...
    sudo mkdir -p $MOUNT
    sudo mount /dev/nbd0p2 $MOUNT
    sudo mkdir -p $MOUNT/boot
    sudo mount /dev/nbd0p1 $MOUNT/boot
}

umount-qcow2()
{
    if (( $# != 2 )); then
	echo umount-qcow2 [img] [mount]
	exit 1
    fi
    IMG=$1
    MOUNT=$2
    echo Unmounting partitions...
    sync
    sudo umount $MOUNT/boot $MOUNT
    sync

    echo Unmounting image...
    sudo killall qemu-nbd # TODO fragile, fix

    echo Removing nbd kernel module...
    sudo modprobe -r nbd
}

mkimage()
{
    echo Creating virtual disk...
    qemu-img create -f qcow2 cleanInstall.qcow2 2G

    mount-qcow2 cleanInstall.qcow2 clean

    echo Downloading image...
    #wget http://archlinuxarm.org/os/ArchLinuxARM-rpi-2-latest.tar.gz

    echo Installing image...
    sudo bsdtar -xpf ArchLinuxARM-rpi-2-latest.tar.gz -C clean

    echo Installing QEMU...
    sudo mkdir -p clean/usr/bin
    sudo cp /usr/bin/qemu-arm-static clean/usr/bin/qemu-arm-static

    echo Binding paths...
    sudo mount --bind /dev clean/dev
    sudo mount --bind /dev/pts clean/dev/pts
    sudo mount --bind /dev/shm clean/dev/shm
    sudo mount --bind /proc clean/proc
    sudo mount --bind /sys clean/sys

    echo CHROOT!
    sudo chroot clean /bin/bash

    sudo umount clean/dev/pts
    sudo umount clean/dev/shm
    sudo umount clean/dev
    sudo umount clean/proc
    sudo umount clean/sys

    echo Unmounting snapshot...
    umount-qcow2 cleanInstall.qcow2 clean
}

install-tools()
{
    wget https://aur.archlinux.org/packages/qe/qemu-static/qemu-static.tar.gz
    wget https://aur.archlinux.org/packages/gl/glib2-static/glib2-static.tar.gz
    wget https://aur.archlinux.org/packages/gl/glibc-static/glibc-static.tar.gz
    wget https://aur.archlinux.org/packages/pc/pcre-static/pcre-static.tar.gz
    tar xvf qemu-static.tar.gz
    tar xvf glib2-static.tar.gz
    tar xvf glibc-static.tar.gz
    tar xvf pcre-static.tar.gz
    pushd glibc-static
        makepkg --skippgpcheck
    popd
    pushd glib2-static
        makepkg --skippgpcheck
    popd
    pushd pcre-static
        makepkg --skippgpcheck
    popd
    sudo pacman --noconfirm -U glibc-static/glibc-static-2.21-1-x86_64.pkg.tar.xz \
	 glib2-static/glib2-static-2.44.0-1-x86_64.pkg.tar.xz \
	 pcre-static/pcre-static-8.36-1-x86_64.pkg.tar.xz
    pushd qemu-static
        makepkg
    popd
    sudo pacman -U qemu-static/qemu-static-2.3.0-1-x86_64.pkg.tar.xz
    sudo sh <<EOF
    echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-arm-static:' > /proc/sys/fs/binfmt_misc/register
EOF
}

case "$1" in
    "mkimage") mkimage ;;
    "install-tools") install-tools ;;
    *) echo "mkimage install-tools" ;;
esac
