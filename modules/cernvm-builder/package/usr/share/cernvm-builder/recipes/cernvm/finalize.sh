#!/bin/bash
# 'r' is a function that runs the command line and checks for errors...
. config.sh
. ../../scripts/imageutil.sh
. ../../scripts/functions.sh
. functions.sh

# Cleanup all the mounts on this directory
cleanmounts "$DIR_FAKEROOT"

# If we were not continuing and we are using partitioning, try to finalize the image
if [ -z "$CMD_continue" ] && [ "$CMD_partition" == "yes" ]; then
    
    # Collapse the partitions into a single disk
    disk_collapse "$CMD_output"
    
fi

# Now that the image is collapsed and we have a single disk image to play with, 
# install the boot loader.
if [ -z "$CMD_continue" ] && [ "$CMD_bootloader" == "yes" ]; then

    # Find a free loop device and place the output image there
    LOOPDEV=$(losetup -f)
    losetup $LOOPDEV "$CMD_output"

    # Create a temporary device map to trick GRUB into thinking that the
    # loop device (currently hosting the mountpoint) is the real disk
    r cat <<EOF > ${DIR_TMP}/device.map
(hd0)	$LOOPDEV
EOF

    # Mount again the first partition
    ANS=$(disk_mount "$CMD_output" 0 "$DIR_FAKEROOT")
    if [ "$ANS" != "OK" ]; then
        echo $ANS
        echo "ERROR: Unable to mount root partition in order to install GRUB"
        exit 1
    fi    

    # Install grub
    r grub --batch --no-floppy --device-map=${DIR_TMP}/device.map <<EOF
device (hd0) $LOOPDEV
geometry (hd0) $DEF_diskgeom
root (hd0,0)
setup --stage2=$DIR_FAKEROOT/boot/grub/stage2 (hd0)
quit
EOF
    
    # Unmount partition
    umount "$DIR_FAKEROOT" 
    
    # Delete loop device
    losetup -d $LOOPDEV
    
fi