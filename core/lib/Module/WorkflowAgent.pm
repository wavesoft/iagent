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

package Module::WorkflowAgent;

=head1 NAME

Module::WorkflowAgent - Workflow implementation agent

=head1 DESCRIPTION

This module provides ability to invoke a workflow and monitor it's progress over the nework. It also provides all the
logic that propage and monitor the workflow over the network.

=head1 BROADCASTED MESSAGES

=head2 workflow_started

=head1 HANDLED MESSAGES

=cut

use strict;
use warnings;
use POE;
use iAgent::Log;
use iAgent::Kernel;
use Date::Format;
use Data::UUID;
use Data::Dumper;
use HTML::Entities;
use Hash::Merge qw( merge );
use Module::Workflow::Definition;

# TODO: What happens if multiple actions need to be remotely invoked?

sub WORKFLOW_NODE               { "/iagent/workflow"; } # The base name of the pub/sub node that will be used as the public message bus

sub LOOP_SPEED                  { 0.2 };    # The delay between loop calls

sub FLAG_REMOTE_ON_FAIL         { 1 };      # If a local invocation failed, try to lookup somebody else on the network to handle it
sub FLAG_REMOTE_ON_BUSY         { 1 };      # If a local invocation is busy, try a remote resource instead of waiting for it to become free
sub FLAG_LOCAL_ON_BUSY          { 1 };      # Switch back to local if all of the remote endpoints are busy or failed

sub TIMEOUT_PENDING             { 0 };      # How many seconds is an action allowed to stay in PENDING state (0 = Infinite)
sub TIMEOUT_GHOST               { 120 };    # How many seconds to stay in GHOST state
sub TIMEOUT_RUN                 { 3600 };   # How many seconds is an action allowed to stay in RUN state (0 = Infinite)
sub TIMEOUT_INVOKED             { 3600 };   # How many seconds is an action allowed to stay in INVOKED state (0 = Infinite)
sub TIMEOUT_OBSERVE             { 3600 };   # How many seconds to stay in OBSERVE state
sub TIMEOUT_LOOKUP              { 30 };     # How many seconds is an action allowed to stay in LOOKUP state (0 = Infinite)
sub TIMEOUT_ASK_PROVIDER        { 10 };     # How long to wait before asking the provider for a new instance (Must be smaller or equal to TIMEOUT_LOOKUP)
sub TIMEOUT_EXPIRE_LOOKUP       { 60 };     # After how much time lookup information will be expired (WARNING! Must be BIGGER than TIMEOUT_LOOKUP!!)
sub TIMEOUT_INVALID_PROVIDERS   { 180 };    # When to reset the invalid state of a provider
sub TIMEOUT_PROVIDE             { 60 };     # How many seconds to wait for the provider to give us an action handler
sub TIMESLOT_LOOKUP             { 5 };      # How many seconds to wait between different lookup requests (Throttling. Set 0 to disable)
sub TIMESLOT_PROVISION          { 5 };      # Do not reply to provision requests for the same action within the specified frame
sub TIMEOUT_HEARTBEAT           { 60 };     # When will an action times out if no heartbeat is arrived
sub TIMESPAN_HEARTBEAT          { 30 };     # Every how many second to send heartbeat signals

sub MAX_ACTION_SLOTS            { 100 };    # How many total actions to run concurrently (locally)
sub MAX_RETRY_INVOKE            { 5 };      # How many times to retry to invoke the action of a target fails 
sub MAX_RETRY_LOOKUP            { 5 };      # How many times to retry to perform the lookup procedure again if there were no targets detected
sub MAX_RETRY_WFLOOKUP          { 2 };      # How many times to retry to perform the lookup procedure before invoking a workflow-defined lookup timeout handler
sub MAX_PROVISIONS              { 10 };     # The global max number of provision instances to provide per action

sub STATE_SCHEDULED             { 1 };      # The workflow is scheduled for local execution
sub STATE_LOOKUP                { 2 };      # The workflow is looking for remote targets that can handle it
sub STATE_RUN                   { 3 };      # The workflow is running locally
sub STATE_CONTINUE              { 4 };      # The workflow action is completed and the next action should kick-in
sub STATE_FAILED                { 5 };      # Something when wrong and the workflow was unable to complete
sub STATE_INVOKED               { 6 };      # The workflow was successfully invoked to a remote entity
sub STATE_PASSED                { 8 };      # The workflow was successfull passed to a remote entity
sub STATE_GHOST                 { 9 };      # The workflow has completed but we need it for a comple of seconds more in case a user requests information
sub STATE_DEAD                  { 10 };     # The workflow is dead. Reaping imminent...
sub STATE_OBSERVE               { 11 };     # The workflow is in observing state. It waits for child status feedbacks.
sub STATE_WAIT                  { 12 };     # Simmilar to OBSERVER, but only for a single remotely invoked action.
sub STATE_PROVIDING             { 13 };     # The workflow action was handled by a provider that will create a handler for it

sub STATE_BUSY                  { 20 };     # There are no free entities that can handle this action
sub STATE_FREE                  { 21 };     # The lookup information indicate that this action is busy 
sub STATE_BLANK                 { 22 };     # There are no entities that can handle this workflow 
sub STATE_INVALID               { 23 };     # The lookup entity responded that it can handle the workflow but under different context 
sub STATE_PROVIDED              { 24 };     # There was no target found, but the entity is a provider of that action.

sub ERRNO_TIMEOUT               { 126 };    # The error code of a timed-out workflow
sub ERRNO_INTERNAL              { 125 };    # The error code of an internal error
sub ERRNO_ABORTED               { 124 };    # The error code of a user-aborted workflow
sub ERRNO_FAILED                { 123 };    # The action was failed

our $MANIFEST = {
    
    XMPP => {
        "iagent:workflow" => {
            "set" => { 
                
                # Feedback from an invoked workflow
                "started"    => "xmpp_started",
                "passed"     => "xmpp_passed",
                "completed"  => "xmpp_completed",
                "abort"      => "xmpp_abort",
                "failed"     => "xmpp_failed",
                "lookup"     => "xmpp_lookup",
                "invoke"     => "xmpp_invoke",
                "provide"    => "xmpp_provide",
                "provided"   => "xmpp_provided",
                "heartbeat"  => "xmpp_heartbeat"
                
            },
            "get" => {
                
                # Respond to query information
                "workflow"  => "xmpp_workflow",
                
                # Respond to log query
                "logs"      => "xmpp_logs",
                "log"       => "xmpp_log"
                
            }
        }
    },
    
    CLI => {
        "wf/dump" => {
            description => "Dump the state of the Workflow Agent",
            message => "cli_wf_dump"
        }
    }
    
};

sub state_str {
    my ($state) = @_;
    return 'STATE_SCHEDULED' if ($state==STATE_SCHEDULED);
    return 'STATE_LOOKUP' if ($state==STATE_LOOKUP);
    return 'STATE_RUN' if ($state==STATE_RUN);
    return 'STATE_CONTINUE' if ($state==STATE_CONTINUE);
    return 'STATE_FAILED' if ($state==STATE_FAILED);
    return 'STATE_INVOKED' if ($state==STATE_INVOKED);
    return 'STATE_GHOST' if ($state==STATE_GHOST);
    return 'STATE_DEAD' if ($state==STATE_DEAD);
    return 'STATE_OBSERVE' if ($state==STATE_OBSERVE);
    return 'STATE_WAIT' if ($state==STATE_WAIT);
    return 'STATE_BUSY' if ($state==STATE_BUSY);
    return 'STATE_FREE' if ($state==STATE_FREE);
    return 'STATE_BLANK' if ($state==STATE_BLANK);
    return 'STATE_INVALID' if ($state==STATE_INVALID);
    return 'STATE_PROVIDED' if ($state==STATE_PROVIDED);
    return 'STATE_PROVIDING' if ($state==STATE_PROVIDING);
    return "UNKNOWN (STATE #$state)";
}


#++++++++++++++++++++++++++++++++++++++++++++++++++
# Debug: Debug dump the workflow agent state
sub __cli_wf_dump {
#++++++++++++++++++++++++++++++++++++++++++++++++++
    my $self = $_[OBJECT];
    sub undefstr { $_[0] or '#undef#' };
    sub undefarr { $_[0] or [] };
    sub undefint { $_[0] or 0 };
    sub undefhsh { $_[0] or {} };
        
    Dispatch("cli_write", "-------------------------------------------------------------------------");
    Dispatch("cli_write", "Instances:");
    foreach (values %{$self->{INSTANCES}}) {
        Dispatch("cli_write", " * DID=$_->{DID}, IID=$_->{IID}, AID=$_->{AID}, ACTION=$_->{Action}, STATE=".state_str($_->{State}).", Timeout=".(time()-undefint($_->{Timeout})).", Observer=".undefstr($_->{Observer}).", Target=".undefstr($_->{Target}));
        if (defined($_->{Children})) {
            foreach my $C (values %{$_->{Children}}) {
                Dispatch("cli_write","    - Instance: IID=".$C->IID.", DID=".$C->DID." AID=".$C->ACTIVE.", ACTION=".$C->ACTION->{action});
            }
        }
    }
    Dispatch("cli_write", " (Empty)") if (!scalar values %{$self->{INSTANCES}});
    
    Dispatch("cli_write", "");
    Dispatch("cli_write", "Lookup information:");
    foreach (keys %{$self->{LOOKUPS}}) {
        my $v = $self->{LOOKUPS}->{$_};
        my %targets = %{undefhsh($v->{Targets})};
        Dispatch("cli_write", " * Index=$_, IID=$v->{IID}, Action=$v->{Action}, State=".state_str($v->{State}).", Timeout=".(time()-undefint($v->{Timeout})).", Targets=".(scalar keys %targets));
        foreach (keys %targets) {
            Dispatch("cli_write", "    - Target $_ ($targets{$_} free slots)");
        }
    }
    Dispatch("cli_write", " (Empty)") if (!scalar keys %{$self->{LOOKUPS}});
    Dispatch("cli_write", "");

    Dispatch("cli_write", "Observe information:");
    foreach (keys %{$self->{OBSERVABLES}}) {
        my $iid = $self->{OBSERVABLES}->{$_};
        Dispatch("cli_write", " * Observable: IID=$_ is observed by IID=$iid");
    }
    Dispatch("cli_write", " (Empty)") if (!scalar keys %{$self->{OBSERVABLES}});
    Dispatch("cli_write", "-------------------------------------------------------------------------");
            
    return RET_COMPLETED;
}

