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

iAgent::Module::XMPP::Roster - Publish/Subscribe extensions on the XMPP object

=head1 DESCRIPTION

TODO

=head1 PROVIDED EVENTS

TODO

=cut

# Basic definitions
package iAgent::Module::XMPP::Roster;
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
        "xmpp/invite" => {
            description => "Invite a user and add him on my roster",
            message => "cli_invite",
        },
        "xmpp/users" => {
            description => "Show the users of my roster",
            message => "cli_users"
        },
        "xmpp/remove" => {
            description => "Remove a user from my roster",
            message => "cli_remove",
        },
        "xmpp/reload_roster" => {
            description => "Reload roster",
            message => "cli_reload"
        }
    }

};


##===========================================================================================================================##
##                                              INITIALIZE SUBMODULE                                                         ##
##===========================================================================================================================##

#######################################
# Called when XMPP module is initializing
sub init {
#######################################
    my ($self, $XMPPCon) = @_;

    # Prepare roster
    $self->{ROSTER} = undef;

    # Prepare users store
    $self->{USERS} = { };
    
}

#######################################
# Called when XMPP module is connected
sub connected {
#######################################
    my ($self, $XMPPCon) = @_;
	
	# Update roster
	log_debug("Initializing Roster");
	$self->update_roster();
    
}

##===========================================================================================================================##
##                                                  ROSTER FUNCTIONS                                                         ##
##===========================================================================================================================##

#######################################
# A user state is changed. Usually called
# by the presence functions in order to
# Update the list
# TODO: Deprecate in favor of roster object
sub user_state_changed {
#######################################
    my ($self, $user, $status) = @_;
    my $jid = new Net::XMPP::JID($user);
    my $base = $jid->GetJID("base");
    my %base_hash;

    # Ensure existence of entry
    if (!defined $self->{USERS}->{$user}) {

        # Fetch base
        if (defined $self->{USERS}->{$base}) {
            %base_hash = %{$self->{USERS}->{$base}};
        } else {
            %base_hash = (
                jid => $jid,
                status => 'offline',
                group => '',
                vcard => undef,
                base => 1
            );
        }

        # Extend base
        $base_hash{'jid'} = $jid;
        $base_hash{'base'} = 0;

        # Update hash
        $self->{USERS}->{$user} = \%base_hash;
        log_debug("User entry $user created using template: $base");

    }

    # Update status
    $self->{USERS}->{$user}->{status} = $status;
    log_debug("User $user status updated to '$status'");

}

#######################################
# Send a request, wait for reply and
# populate roster information
sub update_roster {
#######################################
    my ($self) = @_;
    my $XMPPCon = $self->{XMPPCon};

    $self->{ROSTER} = $XMPPCon->Roster();
    $self->{USERS} = { };
    $XMPPCon->RosterRequest();

    # Scan groups
    my @groups = $self->{ROSTER}->groups();
    foreach my $grp (@groups) {
        my @users = $self->{ROSTER}->jids('group', $grp);
        foreach (@users) {
            my $jid = $_->GetJID("full");
            $self->{USERS}->{$jid} = {
                jid => new Net::XMPP::JID($jid),
                status => 'offline',
                group => $grp,
                vcard => undef,
                base => 1
            };
            $self->update_user_vcard($jid);
        }
    }

    # Scan users without group
    my @users = $self->{ROSTER}->jids('nogroup');
    foreach (@users) {
        my $jid = $_->GetJID("full");
        $self->{USERS}->{$jid} = {
            jid => new Net::XMPP::JID($jid),
            status => 'offline',
            group => '',
            vcard => undef,
            base => 1
        };
        $self->update_user_vcard($jid);
    }

}

##===========================================================================================================================##
##                                                 MODULE ENTRY POINTS                                                       ##
##===========================================================================================================================##

############################################
sub CALLBACK_PRESENCE_SUBSCRIBED {
############################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

    # Update roster information 
    my $jid = $packet->GetFrom();
    $XMPPCon->RosterAdd( jid => $jid );
    log_msg("User $jid subscribed");
    
}

############################################
sub CALLBACK_PRESENCE_UNSUBSCRIBED {
############################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

    # Update roster information 
    my $jid = $packet->GetFrom();
    $XMPPCon->RosterRemove( jid => $jid );
    log_msg("User $jid unsubscribed");
    
}

############################################
# Add a user to my user
sub __comm_add_user { # Handle 'comm_add_user'
############################################
    my ($self, $user, $kernel) = @_[ OBJECT, ARG0, KERNEL ];
    my $XMPPCon = $self->{XMPPCon};

    # Subscription is not working with resources
    # strip it...
    $user =~ s/([^\/]+)\/.*/$1/;

    # Prepare subscription
    $XMPPCon->Subscription(type => "subscribe", to => $user );
    
    # Subscribed
    return RET_OK;
}

