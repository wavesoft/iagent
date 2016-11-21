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

Module::XMPPCLI - Simple XMPP Bridge to Command-Line interface

=head1 DESCRIPTION

This module provides xmpp access to the locally provided command line. This module requires
the iAgent::Module::CLI to be loaded in order to work properly.

=head1 KNOWN ISSUES

Since the CLI system does not support concurrent users, every time a ueser types something on CLI
he will get the output redirected to him.

=cut

# Core definitions
package Module::XMPPCLI;

use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use POE;

our $MANIFEST = {
    priority => 4
};

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { 
        me => '',
        target => undef,
        dispatches => [ ],
        sendbuffer => { }
    };
    $self = bless $self, $class;
    
    return $self;
}

############################################
# Push text on the send buffers
sub send_chat {
############################################
    my ($self, $to, $chat) = @_;
    $self->{sendbuffer}->{$to}="" if (!defined($self->{sendbuffer}->{$to}));
    $self->{sendbuffer}->{$to}.="$chat\n";
    
    # (re-)schedule buffer transmittion in a second
    POE::Kernel->delay('_send_buffers' => 1);

}

############################################
# Send buffers scheduler
sub ___send_buffers {
############################################
    my $self = $_[OBJECT];

    # Process send buffers
    foreach (keys %{$self->{sendbuffer}}) {
        Dispatch("comm_send", {
            context => 'chat:text',
            type => 'chat',
            data => $self->{sendbuffer}->{$_},
            to => $_
        });
    }
    
    # Reset send buffer
    $self->{sendbuffer} = { };

}

############################################
# Run the specified command
sub ___run_command {
############################################
    my ($self, $hash) = @_[OBJECT, ARG0];
    
    # Invoke command
    my $ans = Dispatch("cli_command", $hash);
    
    # Handle error responses
    if ($ans == RET_UNHANDLED) { # No plugin received this or no plugin responded (-1 or -2)
        $self->send_chat($self->{target},"ERROR: The command was not found");

        # Command is NOT active. Do not send more output
        $self->{target}=undef;

    } elsif ($ans == RET_ABORTED) { # Aborted by some plugin
        $self->send_chat($self->{target},"ERROR: The specified action refused to run");

        # Command is NOT active. Do not send more output
        $self->{target}=undef;

    } elsif ($ans == RET_COMPLETED) { # Completed in the same call

        # Command is NOT active. Do not send more output
        $self->{target}=undef;

    } elsif ($ans == RET_ERROR) { # An error occured in the same call
        $self->send_chat($self->{target},"ERROR: The specified action returned with error");
        
        # Command is NOT active. Do not send more output
        $self->{target}=undef;
        
    }

}

############################################
# Hande chat messages
sub __comm_action {
############################################
    my ($self, $packet) = @_[OBJECT, ARG0];
    if ($packet->{type} eq 'chat') {
        
        # If we had that target, stop stdout
        if (($packet->{action} eq 'stop') || ($packet->{action} eq 'exit')) {
            $self->{target}=undef if ($packet->{from} eq $self->{target});
            $self->send_chat($packet->{from}, 'Disconnected from CLI. Type another command to connect again');
            
        } else {
            
            # Switch stdout there
            $self->{target} = $packet->{from};
            
            # Split cmdline
            my ($action, $cmdline) = split(" ",$packet->{data},2);
            
            # Broadcast message in a next cycle
            POE::Kernel->yield('_run_command', {
                command => $action,
                cmdline => $cmdline,
                options => $packet->{parameters},
                unparsed => { },
                interactive => 1,
                raw => $packet->{data}
            });
            
        }
        
        # Handle chat messages
        return RET_OK;
        
    }
    
    # Passthru the rest
    return RET_PASSTHRU;
}

############################################
# Intercept cli_write messages
sub __cli_completed {
############################################
    my ($self, $text) = @_[OBJECT, ARG0];
    
    # Remove target - do not receive more output
    $self->{target} = undef;

    # Continue...
    return RET_OK;
}

############################################
# Intercept cli_write messages
sub __cli_write {
############################################
    my ($self, $text) = @_[OBJECT, ARG0];
    
    if (defined($self->{target})) {
        $self->send_chat($self->{target},$text);
    }
    
    # Continue...
    return RET_OK;
}

############################################
# Intercept cli_error messages
sub __cli_error {
############################################
    my ($self, $text) = @_[OBJECT, ARG0];
    
    if (defined($self->{target})) {
        $self->send_chat($self->{target},$text);
    }

    # Continue...
    return RET_OK;
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
