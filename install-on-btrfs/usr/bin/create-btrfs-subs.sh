#!/bin/bash

echo PWD: $PWD

exitus () {
    echo "ENDE $1 $2"
    case $1 in
        0)
            echo "end $2"
            exit 0
            ;;
        1)
            echo "exit $2"
            exit 1
            ;;
        *)
            echo "exit $2"
            exit $1
            ;;
    esac

}

ANW=$0

# Set defaults
SUBS="boot-grub-x86_64-efi home opt srv subs usr-local var-cache var-lib-mpd var-lib-named var-log var-opt var-spool var-spool-dovecot var-mail var-tmp var-virutal_machines var-www"
ARCH="amd64"
DIST="stretch"
POOLPATH="/var/cache"
POOLDIR="btrfs_pool_SYSTEM"
BACKUPDIR="backup"
POOL="${POOLPATH}/${POOLDIR}"
BACKUP="${POOLPATH}/${BACKUPDIR}"
MAIN="@debian-${DIST}"
ALWAYS="__ALWAYSCURRENT__"
DEVICE=""
TARGET=""
CONVERT=false


# Parse commandline
set -- $(getopt "A:a:CD:d:hH:m:T:" "$@" )

while test $# -gt 1 ; do
    case $1 in
        -A)
            ARCH=$2
            shift; shift
            ;;
        -a)
            ALWAYS=$2
            shift; shift
            ;;
	-C)
	    CONVERT=true
	    shift
	    ;;
        -D)
            DEVICE=$2
            DEV=${DEVICE#/dev/}
            shift; shift
            ;;
        -d)
            DIST=$2
            shift; shift
            ;;
        -h)
            cat <<EOF
 Create a partition with btrfs
 Mount it to a free mountpoint (for example /mnt)
 change directory to this mountpoint (cd /mnt)
 run this script
EOF
            shift
            exit 0
            ;;
        -m)
            MAIN=$2
            shift; shift
            ;;
        -T)
            TARGET=$2
            DEV=$(awk '$9 == "btrfs" && ($5 == targ || $10 == dev) {gsub("/dev/","",$10);print $10}' targ="${TARGET%/}" dev="$DEVICE" /proc/self/mountinfo|uniq)
            shift; shift
            ;;
        --)
            break
            ;;
        *)
            echo "unbekannte Option: $1"
            exit 1
            ;;
    esac
done

if test -z "$DEVICE" -a -z "$TARGET"; then
    echo "No target or device given -> exit"
    exit 1
fi

if test -n $TARGET; then
	echo $TARGET $DEVICE
fi

echo DEV $DEV
if test -e /dev/$DEV; then
    ROT=$(cat /sys/block/$(printf '%s' "$DEV" | sed 's/[0-9]//g')/queue/rotational 2>/dev/null || echo 1 )
    echo ROT: $ROT
    if test $ROT -eq 0; then
        SSD=true
    else
        SSD=false
    fi
else
    echo "/dev/$DEV does not exist"
    exit 2
fi


NO=""
RELATIME="rel" #rel or no or empty
if $SSD
then
	SSDOPTS=",ssd,discard"
	NO="no"
	RELATIME="no"
fi

BTRFS=/bin/btrfs
AWK=/usr/bin/awk
GREP=/bin/grep
FINDMNT=/bin/findmnt
BLKID=/sbin/blkid
MKDIR=/bin/mkdir
MOUNT=/bin/mount
DEBOOTSTRAP=/usr/sbin/debootstrap
SYSTEMDESCAPE=/bin/systemd-escape

UUID=$($BLKID -s UUID -o value $($FINDMNT -n -o SOURCE --target $(pwd)))

test -e "${BACKUP}" || $MKDIR "${BACKUP}"
test -e "${POOL}" || $MKDIR "${POOL}"
echo "UUID: $UUID"
$MOUNT "UUID=${UUID}" "${POOL}" -t btrfs -o "defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=/"

test -e "${POOL}/${MAIN}" || $BTRFS sub create "${POOL}/${MAIN}"
test -e "${POOL}/${ALWAYS}" || $BTRFS sub create "${POOL}/${ALWAYS}"


