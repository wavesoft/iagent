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

Module::WorkflowServer - Workflow management server

=head1 DESCRIPTION

This module provides an autonomous agent that is capable of storing, invoking 
and monitoring workflows.

=cut

# Core definitions
package Module::WorkflowServer;

use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use POE;
use Data::Dumper;
use DBI;
use Module::Workflow::Definition;
use Date::Format;
use HTML::Entities;
use JSON;
use Data::UUID;
use iAgent::DB;

sub WORKFLOW_NODE               { "/iagent/workflow"; } # The base name of the pub/sub node that will be used as the public message bus

our $MANIFEST = {
    oncrash => 'die',

    config => 'workflowserver.conf',

    # CLI bindings
    CLI => {

        "wf/define" => {
            message => 'cli_define',
            options => [ 'file=s' ],
            description => "Define a workflow from file",
        },
        "wf/start" => {
            message => 'cli_invoke',
            options => [ 'name=s' ],
            description => "Invoke a previously defined workflow",
        }

    },

        
    # External communication
    XMPP => {

        # Context
        "iagent:workflow" => {

            "set" => { 

                    # Feedback from an invoked workflow
                    "started"           => "xmpp_started",
                    "passed"            => "xmpp_passed",
                    "completed"         => "xmpp_completed",
                    "abort"             => "xmpp_abort",
                    "failed"            => "xmpp_failed",
                    "lookup_actions"    => "xmpp_lookup_actions",
                    "finished"          => "xmpp_finished",
                    
                    # UI Bindings
                    "remove_definition" => {
                        message => "xmpp_ui_remove_definition",
                        parameters => [ 'wid' ]
                    },
                    "remove_instance" => {
                        message => "xmpp_ui_remove_instance",
                        parameters => [ 'did' ]
                    },
                    "definition_script" => {
                        message => "xmpp_ui_set_definition",
                        parameters => [ 'wid' ]
                    },
                    "definition_new" => {
                        message => "xmpp_ui_new_definition"
                    },
                    "definition_invoke" => {
                        message => "xmpp_ui_invoke",
                        parameters => [ 'wid' ]
                    }
                    
            },
            
            "get" => {
            
                "definitions" => {
                    message => 'xmpp_ui_definitions'
                },
                "definition_script" => {
                    message => "xmpp_ui_get_definition",
                    parameters => [ 'wid' ]
                },
                "statusall" => {
                    message => 'xmpp_ui_statusall'
                },
                "invoke_fields" => {
                    message => 'xmpp_ui_fields',
                    parameters => [ 'wid' ]
                },
                "status" => {
                    message => 'xmpp_ui_status',
                    parameters => [ 'wid' ]
                },
                "actionslist" => {
                    message => 'xmpp_ui_actionslist'
                }
                
            }
            
        }
        
    }
    
};


############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { 
        config => $config,
        me => '',
        
        PENDING_ACTION_LOOKUPS =>   { }  # Lookups that are pending collection
    };
    $self = bless $self, $class;

    # Initialize DB
    $self->db_init();
    
    return $self;
}

############################################
# Grab my JID from the comm_ready event
sub __comm_ready {
############################################
    my ($self, $me) = @_[ OBJECT, ARG0 ];
    $self->{me} = $me;

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
    
    return RET_OK;
}

############################################
# Initialize database
sub db_init {
############################################
    my ($self) = @_;
    my $dbh = DB;
    if (!$dbh) {
       	iAgent::Kernel::Crash("Unable to initialize database!");
       	return;
    }
    
    # Store DBH instance
    $self->{dbh} = $dbh;
    
    # Create missing tables
    $dbh->do("CREATE TABLE IF NOT EXISTS workflow_definitions (
	     wid            INTEGER PRIMARY KEY,
	     name           VARCHAR(120),
	     maxdepth       INTEGER,
	     description    TEXT,
	     script         TEXT
    )");

    $dbh->do("CREATE TABLE IF NOT EXISTS workflow_instances (
	     did            VARCHAR(64) PRIMARY KEY,
	     rootiid        VARCHAR(64),
	     wid            INTEGER,
	     status         VARCHAR(60) DEFAULT 'pending',
	     started        INTEGER,
	     updated        INTEGER,
	     curraction     INTEGER,
	     message        TEXT,
	     result         INTEGER
    )");

    $dbh->do("CREATE TABLE IF NOT EXISTS workflow_actions (
	     iid            VARCHAR(64) PRIMARY KEY,
	     did            VARCHAR(64),
	     wid            INTEGER,
	     aid            INTEGER,
	     target         VARCHAR(120),
	     status         VARCHAR(60) DEFAULT 'running',
	     result         INTEGER,
	     started        INTEGER,
	     updated        INTEGER,
	     message        TEXT
    )");

}
##===========================================================================================================================##
##                                             REMOTE ENDPOINT NOTIFICATIONS                                                 ##
##===========================================================================================================================##

