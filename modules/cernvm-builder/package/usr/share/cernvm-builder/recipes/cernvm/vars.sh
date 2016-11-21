#######################################
# Definition of command-line variables
#######################################

RECIPE_DESCRIPTION="Recipe for building CernVM images"

CMD_size="8192"
DESC_size="The size of the root partition (Mb)"
CMD_swap="1024"
DESC_swap="The size of the sawp file (Mb)"
CMD_postinstall_options=""
DESC_postinstall_options="The commandline to pass to /etc/cernvm/postinstall (Overrides -model, -arch)"
CMD_conary_options=""
DESC_conary_options="The command line to pass to conary update (Overrides -group, -label, -version and -flavor)"
CMD_scripts=""
DESC_scripts="The folder that contains the custom build scripts"
CMD_output=""
DESC_output="The output image filename or folder"
CMD_appliance_name="CERN Virtual Machine"
DESC_appliance_name="The name of the virtual appliance"
CMD_install_label_path="?"
DESC_install_label_path="The installLabelPath parameter of /etc/conaryrc (ex. cernvm.cern.ch@cern:cernvm-2-devel cernvm.cern.ch@cern:sl-5)"
CMD_conary_proxy=""
DESC_conary_proxy="The http(s) proxy to use for conary"
CMD_output_format="raw"
DESC_output_format="The output format for the disk image file"
CMD_output_compress=""
DESC_output_compress="Specify the output image compression (ex. gz or bz2)"
CMD_continue="yes"
DESC_continue="If 'yes', and the target image already exists, it resumes building from it. If '/path/to/diskfile', resumes building from that file. "
CMD_disktype="ide"
DESC_disktype="Defines the geometry of the disk: 255 heads / 63 sectors for 'scsi' or 16 heads / 63 sectors for 'ide'"

CMD_model=""
DESC_model="The virtual machine model to use for post-install (ex: cernvm-basic-vmdk) (Overriden by -postinstall-options)"
CMD_arch="x86"
DESC_arch='Target architecture (x86 or x86_64) (Overriden by -postinstall-options)'
CMD_group=""
DESC_group='The target conary group (ex. cernvm-desktop) (Overriden by -conary-options)'
CMD_label=""
DESC_label='The target conary label (ex. cernvm.cern.ch@cern:cernvm-2) (Overriden by -conary-options)'
CMD_flavor=""
DESC_flavor='The target conary flavor (ex. [is: x86]) (Overriden by -conary-options)'
CMD_version=""
DESC_version="The target conary version (Overriden by -conary-options)"

CMD_bootloader="yes"
DESC_bootloader="Set to 'yes' if you want to install a boot loader on the final image (Overriden by -partition=no and -output-format=ext3)"
CMD_partition="yes"
DESC_partition="Set to 'yes' if you want to create a partition on the final image (Otherwise the entire disk will be used for the filesystem)"

CMD_logfile_dir="$DIR_LOG"
DESC_logfile_dir="Specify the directory you want to store the logs into (Leave empty to keep no logs)"
CMD_logfile_prefix=""
DESC_logfile_prefix="Specify the prefix you want on the logfiles"
