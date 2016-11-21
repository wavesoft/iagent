#!/bin/bash
#
# Utilities for disk image generation
#
# ==================================================================================
#
# This function generates a disk image based on the specified geometry,
# creates filesystems and echoes the names of the loop devices that
# hold
#
# ==================================================================================
#
# Syntax:
#
#  mkdir <disk name> <disk layout>
#
# Disk layout can be:
#
#  <size MB>:<hex_type>[:<flags>[:<filesystem>[:<mkfs.xxxx flags>]]][,<size ...]
#
# Flags can be:
#   
#  -  : None
#  *  : Bootable
#
# For example
#
#  prepare_disk /tmp/disk-31ad3dfma3a9d "512:82:-:linux-swap,2048:83:*:ext3"
#
# ----------------------------------------------------------------------------------
# This script creates one file per partition, allowing them to be mounted without
# need of a version of losetup that supports the --limitsize parameter. It also
# uses a smart collapsing technique in order to be as fast as possible.
#
# It works by collapsing the previous partition to the next partition. For example:
#
#  +---+-------------+---------------+---+
#  |MBR|      A      |        B      | C |
#  +---+-------------+---------------+---+
#
#  It will collapse the  partition files as following:
#
#  1) Collapse B partition to C
#  2) Collapse A partition to BC
#  3) Collapse MBR to ABC
#
# This works the best if the last partition is the biggest
#
# ==================================================================================
function disk_prepare {

    # What FDisk Reports, and how are we basing our disk geometry:
    # (If needed, tune-up those values, but be aware of the consequences)
    local H="4"                   # 4 Heads / Cyclinder
    local S="32"                  # 32 Sectors / Track
    [ ! -z "$DISK_GEOM_H" ] && H="$DISK_GEOM_H"
    [ ! -z "$DISK_GEOM_S" ] && S="$DISK_GEOM_S"

    # Prepare the rest of geometry parameters
    local C="0"                   # Cylinders will grow dynamically as we read the disk layout definition
    local SS="512"                # Sector size = 512b
    [ ! -z "$DISK_GEOM_SS" ] && SS="$DISK_GEOM_SS"
    local CS="0"
    let CS=$H*$S*$SS              # Cylinder size
    local MB="1048576"            # How big a MB is
    
    # Export geometry information to the evironment
    export DISK_GEOM_H="$H"
    export DISK_GEOM_S="$S"
    export DISK_GEOM_SS="$SS"
    
    # Current position on the disk geometry
    local POS=$S                  # First track of first sector is reserved for MBR
    local DIFF=$POS               # The sectors to compensate on the next iteration
    
    # Update local vars from global vars
    
    # Create the collapse script
    # This script will collapse all the partition files back to the original
    # disk image
    touch "$1.collapse.tmp"
    local LAST_FILE="$1.mbr"
    local LAST_POS="0"
    local LAST_SIZE="$SS"

    # Update the collapse script (Remember: The file will be flipped later)
    echo "rm -f \"$1.mbr\"" >> "$1.collapse.tmp"
    
    # Prepare geometry syntax compatible with sfdisk and
    # the script that will be executed after the disk image
    # is ready in order to build the filesystems
    local SFDISK_SCRIPT=""; IFS=$','; local I=0
    for PART in $2; do
        
        # Deserialize information from the geometry string
        local P_SIZE=$(echo $PART | tr ':' ' ' | awk '{ print $1 }')
        local P_TYPE=$(echo $PART | tr ':' ' ' | awk '{ print $2 }')
        local P_FLAG=$(echo $PART | tr ':' ' ' | awk '{ print $3 }')
        local P_FS=$(echo $PART | tr ':' ' ' | awk '{ print $4 }')
        local P_FSFLAGS=$(echo $PART | tr ':' ' ' | awk '{ print $5 }')
        [ -z "$P_FLAG" ] && P_FLAG=''
        [ -z "$P_TYPE" ] && P_TYPE='83'
        [ -z "$P_FSFLAGS" ] && P_FSFLAGS=''
        
        # Calculate SIZE in cylinders
        local SIZE=$(echo "( $(( $P_SIZE*$MB+$DIFF*$SS )) + $CS - 1)/$CS" | bc) # round-up (Ceiling) the number of Cylinders
        let C=${C}+${SIZE}
        let SIZE=${SIZE}*${H}*${S}-$DIFF
        
        # Update parted script
        [ ! -z "$SFDISK_SCRIPT" ] && SFDISK_SCRIPT="${SFDISK_SCRIPT};"
        SFDISK_SCRIPT="${SFDISK_SCRIPT}${POS},${SIZE},${P_TYPE},${P_FLAG}"
        
        # Create the partition disk image (seek= tells the system to create sparse file)
        local PDI="$1.p${I}"
        dd if=/dev/zero of="$PDI" bs=$SS count=0 seek=$(( $SIZE + $POS ))
        
        # Update collapse script (Remember: The file will be flipped later)
        [ $LAST_POS -gt 0 ] && echo "rm -f \"$LAST_FILE\"" >> "$1.collapse.tmp"
        echo "dd if=\"$LAST_FILE\" of=\"$1\" bs=$SS seek=$LAST_POS skip=$LAST_POS count=$LAST_SIZE conv=notrunc" >> "$1.collapse.tmp"
        LAST_FILE="$PDI"
        LAST_POS="$POS"
        LAST_SIZE="$SIZE"
        
        # If we need to create filesystem, create it now
        if [ ! -z "$P_FS" ]; then
            
            # Pick a loop device
            local LOOPDEV=$(losetup -f)
            while [ -z "$LOOPDEV" ]; do # If all loop devices are busy, wait until one becomes free
                sleep 2
                LOOPDEV=$(losetup -f)
            done
            
            # Setup loop device
            local OFS=$(( $POS * $SS ))
            losetup -o $OFS $LOOPDEV "$PDI"
            
            # Create a mount script
            echo "#!/bin/bash" > "$PDI-mount.sh"
            echo '[ -z "$1" ] && echo "Specify a mount point!" && exit 1' >> "$PDI-mount.sh"
            echo "[ -f \"$PDI\" ] && mount -o loop,offset=$OFS \"$PDI\" \"\$1\" && exit 0" >> "$PDI-mount.sh"
            echo "[ -f \"$1\" ] && mount -o loop,offset=$OFS \"$1\" \"\$1\"" >> "$PDI-mount.sh"
            chmod +x "$PDI-mount.sh"
            
            # Make filesystem
            if [ "$P_FS" == "linux-swap" ]; then
                # Swap is an exception
                mkswap ${P_FSFLAGS} $LOOPDEV
            elif [ "$P_FS" == "ext3" ]; then
                # EXT3 is also an exception because we need the -F parameter
                mkfs.ext3 -F $LOOPDEV
                # Use tune2fs to apply more advanced configuration, 
                # such as -c0 to cancel the 'forced check' of the filesystem
                # after X remounts
                tune2fs ${P_FSFLAGS} $LOOPDEV
            else
                # Check if there is a mkfs utility with this name
                BIN=$(which mkfs.${P_FS})
                if [ $? == 0 ]; then
                    $BIN ${P_FSFLAGS} $LOOPDEV
                fi
            fi
            
            # Delete loop device
            losetup -d $LOOPDEV
            
        fi

        # Update sector position
        let POS=$POS+$SIZE
        let I++
        DIFF=0
        
    done
    unset IFS

    # Start collapsing
    echo "mv \"$LAST_FILE\" \"$1\"" >> "$1.collapse.tmp"
    
    # Prepare only the mbr
    dd if=/dev/zero of="$1.mbr" bs=$SS count=$S
    
    # Export the cyliders
    export DISK_GEOM_C="$C"

    # Create partitions (And force sfdisk to ignore the small disk)
    echo $SFDISK_SCRIPT | tr ';' '\n' | sfdisk -C$C -H$H -S$S -uS -uS -f -L --no-reread "$1.mbr"
    
    # Flip lines and make the collapse.sh
    tac "$1.collapse.tmp" > "$1.collapse.sh"
    echo "rm -f \"$1.collapse.sh\"" >> "$1.collapse.sh"
    rm -f "$1.collapse.tmp"

}

