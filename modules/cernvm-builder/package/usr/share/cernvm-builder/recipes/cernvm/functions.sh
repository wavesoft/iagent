#!/bin/bash

# Run the specified cmdline and trap errors
function r {
    CMDLINE="$*"
#    echo "DEBUG: Running $CMDLINE"
    $CMDLINE
    ERR=$?
    if [ $ERR -ne 0 ]; then
        echo "ERROR: Command $CMDLINE exited with error code $ERR!" 1>&2
        exit $ERR
    fi
}

# Run the specified cmdline under eval and trap errors
function reval {
#    echo "DEBUG: Running ${1}"
    eval "$1"
    ERR=$?
    if [ $ERR -ne 0 ]; then
        echo "ERROR: Command '$1' exited with error code $ERR!" 1>&2
        exit $ERR
    fi
}

function retry {
   local nTrys=0
   local maxTrys=5
   local status=256
   until [ $status == 0 ] ; do
      eval "$1 || echo :::ERROR:::$?" 2>&1 | tee "/tmp/$$.out" 
      status=`grep -c ":::ERROR:::" /tmp/$$.out`
      if [ `grep -c "no new troves were found" /tmp/$$.out` -eq 1 ] ; then
         status=0
      fi
      if [ $status != 0 ] ; then
        nTrys=$(($nTrys + 1))
        if [ $nTrys -gt $maxTrys ] ; then
            echo "ERROR: Number of re-trys exceeded. Command: '$1' Exit code: $status" 1>&2
            exit $status
        fi
        echo "Failed (exit code $status)... retry $nTrys" 1>&2
        sleep 30
      fi
   done
   return $status
}

export r
export reval
export retry