############################################
# Get the users in my roster
sub __comm_remove_user { # Handle 'comm_remove_user'
############################################
    my ($self, $user, $kernel) = @_[ OBJECT, ARG0, KERNEL ];
    my $XMPPCon = $self->{XMPPCon};

    # Unsubscription is not working with resources
    # strip it...
    $user =~ s/([^\/]+)\/.*/$1/;

    # Fetch user
    if (!$self->{ROSTER}->exists($user)) {
        return RET_NOTFOUND;
    }

    # Remove roster user from the roster too
    $XMPPCon->Subscription(type => "unsubscribe", to => $user );
    $XMPPCon->RosterRemove( jid => $user );
    $self->{ROSTER}->remove($user);

    # Subscribed
    return RET_OK;
}

############################################
# Get the users in my roster
sub __comm_list_users { # Handle 'comm_list_users'
############################################
    my ($self, $users) = @_[ OBJECT, ARG0 ];

    # If we have no array argument, make one
    $users = [ ] if (!UNIVERSAL::isa($users, 'ARRAY'));

    # Push the users into the reference
    foreach my $user (values %{$self->{USERS}}) {
        push @{$users}, $user;
    }

    # Success
    return RET_OK;
    
}

##===========================================================================================================================##
##                                                  CLI CONNECTIONS                                                         ##
##===========================================================================================================================##

############################################
# Reload the roster
sub __cli_reload { # Handle 'xmpp/invite' command
############################################
    my ($self, $command) = @_[ OBJECT, ARG0 ];
    $self->{ROSTER}->fetch();
    iAgent::Kernel::Reply("cli_write", "Roster reloaded");
    
    # Completed in a single call
    #
    # That's a shortcut for:
    #
    #   iAgent::Kernel::Reply("cli_completed", 0);
    #   return RET_OK;
    #
    return RET_COMPLETED;

}


############################################
# List users
sub __cli_users { # Handle 'xmpp/users' command
############################################
    my ($self, $command) = @_[ OBJECT, ARG0 ];
    
    iAgent::Kernel::Reply("cli_write", "List of known users:");
    iAgent::Kernel::Reply("cli_write", "");

    foreach ($self->{ROSTER}->jids()) { 
        my $line = " * ".$_->GetJID("full");
        $line.=' [online]' if ($self->{ROSTER}->online($_));
        iAgent::Kernel::Reply("cli_write", $line);

        if ($self->{ROSTER}->online($_)) {
            foreach ($self->{ROSTER}->resource($_)) {
                iAgent::Kernel::Reply("cli_write", "     online as: /$_");
            }
        }
    }
    
    iAgent::Kernel::Reply("cli_write", "");
    
    # Completed in a single call
    #
    # That's a shortcut for:
    #
    #   iAgent::Kernel::Reply("cli_completed", 0);
    #   return RET_OK;
    #
    return RET_COMPLETED;

}

############################################
# Invite a user in my roster
sub __cli_invite { # Handle 'xmpp/invite' command
############################################
    my ($self, $command, $kernel) = @_[ OBJECT, ARG0, KERNEL ];
    my $XMPPCon = $self->{XMPPCon};
    my $user = $command->{cmdline};
    
    # Unsubscription is not working with resources
    # strip it...
    $user =~ s/([^\/]+)\/.*/$1/;
    
    # Prepare subscription
    $XMPPCon->Subscription(type => "subscribe", to => $user );

    iAgent::Kernel::Reply("cli_write", "Subscription request sent to $user");

    # Completed in a single call
    #
    # That's a shortcut for:
    #
    #   iAgent::Kernel::Reply("cli_completed", 0);
    #   return RET_OK;
    #
    return RET_COMPLETED;

}

############################################
# Invite a user in my roster
sub __cli_remove { # Handle 'xmpp/invite' command
############################################
    my ($self, $command, $kernel) = @_[ OBJECT, ARG0, KERNEL ];
    my $XMPPCon = $self->{XMPPCon};
    my $user = $command->{cmdline};
    
    # Unsubscription is not working with resources
    # strip it...
    $user =~ s/([^\/]+)\/.*/$1/;

    # Fetch user
    if (!$self->{ROSTER}->exists($user)) {
        iAgent::Kernel::Reply("cli_write", "User $user was not found in the local database");
        return;
    }

    # Remove roster user from the roster too
    $XMPPCon->Subscription(type => "unsubscribe", to => $user );
    $XMPPCon->RosterRemove( jid => $user );
    $self->{ROSTER}->remove($user);

    iAgent::Kernel::Reply("cli_write", "Subscription to $user removed");

    # Completed in a single call
    #
    # That's a shortcut for:
    #
    #   iAgent::Kernel::Reply("cli_completed", 0);
    #   return RET_OK;
    #
    return RET_COMPLETED;

}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut
1;