############################################
# A workflow was aborted 
sub __xmpp_abort {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $aid = $packet->{parameters}->{aid};
    my $from = $packet->{from};
    my $failure = ($packet->{parameters}->{failure} or "Aborted by user");
    
    # Update database records
    my ($found) = $self->{dbh}->selectrow_array("SELECT COUNT(*) FROM workflow_actions WHERE iid = ?", undef, $iid);
    if (!$found) {
        my ($wid) = $self->{dbh}->selectrow_array("SELECT wid FROM workflow_instances WHERE did = ?", undef, $did);
        $self->{dbh}->do("REPLACE INTO workflow_actions ( did,wid,aid,target,started,updated,iid ) VALUES (?,?,?,?,?,?,?)", undef, 
                            $did,$wid,$aid,$from,time(),time(),$iid);
    }

    $self->{dbh}->do("UPDATE workflow_actions SET status = ?, result = ? , message = ? WHERE iid = ?", undef, 
                        'aborted', -1, $failure, $iid);
    $self->{dbh}->do("UPDATE workflow_instances SET status = ?, result = ?, message = ? WHERE did = ?", undef, 
                        'aborted', -1, $failure, $did);

    # Return OK
    return RET_OK;
}

############################################
# The workflow has completed 
sub __workflow_completed {
############################################
    my ($self, $iid, $wf, $result) = @_[ OBJECT, ARG0, ARG1, ARG2 ];
    my $did = $wf->DID;

    log_error("COMPLETED: DID=$did, IID=$iid");

    $self->{dbh}->do("UPDATE workflow_actions SET status = ?, updated = ?, result = ? WHERE iid = ?", undef, 
                        'completed', time(), $result, $iid);

    $self->{dbh}->do("UPDATE workflow_instances SET status = ?, updated = ? WHERE did = ?", undef, 
                        'completed', time(), $did);

    # Return OK
    return RET_OK;
}

############################################
# An action has started 
sub __xmpp_started {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $aid = $packet->{parameters}->{aid};
    my $from = $packet->{from};

    # Update database records
    my ($wid) = $self->{dbh}->selectrow_array("SELECT wid FROM workflow_instances WHERE did = ?", undef, $did);
    $self->{dbh}->do("REPLACE INTO workflow_actions ( did,wid,aid,target,started,updated,iid ) VALUES (?,?,?,?,?,?,?)", undef, 
                        $did,$wid,$aid,$from,time(),time(),$iid);
    $self->{dbh}->do("UPDATE workflow_instances SET status = ?, curraction = ?, updated = ? WHERE did = ? AND status != 'completed'", undef, 
                        'running', $aid, time(), $did);

    # Return OK
    return RET_OK;
}

############################################
# A workflow was completed 
sub __xmpp_completed {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $aid = $packet->{parameters}->{aid};
    my $result = $packet->{parameters}->{result};
    my $from = $packet->{from};

    # TODO: Update DB
    my ($found) = $self->{dbh}->selectrow_array("SELECT COUNT(*) FROM workflow_actions WHERE iid = ?", undef, $iid);
    if (!$found) {
        my ($wid) = $self->{dbh}->selectrow_array("SELECT wid FROM workflow_instances WHERE did = ?", undef, $did);
        $self->{dbh}->do("REPLACE INTO workflow_actions ( did,wid,aid,target,started,updated,iid ) VALUES (?,?,?,?,?,?,?)", undef, 
                            $did,$wid,$aid,$from,time(),time(),$iid);
    }
    
    $self->{dbh}->do("UPDATE workflow_actions SET status = ?, updated = ?, result = ? WHERE iid = ?", undef, 
                        'completed', time(), $result, $iid);

    # If that was the root IID, finalize the workflow
    $self->{dbh}->do("UPDATE workflow_instances SET status = ?, curraction = 0, updated = ?, result = ? WHERE rootiid = ?", undef, 
                        'completed', time(), $result, $iid);
                        
    # Return OK
    return RET_OK;
}

