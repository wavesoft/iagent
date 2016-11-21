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
package iAgent::Module::EncryptionIn;

=head1 NAME

iAgent::Module::EncryptionIn  - Provide decryption support

=head1 DESCRIPTION

This module provides input filtering for the communication module(s).

=cut

use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use iAgent::Crypt;
use MIME::Base64;
use Data::Dumper;
use JSON;
use POE;

sub CONTEXT_ENCRYPTED       { "iagent:encryption" }; # The XMLNS for the encrypted messages

# Define the module's manifest
our $MANIFEST = {
    
    # Use autodetection for the events, 
    # using the '__' for event prefix
    hooks => 'AUTO',
    
    # Go right after XMPP
    priority => 1,
    
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

############################################
# Encrypt the provided packet (Repaces values)
sub encrypt_packet {
############################################
    my $packet = shift;
    
    # Get the user-part of the user ID
    my $user = $packet->{to};
    
    # Check if we should encrypt or not
    log_debug("Checking for encryption to user $user");
    if (($packet->{context} ne CONTEXT_ENCRYPTED)  && ($packet->{type} ne 'error') && CanEncryptFor($user)) {
        
        # Build payload
        my $payload = encode_json({
            context => $packet->{context},
            parameters => $packet->{parameters},
            data => $packet->{data},
            action => $packet->{action}
        });
        
        # Encrypt
        log_debug("Encrypting payload $payload for user $user");
        $payload = EncryptFor($user, $payload);
        if (!$payload) {
            log_error("Unable to encrypt payload for $user!");
            return RET_ABORT;
        }
        
        $payload = encode_base64($payload, '');
        if (!$payload) {
            log_error("Unable to encode payload for $user!");
            return RET_ABORT;
        }
        log_debug("Encrypted payload to $user: $payload");
        log_msg("Sent encrypted message to $user");
        
        # Replace the protected fields
        $packet->{context} = CONTEXT_ENCRYPTED;
        $packet->{action} = 'do';
        $packet->{parameters} = { };
        $packet->{data} = $payload;
        
    }
    
    # Passthru
    return RET_PASSTHRU;
}

#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
# Catch the comm_action message dispatched
# my the communication module.
sub __comm_action {
#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $user = $packet->{from};
    
    # Reject messages from untrusted sources
    if (!IsTrusted($user)) {
        log_warn("Packet from untrusted source: ".$packet->{from});
        return RET_ABORT;
    }
    
    # Add user's permissions
    $packet->{permissions}=PermissionsOf($user);
    
    # Check for encrypted context
    if (($packet->{context} eq CONTEXT_ENCRYPTED) && ($packet->{action} eq 'do')) {
        log_debug("Decrypting payload $packet->{data} from $user");
        
        # Process payload
        my $payload = decode_base64($packet->{data});
        if (!$payload) {
            log_warn("Unable to decode encrypted payload from $user!");
            return RET_ABORT;
        }
        my $struct = DecryptFrom($user, $payload);
        if (!$struct) {
            log_warn("Unable to decrypt encrypted payload from $user!");
            return RET_ABORT;
        }
        eval {
        $struct = decode_json($struct);
            if (!$struct) {
                log_warn("Unable to parse decrypted payload from $user!");
                return RET_ABORT;
            }
        };
        if ($@) {
            log_warn("Invalid passphrase in encryped channel with $user!");
            return RET_ABORT;
        }
        
        # Expand the protected fields
        $packet->{context} = $struct->{context};
        $packet->{data} = $struct->{data};
        $packet->{action} = $struct->{action};
        $packet->{parameters} = $struct->{parameters};
        
        # Add permissions (pluss 'secured')
        $packet->{permissions}->{secured} = 1;
        
        log_debug("Decrypted action $struct->{context}/$struct->{action}");
        log_msg("Got encrypted message from $user. Permissions: ".Dumper($packet->{permissions}));
        
    }
    
    # Passthru
    return RET_PASSTHRU;
    
}

#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
# Catch the comm_reply message replied
# towards the communication module.
sub __comm_reply {
#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Replace variables and return the appropriate return value
    return encrypt_packet($packet);
}

#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
# Return the user's permissions.
sub __permissions_get {
#-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
    my ($self, $who, $perm) = @_[ OBJECT, ARG0..ARG1 ];
    my $permissions = PermissionsOf($who);
    for (keys %$permissions) { $perm->{$_} = 1 };
    return RET_OK;
}
