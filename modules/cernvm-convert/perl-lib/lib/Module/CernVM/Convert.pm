#
# This file is part of CernVM iAgent Project.
#
# iAgent is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# iAgent is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with iAgent. If not, see <http://www.gnu.org/licenses/>.
#
# Developed by Ioannis Charalampidis 2011-2012 at PH/SFT, CERN
# Contact: <ioannis.charalampidis[at]cern.ch>
#

package Module::CernVM::Convert;
use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use Data::UUID;
use Sys::Hostname;
use POE;
use File::Basename;
use Data::Dumper;
use Tools::FileTransfer;

# Brad Fitchpatrickl

our $MANIFEST = {

	WORKFLOW => {
		"ibuilder:convert" => {
			ActionHandler => "image_convert",
			Description => "Convert a raw HDD image into a redisributable virtual disk format",
			Threaded => 1,
			RequiredParameters => [ 
			    'storage_uri', 'build_files', 'build_id', 'convert_targets'
			    ]
		}
	}	
	
};

############################################
# Create new instance
sub new {
############################################
    my $class = shift;
    my $config = shift;
    
    $config->{ConvertWorkdir}="/tmp" unless defined($config->{ConvertWorkdir});
    
    my $self = { 
            Workdir => $config->{ConvertWorkdir}
        };
    return bless $self, $class;
}

############################################
# Convert the specified RAW image into a set
# of formats
sub __image_convert {
############################################
	my ($self, $context, $logdir, $id) = @_[ OBJECT, ARG0, ARG1, ARG2 ];
	
    # Prepare environment
	my $dir = $self->{Workdir}.'/'.$context->{build_id};
	mkdir $dir unless (-d $dir);
	
	# Fetch RAW disk
	my $raw_disk = $dir.'/'.$context->{build_files}->{raw};
	my $barename = $context->{build_id};
	
	# Download raw image
	print("Downloading raw disk\n");
	my $ret = get_file(
	    $context->{storage_uri},
	    $context->{build_files}->{raw},
	    $raw_disk
	    );
	
	# Return on error
	return $ret if ($ret != 0);
	
    # Start conversion
    print("Converting to formats: ".Dumper($context->{convert_targets})."\n");
    foreach (@{$context->{convert_targets}}) {
        my $fmt = $_->{type};
        
        # ==================
        #  RAW -> QCOW2
        # ==================
        if ($fmt eq "qcow2") {
            my $targetname = $barename.'.qcow2';
            my $target = $dir."/$targetname";

            # Convert
            print("Converting to QCOW2: $target\n");
        	$ret = system("qemu-img", "convert", "-O", "qcow2", $raw_disk, $target);
        	print(" = $ret\n");
        	
        	# Compress
        	print("Compressing");
        	$ret = system("pigz", $target);
        	print(" = $ret\n");
        	$target .= ".gz";
            
            # Upload image
        	print("Uploading $target to /$targetname\n");
        	my $ret = put_file(
        	    $context->{storage_uri},
        	    $target,
        	    $targetname
        	    );
        	print(" = $ret\n");
        	
        	# Remove local image to free space
        	unlink($target);

        } 
        
        # ==================
        #  RAW -> VMDK
        # ==================
        elsif ($fmt eq "vmdk") {
            my $targetname = $barename.'.vmdk';
            my $target = $dir."/$targetname";

            # Convert
            print("Converting to QCOW2: $target\n");
        	$ret = system("qemu-img", "convert", "-O", "vmdk", $raw_disk, $target);
        	print(" = $ret\n");
        	
        	# Compress
        	print("Compressing");
        	$ret = system("pigz", $target);
        	print(" = $ret\n");
        	$target .= ".gz";
            
            # Upload image
        	print("Uploading $target to /$targetname\n");
        	my $ret = put_file(
        	    $context->{storage_uri},
        	    $target,
        	    $targetname
        	    );
        	print(" = $ret\n");
        	
        	# Remove local image to free space
        	unlink($target);
        
        }
        
        # ==================
        #  RAW -> EXT3
        # ==================
        elsif ($fmt eq "ext3") {
            my $targetname = $barename.'.ext3';
            my $target = $dir."/$targetname";
            my $partition = $_->{partition};
            $partition=1 unless defined($partition);
            
            # Extract disk layout information

            # Extract partition information
            print("Converting to QCOW2: $target\n");
        	$ret = system("qemu-img", "convert", "-O", "vmdk", $raw_disk, $target);
        	print(" = $ret\n");
        	
        	# Compress
        	print("Compressing");
        	$ret = system("pigz", $target);
        	print(" = $ret\n");
        	$target .= ".gz";
            
            # Upload image
        	print("Uploading $target to /$targetname\n");
        	my $ret = put_file(
        	    $context->{storage_uri},
        	    $target,
        	    $targetname
        	    );
        	print(" = $ret\n");
        	
        	# Remove local image to free space
        	unlink($target);
        } 
        
        # Cannot find conversion target
        else {
            print("ERROR!: Unknown conversion target: $fmt\n");
        }
        
    }
	
    # OK!
    return 0;
    
}

1;