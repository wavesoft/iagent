#!/bin/bash

OUT="/boot/grub/grub.conf"
TITLE=$1

# Put header
cat <<EOF > $OUT
# grub.conf generated by Hephaestus - The CernVM Image Building utility
#
# Note that you do not have to rerun grub after making changes to this file
# NOTICE:  You have a /boot partition.  This means that
#          all kernel and initrd paths are relative to /boot/, eg.
#          root (hd0,0)
#          kernel /vmlinuz-version ro root=/dev/mapper/system-RootVol
#          initrd /initrd-[generic-]version.img
#splashimage=(hd0,0)/boot/grub/cernvm.xpm.gz
default=0
timeout=5
hiddenmenu
EOF

# Put kernel versions that were detected
VERSIONS=$(ls /boot/ | grep ^vmlinuz- | sed -r s/^vmlinuz-//)
for V in $VERSIONS; do
    echo "title $TITLE ($V)" >> $OUT
    echo "      root (hd0,0)" >> $OUT
    echo "      kernel /boot/vmlinuz-$V ro root=LABEL=root " >> $OUT
    echo "      initrd /boot/initrd-$V.img" >> $OUT
done