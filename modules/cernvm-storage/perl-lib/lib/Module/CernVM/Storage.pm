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

Module::CernVM::Storage - Storage agent for CernVM

=head1 DESCRIPTION

This module is the entry point to the Storage Agent. It provides various different
storage mechanisms.

=cut

# Core definitions
package Module::CernVM::Storage;
use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use Data::UUID;
use Sys::Hostname;
use POE;

# Storage providers
use Module::CernVM::Storage::Chirp;

# Manifest definition
our $MANIFEST = {

	WORKFLOW => {
		"storage:allocate" => {
			ActionHandler => "storage_alloc",
			CleanupHandler => "storage_dealloc",
			Threaded => 0
		}
	},
	
	XMPP => {
	    'iagent:storage' => {
	        'set' => {
	            'purge' => {
	                message => "xmpp_purge"
	            }
	        },
	        'get' => {
	            'statusall' => {
	                message => "xmpp_statusall"
	            }
	        }
  	    }
	}
	
};

############################################
# Create new instance
sub new {
############################################
    my $class = shift;
    my $config = shift;
    
    $config->{StorageUser}="user" unless defined($config->{StorageUser});
    $config->{StorageHostname}=hostname unless defined($config->{StorageHostname});
    $config->{StorageFolder}="/tmp" unless defined($config->{StorageFolder});

    # Initialize self
    my $self = { 
            
            # Initialize all the storage providers
            Providers => [
                new Module::CernVM::Storage::Chirp({
                    User => $config->{StorageUser},
                    Hostname => $config->{StorageHostname},
                    Root => $config->{StorageFolder},
                    Config => $config->{CHIRP}
                })
            ],
            
            Allocations => { }      # A mapping between the UUID of the action and the UUID of the allocation
            
        };
    
    # Create instance
    return bless $self, $class;

}

############################################
# Start all the servers when we are ready
sub __ready {
############################################
    my $self = $_[OBJECT];
    foreach my $prov (@{$self->{Providers}}) {
        # Start provider
        log_msg("Starting storage provider: ".$prov->NAME);
        if (!$prov->start()) {
            log_error("Unable to start storage provider ".$prov->NAME);
        }
    }
}

############################################
# Stop all the servers upon exit
sub __exit {
############################################
    my $self = $_[OBJECT];
    foreach my $prov (@{$self->{Providers}}) {
        # Start provider
        log_msg("Stopping storage provider: ".$prov->NAME);
        if (!$prov->stop()) {
            log_error("Unable to stop storage provider ".$prov->NAME);
        }
    }
}


##===========================================================================================================================##
##                                                    HELPER FUNCTIONS                                                       ##
##===========================================================================================================================##


##===========================================================================================================================##
##                                                XMPP UI MESSAGE HANDLERS                                                   ##
##===========================================================================================================================##


############################################
# Purge all the providers or the specified
sub __xmpp_purge {
############################################
    my ($self, $packet) = @_[OBJECT, ARG0];
    my $name = $packet->{parameters}->{name};
    
    # Purge all the providers
    foreach my $prov (@{$self->{Providers}}) {
        if (!defined($name) || ($prov->NAME eq $name)) {
            $prov->purge();
        }
    }
    
    # Return OK
    return RET_OK;
}

############################################
# Return the status of all of the providers
sub __xmpp_statusall {
############################################
    my ($self, $packet) = @_[OBJECT, ARG0];
    my @providers;
    
    # Build response
    foreach my $prov (@{$self->{Providers}}) {
        my $leases = $prov->get_leases;
        push @providers, {
            name => $prov->NAME,
            description => $prov->DESCRIPTION,
            preferred => $prov->is_available,
            
            free => $prov->get_free_mb,
            used => $prov->get_used_mb,
            allocated => scalar(@$leases)
        }
    }
    
    # Reply
    Dispatch("comm_reply", {
        data => {
            providers => \@providers
        }
    });
    
    # Return OK
    return RET_OK;
    
}

##===========================================================================================================================##
##                                               WORKFLOW ACTION HANDLERS                                                    ##
##===========================================================================================================================##

# Dellocate a storage lease
sub __storage_dealloc {
	my ($self, $context, $logdir, $uid) = @_[ OBJECT, ARG0, ARG1, ARG2 ];
    
    # Undefine the allocation for the specified action Id
	print("Deallocating lease for action $uid\n");
    if (defined($self->{Allocations}->{$uid})) {
        my $def = $self->{Allocations}->{$uid};
        
        # Release that ID from the provider
        $def->{provider}->free($def->{id});
        
        # Delete information
        delete $self->{Allocations}->{$uid};
    }
    
}

# Allocate a storage lease
sub __storage_alloc {
	my ($self, $context, $logdir, $uid) = @_[ OBJECT, ARG0, ARG1, ARG2 ];

    # Fetch the requirements
    my $requirements = $context->{storage_requires};
    $requirements={} unless defined($requirements);
    	
	# Allocate a slot
	print("Allocating a slot to the first available provider for action $uid\n");
    foreach my $prov (@{$self->{Providers}}) {
        if ($prov->is_available) {

            print("Allocating slot with provider ".$prov->NAME."\n");
            
            # Allocate a slot on the specified provider
            my ($storage_id, $uri) = $prov->allocate($requirements);
            if (defined($storage_id)) {

                print("Slot allocated. Slot ID=".$storage_id."\n");

                # Store the allocation ID
                $self->{Allocations}->{$uid} = {
                    id => $storage_id,
                    provider => $prov
                };
                
                # Store the URI and the parameters to the context
                $context->{storage_uri} = $uri;
                
                # Completed successfuly!
                return 0;
                
            } else {
                print("Unable to allocate a slot using provider ".$prov->NAME."\n");
            }
            
        }
    }
	
    # No provider was found!
    return 1;
    
}

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