# ==================================================================================
# Collapse disk partitions back to a single file
# ----------------------------------------------------------------------------------
#  This function runs the collapse script, generated by the disk_prepare function.
# ==================================================================================
function disk_collapse {
    
    if [ ! -f "$1.collapse.sh" ]; then
        echo "ERROR: Cannot find collapse information!"
        return
    fi
    
    # Collapse files
    . "$1.collapse.sh"
    
    # Remove mount files
    rm -f $1.p*.sh
    
}

# ==================================================================================
# Analyze the geometry of the disk and try to mount the specified partition
# ==================================================================================
function disk_mount {
    local DISK=$1
    local PARTITION=$2
    local MOUNTPOINT=$3
    
    # Validate input
    [ -z "$DISK" ] && return 1
    [ -z "$PARTITION" ] && return 1
    [ -z "$MOUNTPOINT" ] && return 1
    [ ! -d "$MOUNTPOINT" ] && return 2
    
    # If we are targeting an expanded disk image created by disk_prepare,
    # use the mount scripts already provided....
    if [ -x "$DISK.p${PARTITION}-mount.sh" ]; then
        "$DISK.p${PARTITION}-mount.sh" "$MOUNTPOINT"
        [ $? -eq 0 ] && echo "OK" && return
        # If the script failed, use our implementation...
    fi 
    
    # Fetch fdisk output
    local IFS=$'\n'
    local FDISK=$(fdisk -l "$DISK" 2>&1 | tr '\n' ';') 
    # -->                                  ^^ Compact new lines - they get stripped otherwise and we need them
    
    # Check for unpartitioned disk (Which means RAW filesystem on the disk)
    if [ $(echo "$FDISK" | grep -c "doesn't contain a valid partition table") -ne 0 ]; then
        # Try to mount only if the specified partition is the first one
        if [ $PARTITION -eq 0 ]; then
            mount -o loop "$DISK" "$MOUNTPOINT"
            [ $? -eq 0 ] && echo "OK" && return # OK?
            echo "ERROR: This doesn't seem like a filesystem image"
            return
        fi
        echo "ERROR: Cannot mount other than the partition 0 in a filesystem image"
        return
    else
        # Get the units to calculate the byte offsets
        local FDISK_UNITS=$(echo "$FDISK" | tr ';' '\n' | grep 'Units =')
        local UNITS=$(echo "$FDISK_UNITS" | sed -r 's/.*? ([0-9]+) bytes/\1/')
        local SS=$(echo "$FDISK_UNITS" | sed -r 's/.*? of [0-9]+ \* ([0-9]+) .*/\1/')
        
        # Also get heats and sectors (Usually 4/32 - But just to be sure)
        local FDISK_HDS=$(echo "$FDISK" | tr ';' '\n' | grep 'sectors/track')
        local HEADS=$(echo "$FDISK_HDS" | grep " heads" | sed -r 's/([0-9]+) heads.*/\1/' )
        local SECTORS=$(echo "$FDISK_HDS" | grep " sectors" | sed -r 's/.*? ([0-9]+) sectors.*/\1/' )
        
        # Process the partition table
        local ID=0
        local IFS=$'\n';
        local PARTITIONS=$(echo "$FDISK" | tr ';' '\n' | grep -E "${DISK}p?[0-9]+ " | sed 's/*//')
        for PART in $PARTITIONS; do
            local NAME=$(echo $PART | awk '{ print $1 }')
            local START=$(echo $PART | awk '{ print $2 }')
            local END=$(echo $PART | awk '{ print $3 }')
            
            # Is this the partition we want to mount?
            if [ $ID -eq $PARTITION ]; then
                
                if [ $START -eq 1 ]; then
                    # If the start is 1 it's a bit tricky
                    
                    # 1) Try the legacy approach: MBR occupies 1 sector
                    local OFFSET=$(( $SECTORS * $SS ))
                    mount -o loop,offset=$OFFSET "$DISK" "$MOUNTPOINT"
                    [ $? -eq 0 ] && echo "OK" && return # OK?

                    # 2) Try the squeezed approach: MBR occupies only the 512 first bytes
                    mount -o loop,offset=512 "$DISK" "$MOUNTPOINT"
                    [ $? -eq 0 ] && echo "OK" && return # OK?

                    # 3) Try the stupid approach: MBR occupies the entire cylinder
                    mount -o loop,offset=$UNITS "$DISK" "$MOUNTPOINT"
                    [ $? -eq 0 ] && echo "OK" && return # OK?
                    
                    # Sorry.. no other options
                    echo "ERROR: Cannot detect partition offset"
                    return
                    
                else
                    # Otherwise it's simple
                    local OFFSET=$(( ( $START - 1 ) * $UNITS ))
                    
                    # Mount
                    mount -o loop,offset=$OFFSET "$DISK" "$MOUNTPOINT"
                    [ $? -eq 0 ] && echo "OK" && return # OK?
                    
                    # Sorry.. no other options to try
                    echo "ERROR: Cannot detect partition offset"
                    return
                    
                fi
                
            fi
            let ID++
        done
        
    fi

    # We couldn't find the partition
    echo "ERROR: Cannot find partition $PARTITION"
    
}