############################################
# A workflow was failed 
sub __xmpp_failed {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $aid = $packet->{parameters}->{aid};
    my $result = $packet->{parameters}->{result};
    my $failure = $packet->{parameters}->{failure};
    my $from = $packet->{from};

    # Update database records
    my ($found) = $self->{dbh}->selectrow_array("SELECT COUNT(*) FROM workflow_actions WHERE iid = ?", undef, $iid);
    if (!$found) {
        my ($wid) = $self->{dbh}->selectrow_array("SELECT wid FROM workflow_instances WHERE did = ?", undef, $did);
        $self->{dbh}->do("REPLACE INTO workflow_actions ( did,wid,aid,target,started,updated,iid ) VALUES (?,?,?,?,?,?,?)", undef, 
                            $did,$wid,$aid,$from,time(),time(),$iid);
    }

    $self->{dbh}->do("UPDATE workflow_actions SET status = ?, result = ? , message = ? WHERE iid = ?", undef, 
                        'failed', $result, $failure, $iid);
                        
    my ($state) = $self->{dbh}->selectrow_array("SELECT status FROM workflow_instances WHERE did = ?", undef, $did);
    if ($state ne 'failed') {
        $self->{dbh}->do("UPDATE workflow_instances SET status = ?, result = ?, message = ?, curraction = 0 WHERE did = ?", undef, 
                            'errors', $result, $failure, $did);
    }

    # Return OK
    return RET_OK;
}

############################################
# A workflow was passed to another entity 
sub __xmpp_passed {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $result = $packet->{parameters}->{result};
    my $from = $packet->{from};

    # TODO: Update DB
    return RET_OK;
}

############################################
# The action was runned and finished
sub __xmpp_finished {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $iid = $packet->{parameters}->{iid};
    my $did = $packet->{parameters}->{did};
    my $aid = $packet->{parameters}->{aid};
    my $result = $packet->{parameters}->{result};
    my $from = $packet->{from};

    # Update database records
    $self->{dbh}->do("UPDATE workflow_actions SET status = ?, result = ? , message = ? WHERE iid = ?", undef, 
                        'finished', $result, '', $iid);

    # Return OK
    return RET_OK;
}

##===========================================================================================================================##
##                                              BINDINGS TO WORKFLOW INVOKER                                                 ##
##===========================================================================================================================##

########################################### 
# Workflow started
sub __workflow_started {
########################################### 
	my ($self, $wf) = @_[ OBJECT, ARG0 ];
	
	$self->{dbh}->do("UPDATE workflow_instances SET updated = ?, status = ? WHERE did = ? AND status != 'completed'", undef,
	        time(), 'running', $wf->DID
	    );
	
	# We are just observers.. passthru..
	return RET_PASSTHRU;
}

########################################### 
# Workflow started
sub __workflow_failed {
########################################### 
    my ($self, $iid, $wf, $result, $failure) = @_[ OBJECT, ARG0, ARG1, ARG2, ARG4 ];
    my $did = $wf->DID;

    log_error("FAILED: DID=$did, IID=$iid");

    $self->{dbh}->do("UPDATE workflow_actions SET status = ?, updated = ?, message = ?, result = ? WHERE iid = ?", undef, 
                        'failed', time(), $failure, $result, $iid);

    $self->{dbh}->do("UPDATE workflow_instances SET status = ?, updated = ?, message = ?, curraction = 0 WHERE did = ?", undef, 
                        'failed', time(), $failure, $did);	
                    
	# We are just observers.. passthru..
	return RET_PASSTHRU;
}

##===========================================================================================================================##
##                                                  HELPER FUNCTIONS                                                         ##
##===========================================================================================================================##

