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

package iAgent::Module::Discovery::Listener;
use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use POE;

sub DISCOVERY_NODE               { "/iagent/cloud"; }           # The base name of the pub/sub node that will be used as the public message bus
sub DISCOVERY_CONTEXT            { "iagent:cloud:discovery"; }  # The context of the XMPP messages

############################################
# Create new instance
sub new {
############################################
    my $class = shift;
    my $config = shift;
    
    my $self = { 
        ME => '',
        ACTIONS => { }
    };
    return bless $self, $class;
}

############################################
# Register discovery listener actions
sub __ready {
############################################
    my ($self, $kernel) = @_[ OBJECT, KERNEL ];
    
    # Initialize actions
    $self->{ACTIONS} = { };

    # Eveything is ready. Fetch the exposed actions of every module
	foreach my $mod (@{iAgent::Kernel::SESSIONS}) {
		my $MF = $mod->{manifest};
		my $SESSION = $mod->{session};
		
		# Get the exposed actions
		if (defined $MF->{DISCOVERY}) {
		    
		    # Process discovery events
		    for my $k (keys %{$MF->{DISCOVERY}}) {
		        my $def = $MF->{DISCOVERY}->{$k};
		        
		        # Validate
		        if (ref($def) ne '') {
		            log_warn("Expecting string on discovery action $k in module ".$mod->{CLASS});
		            next;
		        }
		        
		        # Store info
		       $self->{ACTIONS}->{$k} = {
		            session => $SESSION,
		            validate => $def
		        };
		        
		    }
		    
		}
	}
	
}

############################################
# Communication plugin is ready: 
# Check/Establish subscriptions
sub __comm_ready {
############################################
    my ($self, $me) = @_[ OBJECT, ARG0 ];
    $self->{ME} = $me;
    $self->{SUBSCRIBED} = 0;
    
    # Get subscriptions
    my $subs = { };
    if (!iAgent::Kernel::Dispatch("comm_pubsub_subscriptions", $subs)) {
        log_warning("Unable to fetch PubSub subscriptions!");
        return RET_OK;
    }
    
    # Try to join the public discovery channel
    my $node = DISCOVERY_NODE;
    if (!defined $subs->{subscriptions}->{$node}) {

        # Prepare workflow creation node
        my $msg_create = {
            node => $node,
            options => { # MUC-Like Pub/Sub node
                'pubsub#persist_items' => 0,
                'pubsub#type' => 'iagent:pubsub:entry',
                'pubsub#notification_type' => 'headline',
                'pubsub#deliver_notifications' => 1,
                'pubsub#access_model' => 'open',
                'pubsub#publish_model' => 'open',
                'pubsub#deliver_payloads' => 1,
                'pubsub#presence_based_delivery' => 1,
                'pubsub#purge_offline' => 1,
                'pubsub#tempsub' => 1,
                'pubsub#send_last_published_item' => 'never',
                'pubsub#max_items' => 0,
                'pubsub#title' => 'iAgent Workflow Discovery Channel',
                'pubsub#item_expire' => 30
            }
        };

        # Create Pub/Sub node
        if (iAgent::Kernel::Dispatch("comm_pubsub_create", $msg_create) != 1) {
            if (!$msg_create->{error}) {
                log_error("Unable to invoke PubSub creation of node $node!");
                return RET_OK;
            } else {
                if ($msg_create->{error} ne '409') { # "Already exists" is not an error
                    log_error("Unable to create PubSub node $node! Error code: $msg_create->{error}");
                    return RET_OK;
                }
            }
        }

        # Try to subscribe
        if (!iAgent::Kernel::Dispatch("comm_pubsub_subscribe", { node => $node })) {
            log_error("Unable to subscribe to PubSub node $node!");
            return RET_OK;
        }

        # We are ready!
        $self->{SUBSCRIBED} = 1;

    }
    
    # Ok! Continue with the next handlers...
    return RET_OK;
}

############################################
# Process a public discovery requests
sub __comm_pubsub_event {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $permissions = { };
    return RET_PASSTHRU if ($packet->{from} eq $self->{ME});
    
    # Listen only on discovery node
    if (($packet->{node} eq DISCOVERY_NODE) && ($packet->{action} eq 'lookup') && ($packet->{context} eq DISCOVERY_CONTEXT)) {
        
        # Require some parameters in the data space
        my $data = $packet->{data}->{data} or return RET_ERROR;
        my $action = $packet->{data}->{action} or return RET_ERROR;
        my $discovery_id = $packet->{data}->{id} or return RET_ERROR;
        log_msg("[$packet->{from}] Public lookup request for action '$action' with ID $discovery_id");

        # Check for valid action
        my $info = $self->{ACTIONS}->{$action};
        if (!defined $info) {
            log_warn("Action $action was not found!");
            return RET_ERROR;
        }

        # Fetch permissions
        if (Dispatch("permissions_get", $packet->{from}, $permissions) != RET_OK) { # Fetch permissions of the user
            log_warn("Unable to fetch permissions of user $packet->{from}!");
            return RET_ERROR;
        }
        
        # Prepare response
        my $response = { };
        my $response_type = 'ok';

	    # Run validator
	    my $ans = $poe_kernel->call($info->{session}, $info->{validate}, $data, $permissions, $response);
	    if ($ans == RET_BUSY) {
	        log_debug("Action $action validator said we are busy!");
	        $response_type = 'busy';
	        
	    } elsif ($ans != RET_OK) {
			log_warn("Action $action discovery error: Validator rejected the request!");
			return RET_INVALID;
		}
    	
    	# We can send response
        Dispatch("comm_send", {
            to => $packet->{from},
            type => 'set',
            context => DISCOVERY_CONTEXT,
            action => 'response',
            parameters => {
                type => $response_type,
                id => $discovery_id
            },
            data => $response
        });

    } else {
        
        # Otherwise, nothing happened
        return RET_PASSTHRU;
    }
    
}

1;