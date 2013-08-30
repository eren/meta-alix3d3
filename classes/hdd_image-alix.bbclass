# This bbclass is the modified version of sdcard_image-rpi.bbclass and
# boot-directdisk.bbclass. It creates two partitions /dev/sda1 and
# /dev/sda2. The first partition has kernel, initrd, and syslinux, the
# second one contains the rootfs
#
# This can be directly dd'ed info CF Card and can be run.
#
# Eren Turkay <eren@hambedded.org>
# 2013-08-30

inherit image_types

IMAGE_DEPENDS_alix-hddimage = " \
            parted-native \
            mtools-native \
            dosfstools-native \
            syslinux-native \
            virtual/kernel \
            "

INITRD_IMAGE = "core-image-minimal-initramfs-alix3d3"
INITRD = "${DEPLOY_DIR_IMAGE}/${INITRD_IMAGE}-${MACHINE}.cpio.gz"
ROOTFS = "${DEPLOY_DIR_IMAGE}/${IMAGE_BASENAME}-${MACHINE}.ext3"

HDDDIR = "${S}/alix-hdd/boot"
HDDIMG = "${S}/alix-hdd.image"

BOOTDD_VOLUME_ID   ?= "boot"
BOOTDD_EXTRA_SPACE ?= "2048"

# Get the build_syslinux_cfg() function from the syslinux class
LABELS = "boot"
AUTO_SYSLINUXCFG = "1"
SYSLINUX_ROOT = "root=/dev/sda2"
SYSLINUX_TIMEOUT ?= "10"

IMAGE_SUFFIX = "alix-hddimage"

inherit syslinux

IMAGE_CMD_alix-hddimage() {
    IMAGE=${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.${IMAGE_SUFFIX}

    # FIXME: Normally this function should be defined as another task. I
    # added it before do_rootfs but somehow syslinux.cfg gets lots after
    # its creation. This is a hack to build syslinux configuration.
    #
    # Remember that if you have an error in build_syslinux_cfg, you will
    # not get a debug output, neither syslinux.cfg. In this case, to get
    # the output of the function, the commented task definition at the
    # end can be used.
    #
    # -- Eren
    RETVAL="${@bb.build.exec_func('build_syslinux_cfg', d)}"

    install -d ${HDDDIR}
    install -m 0644 ${STAGING_KERNEL_DIR}/bzImage ${HDDDIR}/vmlinuz

    if [ -n "${INITRD}" ] && [ -s "${INITRD}" ]; then
        install -m 0644 ${INITRD} ${HDDDIR}/initrd
    fi

    install -m 0644 ${S}/syslinux.cfg ${HDDDIR}/syslinux.cfg
    install -m 444 ${STAGING_LIBDIR}/syslinux/ldlinux.sys ${HDDDIR}/ldlinux.sys

    BLOCKS=`du -bks ${HDDDIR} | cut -f 1`
    BLOCKS=`expr $BLOCKS + ${BOOTDD_EXTRA_SPACE}`

    # Ensure total sectors is an integral number of sectors per
    # track or mcopy will complain. Sectors are 512 bytes, and we
    # generate images with 32 sectors per track. This calculation is
    # done in blocks, thus the mod by 16 instead of 32.
    BLOCKS=$(expr $BLOCKS + $(expr 16 - $(expr $BLOCKS % 16)))

    mkdosfs -n ${BOOTDD_VOLUME_ID} -S 512 -C ${HDDIMG} $BLOCKS 
    mcopy -i ${HDDIMG} -s ${HDDDIR}/* ::/

    syslinux ${HDDIMG}
    chmod 644 ${HDDIMG}

    ROOTFSBLOCKS=`du -Lbks ${ROOTFS} | cut -f 1`
    TOTALSIZE=`expr $BLOCKS + $ROOTFSBLOCKS`
    END1=`expr $BLOCKS \* 1024`
    END2=`expr $END1 + 512`
    END3=`expr \( $ROOTFSBLOCKS \* 1024 \) + $END1`

    echo $ROOTFSBLOCKS $TOTALSIZE $END1 $END2 $END3
    rm -rf $IMAGE
    dd if=/dev/zero of=$IMAGE bs=1024 seek=$TOTALSIZE count=1

    parted $IMAGE mklabel msdos
    parted $IMAGE mkpart primary fat16 0 ${END1}B
    parted $IMAGE unit B mkpart primary ext2 ${END2}B ${END3}B
    parted $IMAGE set 1 boot on 
    parted $IMAGE print

    OFFSET=`expr $END2 / 512`
    dd if=${STAGING_LIBDIR}/syslinux/mbr.bin of=$IMAGE conv=notrunc
    dd if=${HDDIMG} of=$IMAGE conv=notrunc seek=1 bs=512
    dd if=${ROOTFS} of=$IMAGE conv=notrunc seek=$OFFSET bs=512
}


#python do_createsyslinuxcfg() {
#    bb.build.exec_func('build_syslinux_cfg', d)
#}
#addtask create_syslinuxcfg before do_rootfs

do_rootfs[depends] += "${INITRD_IMAGE}:do_rootfs"
