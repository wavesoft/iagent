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

=head1 NAME

iAgent::Module::XMPP::MUC - Multi-User Chat implementation for the XMPP Module

=head1 DESCRIPTION

This XMPP Plugin implpements the XEP-0045 (Multi-User Chat) standard and exposes it's functionality
through the C<comm_group_*> messages.

=head1 HANDLED MESSAGES

=head2 comm_group_join HASHREF

Join the specified MUC channel

=head2 comm_group_leave HASHREF

Leave the specified MUC channel

=head2 comm_group_send HASHREF

Send a message to the specified MUC Channel

=head2 comm_group_members HASHREF

List the members of the specified MUC Channel

=head1 BROADCASTED MESSAGES

=head2 comm_group_chat HASHREF

A mesage has arrived 

=head2 comm_group_joined HASHREF

A user has joined the channel

=head2 comm_group_leaved HASHREF

A user has left the channel

=cut

# Basic definitions
package iAgent::Module::XMPP::MUC;
use strict;
use warnings;

# For connection with iAgent
use iAgent;
use iAgent::Kernel;
use iAgent::Log;

# The actually usable stuff
use POE;
use Data::Dumper;
use Net::XMPP;
use Sys::Hostname;
use XML::Simple;

# Extend XMPP Cache
our $MANIFEST = {

    CLI => {

        "xmpp/muc/rooms" => {
            description => "List all the chatrooms I am currently member in",
            message => "cli_muc_list"
        },
        "xmpp/muc/join" => {
            description => "Join the specified chatroom",
            message => "cli_muc_join"
        },
        "xmpp/muc/leave" => {
            description => "Leave the specified chatroom",
            message => "cli_muc_leave"
        }
    
    }

};

##===========================================================================================================================##
##                                           HELPER FUNCTIONS FOR THE MUC MODULE                                             ##
##===========================================================================================================================##


##===========================================================================================================================##
##                                         MULTI-USER-CHAT IMPLEMENTATION                                                    ##
##===========================================================================================================================##

############################################
# Join a MUC Chatroom
sub __comm_group_join { # Handle 'comm_chat_join'
############################################
    my ($self, $packet, $replyTo) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};
    my $config = $self->{config};

    # Fetch my hostname
    my $host = hostname;
    $host=$config->{XMPPResource} if defined $config->{XMPPResource};

    # Check if we have password provides
    my $password_node = '/';
    if (defined ($packet->{password})) {
        $password_node = '><password>'.$packet->{password}.'</password></x';
    }

    # Register the chat group
    $self->{DATA_CHATROOMS}->{$packet->{group}.'@conference.'.$config->{XMPPServer}} = {
        group => $packet->{group},
        group_jid => $packet->{group}.'@conference.'.$config->{XMPPServer}.'/'.$config->{XMPPUser}.'-'.$host,
        config => $packet,
        error => '',
        replyTo => {
            join => $replyTo
        }
    };
    
    # Send the packet
    $self->send_presence({
        from => $self->{me},
        to => $packet->{group}.'@conference.'.$config->{XMPPServer}.'/'.$config->{XMPPUser}.'-'.$host,
        data => "<x xmlns='http://jabber.org/protocol/muc'$password_node>" # Add MUC XMLNS
    });
    
    return 1; # Ok, continue if needed
}

############################################
# Leave all the groups I am currently member
sub leave_all_groups {
############################################
    my ($self) = @_;
    my $XMPPCon = $self->{XMPPCon};
    my $config = $self->{config};

    # Fetch my hostname
    my $host = hostname;
    $host=$config->{XMPPResource} if defined $config->{XMPPResource};

    # Leave all groups
    for my $room (keys %{$self->{DATA_CHATROOMS}}) {
        my $grp = $self->{DATA_CHATROOMS}->{$room};
        $self->send_presence({
            from => $self->{me},
            to => $grp->{group_jid},
            type => 'unavailable'
        });
    }

    # Clear hash
    $self->{DATA_CHATROOMS} => { };
}

############################################
# Leave a MUC Chatroom
sub __comm_group_leave { # Handle 'comm_chat_leave'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};
    my $config = $self->{config};

    # Fetch my hostname
    my $host = hostname;
    $host=$config->{XMPPResource} if defined $config->{XMPPResource};

    # Register possible replyTo
    delete $self->{DATA_CHATROOMS}->{$packet->{group}.'@conference.'.$config->{XMPPServer}};

    # Send the packet
    $self->send_presence({
        from => $self->{me},
        to => $packet->{group}.'@conference.'.$config->{XMPPServer}.'/'.$config->{XMPPUser}.'-'.$host,
        type => 'unavailable'
    });
    
    return 1; # Ok, continue if needed
}

############################################
# Send a packet in the group
sub __comm_group_send { # Handle 'comm_group_send'
############################################
    my ($self, $packet, $replyTo) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};
    my $config = $self->{config};

    # Fetch my hostname
    my $host = hostname;
    $host=$config->{XMPPResource} if defined $config->{XMPPResource};

    # Update TO
    $packet->{to} = $packet->{group}.'@conference.'.$config->{XMPPServer}.'/'.$config->{XMPPUser}.'-'.$host;

    # Send the packet
    $self->send_packet($packet, $replyTo);
    
    return 1; # Ok, continue if needed
}

############################################
# Get the members of a group
sub __comm_group_members { # Handle 'comm_group_members'
############################################
    my ($self, $packet, $replyTo) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};
    my $config = $self->{config};

    # Fetch my hostname
    my $host = hostname;
    $host=$config->{XMPPResource} if defined $config->{XMPPResource};

    # Update TO
    $packet->{to} = $packet->{group}.'@conference.'.$config->{XMPPServer}.'/'.$config->{XMPPUser}.'-'.$host;

    # Send the packet
    $self->send_packet($packet, $replyTo);
    
    return 1; # Ok, continue if needed
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
