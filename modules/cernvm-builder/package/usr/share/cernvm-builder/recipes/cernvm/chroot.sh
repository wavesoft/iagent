#!/bin/bash

. config.sh
. functions.sh

# Update the grub menu
./scripts/updategrub.sh "$CMD_appliance_name"

# Run ldconfig
r /sbin/ldconfig

# Sync shadow and password file
r /usr/sbin/pwconv

# Post-install CernVM
r /etc/cernvm/postinstall $CMD_postinstall_options
