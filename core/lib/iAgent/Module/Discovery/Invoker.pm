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

package iAgent::Module::Discovery::Invoker;
use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use Data::UUID;
use POE;

sub DISCOVERY_NODE               { "/iagent/cloud"; }           # The base name of the pub/sub node that will be used as the public message bus
sub DISCOVERY_CONTEXT            { "iagent:cloud:discovery"; }  # The context of the XMPP messages
sub LOOP_SPEED                   { 0.2 };                       # The delay between loop calls
sub SCHED_SPEED                  { 1 };                         # The delay between discovery queries
sub SCHED_SLOTS                  { 10 };                        # How many queries to perform at once

sub TIMEOUT_PUBLISHED            { 2 };                         # How many seconds to wait after the last discovery response arrives before we process them

sub STATE_PENDING                { 0 };                         # The request is not yet processed
sub STATE_PUBLISHED              { 1 };                         # We published a discovery
sub STATE_CLEANUP                { 2 };                         # We are done, cleanup the job

our $MANIFEST = {
    
    XMPP => {
        
        # Discovery invocation action
        DISCOVERY_CONTEXT() => {
            
            # set/invoke starts an action that we looked up earlier
            'set' => {
                'response' => 'xmpp_result'
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
    
    my $self = { 
        ME => '',
        QUEUE => [ ],
        ACTIVE => { },
        SLOTS => 0,
    };
    return bless $self, $class;
}

############################################
# Setup the session instance (called by the kernel)
sub ___setup {
############################################
    $poe_kernel->yield('_scheduler');
    $poe_kernel->yield('_loop');
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
# Schedule a discovery
sub __discover_request {
############################################
    my ($self, $action, $data, $callback, $user_data) = @_[ OBJECT, ARG0..ARG3 ];
    
    # Schedule a discovery request
    log_msg("Preparing discovery for action $action");
    my $request = {
        session => $iAgent::Kernel::LAST_SOURCE,
        action => $action,
        data => $data,
        callback => $callback,
        user_data => $user_data
    };
    
    # Schedule
    push @{$self->{QUEUE}}, $request;
    
}

############################################
# The scheduling queue
sub ___scheduler {
############################################
    my $self = $_[OBJECT];
    
    # Check for free slots
    if ((scalar @{$self->{QUEUE}} > 0) && ($self->{SLOTS} < SCHED_SLOTS)) {
        
        # Acquire slot
        $self->{SLOTS} += 1;
        
        # Fetch request
        my $req = shift(@{$self->{QUEUE}});
        
        # Transform the request to a proper FSM structure
        $req->{id} = Data::UUID->new()->create_str;
        $req->{state} = STATE_PENDING;
        $req->{time} = time();
        
        # Push to active structures
        log_msg("Dequeued action $req->{action} with ID $req->{id}");
        $self->{ACTIVE}->{$req->{id}} = $req;
        
    }
    
    # Schedule next queue shift
    $poe_kernel->delay('_scheduler' => LOOP_SPEED);
}

############################################
# The main discovery loop
sub ___loop {
############################################
    my $self = $_[OBJECT];
    my $time = time();
    
    # Process jobs
    JOBLOOP: foreach my $id (keys %{$self->{ACTIVE}}) {
        my $job = $self->{ACTIVE}->{$id};
        
        #
        # PENDING => PUBLISHED
        #
        # If the job is pending, invoke it
        #
        if ($job->{state} == STATE_PENDING) {
            
            # Dispatch the event on the node
            my $ans = Dispatch("comm_pubsub_publish", {
                node => DISCOVERY_NODE,
                context => DISCOVERY_CONTEXT,
                action => 'lookup',
                data => {
                    action => $job->{action},
                    data => $job->{data},
                    id => $job->{id}
                }
            });
            
            # Prepare responses
            $job->{responses} = { };
            
            # Update status
            $job->{state} = STATE_PUBLISHED;
            $job->{time} = time();
                         
        } 
        
        #
        # PUBLISHED => CLEANUP
        #
        # If the job is published, wait for discovery timeout and then check
        # what to do
        #
        elsif (($job->{state} == STATE_PUBLISHED) && ($time >= $job->{time}+TIMEOUT_PUBLISHED)) {
            
            # Call the callback event
            $poe_kernel->post($job->{session}, $job->{callback}, $job->{responses}, $job->{user_data});
            
            # Everything looks fine, we are done
            $job->{state} = STATE_CLEANUP;
            
        }
        
        #
        # CLEANUP
        #
        # Delete instance and release slot
        #
        elsif ($job->{state} == STATE_CLEANUP) {
            
            # Delete from active
            delete $self->{ACTIVE}->{$id};
            
            # Release slot
            $self->{SLOTS} -= 1;
            
        }
        
    }
    
    $poe_kernel->delay('_loop' => LOOP_SPEED);
}

############################################
# Got a discovery result from the remote endpoint
sub __xmpp_result {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $id = $packet->{parameters}->{id};
    my $type = $packet->{parameters}->{type};
    my $data = $packet->{data};
    return RET_ABORT unless defined($id);
    
    # Fetch the associated job
    my $job = $self->{ACTIVE}->{$id};
    if (!defined $job) {
        log_warn("[$packet->{from}] Responded on a non-existing job ($id)! Probably increase TIMEOUT_PUBLISHED?");
        return RET_ABORT;
    } else {
        log_msg("[$packet->{from}] Discovery response for action $job->{action} ($id)");
    }
    
    # Update the job response pool
    $job->{responses}->{$packet->{from}} = {
        type => $type,
        data => $data
    };
    
    # Update the timer of the job
    $job->{time} = time();
    
    # Continue event
    return RET_OK;
    
}

1;