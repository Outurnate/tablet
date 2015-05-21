#!/bin/bash
#qemu
#bindfs
#binfmt_misc

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
    MOUNTOPTS="-u $(id -u) -g $(id -g)"
    sudo mkdir -p root/$MOUNT
    sudo mount /dev/nbd0p2 root/$MOUNT
    sudo mkdir -p root/$MOUNT/boot
    sudo mount /dev/nbd0p1 root/$MOUNT/boot -o uid=$(id -u) -o gid=$(id -g)
    mkdir -p $MOUNT
    mkdir -p $MOUNT/boot
    sudo bindfs $MOUNTOPTS root/$MOUNT $MOUNT
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
    sudo umount $MOUNT/boot $MOUNT
    sync
    sudo umount root/$MOUNT/boot root/$MOUNT
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
    wget http://archlinuxarm.org/os/ArchLinuxARM-rpi-2-latest.tar.gz

    echo Installing image...
    bsdtar -xpf ArchLinuxARM-rpi-2-latest.tar.gz -C clean

    umount-qcow2 cleanInstall.qcow2 clean

    echo Building snapshot image...
    qemu-img create -f qcow2 -b cleanInstall.qcow2 snapshot.qcow2
}

install-tools()
{
    if [[ ! -d "qemu" ]]; then
       git clone --depth=1 git://git.savannah.nongnu.org/qemu.git
    fi
    pushd qemu
    ./configure --disable-kvm --target-list=arm-linux-user --static
    make $MAKEOPTS
    echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-arm-static:' > /proc/sys/fs/binfmt_misc/register
}

case "$1" in
    "mkimage") mkimage ;;
    "install-tools") install-tools ;;
    *) echo "mkimage install-tools" ;;
esac
