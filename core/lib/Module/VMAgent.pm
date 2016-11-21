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

package Module::VMAgent;
use warnings;

# Basic inclusions
use iAgent::Log;
use POE;

# Define manifest
our $MANIFEST = {
    XMPP => {
        "iagent:vmagent:admin" => {
            permissions => [ 'vm_admin', 'vm_owner' ],
            "set" => {

                "schedule" => {
                    parameters => [ 'action', 'parameters' ],
                    message => "admin_command_schedule"
                },
                
                "apply" => "admin_command_apply",
                "abort" => "admin_command_abort"
                
            },

            "get" => {

                "all" => "admin_command_getall",
                "details" => {
                    parameters => [ 'action' ],
                    message => "admin_command_details"
                }
                
            }
        },

        "chat:text" => {
            "chat" => {
            
                "schedule" => {
                    parameters => [ {1=>'action'}, {2=>'parameters'} ],
                    message => "admin_command_schedule"
                },
                
                "apply" => "admin_command_apply",
                "abort" => "admin_command_abort",
                "getall" => "admin_command_getall",
                "getdetails" => {
                    parameters => [ 'action' ],
                    message => "admin_command_details"
                }
                
            }
        }
    }
};

sub new {
    my ($class, $config) = @_;
    
    # Prepare my instance 
    my $self = {
        config => $config,

        TRANSACTIONS => { }
    };
    $self = bless $self, $class;
    
    # Ensure database state
    log_debug("Initializing Virtual Machine Agent");
    
    # Return instance
    return $self;

}

sub __admin_command_schedule {
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];

    # Build transactions for this user, if missing
    $self->{TRANSACTIONS}->{$packet->{from}} = [ ] unless
        defined $self->{TRANSACTIONS}->{$packet->{from}};

    # Put transaction in queue
    push @{$self->{TRANSACTIONS}->{$packet->{from}}}, $packet->{parameters};
    iAgent::Kernel::Reply("comm_reply", { }); # OK!

    # Continue
    return 1;
}

sub __admin_command_apply {
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];

    if (!defined $self->{TRANSACTIONS}->{$packet->{from}}) {
        iAgent::Kernel::Reply("comm_reply_error", { message => "You have no actions to apply!" });
        return 0;
    };

    # Process actions
    for my $a (@{$self->{TRANSACTIONS}->{$packet->{from}}}) {
        my $res;

        # $res = <call the action>
        my $cmd = $a->{action}." ".$a->{parameters};
        $res = `$cmd 2>&1`;

        # Reply progress
        iAgent::Kernel::Dispatch('comm_send', {
            type => "chat",
            context => "chat:text",
            to => $packet->{from},
            data => $res
        });
    };

    # Reply what happened
    iAgent::Kernel::Dispatch("comm_reply_to", $packet, {
        data => "successful"
    });
    
    return 1;
}

sub __admin_command_abort {
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];

    # Delete transaction
    delete $self->{TRANSACTIONS}->{$packet->{from}};
    iAgent::Kernel::Reply("comm_reply", { }); # OK!

    return 1;
}

sub __admin_command_getall {
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];
    return 1;
}

sub __admin_command_details {
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];
    return 1;
}

1;