cd "${POOL}/${ALWAYS}"
for i in $SUBS
do
	"$BTRFS" sub create "$i"
	$MKDIR -p "../${MAIN}/$($SYSTEMDESCAPE -pu $i)"
	echo $MOUNT "UUID=${UUID}" "${POOL}/${MAIN}/$($SYSTEMDESCAPE -pu $i)" -t btrfs -o "defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=${ALWAYS}/${i}"
	$MOUNT "UUID=${UUID}" "${POOL}/${MAIN}/$($SYSTEMDESCAPE -pu $i)" -t btrfs -o "defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=${ALWAYS}/${i}"
done
cd ..
mkdir -p "${MAIN}/etc"

echo "UUID=$UUID	/	btrfs	defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS}	0	0" 
echo "UUID=$UUID	${POOL}	btrfs	defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=/	0	0" 
echo "UUID=$UUID	/	btrfs	defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS}	0	0" > "${MAIN}/etc/fstab"
echo "UUID=$UUID	${POOL}	btrfs	defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=/	0	0" >> "${MAIN}/etc/fstab"

for i in $SUBS
do
	#echo "UUID=$UUID	/$(echo $i|sed 's@-@/@g')	btrfs	defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=${ALWAYS}/${i}	0	0" >> "${MAIN}/etc/fstab"
	echo "UUID=$UUID	$($SYSTEMDESCAPE -pu $i)	btrfs	defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=${ALWAYS}/${i}	0	0" 
	echo "UUID=$UUID	$($SYSTEMDESCAPE -pu $i)	btrfs	defaults,compress=lzo,${NO}space_cache,${NO}inode_cache,${RELATIME}atime${SSDOPTS},subvol=${ALWAYS}/${i}	0	0" >> "${MAIN}/etc/fstab"
done


cp "${MAIN}/etc/fstab" "${MAIN}/etc/fstab.orig"
rsync -a "${POOL}/"  "${POOL}/${MAIN}/" --exclude="${MAIN}" --exclude="${ALWAYS}" --exclude="proc" --exclude="sys" --exclude="tmp"  --exclude="dev" --exclude="run" --exclude="var/run"

#cat <<EOF
#Now your BTRFS-Subvolumes are created and mounted.
#You can now install your system with debootstrap 
#
#Install with debootstrap? [Y/n]
#EOF
#

if $CONVERT; then
	echo convert
else
	echo no convert
fi
exit 0

if [ ! -t 0 ]; then

#read i
#case i in
#    N|n)
#        echo "Exit skript"
#        ;;
#    Y|y) 
        $DEBOOTSTRAP --arch "${ARCH}" "${DIST}" "${MAIN}" http://ftp.at.debian.org/debian

        $MOUNT -o bind /dev "${MAIN}/dev"
        $MOUNT -o bind /dev/pts "${MAIN}/dev/pts"
        $MOUNT -t sysfs /sys "${MAIN}/sys"
        $MOUNT -t proc /proc "${MAIN}/proc"
        cp /proc/mounts "${MAIN}/etc/mtab"
        cp /etc/resolv.conf "${MAIN}/etc/resolv.conf"

        chroot "${MAIN}"
        cat <<EOF 
    You are now in the chroot, groundsystem is now installed. Now install other packages.
    add new users, and add them to several groups
    add grub2 or refind and initramfs
    try apt install linux-image task-desktop task-german-desktop console-setup tzdata
EOF
#        ;;
#esac

fi



exit 0

#UUID=03d34c21-a150-4e91-8470-a6346d04287a	/			btrfs	defaults,compress=lzo,nospace_cache,inode_cache,relatime,ssd,discard							0	0
#UUID=03d34c21-a150-4e91-8470-a6346d04287a	/boot/grub/x86_64/efi	btrfs	defaults,compress=lzo,nospace_cache,inode_cache,relatime,ssd,discard,subvol=__ALWAYSCURRENT__/boot-grub-x86_64-efi	0	0