sub register_workflow {
    my ($self, $workflow) = @_;

    # Build serialized script
    return RET_ERROR if ((!UNIVERSAL::isa($workflow, 'HASH')) && (!UNIVERSAL::isa($workflow, 'Module::Workflow::Definition')));
        
    # Create a workflow object (used for calculations)
    my $w = new Module::Workflow::Definition($workflow);
    my $def = $w->DEFINITION;
    my $script = Dumper($w);
    $script =~ s/.*bless/bless/;

    # Create instance
    my $sth = $self->{dbh}->prepare("INSERT INTO workflow_definitions ( name, maxdepth, description, script ) VALUES ( ?, ?, ?, ? )");
    return RET_ERROR if(!$sth);
    return RET_ERROR if (!$sth->execute(
        $w->NAME,
        $w->depth(1),
        $workflow->{DESCRIPTION},
        $script
    ));

    # Return OK
    return RET_OK;    
}

sub start_workflow {
    my ($self, $id, $parameters) = @_;
    my $row = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_definitions WHERE wid = $id");
    return RET_ABORT unless($row);
    
    # Fetch definition
    my $w = eval($row->{script}); # !!!!!!! TODO: UNSAFE !!!!!!!
    return RET_ERROR unless(UNIVERSAL::isa($w, 'Module::Workflow::Definition'));
    $w->new_did;
    $w->new_iid;
    
    # Validate that the provided parameters are ok
    return RET_INCOMPLETE unless ($w->init_context($parameters));
    
    # Add my JID on the notification targets
    $w->notify($self->{me});
    
    # Try to invoke the workflow and see what happens
    my $ans =  iAgent::Kernel::Dispatch("workflow_invoke", $w, $self->{ME});
    return $ans unless ($ans == RET_OK);
    
    # Create an instance definition
    $self->{dbh}->do("INSERT INTO workflow_instances (did, rootiid, wid, status, started, updated, curraction) 
                                              VALUES (?,?,?,'pending',?,?,?)", undef,
        $w->DID, $w->IID, $id, time(), time(), $w->ACTIVE
    );
    
    # OK!
    return RET_OK;    
}

##===========================================================================================================================##
##                                                    CLI BINDINGS                                                           ##
##===========================================================================================================================##

############################################
# Invoke a workflow
sub __cli_define {
############################################
    my ($self, $cmd) = @_[ OBJECT, ARG0 ];

    # Check if the file is loading
    my $file = $cmd->{options}->{file};
    if (!-f $file) {
        iAgent::Kernel::Dispatch("cli_error", "The specified file: $file was not found!");
        return RET_ERROR;
    }

    # Get the workflow definition from file
    my $def=undef;
	eval {
        $def = require($cmd->{options}->{file});
    };
	if ($@) {
        iAgent::Kernel::Dispatch("cli_error", "Error while parsing $file: $@");
        return RET_ERROR;
    };

    # Validate definition
    if (ref($def) ne 'HASH') {
        iAgent::Kernel::Dispatch("cli_error", "The specified definition is not in expected format!");
        return RET_ERROR;
    }
    
    # Register workflow
    return RET_ERROR unless($self->register_workflow($def) == RET_OK);
    return RET_COMPLETED;

}

############################################
# Invoke a workflow
sub __cli_invoke {
############################################
    my ($self, $cmd) = @_[ OBJECT, ARG0 ];
    
    # Lookup id from the name
    my $name = $cmd->{options}->{name};
    my $row = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_definitions WHERE name = ?", undef, $name);
    return RET_ABORT unless($row);
    my $id = $row->{wid};
    
    Reply("cli_write", "Starting workflow '$name' (definition id #$id)");
    if ($self->start_workflow($id,{ }) == RET_OK) {
        return RET_COMPLETED;
    } else {
        return RET_ABORT;
    }

}

##===========================================================================================================================##
##                                                XMPP FEEDBACK HANDLERS                                                     ##
##===========================================================================================================================##

