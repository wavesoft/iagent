#!/bin/bash

# Remove all the mounts under this root folder
function cleanmounts {
    local ROOT_DIR="$1"
    sync
    local MPS=$(mount | grep "$ROOT_DIR[/ ]" | sed -r 's/.*? on (.*?) type.*/\1/')
    for MP in $MPS; do
        echo " * Unmounting $MP"
        umount $MP
    done
    if [ $(mount | grep -c "$ROOT_DIR ") -ne 0 ]; then
        echo " * Unmounting $ROOT_DIR"
        umount "$ROOT_DIR"
    fi    
}

# Cleanup and exit
function cleanexit {
    EXITCODE=$1
    
    # Display the appropriate messages
    if [ -z "$EXITCODE" ]; then
        # Called by the exit trap
        
        # Remove config file from recipe
        [ -f "$DIR_RECIPE/config.sh" ] && rm "$DIR_RECIPE/config.sh"

        # Cleanup the mess we created with the mounts
        cleanmounts "$DIR_FAKEROOT"

        # Try to remove mountpoint
        [ -d "$DIR_FAKEROOT" ] && rmdir "$DIR_FAKEROOT"        
        
        # Untrap and exit
        echo "Exit value: $RETURN_VALUE"
        trap - EXIT
        exit $RETURN_VALUE
        
    elif [ $EXITCODE -ne 0 ]; then
        echo "Build script failed! Error log follows:"
        echo "---------------------------------------------------------"
        cat "$DIR_LOG/errors.log"    
        echo "---------------------------------------------------------"
        export RETURN_VALUE=$EXITCODE
    else
        echo "Build script completed successfully!"
        export RETURN_VALUE=$EXITCODE
    fi
    
    exit $EXITCODE
}

# Run the specified cmdline and trap errors
function r {
    CMDLINE="$*"
    echo "-- Executing '$CMDLINE' at $(date)" >> "$DIR_LOG/build.log"
    $CMDLINE >>"$DIR_LOG/build.log" 2>>"$DIR_LOG/errors.log"
    ERR=$?
    echo "== Completed at $(date). RETURN = $ERR" >> "$DIR_LOG/build.log"
    if [ $ERR -ne 0 ]; then
        echo "!!! Command $CMDLINE exited with error code $ERR!" >> "$DIR_LOG/errors.log"
        cleanexit $ERR
    fi
}

# Run the specified cmdline under eval and trap errors
function reval {
    echo "-- Executing '$1' at $(date)" >> "$DIR_LOG/build.log"
    eval "$1" >>"$DIR_LOG/build.log" 2>>"$DIR_LOG/errors.log"
    ERR=$?
    echo "== Completed at $(date). RETURN = $ERR" >> "$DIR_LOG/build.log"
    if [ $ERR -ne 0 ]; then
        echo "!!! Command $1 exited with error code $ERR!" >> "$DIR_LOG/errors.log"
        cleanexit $ERR
    fi
}

# Usage message
function usage {
    echo "This script accepts no parameters. Instead you set-up the"
    echo "following environment variables before execution:"
    echo ""
    echo "   BUILD_RECIPE = The name of the build recipe"
    echo "   BUILD_ID     = The unique ID of the build"
    echo ""
    echo "Additionally, each build recipe expects a different set"
    echo "of parameters. Tey are prefixed wih PARM_xxxx."
    echo ""
    echo "If you want more help for a recipe use: $0 help <recipe>"
    echo "To list the available recipes type: $0 recipes"
    echo ""
    exit 0
}

# Helper function to echo and pad with spaces till you reach specified length
function lenecho {
    LENGTH=$1
    MESSAGE=$2
    MSGLEN=${#MESSAGE}
    let LENGTH-=$MSGLEN
    echo -n "$MESSAGE"
    for (( i=0; i<$LENGTH; i++)); do
        echo -n " "
    done
}

# Help for the specified recipe
function recipe_help {
    if [ ! -d "$DIR_RECIPES/$1" ]; then
        echo "ERROR: The recipe '$1' was not found at $DIR_RECIPES!"
        exit 1
    fi
    if [ ! -f "$DIR_RECIPES/$1/vars.sh" ]; then
        echo "ERROR: The recipe '$1' has no variable definition!"
        exit 1
    fi
    
    # Include the recipe variables
    . "$DIR_RECIPES/$1/vars.sh"

    echo " The following parameters are expected for recipe '$1':"
    echo ""
    lenecho 30 "  Variable"
    lenecho 30 "Default Value"
    echo "Description"
    lenecho 30 "  ----------"
    lenecho 30 "--------------"
    echo "------------"
    VARS=$(set | grep ^CMD_ | sed -r "s/CMD_([^=]+)=.*/\\1/" | sort)
    for VAR in $VARS; do
        VNAME="CMD_$VAR"
        VDESC="DESC_$VAR"
        VAR=$(echo $VAR | sed s/_/-/g)
        if [ "${!VNAME}" == "?" ]; then
            lenecho 60 "  -$VAR *"
        else
            lenecho 30 "  -$VAR"
            lenecho 30 "(${!VNAME})"
        fi
        echo "${!VDESC}"
    done
    echo ""
}

function recipes {
    echo "Recipes installed:"
    echo ""
    RECIPES=$(ls "$DIR_RECIPES")
    for RECIPE in $RECIPES; do
        . "$DIR_RECIPES/$RECIPE/vars.sh"
        echo "  * $RECIPE ($RECIPE_DESCRIPTION)"
        unset RECIPE_DESCRIPTION
    done
    echo ""
    echo "Use: $0 help <recipe> for more details for the parameters accepted for each recipe"
    echo ""
}

# A function to automate running of multiple scripts
function runscript {
    echo "-- Starting script $1 at $(date)" >>"$DIR_LOG/build.log"
    if [ -x $1 ]; then
        $1 >>"$DIR_LOG/build.log" 2>>"$DIR_LOG/errors.log"
        RET=$?
        echo "== Completed script $1 at $(date). RETURN = $RET" >>"$DIR_LOG/build.log"
        if [ $RET -ne 0 ]; then
            echo "!!! $1 exited with error code $RET" >> "$DIR_LOG/errors.log"
            cleanexit $RET
        fi
    else
        echo "... File $1 is missing. Silently skipping." >> "$DIR_LOG/errors.log"
    fi
}

function runchroot {
    echo "-- Starting chroot script $1 at $(date)" >>"$DIR_LOG/build.log"
    if [ -x $1 ]; then
        chroot "$DIR_FAKEROOT" /bin/bash -c "cd '$DIR_FAKEROOT_RECIPE' && $1" >>"$DIR_LOG/build.log" 2>>"$DIR_LOG/errors.log"
        RET=$?
        echo "== Completed chroot script $1 at $(date). RETURN = $RET" >>"$DIR_LOG/build.log"
        if [ $RET -ne 0 ]; then
            echo "!!! Chroot'ed script $1 exited with error code $RET" >> "$DIR_LOG/errors.log"
            cleanexit $RET
        fi
    else
        echo "... File $1 is missing. Silently skipping." >> "$DIR_LOG/errors.log"
    fi
}

# Export functions
export cleanexit
export runchroot
export runscript
export recipes
export recipe_help
export usage
export r

