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

package Module::CernVM::Builder;
use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use Data::UUID;
use POE;
use Tools::FileTransfer;

# Brad Fitchpatrickl

our $MANIFEST = {
	
	WORKFLOW => {
		"ibuilder:build" => {
			ActionHandler => "ibuilder_build",
			Description => "Starts a new build of a CernVM image. Expects storage information at 'storage_uri' and build information in 'flavor'.",
			Threaded => 1,
			MaxInstances => `cat /proc/cpuinfo | grep -c 'processor'`, # Max instances = Max number of CPUs
			RequiredParameters => [ 'storage_uri', 'build' ]
		}
	}
	
};

sub new {
    my $class = shift;
    my $config = shift;
    my $self = { 
            Workdir => $config->{BuildWorkDir}
        };
    return bless $self, $class;
}

sub __ibuilder_build {
	my ($self, $context, $logdir, $id) = @_[ OBJECT, ARG0, ARG1, ARG2 ];
	my $uuid = Data::UUID->new()->create_str;
	
	# Calculate a folder for the ISO
	my $image_name = "$uuid.raw";
	
	# Check if we have an output file specified on the request
	$image_name=$context->{build}->{output} if defined($context->{build}->{output});

	# Calculate the full path for the iso
	my $iso = $self->{Workdir}."/".$image_name;
	print("Starting build #$uuid @ $iso\n");
	
	# Prepare builder arguments
	my @build_args = ("/usr/bin/cernvm-builder", "build", "cernvm",
	    '-bid',                 $uuid,
	    '-logdir',              $logdir,
	    '-conary-options',      $context->{build}->{conary_options},
	    '-postinstall-options', $context->{build}->{postinstall_options},
	    '-install-label-path',  $context->{build}->{install_label_path},
	    '-output',              $iso
	    );
	
	# Check if we have to continue the previous image
	if (defined($context->{build}->{continue})) {

	    # Download previous image
    	my $ret = get_file(
    	    $context->{storage_uri},
    	    $context->{build}->{continue},
    	    $iso
    	    );
    	
    	# Put the continue directive in the builder
    	push @build_args, '-continue', 'yes';

	}
	
	# Invoke the image builder
	print("Starting build\n");
	my $ret = system(@build_args);
	print(" = $ret\n");
	
	# Return on error
	return $ret if ($ret != 0);
	
	# Send file to storage server
	my $ret = put_file(
	    $context->{storage_uri},
	    $iso,
	    $image_name
	    );
	
	# Return on error
	return $ret if ($ret != 0);
	
	# Update context
	$context->{build_id} = $uuid;
	$context->{build_files} = {
	    'raw' => $image_name
 	};
	
	# Remove iso
	unlink($iso);
	
	# Just return what happened
	return $ret;
	
}

1;