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
package iAgent::Module::EncryptionOut;

=head1 NAME

iAgent::Module::EncryptionOut  - Provide encryption support

=head1 DESCRIPTION

This module provides output filtering for the communication module(s).

=cut

use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use iAgent::Crypt;
use MIME::Base64;
use Data::Dumper;
use iAgent::Module::EncryptionIn;
use JSON;
use POE;

sub CONTEXT_ENCRYPTED       { "iagent:encryption" }; # The XMLNS for the encrypted messages

# Define the module's manifest
our $MANIFEST = {
    
    # Use autodetection for the events, 
    # using the '__' for event prefix
    hooks => 'AUTO',
    
    # Go right before XMPP
    priority => -1,
    
    # If we are dead, kill iAgent
    oncrash => 'die'
    
};

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    
    # Prepare hash
    my $self = {
    };

    return bless $self, $class;
}


#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
# Catch the comm_reply message dispatched
# in the global plugin stack.
sub __comm_reply {
#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Replace variables and return the appropriate return value
    return iAgent::Module::EncryptionIn::encrypt_packet($packet);
}

#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
# Catch the comm_send message dispatched
# in the global plugin stack.
sub __comm_send {
#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

    # Replace variables and return the appropriate return value
    return iAgent::Module::EncryptionIn::encrypt_packet($packet);
}

#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
# Catch the comm_send_action message dispatched
# in the global plugin stack.
sub __comm_send_action {
#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

    # Replace variables and return the appropriate return value
    return iAgent::Module::EncryptionIn::encrypt_packet($packet);
}