############################################
# Actions lookup response
sub __xmpp_lookup_actions {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $actions = $packet->{data}->{actions};
    my $uid = $packet->{parameters}->{id};
    
    # Validate
    map { log_msg($_) } split("\n",Dumper($packet->{data}));
    return RET_ERROR if (!defined($uid));
    return RET_ERROR if (!defined($actions));
    return RET_OK if (!defined($self->{PENDING_ACTION_LOOKUPS}->{$uid}));
    
    # Fetch stored record
    my $rec = $self->{PENDING_ACTION_LOOKUPS}->{$uid};
    
    # Merge actions
    foreach (@$actions) {
        $rec->{actions}->{$_->{name}} = $_;
    }
    
    # Update timer
    POE::Kernel->alarm_remove($rec->{timer});
    $rec->{timer}=POE::Kernel->delay_set('xmpp_ui_actionslist_reply', 2, $uid);
    
    # Return OK
    return RET_OK;
    
}

############################################
# Reply the actions collected so far
sub __xmpp_ui_actionslist_reply {
############################################
    my ($self, $uid) = @_[ OBJECT, ARG0 ];
    
    # Pop the specified record
    my $rec = $self->{PENDING_ACTION_LOOKUPS}->{$uid};
    delete $self->{PENDING_ACTION_LOOKUPS}->{$uid};
    
    # Send response
    my @actions = values(%{$rec->{actions}});
    Dispatch("comm_reply_to", $rec->{packet}, {
        data => {
            actions => \@actions
        }
    });
    log_msg("Replying with ".Dumper($rec->{actions}));
    
    # Return OK
    return RET_OK;
}

############################################
# Broadcast a lookup request
sub __xmpp_ui_actionslist_request {
############################################
    my ($self, $uid) = @_[ OBJECT, ARG0 ];
    
    # Send the lookup discovery message
    my $ans = Dispatch("comm_pubsub_publish", {
        node => WORKFLOW_NODE.'/discovery',
        context => "iagent:workflow",
        action => 'lookup_actions',
        data => {
            id => $uid
        }
    });    
    
}

############################################
# Invoke a new workflow
sub __xmpp_ui_actionslist {
############################################
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];
    my $uid = Data::UUID->new()->create_str;
    
    # Schedule reply in a couple of seconds, when
    # all the actions are collected
    $self->{PENDING_ACTION_LOOKUPS}->{$uid} = {
        packet => $packet,
        actions => { },
        timer => $kernel->delay_set('xmpp_ui_actionslist_reply', 2, $uid)
    };
    
    # Invoke and wait for response (comm_pubsub_publish MUST be called outside this call)
    $kernel->yield('xmpp_ui_actionslist_request', $uid);
    
    # Do not send any reply yet
    return RET_SCHEDULED;
}

############################################
# Invoke a new workflow
sub __xmpp_ui_invoke {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Lookup id from the name
    my $args = $packet->{parameters};
    my $id = $args->{wid};
    delete $args->{wid};
    
    # Invoke workflow
    if ($self->start_workflow($id, $args) == RET_OK) {
        return RET_OK;
    } else {
        return RET_ABORT;
    }

}

############################################
# Create new definition
sub __xmpp_ui_new_definition {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $script = eval($packet->{data}->{script});
    $self->register_workflow($script);
    return RET_OK;
}

############################################
# Return the definition script of that workflow
sub __xmpp_ui_get_definition {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $wid = $packet->{parameters}->{wid};
    
    my $def = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_definitions WHERE wid = ?", undef, $wid);
    if(!$def) {
        log_warn("Unable to find workflow definition wid=$wid from workflow_definitions");
        return RET_ERROR;
    }
    
    # Fetch the workflow object
    my $w = eval($def->{script});
    return RET_ERROR unless(UNIVERSAL::isa($w, 'Module::Workflow::Definition'));

    my $df = $w->DEFINITION;
    delete $df->{DID};
    delete $df->{IID};
    
    my $fmt = ($packet->{parameters}->{format} or 'perl');
    my $text = '';
    if ($fmt eq 'perl') {
        $text = Dumper($df);
        $text =~ s/\$VAR1 = //;
    } elsif ($fmt eq 'json') {
        $text = to_json($df, {utf8 => 1, pretty => 1});
    } else {
        Reply("comm_reply_error", {
            type=> 'bad-request',
            message=> 'Unsupported script format: '.$fmt,
            code=>601 
        });
        return RET_ERROR;
    }
    
    # Send the definition
    iAgent::Kernel::Reply("comm_reply", {
        data => {
            script => [ $text ]
        }
    });
    
    return RET_OK;
}

