#!/bin/bash
# 'r' is a function that runs the command line and checks for errors...
# 'reva' is the same as r, but uses eval on the first argument
. config.sh
. functions.sh

# Update conaryrc on the host
cat <<EOF > /etc/conaryrc
installLabelPath $CMD_install_label_path
pinTroves (kernel|linux-image-2\.6\.[0-9]+-[0-9]+(-[a-z]+)?)([:-].*|$)
autoResolve True
includeConfigFile /etc/conary/config.d/*
EOF

# Prepare conary proxy string
CPROXY=""
# Set conary proxy if defined
if [ ! -z "$CMD_conary_proxy" ]; then
    r mkdir -p /etc/conary/config.d
    PROTOCOL=$(echo $CMD_conary_proxy | sed -r "s/(\w+):.*/\1/")
    CPROXY=" --config=\"conaryProxy $PROTOCOL $CMD_conary_proxy\""
fi

retry "conary update distro-conary-config'''$CMD_flavor''' $CPROXY"

if [ ! -f ${DIR_FAKEROOT}/sbin/ldconfig ]; then
  # Install glibc (It provides /sbin/ldconfig, so upcoming packages will not complain)
  if [ "$CMD_arch" == "x86" ]; then
      retry "conary update glibc'[is: x86(i486,i586,i686)]' --root ${DIR_FAKEROOT} $CPROXY"
  else
      retry "conary update glibc'[is: x86_64]' glibc:devel'[is: x86(i486,i586,i686)]' glibc:devellib'[is: x86(i486,i586,i686)]' glibc:lib'[is: x86(i486,i586,i686)]' --root ${DIR_FAKEROOT} $CPROXY"  
  fi
fi

# Install packages
retry "conary migrate $CMD_conary_options --root ${DIR_FAKEROOT} --no-conflict-check --no-resolve $CPROXY"

# Install GRUB
if [ "$CMD_bootloader" == "yes" ]; then
    
    # Locate GRUB files
    GRUB_DIR="${DIR_FAKEROOT}/usr/share/grub/i386-redhat/"
    if [ ! -d "$GRUB_DIR" ]; then
        echo "ERROR: Unable to locate grub files at $GRUB_DIR" 1>&2
        echo "ERROR: Is the grub package installed?" 1>&2
        exit 1
    fi
    
    # Make sure we have grub directory
    [ ! -d ${DIR_FAKEROOT}/boot/grub ] && mkdir -p ${DIR_FAKEROOT}/boot/grub
    
    # Copy all the stage files to the boot directory
    cp $GRUB_DIR/* ${DIR_FAKEROOT}/boot/grub/

    # Setup device map that will be used within the VM
    r cat <<- 'EOF' > ${DIR_FAKEROOT}/boot/grub/device.map
(hd0)	/dev/hda
EOF

    # (GRUB will be actually installed at finalize.sh
    # when the disk image file is consolidated. For now we just
    # need the stage files to the /boot/grub directory)

fi

# Copy some important files
r cp /etc/resolv.conf ${DIR_FAKEROOT}/etc/resolv.conf
r cp /etc/conary/config.d/* ${DIR_FAKEROOT}/etc/conary/config.d/

# Copy files from files/ directory
r cp -vRf files/* ${DIR_FAKEROOT}/

# Make swap
r dd if=/dev/zero of=${DIR_FAKEROOT}/var/swap bs=1k count=${CMD_swap}k
r mkswap ${DIR_FAKEROOT}/var/swap

# Generate conaryrc
cat <<EOF > ${DIR_FAKEROOT}/etc/conaryrc
installLabelPath $CMD_install_label_path
pinTroves (kernel|linux-image-2\.6\.[0-9]+-[0-9]+(-[a-z]+)?)([:-].*|$)
autoResolve True
includeConfigFile /etc/conary/config.d/*
EOF

# Set appliance name
echo $CMD_appliance_name > ${DIR_FAKEROOT}/etc/sysconfig/appliance-name
