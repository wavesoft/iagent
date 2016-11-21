#!/bin/bash

#####################################
# Check environment sanity
#####################################

which uuidgen 2>/dev/null >/dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: qemu-img was not found! Please install 'util-linux-ng'!" 1>&2
    exit 2
fi

#####################################
# Generate unspecified parameters
# or update some other parameters
#####################################

####################
# -conary-options VS. -group,-label,-version and -flavor
####################
if [ ! -z "$CMD_conary_options" ]; then 
    # Revert escaped characters
    CMD_conary_options=$(echo "$CMD_conary_options" | sed -r 's/\\(.)/\1/'g)
    
    # If we have -conary-options defined, override the  -group, -label, -version and -flavor
    CMD_group=$(echo "$CMD_conary_options" | awk -F "=|'|/" '{ print $1 }' | sed -r 's/^group-//')
    CMD_label=$(echo "$CMD_conary_options" | awk -F "=|'|/" '{ print $2 }')
    CMD_flavor=$(echo "$CMD_conary_options" | awk -F "=|'|/" '{ print $3 }')
    CMD_version=$(echo "$CMD_conary_options" | awk -F "=|'|/" '{ print $5 }')
else
    # If we don't have -conary-options defined, generate it from  -group, -label, -version and -flavor
    if [ -z "$CMD_group" ]; then
        echo "Please specify at least the-group parameter OR use the -conary-options!" 1>&2
        exit 1
    fi
    CMD_conary_options="group-$CMD_group"
    if [ ! -z "$CMD_label" ]; then
        CMD_conary_options="${CMD_conary_options}=${CMD_label}"
        [ ! -z "$CMD_flavor" ] && CMD_conary_options="${CMD_conary_options}'${CMD_flavor}'"
        [ ! -z "$CMD_version" ] && CMD_conary_options="${CMD_conary_options}/${CMD_version}"
    fi
fi

####################
# -postinstall-options VS. -model and -arch
####################
if [ ! -z "$CMD_postinstall_options" ]; then
    # If we have -postinstall-options, override the -model and -arch
    CMD_model=$(echo $CMD_postinstall_options | awk '{ print $1 }')
    CMD_arch=$(echo $CMD_postinstall_options | awk '{ print $2 }')
else
    # Build postinstall-options from -model and -arch
    if [ -z "$CMD_arch" ]; then
        echo "Please specify the -arch and -model parameter OR use the -postinstall-options!" 1>&2
        exit 1
    fi
    if [ -z "$CMD_model" ]; then
        echo "Please specify the -arch and -model parameter OR use the -postinstall-options!" 1>&2
        exit 1
    fi
    CMD_postinstall_options="$CMD_model $CMD_arch"
fi

####################
# -output-format=ext3 VS. -bootloader and -partition
####################
if [ "$CMD_output_format" == "ext3" ]; then
    # EXT3 is a shortcut for:
    # -output-format raw -bootloader no -partition no
    CMD_bootloader="no"
    CMD_partition="no"
    CMD_output_format="raw"
fi

# We cannot add a bootloader without partitions
if [ "$CMD_partition" == "no" ]; then
    CMD_bootloader="no"    
fi

#####################################
#####################################

#####################################
# Prepare partitions or continue past image
# In both cases.. mount the root filesystem
#####################################

# Default values
[ -z "$CMD_output" ] && CMD_output="$DIR_TMP"

# Prepare filesystem
if [ ! -z "$CMD_continue" ]; then
    
    # If continue == yes and the image exists, continue from there
    if [ "$CMD_continue" == "yes" ]; then
        if [ -f "$CMD_output" ]; then
            CMD_continue="$CMD_output"
        else
            CMD_continue=""
        fi
    fi

    # If we really have the file, try to mount
    if [ -f "$CMD_continue" ]; then
        
        # Continue from the previous image
        ANS=$(disk_mount "$CMD_continue" 0 "$DIR_FAKEROOT")
        if [ "$ANS" != "OK" ]; then
            echo $ANS
            exit 1
        fi
    
        # Update CMD_output => CMD_continue
        CMD_output="$CMD_continue"
        
    else
        CMD_continue=""
    fi
    
fi

# If we are not continuing, make filesystem
if [ -z "$CMD_continue" ]; then
    
    # Configurable parameters
    # - LABEL is 'root'
    # - Disable 'forced fsck after X remounts'
    TUNE2FS_ARGS="-Lroot -c0"
    
    # Detect the output image name
    [ -d "$CMD_output" ] && CMD_output="${CMD_output}/disk.hdd"
    [ -f "$CMD_output" ] && rm "$CMD_output"
    
    # Check if we should partition the image
    if [ "$CMD_partition" == "yes" ]; then
        
        # Based on the disk type, estimate geometry 
        # Got details from here: http://sanbarrow.com/vmdk-basics.html#calcgeo
        if [ "$CMD_disktype" == 'scsi' ]; then
            export DISK_GEOM_H="255"
            export DISK_GEOM_S="63"
        elif [ "$CMD_disktype" == 'ide' ]; then
            export DISK_GEOM_H="16"
            export DISK_GEOM_S="63"
        fi
        
        # Create a new image with 1 partition (It contains swapspace as file)
        TOTAL_SIZE=$(($CMD_size+$CMD_swap))
        disk_prepare "$CMD_output" "$TOTAL_SIZE:83:*:ext3:$TUNE2FS_ARGS" # If you want two partitions add: ,$CMD_swap:82:-:linux-swap
        [ $? -ne 0 ] && echo "ERROR: Unable to create disk image!" && exit 1
        
        # Create a geometry string, needed by GRUB install
        DEF_diskgeom="$DISK_GEOM_C $DISK_GEOM_H $DISK_GEOM_S"
        
    else

        # Create a raw filesystem image
        dd if=/dev/zero of="$CMD_output" bs=1k count=${CMD_size}k
        [ $? -ne 0 ] && echo "ERROR: Unable to allocate space for the disk image!" && exit 1
        
        mkfs.ext3 -f "$CMD_output"
        [ $? -ne 0 ] && echo "ERROR: Unable to create disk image!" && exit 1

        tune2fs $TUNE2FS_ARGS "$CMD_output"
        [ $? -ne 0 ] && echo "ERROR: Unable setup filesystem parameters!" && exit 1
        
    fi

fi
    
# Mount the root filesystem
ANS=$(disk_mount "$CMD_output" 0 "$DIR_FAKEROOT")
if [ "$ANS" != "OK" ]; then
    echo $ANS
    exit 1
fi

# Get the loop device that created this file
export DEF_loopdev=$(losetup -a | grep "$CMD_output" | sed -r 's/^([^:]+):.*/\1/')
if [ -z "$DEF_loopdev" ]; then
    echo "ERROR: Unable to detect the loop device used for the mount"
    exit 1
fi