############################################
# Update the definition script of that workflow
sub __xmpp_ui_set_definition {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $wid = $packet->{parameters}->{wid};

    my $def = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_definitions WHERE wid = ?", undef, $wid);
    if(!$def) {
        log_warn("Unable to find workflow definition wid=$wid from workflow_definitions");
        return RET_ERROR;
    }
    
    # Fetch the workflow object
    my $w = eval($def->{script});
    return RET_ERROR unless(UNIVERSAL::isa($w, 'Module::Workflow::Definition'));
    
    # Update definition
    $def = {};
    my $fmt = ($packet->{parameters}->{format} or 'perl');
    if ($fmt eq 'perl') {
        $def = eval($packet->{data}->{script});
        if ($@) {
            Reply("comm_reply_error", {
                type=> 'bad-request',
                message=> 'Syntax error: '.$@,
                code=>601 
            });
            return RET_ERROR;
        };
    } elsif ($fmt eq 'json') {
        $def = decode_json($packet->{data}->{script});
    } else {
        Reply("comm_reply_error", {
            type=> 'bad-request',
            message=> 'Unsupported script format: '.$fmt,
            code=>601 
        });
        return RET_ERROR;
    }

    # Try to update definition
    my $ans = $w->define($def);
    if ($ans != RET_OK) {
        if ($ans == RET_DENIED) {
            Reply("comm_reply_error", {
                type=> 'bad-request',
                message=> 'Recursion detected. Recursive workflows are not allowed.',
                code=>602
            });
            return RET_ERROR;
        } elsif ($ans == RET_SYNTAXERR) {
            Reply("comm_reply_error", {
                type=> 'bad-request',
                message=> 'Syntax error in the workflow structure.',
                code=>602
            });
            return RET_ERROR;
        } else {
            Reply("comm_reply_error", {
                type=> 'bad-request',
                message=> 'Unable to update the workflow! Definition class denied the update!',
                code=>603
            });
            return RET_ERROR;
        }
    }
    
    # Get script
    my $script = Dumper($w);
    $script =~ s/.*bless/bless/;
    
    # New script
    $self->{dbh}->do("UPDATE workflow_definitions SET script = ? WHERE wid = ?", undef, $script, $wid);
    return RET_OK;
    
}

############################################
# Remove an entry from the workflow
sub __xmpp_ui_remove_definition {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $wid = $packet->{parameters}->{wid};

    # Delete entry
    $self->{dbh}->do("DELETE FROM workflow_definitions WHERE wid = ?", undef, $wid);
    
    # Return OK
    return RET_OK;
        
}

############################################
# Remove an entry from the workflow
sub __xmpp_ui_remove_instance {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $did = $packet->{parameters}->{did};
    my $inst = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_instances WHERE did = ?", undef, $did);
    if(!$inst) {
        log_warn("Unable to find workflow instance did=$did from workflow_instances");
        return RET_ERROR;
    }
    
    # Check the status
    if (($inst->{status} eq 'failed') || ($inst->{status} eq 'completed') || ($inst->{status} eq 'aborted')) {

        # Delete entry
        $self->{dbh}->do("DELETE FROM workflow_instances WHERE did = ?", undef, $did);
        $self->{dbh}->do("DELETE FROM workflow_actions WHERE did = ?", undef, $did);
        
        # Return OK
        return RET_OK;
        
    } elsif ($inst->{status} eq 'aborting') {
        
        # We cannot re-abort an aborted action
        #Reply("comm_reply_error", {
        #    type=> 'bad-request',
        #    message=> 'Workflow is currently being aborted. Cannot be aborted again',
        #    code=>601 
        #}, $packet);

        # Delete entry
        $self->{dbh}->do("DELETE FROM workflow_instances WHERE did = ?", undef, $did);
        $self->{dbh}->do("DELETE FROM workflow_actions WHERE did = ?", undef, $did);
        
        # Return error
        return RET_OK;
        
    } else {
        
        # Update status of the entry
        $self->{dbh}->do("UPDATE workflow_instances SET status = ? WHERE did = ?", undef, 
                            'aborting', $did);
        
        # Abort workflow
        my $ans = Dispatch("workflow_abort", $did);
        
        if ($ans == RET_NOTFOUND) {
        
            # Fail the instance
            $self->{dbh}->do("UPDATE workflow_instances SET status = ?, result = ?, message = ? WHERE did = ?", undef, 
                                'failed', -1, 'Workflow was aborted by the user', $did);
                                
            # Return ok
            return RET_OK;
        
        } elsif ($ans != RET_OK) {

            # Fail the instance
            $self->{dbh}->do("UPDATE workflow_instances SET status = ?, result = ?, message = ? WHERE did = ?", undef, 
                                'failed', -1, 'Unable to abort a running workflow', $did);
            
            # Send an error
            Reply("comm_reply_error", {
                message=> 'Unable to abort the workflow!',
            });
            
            # Return error
            return RET_ERROR;
            
        } else {
            
            # Return OK
            return RET_OK;
            
        }

    }
}