###################################################
# Create new instance
sub new {
###################################################
    my $class = shift;
    my $self = {
        
        LOGDIR => "/tmp",       # Where to store the logs
        
        LOOKUPS => { },         # Lookup information for actions
        LOOKUP_TIMEOUT => 0,    # The time we sent the last lookup request
        
        INSTANCES => { },       # The container of all the action instances
        SLOTS => 0,             # The number of currently used action slots
        OBSERVABLES => { },     # A mapping hash between the observed instance IDs and the observee ID
        
        PROVISIONS => { },      # A hash that holds the information about provided actions
        INVALID_PROVIDERS => {},# A list of providers that failed to provide us with an action
        
        DIRTY_ACTIONS => { },   # A hash of workflow DIDs and the actions they invoked so that they can be cleaned afterwords
        
        ME => '',               # My JID (Updated by __comm_ready)
        LOCAL_FEEDBACK => { }   # The local DIDs that should trigger the workflow_progress/start event
        
    };
    
    # Return instance
    return bless $self, $class;
}

############################################
# Communication plugin is ready: 
# Check/Establish subscriptions
sub __comm_ready {
############################################
    my ($self, $me) = @_[ OBJECT, ARG0 ];
    $self->{ME} = $me;
    $self->{SUBSCRIBED} = 0;
    
    log_debug("Hello world. I'm $me");
    
    # Get a list of actions available to workflow
	my $actions = iAgent::Kernel::Query("workflow_actions_list");
	if (ref($actions) eq '') { # Got error code?
	    return RET_OK; # Join nothing - continue
	}

    # Get subscriptions
    my $subs = { };
    if (!iAgent::Kernel::Dispatch("comm_pubsub_subscriptions", $subs)) {
        log_warning("Unable to fetch PubSub subscriptions!");
        return RET_OK;
    }
    
    # Try to join the public discovery channel
    my $node = WORKFLOW_NODE.'/discovery';
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
                if ($msg_create->{error} ne '409') { # Already exists
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

    }

    # Try to join all the action nodes
	foreach (@{$actions}) {
        my $node = get_action_node($_->{Name});
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
                    'pubsub#title' => 'iAgent Workflow Channel for action '.$_->{Name},
                    'pubsub#item_expire' => 30
                }
            };

            # Create Pub/Sub node
            if (iAgent::Kernel::Dispatch("comm_pubsub_create", $msg_create) != 1) {
                if (!$msg_create->{error}) {
                    log_error("Unable to invoke PubSub creation of node $node!");
                    return RET_OK;
                } else {
                    if ($msg_create->{error} ne '409') { # Already exists
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
    }
    
    return RET_OK;
}

sub ___setup {
    $poe_kernel->delay('_loop' => LOOP_SPEED);
}

##===========================================================================================================================##
##                                                HELPER FUNCTIONS                                                           ##
##===========================================================================================================================##

###################################################
# Create a node name based on the action specified
sub get_action_node {
###################################################
    my $n = shift;
	$n =~ s/[:\.]/-/;
	$n =~ s/[\/\\]/_/;
	return WORKFLOW_NODE . "/$n";
}

###################################################
# Place a lookup request
sub targets_lookup {
###################################################
    my ($self, $iid, $action, $context) = @_;
    return unless not defined($self->{LOOKUPS}->{$iid});
    
    # Prepare the lookup entry
    $self->{LOOKUPS}->{$iid} = {
        Targets => { },
        State => STATE_SCHEDULED,
        Action => $action,
        Context => $context,
        IID => $iid
    };
    
    # Don't invoke it directly, but schedule it
    # this is a throttling mechanism to avoid pollution
    # of the public channel
    
}

###################################################
# Update the flag of the lookup information of the
# specified action, depending on if there are free
# targets to pick or not.
sub targets_refresh {
###################################################
    my ($self, $iid) = @_;
    my $entry = $self->{LOOKUPS}->{$iid};
    return unless defined $entry;

    # Start by assuming we are not going to find anthing
    $entry->{State} = STATE_BLANK;
    
    # Check if we had a provider in the list
    my $provider=0;
        
    # By default we consider everything busy if we have
    # at least one target defined
    if (scalar keys %{$entry->{Targets}} > 0) {
        $entry->{State} = STATE_BUSY;
    }
    
    # Scan targets
    foreach (keys %{$entry->{Targets}}) {
        
        # Check if this target is free and break if true
        if ($entry->{Targets}->{$_} > 0) {
            
            log_debug("[$iid] Target availability: FREE ($_)");
            
            # We have at least one available node that is not acquired
            $entry->{State} = STATE_FREE;
            return;
            
        } elsif ($entry->{Targets}->{$_} == -1) {
            
            log_debug("[$iid] Target is a provider");
            $entry->{State} = STATE_PROVIDED;
            
        }
    }
    
    if ($entry->{State} == STATE_BLANK) {
        log_debug("[$iid] Target availability: BLANK");
    } elsif ($entry->{State} == STATE_PROVIDED) {
        log_debug("[$iid] Target availability: PROVIDED");
    } else {
        log_debug("[$iid] Target availability: BUSY");
    }

}

###################################################
# Pick the next available target from the lookup stack
sub target_pick {
###################################################
    my ($self, $iid) = @_;
    my $entry = $self->{LOOKUPS}->{$iid};
    return undef unless defined $entry;
    
    # Return the provided target if the state is STATE_PROVIDED
    if ($entry->{State} == STATE_PROVIDED) {
        
        # Pick the provided target (only once - so pop it)
        foreach (keys %{$entry->{Targets}}) {
            if ($entry->{Targets}->{$_} == -1) {
                
                # Remove target (Use each target only once)
                delete $entry->{Targets}->{$_};
                return $_;
                
            }
        }
        
    }
    
    # If there are no free slots, just don't bother
    return undef unless ($entry->{State} == STATE_FREE);
    
    # Sort keys decending based on their max slots
    my @keys = sort { $entry->{Targets}->{$b} cmp $entry->{Targets}->{$a} } keys(%{$entry->{Targets}});
    
    # Pick the first available
    my $target = shift @keys;
    my $slots = $entry->{Targets}->{$target};
    
    log_debug("[$iid] Picked target $target having $slots slots free");
    
    # Acquire slot
    $entry->{Targets}->{$target}--;
    
    # Update availability
    $self->targets_refresh($iid);

    # Return target
    return $target;
    
}

###################################################
# Release a previously acquired target
sub target_release {
###################################################
    my ($self, $iid, $target) = @_;
    my $entry = $self->{LOOKUPS}->{$iid};
    return unless defined $entry;
    return unless defined $target;
    
    # Release target slot
    $entry->{Targets}->{$target}++;
    log_debug("[$iid] Released target $target");
    
    # Update availability
    $self->targets_refresh($iid);
}

###################################################
# Mark that the specified target has failed to 
# run this action.
sub target_fail {
###################################################
    my ($self, $iid, $target) = @_;
    my $entry = $self->{LOOKUPS}->{$iid};
    return unless defined $entry;
    return unless defined $target;
    
    # Discard target
    delete $entry->{Targets}->{$target};
    log_debug("[$iid] Dicarded target $target because of invalid response");
    
    # Update availability
    $self->targets_refresh($iid);
}

###################################################
# Write an entry on the workflow's report log
sub report {
###################################################
    my $dir = shift;
    my $log = join(" ",@_);
    return if (!-d $dir);

    # Log the line
    my $ts = time2str('%c',time);
    if (open(ALOG, ">>$dir/report.log")) {
        print ALOG "[$ts] $log\n";
        close ALOG;
    } else {
        log_warn("Unable to open $dir/report.log! $!");
    }
    
}

###################################################
# Allocate a new report entry
sub report_alloc {
###################################################
    my ($self, $wf) = @_;
    my $id = $wf->IID;
    my $def_id = $wf->DID;
    my $dir = $self->{LOGDIR};
    
    # Create a directory entry
    mkdir $dir unless(-d $dir);
    $dir .= "/$def_id";
    mkdir $dir unless(-d $dir);
    $dir .= "/$id";
    mkdir $dir unless(-d $dir);
    
    # Store log entry
    my $ts = time2str('%c',time);
    if (open(ALOG, ">$dir/report.log")) {
        print ALOG "Report started at ".time2str('%a %b %e %T %Y',time)."\n";
        print ALOG "[$ts] Loaded workflow ".$wf->NAME." (Definition ID: ".$wf->DID.") invoked by ".$wf->INVOKER."\n";
        print ALOG "[$ts] Running instance with ID ".$wf->IID." on state #".$wf->ACTIVE." (Action: ".$wf->ACTION->{action}.")\n";
        print ALOG "[$ts] Context: ".Dumper($wf->CONTEXT)."\n";
        close ALOG;
    } else {
        log_warn("Unable to open $dir/report.log! $!");
    }
    
    # Return the log dir (That's also the log information ID)
    return $dir;
}

###################################################
# Stop all the provided instances for the specified DID
sub dispose_provisions {
###################################################
    my ($self, $did) = @_;
    
    # Scan all provisions
    foreach my $action (keys %{$self->{PROVISIONS}}) {
        foreach my $id (keys %{$self->{PROVISIONS}->{$action}}) {
            my $provision = $self->{PROVISIONS}->{$action}->{$id};
            if ($provision->{DID} eq $did) {
                
                # Don't care about the answer
                Dispatch( 'workflow_action_deallocate', $provision->{action}, {
                    ID => $provision->{id},
                    LogDir => $provision->{dir},
                    Context => $provision->{context},
                    Permissions => $provision->{permissions}
                });
                
                # Delete provision
                delete $self->{PROVISIONS}->{$action}->{$id};
            }
        }
        
        # If the provisions for this action are empty, remove them
        delete $self->{PROVISIONS}->{$action} if (scalar keys %{$self->{PROVISIONS}->{$action}} == 0);
        
    }
}

###################################################
# Cleanup all the dirty actions of the specified DID
sub cleanup_dirty {
###################################################
    my ($self, $did) = @_;
    
    # Cleanup a dirty entry
    if (defined($self->{DIRTY_ACTIONS}->{$did})) {
        log_msg("[$did] Cleaning up dirty workflow");
        
        foreach (@{$self->{DIRTY_ACTIONS}->{$did}}) {

            # Report the cleanup
            log_debug("Cleaning $_->{ID} : $_->{Action}");
            report($_->{LogDir}, "Calling action cleanup handler");

            # Call on workflow cleanup
            my $ans = Dispatch("workflow_action_cleanup", $_->{Action}, {
                ID => $_->{IID},
                LogDir => $_->{LogDir},
                Context => $_->{Context},
                Permissions => $_->{Permissions}
            });
            
        }
        
        # Remove dirty definition
        delete $self->{DIRTY_ACTIONS}->{$did};
    }
}


##===========================================================================================================================##
##                                            HELPER MESSAGE HANDLERS                                                        ##
##===========================================================================================================================##

############################################
# Notify the successful completion of an observed instance
sub ___succeed_observable {
############################################
    my ($self, $iid, $result) = @_[ OBJECT, ARG0..ARG1 ];
    log_info("SUCCEED OBSERVABLE: $iid");

    # If this workflow is being observed, notify the observee
    if (defined($self->{OBSERVABLES}->{$iid})) {
        my $oiid = $self->{OBSERVABLES}->{$iid};
        if (defined($self->{INSTANCES}->{$oiid})) {
            my $inst = $self->{INSTANCES}->{$oiid};
            log_debug("[$iid] Notifying the observer $oiid for success");
            
            # Delete the child with the specified ID
            delete $inst->{Children}->{$iid};
            delete $self->{OBSERVABLES}->{$iid};
            log_info("  -> CHILDREN LEFT: ".scalar values %{$inst->{Children}});
            
            # Update result code
            $inst->{Result} = $result unless ($result == 0);
            
        }
    }
    
    # Return OK
    return RET_OK;
}

############################################
# Notify the failure of an observed instance
sub ___fail_observable {
############################################
    my ($self, $iid, $result, $failure) = @_[ OBJECT, ARG0..ARG2 ];
    log_info("FAIL OBSERVABLE: $iid");

    # If this workflow is being observed, notify the observee
    if (defined($self->{OBSERVABLES}->{$iid})) {
        my $oiid = $self->{OBSERVABLES}->{$iid};
        if (defined($self->{INSTANCES}->{$oiid})) {
            my $inst = $self->{INSTANCES}->{$oiid};
            log_debug("[$iid] Notifying the observer $oiid for failure ($failure) #$result");
            
            # If this workflow endures failures on observables, do not abor the instance
            if ($inst->{WF}->ERROR_MODE eq 'endure') {
                
                delete $inst->{Children}->{$iid};
                delete $self->{OBSERVABLES}->{$iid};
                
                log_debug("[$iid] Workflow endures errors. Will continue");
                log_info("  -> CHILDREN LEFT: ".scalar values %{$inst->{Children}});
                
            } else {
            
                # Update result code
                $inst->{State} = STATE_FAILED;
                $inst->{Failure} = $failure;
                $inst->{Result} = $result;
            
                # Abort all the observing instances
                foreach (values %{$inst->{Children}}) {
                    $poe_kernel->yield('_abort_instance', $_->IID, $result, $failure);
                    delete $self->{OBSERVABLES}->{$_->IID};
                }
                $inst->{Children}={};
                
            }
            
        }
    }
    
    # Return OK
    return RET_OK;
}

############################################
# Abort the specified instance
sub ___abort_instance {
############################################
    my ($self, $iid, $result, $failure) = @_[ OBJECT, ARG0..ARG2 ];
    return unless defined($self->{INSTANCES}->{$iid});
    my $inst=$self->{INSTANCES}->{$iid};

    log_debug("[$iid] Aborting instance");
    $failure='User abort' unless defined($failure);
    $result = ERRNO_ABORTED unless defined($result);
    
    # If it's a local running instance, stop if
    if ($inst->{State} == STATE_RUN) {
        log_debug("[$iid] ABORT: Aborting locally running action");
        
        # Abort workflow
        report($inst->{LogDir}, "Action aborted. Reason: $failure");
        my $ans = Dispatch("workflow_action_abort", $iid);

        # Release slot
        $self->{SLOTS}--;
        
        # Don't care much about the answer... fail workflow
        $inst->{State} = STATE_FAILED;
        $inst->{Result} = $result;
        $inst->{Failure} = 'Action aborted: '.$failure;
        
    } 
    
    # If we are just waiting for workflow completion, just abort
    # the action
    elsif ($inst->{State} == STATE_WAIT) {
        log_debug("[$iid] ABORT: Aborting remote workflow in WAIT state");

        # Don't care much about the answer... fail workflow
        $inst->{State} = STATE_FAILED;
        $inst->{Result} = $result;
        $inst->{Failure} = 'Action aborted: '.$failure;
        
        # Inform interested parties that we are finished
        $poe_kernel->yield('_sendto', [ $inst->{Target} ], 'abort', {
            iid => $inst->{IID},
            did => $inst->{DID},
            aid => $inst->{AID},
            failure => $inst->{Failure}
        });
                
    }
            
    # If it's a remotely invoked instance, send a stop message
    elsif ($inst->{State} == STATE_INVOKED) {
        log_debug("[$iid] ABORT: Aborting remotely invoked workflow");

        # Don't care much about the answer... fail workflow
        $inst->{State} = STATE_FAILED;
        $inst->{Result} = $result;
        $inst->{Failure} = 'Action aborted: '.$failure;
        
        # Inform interested parties that we are finished
        $poe_kernel->yield('_sendto', [ $inst->{Target} ], 'abort', {
            iid => $inst->{IID},
            did => $inst->{DID},
            aid => $inst->{AID},
            failure => $inst->{Failure}
        });

    }

    # If we are observing targets, abort them all (and me too)
    elsif ($inst->{State} == STATE_OBSERVE) {
        log_debug("[$iid] ABORT: Aborting observing workflows");

        # Don't care much about the answer... fail workflow
        $inst->{State} = STATE_FAILED;
        $inst->{Result} = $result;
        $inst->{Failure} = 'Action aborted: '.$failure;
        
        # Abort targets
        foreach (keys %{$inst->{Children}}) {
            log_debug("[$iid]  -> Aborting $_");
            
            # Abort instances
            $poe_kernel->yield('_abort_instance', $_, $result, $failure);
            
            # Remove from observables
            delete $self->{OBSERVABLES}->{$_};
            delete $inst->{Children}->{$_};

        }

    }
    
    # If it's in any other state (Besides GHOST, DEAD or other failure), fail it now
    elsif (($inst->{State} != STATE_GHOST) && ($inst->{State} != STATE_DEAD) && ($inst->{State} != STATE_FAILED)) {

        # Mark instance as failed
        $inst->{State} = STATE_FAILED;
        $inst->{Result} = $result;
        $inst->{Failure} = 'Action aborted: '.$failure;
        
    }
    
}

###################################################
# Send an action to multiple entities
sub ___sendto {
###################################################
    my ($self, $targets, $action, $parameters, $data) = @_[ OBJECT, ARG0..ARG3 ];
    my $sent = { };
    foreach (@{$targets}) {
        next if (!$_);
        next if ($sent->{$_});
        next if ($_ eq $self->{ME});
        Dispatch("comm_send", {
            to => $_,
            type => 'set',
            context => 'iagent:workflow',
            action => $action,
            parameters => $parameters,
            data => $data
        });
        $sent->{$_}=1;
    }
    log_debug("Sent '$action' to ".join(",",keys(%$sent)));
}

##===========================================================================================================================##
##                                                HANDLED MESSAGES                                                           ##
##===========================================================================================================================##

############################################

=head2 workflow_invoke WORKFLOW, PERMISSIONS/USERNAME

This action will invoke a workflow either as a local action or as a remote action, depending on if our
configuration supports it.

C<ARG0> is an instance of a Module::Workflow::Definition object. The workflow will continue from the
currently ACTIVE action of the definition.

C<ARG1> is either a string that represents the name of the sender or a hash of permissions that the 
requesting entity has. 

=cut

#-------------------------------------------
sub __workflow_invoke {
############################################
    my ($self, $wf, $from_or_permissions, $_internal) = @_[ OBJECT, ARG0..ARG2 ];
    my $permissions = { };
    
    # Ensure wf is an instance to a workflow object
    return RET_SYNTAXERR unless (UNIVERSAL::isa($wf, 'Module::Workflow::Definition'));
    log_debug("Invoking workflow ".$wf->NAME);
    
    # Populate permissions Hash
    if (ref($from_or_permissions) eq 'HASH') {
        $permissions = $from_or_permissions; # Use the hash as-is
        
    } elsif (ref($from_or_permissions) eq 'ARRAY') {
        $permissions = \%{ {map {($_,1)} @$from_or_permissions} }; # Build a hash from the array
        $permissions->{any} = 1;
        
    } elsif (ref($from_or_permissions) eq '') {
        if (Dispatch("permissions_get", $from_or_permissions, $permissions)!=RET_OK) { # Fetch permissions of the user
            log_warn("Unable to fetch permissions of user $from_or_permissions!");
            return RET_ERROR;
        }
        
    } else {
        return RET_SYNTAXERR; # Syntax error (Expecting HASH/ARRAY or scalar)
        
    }
    log_debug("Detected permissions: ".join(",",keys(%$permissions)));
    
    # If this was not an internal call, register me as the invoker and register this workflow as local
    my $observer = undef;
    if (!defined($_internal)) {
        
        # I am the invoker
        $wf->{INVOKER} = $self->{ME};

        # Mark this DID as pending for start notification
        $self->{LOCAL_FEEDBACK}->{$wf->DID} = {
            WF => $wf,
            DID => $wf->{DID},
            IID => $wf->{IID}
        };
        
    } else {
        # When used internally and it's not '', it's the observer
        $observer = $_internal unless ($_internal eq '');
    }

    # Prepare action information
    my $action = $wf->ACTION;
    my $context = $wf->CONTEXT;
    
    # Allocate report records for this action
    my $dir = $self->report_alloc($wf);
    
    # Register entry on instances
    log_debug("ENTERED: ".$wf->IID);
    $self->{INSTANCES}->{$wf->IID} = {
        IID => $wf->IID,                # The workflow instance ID
        DID => $wf->DID,                # The workflow definition ID
        AID => $wf->ACTIVE,             # The current action ID
        WF => $wf,                      # The workflow object representation
        LogDir => $dir,                 # The directory to store the logfiles into
        Permissions => $permissions,    # The permissions of the invoking entity
        Context => $context,            # The context of the action
        Action => $action->{action},    # The name of the action
        State => STATE_SCHEDULED,       # The workflow state
        Observer => $observer,          # The immediate responsible to send feedback to
        Heartbeat => 0,                 # Heartbeat timer
        LookupRetries => 0,             # Lookup retires
        InvokeRetries => 0,             # Invocation retries
        Timeout => time(),              # (For different context every time)
        Children => { },                # Child instances invoked by this action
        Alive => 0                      # The number of alive instances
    };
    
    # If this action is a fork fanout, invoke the children and go to ovserve mode
    if ($wf->ACTION->{type} eq 'fork') {

        # Go to CONTINUE -> It will generate the instances
        log_debug('['.$wf->IID.'] Action is a fork fanout. Moving to continue');
        $self->{INSTANCES}->{$wf->IID}->{State} = STATE_CONTINUE;
        $self->{INSTANCES}->{$wf->IID}->{Timeout} = time();
                
        # Return ok
        return RET_OK;
        
    }
    
    # Check if we can run locally
    my $ans = Dispatch("workflow_action_validate", $action->{action}, $context, $permissions);
    unless (($ans == RET_BUSY) || ($ans == RET_OK)) {
        
        # If we are not allowed to distribute this action, fail
        if (!$wf->ACTION->{distributed}) {
            $self->{INSTANCES}->{$wf->IID}->{State} = STATE_FAILED;
            $self->{INSTANCES}->{$wf->IID}->{Result} = ERRNO_FAILED;
            $self->{INSTANCES}->{$wf->IID}->{Failure} = 'Action returned with an error and distribution was denied';
            
        }
        
        # We cannot run this action.... try to lookup somebody on the network that can handle it, but only if told so
        elsif (FLAG_REMOTE_ON_FAIL == 1) {
            $self->{INSTANCES}->{$wf->IID}->{State} = STATE_LOOKUP;
            log_debug("Scheduled for remote execution");
            
        } 
        
        # Could not do anything
        else {
            $self->{INSTANCES}->{$wf->IID}->{State} = STATE_FAILED;
            $self->{INSTANCES}->{$wf->IID}->{Result} = ERRNO_FAILED;
            $self->{INSTANCES}->{$wf->IID}->{Failure} = 'Action returned with an error';
        }
        
    } else {
        
        log_debug("Scheduled for local execution");
        
    }
    
    # Return OK
    return RET_OK;
        
}

############################################

=head2 workflow_abort DID

This action will abort a workflow that is in progress, notifying all the child nodes too.

C<ARG0> is the definition id of the workflow you want to abort.

=cut

#-------------------------------------------
sub __workflow_abort {
############################################
    my ($self, $did, $reason) = @_[ OBJECT, ARG0 ];
    $reason = 'Aborted by the user' unless defined($reason);
    log_info("Aborting workflow DID=$did");
    
    # If we don't have such workflow, return error
    return RET_NOTFOUND if (scalar keys %{$self->{INSTANCES}} == 0);
    
    # Find all the instances under this DID and destroy them
    foreach (values %{$self->{INSTANCES}}) {
        if ($_->{DID} eq $did) {
            log_debug(" -> Aborting instance $_->{IID}");
            $poe_kernel->yield('_abort_instance', $_->{IID}, ERRNO_ABORTED, $reason);
        }
    }
    
    return RET_OK;
}

##===========================================================================================================================##
##                                                  FEEDBACK MESSAGES                                                        ##
##===========================================================================================================================##

############################################
# Handle the event of the slot allocation completion
sub __workflow_action_allocated {
############################################
    my ($self, $iid, $result, $context) = @_[ OBJECT, ARG0..ARG2 ];
    return RET_PASSTHRU unless defined($self->{INSTANCES}->{$iid});
    my $wf = $self->{INSTANCES}->{$iid};
    
}

############################################
# Handle local workflow action completion
sub __workflow_action_completed {
############################################
    my ($self, $iid, $result, $context) = @_[ OBJECT, ARG0..ARG2 ];
    return RET_PASSTHRU unless defined($self->{INSTANCES}->{$iid});
    my $wf = $self->{INSTANCES}->{$iid};
    
    # Log the completion
    report($self->{INSTANCES}->{$iid}->{LogDir}, "Action completed with result = $result");
    report($self->{INSTANCES}->{$iid}->{LogDir}, "New context: ".Dumper($context));

    # If the action is not really running (like aborted or timed out), do nothing more
    return if ($wf->{State} != STATE_RUN);    

    # Inform interested parties that we finished
    $poe_kernel->yield('_sendto', [ $wf->{WF}->INVOKER, $wf->{WF}->NOTIFY ], 'finished', {
        iid => $iid,
        did => $wf->{DID},
        aid => $wf->{WF}->ACTIVE,
        result => $result
    });

    # Update workflow information
    log_msg("[$iid] LOCAL: Action $wf->{Action} completed with result $result");
    $wf->{Result} = $result;
    $wf->{WF}->completed($result);
    $wf->{WF}->merge_context($context);

    # Put workflow in continue state
    $wf->{State} = STATE_CONTINUE;

    # Release slot
    $self->{SLOTS}--;

}

############################################
# Query logs for the specified action
sub __xmpp_logs {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Collect and validate info
    my $did = $packet->{parameters}->{did};
    my $iid = $packet->{parameters}->{iid};
    return RET_ABORT unless defined($did);
    return RET_ABORT unless defined($iid);
    log_debug("Looking up logfiles of action $iid of workflow $did");

    # Validate logdir
    my $logdir = $self->{LOGDIR}."/$did/$iid";
    return RET_OK if (! -d $logdir);
    
    # List files within
    my @ans;
    log_debug("Looking for files at $logdir/*");
    foreach (<$logdir/*>) {
        log_debug(" - found $_");
        my $file = substr($_,length($logdir)+1);
        push @ans, $file;
    }
    
    # Reply
    Reply("comm_reply", {
        data => {
            file => \@ans
        }
    });
    
    return RET_OK;
}

############################################
# Query logs for the specified action
sub __xmpp_log {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Collect and validate info
    my $did = $packet->{parameters}->{did};
    my $iid = $packet->{parameters}->{iid};
    my $file = $packet->{parameters}->{file};
    my $limit = $packet->{parameters}->{limit};
    return RET_ABORT unless defined($did);
    return RET_ABORT unless defined($iid);
    return RET_ABORT unless defined($file);
    
    # Secure filename
    $file =~ s/\.\.//g;

    # Validate logdir
    my $logfile = $self->{LOGDIR}."/$did/$iid/$file";
    log_debug("Fetching last 100 lines of logfile $logfile");
    return RET_OK if (! -f $logfile);
    
    # Validate limit
    $limit=100 unless defined($limit) && ($limit =~ m/^[0-9]+$/);
    
    # Prepare filter if specified
    my $filter = "";
    if (defined $packet->{parameters}->{filter}) {
        my $f = $packet->{parameters}->{filter};
        $f =~ s/\'/\\\'/g;
        $filter = "| grep -Ei '$f'";
    }
    
    # Build lines array
    my $buffer = `cat $logfile $filter | tail -n$limit`;
    my @lines = split(/\r?\n/, $buffer);
    my @filtered_lines = map { encode_entities($_) } @lines;
    
    # Reply
    Reply("comm_reply", {
        data => {
            l => \@filtered_lines
        }
    });
    
    return RET_OK;
}

############################################
# Forcefully abort a workflow
sub __xmpp_abort {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

    # Collect and validate info
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $failure = ($packet->{parameters}->{failure} or "Aborted by user");
    return RET_ABORT unless defined($iid);
    return RET_ABORT unless defined($self->{INSTANCES}->{$iid});
    log_msg("[$iid\@$packet->{from}] Action aborted : $failure");
    
    # Abort instance
    $poe_kernel->yield('_abort_instance', $iid, ERRNO_ABORTED, $failure);
    
}

############################################
# Notification from a remote workflow action 
# that just started
sub __xmpp_started {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

    # Collect and validate info
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $aid = $packet->{parameters}->{aid};
    log_msg("[$aid#$iid\@$packet->{from}] Action started");
    
    # If this workflow was invoked by us, send notifications
    if (defined($self->{LOCAL_FEEDBACK}->{$did})) {
        my $def = $self->{LOCAL_FEEDBACK}->{$did};
        if (!$def->{Started}) {
            my $wf = $def->{WF};
            $def->{Started}=1;

            # Notify progress of the workflow
            Dispatch("workflow_started", $wf, {
                Target => $packet->{from}
            });
            
        }
    }

    # Return OK
    return RET_OK;
}

############################################
# Remote request to invoke a workflow
sub __xmpp_invoke {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $wf = $packet->{data}->{workflow};
    return RET_ABORT unless defined($wf);
    log_msg("[".$wf->{IID}."\@$packet->{from}] Workflow invocation request");
    
    # Create workflow object
    $wf = new Module::Workflow::Definition($wf);

    log_msg("[".$wf->IID."] INCOMING: Importing workflow DID=".$wf->DID.", Action=".$wf->ACTION->{action});
    
    # Attempt to start the workflow
    return $poe_kernel->call($_[SESSION], 'workflow_invoke', $wf, $wf->INVOKER, $packet->{from});
    
}

############################################
# Remote request to provide the action for
# a workflow action.
sub __xmpp_provide {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $wf = $packet->{data}->{workflow};
    return RET_ABORT unless defined($wf);
    log_msg("[".$wf->{IID}."\@$packet->{from}] Workflow provider request");
    
    # Create workflow object
    $wf = new Module::Workflow::Definition($wf);

    log_msg("[".$wf->IID."] INCOMING: Providing for workflow DID=".$wf->DID.", Action=".$wf->ACTION->{action});

    # Check for provision limits
    my $action=$wf->ACTION->{action};
    if (defined($self->{PROVISIONS}->{$action})) {
        # Check for limits
        if (scalar keys %{$self->{PROVISIONS}->{$action}} > MAX_PROVISIONS) {
            return RET_ERROR;
        }
    } else {
        # Prepare hash
        $self->{PROVISIONS}->{$action} = { };
    }
    
    # Get the permissions of the invoker
    my $permissions = { };
    if (Dispatch("permissions_get", $packet->{from}, $permissions) != RET_OK) { # Fetch permissions of the user
        log_warn("Unable to fetch permissions of user $packet->{from}!");
        return RET_ERROR;
    }
    
    # Allocate a UUID for the provision
    my $id = "PR-".Data::UUID->new()->create_str;
    
    # Build the logdir
    my $dir = $self->{LOGDIR};
    mkdir $dir unless(-d $dir);
    $dir .= "/provisions";
    mkdir $dir unless(-d $dir);
    $dir .= "/$action";
    mkdir $dir unless(-d $dir);
    $dir .= "/$id";
    mkdir $dir unless(-d $dir);
    
    # Store log
    my $ts = time2str('%c',time);
    if (open(ALOG, ">$dir/provision.log")) {
        print ALOG "Report started at ".time2str('%a %b %e %T %Y',time)."\n";
        print ALOG "[$ts] Starting provision for action $action - requested by $packet->{from}\n";
        print ALOG "[$ts] Context: ".Dumper($wf->CONTEXT)."\n";
        close ALOG;
    } else {
        log_warn("Unable to open $dir/provision.log! $!")
    }
    
    # Store provision info
    my $context = $wf->CONTEXT;
    $self->{PROVISIONS}->{$action}->{$id} = { 
            DID => $wf->DID,
            IID => $wf->IID,
            LogDir => $dir,
            Context => $context,
            Permissions => $permissions,
            Action => $action
        };
    
    # Attempt to start the workflow
    my $ans=Dispatch( 'workflow_action_allocate', $action, {
        ID => $id,
        LogDir => $dir,
        Context => $context,
        Permissions => $permissions
    });

    # Handle result into two clean answers
    if ($ans==RET_OK) {
        return RET_OK;
    } else {
        return RET_ERROR;
    }
    
}

############################################
# A previous invoke to 'provide' event is completed
sub __xmpp_provided {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

}

############################################
# Return the workflow definition of a previously
# invoked workflow
sub __xmpp_workflow {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

    # Collect and validate info
    my $iid = $packet->{parameters}->{iid};
    log_msg("[$iid\@$packet->{from}] Workflow details request");
    return RET_ABORT unless defined($iid);
    return RET_ABORT unless defined($self->{INSTANCES}->{$iid});

    # Reply with the definition of the workflow
    Reply("comm_reply_to", $packet, {
        encode => 'json',
        data => {
            workflow => $self->{INSTANCES}->{$iid}->{WF}->DEFINITION
        }
    });
    
    # Return OK
    return RET_OK;
}

############################################
# Update heartbeat information
sub __xmpp_heartbeat {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

    # Collect and validate info
    my $iid = $packet->{parameters}->{iid};
    return RET_SYNTAXERR unless defined($iid);
    return RET_NOTFOUND unless defined($self->{INSTANCES}->{$iid});
    log_msg("[$iid\@$packet->{from}] Heartbeat");
    
    # Update workflow keepalive timer
    $self->{INSTANCES}->{$iid}->{Heartbeat} = time;
    log_debug("[$iid] REMOTE: Updated heartbeat timer of action ".$self->{INSTANCES}->{$iid}->{Action});
    
    # Return OK
    return RET_OK;
}

############################################
# A workflow we invoked is completed by a
# remote endpoint.
sub __xmpp_completed {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Collect and validate info
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $result = $packet->{parameters}->{result};
    log_msg("[$iid\@$packet->{from}] Action completed");
    
    # If this workflow is being observed, notify the observee
    $poe_kernel->yield('_succeed_observable', $iid, $result);

    # Finalize action
    if (defined($self->{INSTANCES}->{$iid})) {
        my $inst = $self->{INSTANCES}->{$iid};
        my $wf = $inst->{WF};
        my $context = $inst->{Context};
        
        log_debug("[$iid] REMOTE: Action completed. Entering GHOST state fom $inst->{State}.");
        
        # Update result
        $inst->{Result} = $result;
        
        # Release target
        my $index = $inst->{DID}.'::'.$inst->{Action};
        $self->target_release($index, $inst->{Target});
                
        # If we were waiting for such an event to complete, complete now
        # (If we went directly to COMPLETED from INVOKED, this means that was the last part
        # of the workflow and there is nothing to continue. Complete workflow...)
        if (($inst->{State} == STATE_WAIT) || ($inst->{State} == STATE_INVOKED)) {
            log_debug("[$iid] Entity is in WAIT state. Completing it");

            # Notify the success of a possibly observed ID
            $poe_kernel->yield('_succeed_observable', $inst->{IID}, $inst->{Result});

            # Inform interested parties that we are finished
            $poe_kernel->yield('_sendto', [ $wf->INVOKER, $wf->NOTIFY, $inst->{Observer} ], 'completed', {
                iid => $inst->{IID},
                did => $inst->{DID},
                aid => $inst->{AID},
                result => $inst->{Result}
            });
            
            # Inform everybody that the workflow is completed
            log_msg("[$inst->{DID}] REMOTE: Workflow ".$wf->NAME." completed");
            $self->cleanup_dirty($inst->{DID});
            Dispatch("workflow_completed", $inst->{IID}, $wf, $inst->{Result}, $context);
            
        } 

        # Switch to GHOST state that concludes
        # the remote invocation cycle.
        $self->{INSTANCES}->{$iid}->{State} = STATE_GHOST;
        $self->{INSTANCES}->{$iid}->{Heartbeat} = time();


    }
    
    # Continue
    return RET_OK;
    
}

############################################
# A workflow we invoked is failed as told
# by a remote endpoint.
sub __xmpp_failed {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Collect and validate info
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $result = $packet->{parameters}->{result};
    my $failure = $packet->{parameters}->{failure};
    log_msg("[$iid\@$packet->{from}] Action failed: $failure");

    # If this workflow is being observed, notify the observee
    $poe_kernel->yield('_fail_observable', $iid, $result, $failure);
    
    # Finalize action
    if (defined($self->{INSTANCES}->{$iid})) {
        my $inst = $self->{INSTANCES}->{$iid};
        my $wf = $inst->{WF};
        my $context = $inst->{Context};
        
        # Update result
        $inst->{Result} = $result;
        
        # Release target
        my $index = $inst->{DID}.'::'.$inst->{Action};
        $self->target_release($index, $inst->{Target});
                
        # If we were waiting for such an event to complete, complete now
        if ($inst->{State} == STATE_WAIT) {
            log_debug("[$iid] Entity is in WAIT state. Failing it");

            # Fail instance
            $inst->{State} = STATE_FAILED;
            $inst->{Failure} = $failure;
 
        }
    }
    
    # Continue
    return RET_OK;
    
}

############################################
# The workflow was successfully passed to a
# child of mine.
sub __xmpp_passed {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Validate parameters for progress
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $result = $packet->{parameters}->{result};
    log_msg("[$iid\@$packet->{from}] Endpoint took over the workflow");
    
    # If we have a local action on INVOKED state, switch to OBSERVING
    if (defined($self->{INSTANCES}->{$iid}) && ($self->{INSTANCES}->{$iid}->{State} == STATE_INVOKED)) {
        my $inst = $self->{INSTANCES}->{$iid};
        log_info("[$iid] REMOTE: Entering waiting state for this entity");
        
        # Put me in WAIT state, waiting for this action to finish
        $inst->{State} = STATE_WAIT;
        $inst->{Timeout} = time();
        
    }
    
    # Inform that a remotely invoked action has passed on the next step
    #$poe_kernel->yield('_step_remotely_invoked',$iid, $did, $result, $packet->{from}) 
    #    if defined($self->{INSTANCES}->{$iid});
    
    # Continue...
    return RET_OK;
}

############################################
# Handle lookup responses
sub __xmpp_lookup {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $id = $packet->{parameters}->{id};
    return RET_SYNTAXERR unless defined($id);
    return RET_NOTFOUND unless defined($self->{LOOKUPS}->{$id});
    
    my $state = $packet->{parameters}->{state};
    return RET_SYNTAXERR unless defined($state);

    # Update target state
    my $st = undef;
    if ($state eq 'busy') {
        $st = 0;
    } elsif ($state eq 'free') { 
        $st = defined($packet->{parameters}->{slots}) ? $packet->{parameters}->{slots} : 1;
    } elsif (($state eq 'provides') && (!defined($self->{INVALID_PROVIDERS}->{$packet->{from}}))) {
        $st = -1;
    }
    
    $self->{LOOKUPS}->{$id}->{Targets}->{$packet->{from}} = $st if (defined($st));

    log_msg("[$id\@$packet->{from}] Lookup response: $st free slots");

    # Update target state
    $self->targets_refresh($id);
    
    # Return OK
    return RET_OK;
    
}

############################################
# Respond to public discovery requests
sub __comm_pubsub_event {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $action = $packet->{data}->{action};
    my $context = $packet->{data}->{context};
    my $id = $packet->{data}->{id};
    my $permissions = { };
    return RET_PASSTHRU if ($packet->{from} eq $self->{ME});
    
    if ($packet->{action} eq 'lookup') {
        log_msg("[$id\@$packet->{from}] Public lookup request for action '$action'");

        # Ensure permissions
        if (Dispatch("permissions_get", $packet->{from}, $permissions) != RET_OK) { # Fetch permissions of the user
            log_warn("Unable to fetch permissions of user $packet->{from}!");
            return RET_ERROR;
        }

        # Validate my actions against he information we just received 
        my $ans = Dispatch("workflow_action_validate", $action, $context, $permissions);
        my $alloc_ans = Dispatch("workflow_action_provide", $action, $context, $permissions);

        # Respond only to specific cases
        if ($ans == RET_OK) { # We found a free slot

            # Get details on the specified action
            my $details = { };
            Dispatch("workflow_action_details", $action, $details);

            log_debug("[$id] Answering lookup request of $packet->{from} with: FREE (SLOTS=".($details->{MaxInstances} - $details->{Instances}).")");

            # Inform users
            $poe_kernel->yield('_sendto', [ $packet->{from} ], 'lookup', {
                id => $id,
                state => 'free',
                slots => $details->{MaxInstances} - $details->{Instances}
            });

        } elsif ($ans == RET_BUSY) { # Is valid, but busy

            log_debug("[$id] Answering lookup request of $packet->{from} with: BUSY");

            # Inform users
            $poe_kernel->yield('_sendto', [ $packet->{from} ], 'lookup', {
                id => $id,
                state => 'busy'
            });

        } elsif ($alloc_ans == RET_OK) { # We didn't have any action handler, but we do have an action allocator
        
            log_debug("[$id] Answering lookup request of $packet->{from} with: PROVIDES");

            # Inform users
            $poe_kernel->yield('_sendto', [ $packet->{from} ], 'lookup', {
                id => $id,
                state => 'provides'
            });
            
        }
        
    } elsif ($packet->{action} eq 'lookup_actions') {
        
    	# Process actions
    	my $ans = iAgent::Kernel::Query("workflow_actions_list");
    	my @actions;
    	foreach (@{$ans}) {
    	    push @actions, {
    	        required => $_->{RequiredParameters},
    	        name => $_->{Name},
    	        description => $_->{Description},
    	        module => $_->{Module}
    	    }
    	}

        # Send the actions
        Dispatch("comm_send", {
            to => $packet->{from},
            type => 'set',
            context => 'iagent:workflow',
            action => 'lookup_actions',
            parameters => { id => $id },
            encode => 'json',
            data => { actions => \@actions }
        });
        
    }
    
    # Otherwise do not respond AT ALL
    return RET_OK;
}

##===========================================================================================================================##
##                                                         LOGIC                                                             ##
##===========================================================================================================================##

############################################
# Main processing loop
sub ___loop {
############################################
    my $self = $_[ OBJECT ];
    my $time = time();

    #-------------------------------
    # Reset invalid providers
    #-------------------------------
    foreach (keys %{$self->{INVALID_PROVIDERS}}) {
        delete $self->{INVALID_PROVIDERS}->{$_} if ($time - $self->{INVALID_PROVIDERS}->{$_} > TIMEOUT_INVALID_PROVIDERS);
    }

    #-------------------------------
    # Process pending lookups stack
    #-------------------------------
    foreach (values %{$self->{LOOKUPS}}) {
        
        # Process scheduled entries that can be executed
        if (($_->{State} == STATE_SCHEDULED) && ((TIMESLOT_LOOKUP == 0) || (($time - $self->{LOOKUP_TIMEOUT}) > TIMESLOT_LOOKUP))) {
            log_debug("[$_->{IID}] Sending lookup request for action $_->{Action}");

            # Send a lookup request
            my $ans = Dispatch("comm_pubsub_publish", {
                node => get_action_node($_->{Action}),
                context => "iagent:workflow",
                action => 'lookup',
                data => {
                    action => $_->{Action},
                    context => $_->{Context},
                    id => $_->{IID}
                }
            });
            
            # Update lookup timer
            $self->{LOOKUP_TIMEOUT} = time();
            
            # Switch to blank
            $_->{State} = STATE_BLANK;
            $_->{Timeout} = time();
            
            # If we failed to peform a request, fail lookup
            $_->{State} = STATE_FAILED if ($ans != RET_OK);
            
        } 
        
        # Delete timed out information
        elsif (($_->{State} != STATE_SCHEDULED) && ($time - $_->{Timeout} > TIMEOUT_EXPIRE_LOOKUP)) {
            log_debug("[$_->{IID}] Deleting expired entry");
            
            # Delete expired information
            delete $self->{LOOKUPS}->{$_->{IID}};
            
        }
        
    }
        
    #-------------------------------
    # Process pending actions stack
    #-------------------------------
    foreach (values %{$self->{INSTANCES}}) {
        my $wf = $_->{WF};
        my $context = $_->{Context};
        my $permissions = $_->{Permissions};
        
        # A unique indexing ID used to address lookup information
        # (TODO: See FOOD FOR THOUGHT on the documentation for some things that might go wrong here)
        my $index = $_->{DID}.'::'.$_->{Action};
                    
        # [ SCHEDULED ] => RUN/FAILED
        # An action pending local execution. Check if we can start and start it
        # -------------------------------------------------------------------------------------
        if ($_->{State} == STATE_SCHEDULED) {
            
            # Only if we have a running slot enter the running state
            if ($self->{SLOTS} < MAX_ACTION_SLOTS) {
                log_debug("[$_->{IID}] Found free slot. Starting action");

                # If this workflow was invoked by us, send notifications
                if (defined($self->{LOCAL_FEEDBACK}->{$_->{DID}})) {
                    my $def = $self->{LOCAL_FEEDBACK}->{$_->{DID}};
                    if (!$def->{Started}) {
                        my $wf = $def->{WF};
                        $def->{Started}=1;

                        # Notify progress of the workflow
                        Dispatch("workflow_started", $wf, {
                            Target => undef
                        });
                        
                    }
                }
                
                # Put this action in the dirty stack so it can be cleaned up when the workflow finishes
                $self->{DIRTY_ACTIONS}->{$_->{DID}}=[ ] unless defined( $self->{DIRTY_ACTIONS}->{$_->{DID}} );
                push @{$self->{DIRTY_ACTIONS}->{$_->{DID}}}, {
                    Action => $_->{Action},
                    LogDir => $_->{LogDir},
                    Context => $context,
                    Permissions => $permissions,
                    ID => $_->{IID}
                };

                # Try to invoke the action
                my $ans = Dispatch("workflow_action_invoke", $_->{Action}, {
                    ID => $_->{IID},
                    LogDir => $_->{LogDir},
                    Context => $context,
                    Permissions => $permissions
                });

                # Check what happened
                if ($ans == RET_OK) { # Invoked successfully
                    log_msg("[$_->{IID}] LOCAL: Action $_->{Action} started");
                    
                    # Acquire slot
                    $self->{SLOTS}++;
                    
                    # Switch to running state
                    $_->{State} = STATE_RUN;
                    $_->{Timeout} = time(); # < Update timeout
                    
                    # Inform interested parties that we started
                    $poe_kernel->yield('_sendto', [ $wf->INVOKER, $wf->NOTIFY, $_->{Observer} ], 'started', {
                        iid => $_->{IID},
                        did => $_->{DID},
                        aid => $_->{AID}
                    });

                    
                # If the action was busy - for some weird reason - do nothing and let
                # this handler to be called again; hopefully then it's free
                } elsif ($ans == RET_BUSY) {
                    
                    # Only if we are told to go remotely on busy...
                    if ((FLAG_REMOTE_ON_BUSY == 1) && ($wf->ACTION->{distributed})) {

                        log_debug("[$_->{IID}] LOCAL: Action was busy, thinking of switching to remote mode");
                        
                        # If we don't have target definition fetch some...
                        if (!defined($self->{LOOKUPS}->{$index})) {
                            log_debug("[$_->{IID}] Placing lookup request");

                            # Place a lookup request
                            $self->targets_lookup($index, $_->{Action}, $_->{Context});

                        # If there are free remote slots for the action, switch to remote
                        } elsif ($self->{LOOKUPS}->{$index}->{State} == STATE_FREE) {
                            log_debug("[$_->{IID}] Going remote");
                            
                            # Switch to remote with me as an observer
                            $_->{State} = STATE_LOOKUP;
                            $_->{Observer} = $self->{ME};
                            
                        } else {
                            log_debug("[$_->{IID}] Staying local");                            
                            
                        }
                        
                        
                    } else {
                        
                        log_debug("[$_->{IID}] Local action was busy, will try again later");
                        next;
                        
                    }
                    
                # Otherwise something went wrong
                } else {
                    log_warn("[$_->{IID}] LOCAL: Error while trying to invoke the action! Result was $ans");

                    # Enter failed state
                    $_->{State} = STATE_FAILED;
                    $_->{Failure} = "Unable to invoke action $_->{Action}";
                    $_->{Result} = ERRNO_FAILED;

                }
                
                
            }
            
            # Check also for timed-out actions in RUN state
            if ((TIMEOUT_PENDING > 0) && ($time - $_->{Timeout} > TIMEOUT_PENDING)) {
                
                # Switch to failed state
                $_->{State} = STATE_FAILED;
                $_->{Failure} = "Waited for too long on PENDING state";
                $_->{Result} = ERRNO_TIMEOUT;

            }
            
        }
        
        # [ RUN ] => FAILED
        # Timeout an action that stays in RUN state for too long
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_RUN) {

            # Check for timed-out action
            if ((TIMEOUT_RUN > 0) && ($time - $_->{Timeout} > TIMEOUT_RUN)) {
                log_debug("$_->{AID}#[$_->{IID}] Action timed out at RUN state");

                # Release slot
                $self->{SLOTS}--;
                
                # Switch to failed state
                $_->{State} = STATE_FAILED;
                $_->{Failure} = "Waited for too long on RUN state";
                $_->{Result} = ERRNO_TIMEOUT;

            }
            
            # Send heartbeat signals every once in a while
            elsif ((TIMESPAN_HEARTBEAT > 0) && ($time - $_->{Heartbeat} > TIMESPAN_HEARTBEAT)) {
                log_debug("[$_->{IID}] Sending heartbeat");
                
                # Release slot
                $self->{SLOTS}--;

                # Reset heartbeat timer
                $_->{Heartbeat} = time();
                
                # Send heartbeat signal
                $poe_kernel->yield('_sendto', [ $wf->INVOKER, $wf->NOTIFY, $_->{Observer} ], 'heartbeat', {
                    iid => $_->{IID},
                    did => $_->{DID}
                });
                
            }

            # Abort workflow if it takes too long, according to workflow definition
            elsif ((defined($wf->ACTION->{timeout})) && ($time - $_->{Timeout} > $wf->ACTION->{timeout})) {
                log_debug("[$_->{IID}] Timed out according to workflow definition");
                
                # Abort instance (Synchronously)
                $poe_kernel->call($_[SESSION], '_abort_instance', $_->IID, ERRNO_TIMEOUT, "Timed out according to workflow definition!");
                
                # Check if the TimeOut handler exists
                if ($wf->fail('TO')) { # Yup, there is

                    # Switch to 'continue' state to run the next step in the workflow
                    $_->{State} = STATE_CONTINUE;
                    
                } else {
                    
                    # Otherwise, fail workflow

                    # Switch to 'continue' state to run the next step in the workflow
                    $_->{State} = STATE_FAILED;
                    $_->{Failure} = "Timed out according to workflow definition!";
                    $_->{Result} = ERRNO_TIMEOUT;
                    
                    # Release slot
                    $self->{SLOTS}--;
                    
                }
                
            }
            
        }

        # [ CONTINUE ] => DEAD ( + PENDING/PUSHING )
        # Execute the next step of the workflow
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_CONTINUE) {

            # Enter dead state
            $_->{State} = STATE_GHOST;
            $_->{Timeout} = time();
            
            # Are we finished?
            if ($wf->COMPLETED) {
                log_debug("[$_->{AID}#$_->{IID}] Action completed! Notifiying targets");
    
                # Notify the success of a possibly observed ID
                $poe_kernel->yield('_succeed_observable', $_->{IID}, $_->{Result});

                # Inform interested parties that we are finished
                $poe_kernel->yield('_sendto', [ $wf->INVOKER, $wf->NOTIFY, $_->{Observer} ], 'completed', {
                    iid => $_->{IID},
                    did => $_->{DID},
                    aid => $_->{AID},
                    result => $_->{Result}
                });
                
                # Inform everybody that the workflow is completed
                log_msg("[$_->{DID}] LOCAL: Workflow ".$wf->NAME." completed");
                $self->cleanup_dirty($_->{DID});
                Dispatch("workflow_completed", $_->{IID}, $wf, $_->{Result}, $context);
                
            } else {
                log_debug("[$_->{AID}#$_->{IID}] Action has more stuff to do. Scheduling children from action ".$wf->ACTIVE);
                my $inst = $wf->INSTANCES;
                
                # Inform interested parties that we spawning children this step
                $poe_kernel->yield('_sendto', [ $wf->INVOKER, $wf->NOTIFY, $_->{Observer} ], 'passed', {
                    iid => $_->{IID},
                    did => $_->{DID},
                    aid => $_->{AID},
                    children => scalar @$inst,
                    result => $_->{Result}
                });
                
                # Invoke all the workflow instances this action will generate
                my $children = { };
                my $myiid = $_->{IID};
                foreach my $I (@$inst) {
                    $children->{$I->IID} = $I; # Store child instance
                    $self->{OBSERVABLES}->{$I->IID} = $myiid; # Store observable
                    $poe_kernel->yield('workflow_invoke', $I, $permissions, ''); # << ''=Internally used
                }
                $_->{Children} = $children;
                
                # Enter observing state. In observing state we are waiting
                # for 'complete' message from all of our children and when
                # every message is collected, we notify the parent
                log_info("[$_->{IID}] Entering observing state with ".scalar(@$inst)." children");
                $_->{State} = STATE_OBSERVE;
                $_->{Timeout} = time();
                
            }
            
        }

        # [ RUN_FAILED ] => DEAD 
        # Notify observer that we are completed and enter PUSH state
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_FAILED) {
            log_debug("[$_->{AID}#$_->{IID}] Action failed. Reason: $_->{Failure}");
            
            # Fail workflow and check if there was an 'F' rule
            if ($wf->fail()) { # Yup, there is
                log_debug("[$_->{IID}] Workflow can compensate. Resuming from there");
                
                # Switch to 'continue' state to run the next step in the workflow
                $_->{State} = STATE_CONTINUE;
                
            } else {
                log_debug("[$_->{IID}] Workflow cannot compensate. Failing");

                # Inform interested parties that we failed to complete
                $poe_kernel->yield('_sendto', [ $wf->INVOKER, $wf->NOTIFY, $_->{Observer} ], 'failed', {
                    iid => $_->{IID},
                    did => $_->{DID},
                    aid => $_->{AID},
                    result => $_->{Result},
                    failure => $_->{Failure}
                });
        
                # And die
                $_->{State} = STATE_GHOST;
                $_->{Timeout} = time();

                # Notify the failure of the observable
                $poe_kernel->yield('_fail_observable', $_->{IID}, $_->{Result}, $_->{Failure});                                

                # Inform everybody that the workflow has died
                $self->cleanup_dirty($_->{DID});
                Dispatch("workflow_failed", $_->{IID}, $wf, $_->{Result}, $wf->{Context}, $_->{Failure});
                
            }

        }
        
        
        # [ LOOKUP ] => INVOKED
        # Lookup for somebody to handle this workflow
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_LOOKUP) {
            
            # If there are no lookup information, request a lookup now
            if (!defined($self->{LOOKUPS}->{$index})) {
                log_debug("[$_->{IID}] Placing lookup request");
                
                # Place a lookup request
                $self->targets_lookup($index, $_->{Action}, $_->{Context});
            
            # Unable to place lookup request -> Fail workflow
            } elsif ($self->{LOOKUPS}->{$index}->{State} == STATE_FAILED) {
                
                log_debug("[$_->{IID}] Lookup failed!");
                
                $_->{State} = STATE_FAILED;
                $_->{Failure} = "Unable to place a public lookup request!";
                $_->{Result} = ERRNO_INTERNAL;
                
            # TODO: Add 'Can invoke' state -> Will pause discovery

            # Wait until we have a free target
            } elsif ($self->{LOOKUPS}->{$index}->{State} == STATE_FREE) {
                
                # Acquire the free slot
                my $target = $self->target_pick($index);
                log_debug("[$_->{IID}] Picked lookup target $target");
                
                # Try to invoke the action
                $_->{Target} = $target;
                my $ans = Dispatch("comm_send_action", {
                    to => $target,
                    context => "iagent:workflow",
                    action => "invoke",
                    type => 'set',
                    encode => 'json',
                    data => {
                        workflow => $wf->DEFINITION
                    }
                });
                
                # If we failed to invoke, mark this target as invalid and
                # try again with other target.
                if ($ans != RET_OK) {
                    log_warn("[$_->{IID}] REMOTE: Action ".$wf->ACTION->{action}." failed to be invoked on target $target. Will retry with another");
                    
                    # Mark target as invalid
                    $self->target_fail($index, $target);
                    
                    # (And retry)
                    
                } else {
                    log_msg("[$_->{IID}] REMOTE: Action ".$wf->ACTION->{action}." invoked on target $target successfully");
                    
                    # Reset retries
                    $_->{LookupRetries} = 0;

                    # Otherwise enter INVOKED state
                    $_->{State} = STATE_INVOKED;
                    $_->{Timeout} = time();
                    $_->{Heartbeat} = time();
                    
                }

            # Ask provider for a new entity if we found a provider and the workflow could not pick
            # anybody else for some time.
            } elsif (($self->{LOOKUPS}->{$index}->{State} == STATE_PROVIDED) && ($time - $_->{Timeout} > TIMEOUT_ASK_PROVIDER)) {

                # Acquire the free slot
                my $target = $self->target_pick($index);
                log_debug("[$_->{IID}] Picked provided target $target");

                # Request action provision
                $_->{Target} = $target;
                my $ans = Dispatch("comm_send_action", {
                    to => $target,
                    context => "iagent:workflow",
                    action => 'provide',
                    type => 'set',
                    encode => 'json',
                    data => {
                        workflow => $wf->DEFINITION
                    }
                });

                # Check provision result
                if ($ans != RET_OK) {

                    log_warn("Could not request provision of action $_->{Action} on target $target");

                    # Mark the provider as invalid so we don't pick him again within
                    # a timeout
                    $self->{INVALID_PROVIDERS}->{$target} = time();

                    # Update availability (action provider target was removed)
                    $self->targets_refresh($index);

                    # (And retry with other targets)

                } else {

                    log_msg("[$_->{IID}] Action is under provision by $target");

                    # Enter lookup mode again
                    log_debug("[$_->{IID}] Resetting lookup state");
                    
                    # Reset retries
                    $_->{LookupRetries} = 0;

                    # Otherwise enter PROVIDING state
                    log_debug("[$_->{IID}] Entering providing state");
                    $_->{State} = STATE_PROVIDING;
                    $_->{Timeout} = time();
                    $_->{Heartbeat} = time();                   

                }
                            
            # Also, fail if waited for too long but still the lookup records are blank
            } elsif (($self->{LOOKUPS}->{$index}->{State} == STATE_BLANK) && ($time - $_->{Timeout} > TIMEOUT_LOOKUP)) {
                log_debug("[$_->{IID}] REMOTE: Timed out while waiting for lookup response");
                my $retries = ++$_->{LookupRetries}; # Calculate retires
                
                # No free target was detected after waiting for some time for response.

                # Check if such timeout handler exists in the workflow definition
                if (defined($wf->ACTION->{route}->{TL}) && ($retries > MAX_RETRY_LOOKUP)) {
                    log_debug("[$_->{IID}] REMOTE: Timed out while waiting for lookup response, but handled by the workflow");
                    
                    # Trigger/Switch to that failure handler
                    $wf->fail('TL');

                    # Switch to 'continue' state to run the next step in the workflow
                    $_->{State} = STATE_CONTINUE;
                    
                }
                
                # Check if we can retry the lookup procedure or if we must fail
                elsif ($retries > MAX_RETRY_LOOKUP) {
                    log_warn("[$_->{IID}] REMOTE: Unable to locate a target that can pick this workflow within time!");
                
                    $_->{State} = STATE_FAILED;
                    $_->{Failure} = "Unable to locate a target that can pick this workflow within time!";
                    $_->{Result} = ERRNO_TIMEOUT;
                
                } 
                
                # Otherwise rest and retry
                else {
                    log_debug("[$_->{IID}] Resetting lookup state");
                
                    # Put back to lookup state
                    $_->{State} = STATE_LOOKUP;
                    $_->{Timeout} = time();
                
                    # And reset current lookup information
                    delete $self->{LOOKUPS}->{$index};
                
                }
                
                
            }
            
        }

        # [ STATE_PROVIDING ] => STATE_LOOKUP 
        # Notify observer that we are completed and enter PUSH state
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_PROVIDING) {
            
            # Check for timed-out action
            if ((TIMEOUT_PROVIDE > 0) && ($time - $_->{Timeout} > TIMEOUT_PROVIDE)) {
                log_warn("Provider '$_->{Target}' did not allocate instance for action '$_->{Action}' within time");

                # Mark the provider as invalid so we don't pick him again within
                # a timeout
                $self->{INVALID_PROVIDERS}->{$_->{Target}} = time();

                # Update availability (action provider target was removed)
                $self->targets_refresh($index);
                                
                # Switch back to lookup mode
                $_->{State} = STATE_LOOKUP;
                $_->{Timeout} = time();
            
                # And reset current lookup information
                delete $self->{LOOKUPS}->{$index};
                
            }
    
        }
        
        # [ INVOKED ] => FAILED
        # Timeout an action that stays in INVOKED state for too long
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_INVOKED) {

            # Check for timed-out action
            if ((TIMEOUT_INVOKED > 0) && ($time - $_->{Timeout} > TIMEOUT_INVOKED)) {
                log_debug("[$_->{IID}] Timed out on INVOKED state");

                # Release target
                $self->target_release($index, $_->{Target});
                
                # Switch to failed state
                $_->{State} = STATE_FAILED;
                $_->{Failure} = "Waited for too long on INVOKED state";
                $_->{Result} = ERRNO_TIMEOUT;
                
            }
            
            # Check for keepalive timeout
            elsif ((TIMEOUT_HEARTBEAT > 0) && ($time - $_->{Heartbeat} > TIMEOUT_HEARTBEAT)) {
                log_warn("[$_->{IID}] REMOTE: Did not receive heartbeat within expected time");
                
                # If the target information are still in lookup cache, mark the target as invalid
                # so we don't pick that again.
                $self->target_fail($index, $_->{Target});
                
                # Check if this action has exhausted it's maximum number of retries
                if (++$_->{InvokeRetries} > MAX_RETRY_INVOKE) {

                    $_->{State} = STATE_FAILED;
                    $_->{Failure} = "Maximum retries reached because remote agent did not send heartbeat signals in time!";
                    $_->{Result} = ERRNO_TIMEOUT;
                    
                } else {
                    
                    # Place action back in lookup state
                    $_->{State} = STATE_LOOKUP;
                    $_->{Timeout} = time();
                    
                }
                
            }
            
        }

        # [ PASSED ] => DEAD
        # We have successfully passed the action to the remote endpoint.
        # Now it's time to enjoy a peaceful death....
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_PASSED) {
            log_debug("[$_->{IID}] Workflow passed to remote endpoint successfully. Ghosting");
            
            $_->{State} = STATE_GHOST;
            $_->{Timeout} = time();

        }

        # [ OBSERVE ] => COMPLETED/FAILED
        # We have passed
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_OBSERVE) {
            
            # If all of my children are completed, notify my observer
            if (scalar values %{$_->{Children}} == 0) {
                log_debug("[$_->{IID}] Observation completed");

                # Notify the success of a possibly observed ID
                $poe_kernel->yield('_succeed_observable', $_->{IID}, $_->{Result});
                
                # If we were ovserving a 'fork' workflow node, we might
                # want to do something upon completion of the workflow
                if ($wf->ACTION->{type} eq 'fork') {

                    # TODO: Not throway thought :/

                    # Inform interested parties that we finished
                    $poe_kernel->yield('_sendto', [ $wf->{WF}->INVOKER, $wf->{WF}->NOTIFY ], 'finished', {
                        iid => $_->{IID},
                        did => $_->{DID},
                        aid => $wf->ACTIVE,
                        result => $_->{RESULT}
                    });

                    # Update workflow information
                    log_msg("[".$_->{IID}."] FORK Action ".$_->{Action}." completed with result ".$_->{Result});
                    $wf->completed($_->{Result});

                    # Put workflow in continue state
                    $_->{State} = STATE_CONTINUE;
                    
                } 
                
                # Otherwise, a common workflow action is now completed
                else {
                
                    # Inform interested parties that we are finished
                    $poe_kernel->yield('_sendto', [ $wf->INVOKER, $wf->NOTIFY, $_->{Observer} ], 'completed', {
                        iid => $_->{IID},
                        did => $_->{DID},
                        aid => $_->{AID},
                        result => $_->{Result}
                    });
                
                    # And enter ghost state
                    $_->{State} = STATE_GHOST;

                    # Inform everybody that the workflow is completed
                    log_msg("[$_->{DID}] REMOTE: Workflow ".$wf->NAME." completed");
                    $self->cleanup_dirty($_->{DID});
                    Dispatch("workflow_completed", $_->{IID}, $wf, $_->{Result}, $context);

                }
                
            }

            # Check for keepalive timeout
            elsif ((TIMEOUT_OBSERVE > 0) && ($time - $_->{Timeout} > TIMEOUT_OBSERVE)) {
                log_warn("[$_->{IID}] REMOTE: Waited for too long on OBSERVED state");
                
                # Switch to failed state
                $_->{State} = STATE_FAILED;
                $_->{Failure} = "Waited for too long on OBSERVED state";
                $_->{Result} = ERRNO_TIMEOUT;
                
                # Abort remaining child instances
                foreach (values %{$_->{Children}}) {
                    $poe_kernel->yield('_abort_instance', $_->IID, $_->{Result}, $_->{Failure});
                    delete $self->{OBSERVABLES}->{$_};
                }
                $_->{Children}={};
                
            }
            
        }
        
        # [ WAIT ] => DEAD
        # We have just invoked a remote action and it succeeded. We are now just waiting for
        # it to finish in order to notify any possible observer.
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_WAIT) {

            # Timeout if we are waiting for toooo long 
            if ((TIMEOUT_OBSERVE > 0) && ($time - $_->{Timeout} > TIMEOUT_OBSERVE)) {
                log_warn("[$_->{IID}] REMOTE: Waiting for WAIT feedback for too long");
                
                # Switch to failed state
                $_->{State} = STATE_FAILED;
                $_->{Failure} = "Waited for too long on WAIT state";
                $_->{Result} = ERRNO_TIMEOUT;
                
            }

        }

        
        # [ GHOST ] => DEAD
        # We need to state at GHOST state for a couple of seconds to let users query us
        #      .--. 
        #     /..  \
        #     \ o  /
        #     /    \
        #    /      \
        #   (/      \)
        #    |      \ 
        #     \      '._
        #      '._      '-.
        #         `'- ,~- _.`
        # -------------------------------------------------------------------------------------
        elsif (($_->{State} == STATE_GHOST) && (TIMEOUT_GHOST > 0) && ($time - $_->{Timeout} > TIMEOUT_GHOST)) {
            log_debug("[$_->{IID}] Ghost timed out. Entering dead state");
                         
            # Schedule for reap...
            $_->{State} = STATE_DEAD;
            
        }

        # [ DEAD ] => *DEAD*
        # Yup... the grim reaper is here for you..
        #                    ,____
        #                    |---.\
        #            ___     |    `
        #           / .-\  ./=)
        #          |  |"|_/\/|
        #          ;  |-;| /_|                     .--.
        #         / \_| |/ \ |                    /  ..\
        #        /      \/\( |               ____.'  _o/
        #        |   /  |` ) |              '--.     |.__
        #        /   \ _/    |             _.-'     /--'
        #       /--._/  \    |        _.--'        /
        #       `/|)    |    /       ~'--....___.-' 
        #         /     |   |
        #       .'      |   |
        #      /         \  |
        #     (_.-.__.__./  /
        #
        # -------------------------------------------------------------------------------------
        elsif ($_->{State} == STATE_DEAD) {
            
            # Reap that instance....
            delete $self->{INSTANCES}->{$_->{IID}};
            log_debug("DELETED: ".$wf->IID);
            
        }
        
    }
    
    # Continue loop
    $poe_kernel->delay('_loop' => LOOP_SPEED);
    
}

=head1 FOOD FOR THOUGHT

(Here are some thoughts regarding the lookup mechanism. You will find the refered part of the code if you search
for 'TODO: See FOOD FOR THOUGHT' )

The whole purpose of the LOOKUPS hash and the whole lookup state
is to fetch as much information as possible from all the endpoints that can are capable to handle the
action in order to avoid re-requesting lookup information and thus polluting the public channel.

Now, in order to pile up responses in the same lookup hash we need an indexing key right?. Ideally we 
will could use the action name... This will do the following:

 - We request "Who can handle 'Action'"
 - We pile all the responses under the same 'Action'
 - We pick the first available target
 - If somebody else wants to handle this action, we pick the next available from the same pile, etc...

This sounds very nice, but there is something important. We are not requesting "Who can handle 'Action'"
but we are requesting "Who can handle 'Action' under context { context }"!

This means that if the context of an action is invalid the endpoint will not respond at all! (And thus if we
try to invoke this action again and we use the cached information we are going to miss those targets that 
might not fail this time).

How to include all of them? Without polluting the public message bus?? What would be the ideal index???

A not-so-good solution will be to use the workflow definition ID (Which is generated once by the first invoking
node) PLUS the action name. This is GOOD because usually when an entity rejects the action's context it will
keep rejecting it for the entire workflow. It is BAD, because of the 'usually' in the previous sentence...

If you have a better idea... go for it!

=cut

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;