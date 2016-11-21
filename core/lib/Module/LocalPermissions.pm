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

# Core definitions
package Module::LocalPermissions;

use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use POE;
use Data::Dumper;
use HTML::Entities; 

our $MANIFEST = {
    oncrash => 'die',
    priority => 1
};

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { 

        PERMISSIONS => {
        }
        
    };

    return bless $self, $class;
}

###############################################################
# Convert the specified permissions hash to an archipel-
# compatible representation and return it.
sub permissions_xml {
###############################################################
    my ($self, $can) = @_;
    # Build and reply permissions
    my $buf = '';
    for my $perm (keys %{$can}) {
        $buf .= '<permission name="'.encode_entities($perm).'" />'
            if ($can->{$perm});
    }
    return $buf;
}

# Intercept comm_action and add permissions
sub __comm_action {
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $SOURCE = $packet->{from};
    my %perm;
    %perm = %{$packet->{permissions}} if (defined $packet->{permissions});

    # Intercept archipel:permissions messages
    # and reply the permissions of the user
    if ($packet->{context} eq 'archipel:permissions') {
    	
       	# We might need the source's bare JID
       	my @bare_jid_parts = split "/", $SOURCE;
       	my $bare_jid = $bare_jid_parts[0];
        
        # Handle the get/getown
        if (($packet->{action} eq 'getown') and ($packet->{type} eq 'get')) {
            
			my $permissions = {
				permission_getown => 1,
				permission_list => 1,
				read => 1
			};
			iAgent::Kernel::Reply('comm_reply', { data => $self->permissions_xml($permissions) });
			
            # Block message
            return RET_ABORT;
            
        }
        
        # Handle the get/get
        elsif (($packet->{action} eq 'get') and ($packet->{type} eq 'get')) {
        	

           	# Block message
            return RET_ABORT;
            	
        }
        	
        # Handle the get/get
        elsif (($packet->{action} eq 'list') and ($packet->{type} eq 'get')) {

           	# Block message
            return RET_ABORT;
            	
        }

    }

    # Add some default stuff
    $perm{read} = 1;
    $perm{any} = 1;

	# Append permissions hash
    $packet->{permissions} = \%perm;

    # Passthru
    return RET_PASSTHRU;

}

sub __permissions_get {
    my ($self, $who, $perm) = @_[ OBJECT, ARG0..ARG1 ];
    $perm->{any} = 1;
    $perm->{read} = 1;
    $perm->{cli} = 1;
}

1;