############################################
# Get the required fields of a workflow
sub __xmpp_ui_fields {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $wid = $packet->{parameters}->{wid};
    my $def = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_definitions WHERE wid = ?", undef, $wid);
    if(!$def) {
        log_warn("Unable to find workflow definition wid=$wid from workflow_definitions");
        return RET_ERROR;
    }

    # Fetch the workflow object
    my $w = eval($def->{script});
    return RET_ERROR unless(UNIVERSAL::isa($w, 'Module::Workflow::Definition'));

    # Return the required fields
    iAgent::Kernel::Reply("comm_reply", {
        data => {
            fields => $w->{REQUIRED}
        }
    });
    
    # Return OK
    return RET_OK;

}

############################################
# Return the defined actions
sub __xmpp_ui_definitions {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    # Fetch the instance details
    my $sth = $self->{dbh}->prepare("SELECT * FROM workflow_definitions");
    return RET_ERROR if(!$sth);
    $sth->execute();

    # Build response array
    my @entries;
    while (my $r = $sth->fetchrow_hashref()) {
        
        # Fetch the workflow object
        my $w = eval($r->{script});
        return RET_ERROR unless(UNIVERSAL::isa($w, 'Module::Workflow::Definition'));

        # Count instances
        my ($inst) = $self->{dbh}->selectrow_array("SELECT COUNT(*) FROM workflow_instances WHERE wid = ? AND status = 'running'", undef, $r->{wid});
        
        # Push entry
        push @entries, {
            name => $r->{name},
            maxdepth => $r->{maxdepth},
            wid => $r->{wid},
            instances => $inst,
            
            notify => $w->{NOTIFY},
            description => ($r->{description} or '') # Avoid undef -> Creates warnings
        };

    }
    
    # Reply a status
    iAgent::Kernel::Reply("comm_reply", {
        data => {
            definitions => \@entries
        }
    });

    # Return OK
    return RET_OK;

}

############################################
# Return the status of all workflow instances
sub __xmpp_ui_statusall {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];

    # Return all the running workflows
    my $sth = $self->{dbh}->prepare("SELECT * FROM workflow_instances");
    return RET_ERROR if(!$sth);
    $sth->execute();

    # Build response array
    my @entries;
    while (my $r = $sth->fetchrow_hashref()) {

        # Fetch source action information
        my $sth2 = $self->{dbh}->prepare("SELECT * FROM workflow_definitions WHERE wid = ?");
        return RET_ERROR if(!$sth2);
        $sth2->execute($r->{wid});
        my $src = $sth2->fetchrow_hashref();

        # Fetch the workflow object
        my $w = eval($src->{script});
        return RET_ERROR unless(UNIVERSAL::isa($w, 'Module::Workflow::Definition'));

        # Store entry
        push @entries, {
            name => $src->{name},
            action => $r->{curraction},
            position => $w->depth($r->{curraction}),
            message => ($r->{message} or ''),
            result => ($r->{result} or ''),
            depth => $src->{maxdepth},
            status => $r->{status},
            id => $r->{did}
        }
        
    }

    # Reply a status
    iAgent::Kernel::Reply("comm_reply", {
        data => {
            instances => \@entries
        }
    });

    # Return OK
    return RET_OK;
}



############################################
# Get status details of a specific action
sub __xmpp_ui_status {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $did = $packet->{parameters}->{wid}; # << TODO: Change to DID
 
    # Fetch the instance details
    my $inst = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_instances WHERE did = ?", undef, $did);
    if(!$inst) {
        log_warn("Unable to find workflow instance did=$did from workflow_instances");
        return RET_ERROR;
    }
    
    # Fetch the definition
    my $def = $self->{dbh}->selectrow_hashref("SELECT * FROM workflow_definitions WHERE wid = ?", undef, $inst->{wid});
    if(!$def) {
        log_warn("Unable to find workflow definition wid=$inst->{wid} from workflow_definitions");
        return RET_ERROR;
    }

    # Fetch the workflow object
    my $wf = eval($def->{script});
    return RET_ERROR unless(UNIVERSAL::isa($wf, 'Module::Workflow::Definition'));

    # Update the active action on the workflow
    $wf->{ACTIVE} = $inst->{curraction};
    
    # Get the actions timeline
    my @ans;
    my $sth = $self->{dbh}->prepare("SELECT * FROM workflow_actions WHERE did = ?");
    if(!$sth) {
        log_warn("Unable to find any action under workflow did=$did");
        return RET_ERROR 
    }
    $sth->execute($did);
    while (my $action = $sth->fetchrow_hashref()) {
        
        # Calculate the elapsed time
        my $timediff = 0; my $elapsed='';
        if (($action->{aid} == $inst->{curraction}) && ($action->{status} ne 'failed')) {
            $timediff = time() - int($action->{started});
            $action->{status} = 'active';
        } else {
            $timediff = int($action->{updated}) - int($action->{started});
        }
        my ($sec,$min,$hour,$mday) = gmtime($timediff);
        $mday--;
        $elapsed .= "${mday}d " if ($mday);
        $elapsed .= "${hour}h " if ($hour);
        $elapsed .= "${min}m " if ($min);
        $elapsed .= "${sec}s " if ($sec);
         
        # Find name/alias
        my $a_name = $wf->{ACTIONS}->{$action->{aid}}->{description};
        $a_name = $wf->{ACTIONS}->{$action->{aid}}->{action} unless (defined($a_name) && ($a_name ne ''));
        
        # Put the action
        push @ans, {
            name => $a_name,
            started => time2str('%d/%m/%y %H:%M:%S',$action->{started}),
            updated => time2str('%d/%m/%y %H:%M:%S',$action->{updated}),
            status => $action->{status},
            target => $action->{target},
            aid => $action->{iid},
            id => $action->{aid},
            elapsed => $elapsed
        };
        
        # If the action had an error, put also a comment
        if ($action->{status} eq 'failed') {
            push @ans, {
                name => '',
                started => '',
                updated => '',
                status => 'comment',
                elapsed => '',
                
                # Target field contains the message
                target => $action->{message},
                
                aid => $action->{iid},
                id => $action->{aid}
            };
        }
    
    }
    
    # Put the actions that are pending or put a terminator marker
    if ($wf->COMPLETED) {
        
        # Put a completion marker
        push @ans, {
            name => '(Completed)',
            started => '',
            updated => '',
            status => 'final',
            elapsed => '',
            target => '',
            aid => 0,
            id => 0
        };
        
    } else {
        
        # Put a pending marker
        push @ans, {
            name => '(In progress)',
            started => '',
            updated => '',
            status => 'decision',
            elapsed => '',
            target => '',
            aid => 0,
            id => 0
        };
        
        # Get pending actions
        my %unique_aids;
        foreach (values %{$wf->ACTION->{route}}) {
            $unique_aids{$_}=1;
        }
        foreach (keys %unique_aids) {
            # Put a pending action
            push @ans, {
                name => $wf->{ACTIONS}->{$_}->{action},
                started => '',
                updated => '',
                status => 'pending',
                elapsed => '',
                target => '',
                aid => 0,
                id => 0
            };            
        }
        
    }

    # Calculate depth
    my $wfstatus = {
            depth => $def->{maxdepth},
            position => $wf->depth($inst->{curraction})
    };

    # Reply a status
    iAgent::Kernel::Reply("comm_reply", {
        data => {
            actions => \@ans,
            status => $wfstatus
        }
    });

    # Return OK
    return RET_OK;

}

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
