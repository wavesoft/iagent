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
# Developed by Ioannis Charalampidis 2011-2012 at CERN
# Contact: <ioannis.charalampidis[at]cern.ch>
#

package Module::WorkflowActions;

=head1 NAME

Module::WorkflowActions - Workflow Actions invocation module

=head1 DESCRIPTION

This module provides ability to invoke predefined workflow actions in serial or threaded mode. The main advntage
of this module is the transparent threaded-execution mode.

=head1 MANIFEST DEFINITION

In order to register your own custom workflow-capable actions, in your module you have to define the following
manifest parameter:

 our $MANIFEST = {
 	WORKFLOW => {
 	
 		"action_name" => {
 	
 			ActionHandler => "action_handler",      # The function that will handle this action
 			ValidateHandler => "validate_handler",  # The handler that will verify the integrity of the context [Optional]
 			CleanupHandler => "cleanup_handler",    # The handler that cleans-up the action
			Description => "A short description",   # A short description that describes what this function does [Optional]
 			Threaded => 1 | 0,                      # Set to 1 (Default) to run the handler in a separate thread [Optional]
			MaxInstances => undef | 1~MAX           # Set the number of maximum concurrent instances to allow or undef for unlimited [Optional]
 			Permissions => [ 'read', 'write' ],     # Optionally you can specify the permissions required in order to invoke this action [Optional]
 			RequiredParameters => [ 'name' ],       # Which parameters are mandatory to be present [Optional]
 			Provider => 1                           # The action is a provider
 			
 		}
 		
 	}
 };

=head2 ActionHandler

Action handler is the name of the message handler that will implement the action. The C<OBJECT> is a (read-only) copy of the object
instance. If anything is changed, the changes will not be reflected to the original instance.

The C<ARG0> is a reference to a hash that holds the context of the action. The action can freely update the context as required. The WorkflowActions
module will take care of updating the original hash and responding to the invoker.

The second argument C<ARG1> is the path where the log files reside. It is recommended that your action moves it's log files there acter the execution
in order to be collected by the invoking entity later.

The third argument C<ARG2> is a unique string ID allocated on this action. This ID will be the same when the CleanupHandler for this action is called.

The the return value of the handler sub will be the return value of the action.

For example:

 sub __my_handler {
 	my ($self, $context, $logdir, $uid) = @_[ OBJECT, ARG0, ARG1, ARG2 ];
 	
 	my $names = $self->get_names; 	# This could be valid only if the function get_names does not modify anything
    $context->{names} = $names;		# Context will be updated automatically    
    
    open LOGFILE, ">$logdir/my.log";
    print LOGFILE "Started!"
    close LOGFILE
    
    return 0;                       # The return code of the action
 }

=head2 ValidateHandler

The Validation Handler is called when the action is about to be executed or when somebody requested validation status of an action. 

The C<ARG0> is a reference to a hash that holds the context of the action.

You must return RET_OK if the validation succeeeded. Otherwise it will be considered invalid.

For example:

 sub __my_validator {
     my ($self, $context) = @_[ OBJECt, ARG0 ];	
     return RET_ERROR unless defined($context->{name});
     return RET_OK;
 }

=head1 HANDLED MESSAGES

The following messages are handled by this module:

=cut

use strict;
use warnings;
use POE qw( Wheel::Run );
use iAgent::Kernel;
use iAgent::Log;
use Data::UUID;
use Data::Dumper;
use POSIX;

our $MANIFEST = {
	
	priority => 4 	# Right above the normal modules
	
};

my $STORE = undef;   # When NEW is called, this one is updated

sub new {
	my $class = shift;
	my $self = {
		PIDS => { },
		WIDS => { },
		UIDS => { },
		INSTANCES => { },
		DEFINITIONS => { }
	};
	
	# Bless myself and keep a singleton copy
	$self = bless $self, $class;
	$STORE = $self;
	
	return $self;
}

##===========================================================================================================================##
##                                                HELPER FUNCTIONS                                                           ##
##===========================================================================================================================##

####################################################################
# Validate the specified action
sub validate_action {
####################################################################
	my ($heap, $object, $action, $context, $permissions) = @_;

	# Fetch action information
	my $info = $heap->{WORKFLOW}->{$action};

	# If we have required parameters, validate parameters array
	foreach (@{$info->{RequiredParameters}}) {
		if (!defined($context->{$_})) {
			log_warn("Action $action invocation error: Missing required context parameter '$_'");
			return RET_INCOMPLETE;
		}
	}
	
	# Validate permissions
	if ($#{$info->{Permissions}}>=0) {
	 	if (scalar keys %$permissions == 0) { # Require permissions, but we haven't any permissions specified?
			log_warn("Action $action invocation error: Permissions array is required!");
			return RET_DENIED;
		} else {
			foreach (@{$info->{Permissions}}) { # Require each permission to exist in the permissions hash
				if (!$permissions->{$_}) {					
					log_warn("Action $action invocation error: Required permission '$_'!");
					return RET_DENIED;
				}
			}
		}
	}
	
	# Run custom validator
	if (defined($info->{ValidateHandler})) {
		if ($poe_kernel->call($poe_kernel->get_active_session, $info->{ValidateHandler}, $context) != RET_OK) {
			log_warn("Action $action invocation error: Validator reqjected the request!");
			return RET_INVALID;
		}
	}
	
	# Check if we can actually handle this action
	if (!defined($info->{ActionHandler})) {
        # This action cannot be run in any way
        return RET_INVALID;
	}

	# Check for maximum allowed instances
	$STORE->{INSTANCES}->{$action}=0 unless defined($STORE->{INSTANCES}->{$action});
	if (defined($info->{MaxInstances}) && ($STORE->{INSTANCES}->{$action} >= $info->{MaxInstances})) {
		log_debug("Maximum instances of action $action reached!");
		return RET_BUSY;
	}
	
	# Passed by everything? Return OK
	return RET_OK;
		
}

##===========================================================================================================================##
##                                     DELEGATE FUNCTIONS INSERTED TO MODULES                                                ##
##===========================================================================================================================##

####################################################################
# Delegate function that handles the workflow_action_provide event
#-------------------------------------------------------------------

=head2 workflow_action_provide ACTION, [ HASHREF ]

This function returns RET_OK if the specified action is valid under the specified context as a provider. This function can return
one of the following values:

B<RET_OK> If the action is valid and ready to be invoked.

B<RET_BUSY> If the action is valid, but all the execution slots are taken.

B<RET_INCOMPLETE> If there are one or more missing context parameters.

B<RET_INVALID> If the validation function of this action failed to complete successfully.

B<RET_DENIED> If the invoking entity has no permissions for the specified action.

B<RET_UNHANDLED> If the specified action does not exist.

C<ACTION> is the name of the action you want to check. C<CONTEXT> is a hash that contains the action's context
variables. C<PERMISSIONS> is a hash of permissions in { permission => 1 } format of the entity that wants to
invoke this action.

=cut

#-------------------------------------------------------------------
sub DELEGATE_ACTION_PROVIDE {
####################################################################
	my ($heap, $object, $action, $context, $permissions) = @_[ HEAP, OBJECT, ARG0..ARG2 ];

	# Check if it doesn't exist
	return RET_PASSTHRU unless (defined($heap->{WORKFLOW}) && defined($heap->{WORKFLOW}->{$action}));

    # Check if it's not a provider
	return RET_PASSTHRU unless ($heap->{WORKFLOW}->{$action}->{Provider});
    
	# Return validation status
	return validate_action($heap, $object, $action, $context, $permissions);

}

####################################################################
# Delegate function that handles the workflow_action_cleanup event
#-------------------------------------------------------------------

=head2 workflow_action_cleanup ACTION, [ HASHREF ]

Cleanup a workflow action upon the workflow completion. The first argument is the name of the action you want to invoke, 
the second argument is a hash reference that contains any of the following parameters:

 {
 	Context => { .. },				# The context variables for this action. If not specified { } will be used
 	Permissions => { read => 1 },	# The permissions that the invoking user have. Usually that's the 'permissions' hash received from the LDAP module
	ID => 'UUID',					# The unique ID for this action. If not specified, it will be generated
	LogDir => "/tmp"				# The directory that will hold all the log information for this action
 }

B<Warning!> Keep in mind that this action is invoked serially. No threaded mode is currently supported. Thus the
'Threaded' attribude dues not affect this action.

=cut

#-------------------------------------------------------------------
sub DELEGATE_ACTION_CLEANUP {
####################################################################

    my ($heap, $action, $details) = @_[ HEAP, ARG0, ARG1 ];
    return RET_PASSTHRU unless defined($heap->{WORKFLOW}->{$action}); # Skip undefined actions

    # Fetch action information
    my $info = $heap->{WORKFLOW}->{$action};

    # Validate some input parameters
    $details->{Context} = { } 						unless defined($details->{Context});
    $details->{Permissions} = { } 					unless defined($details->{Permissions});
    $details->{ID} = Data::UUID->new()->create_str 	unless defined($details->{ID});
    $details->{LogDir} = "/tmp" 					unless defined($details->{LogDir});

    # Validate action
    my $ans = validate_action($heap, $info->{ClassRef}, $action, $details->{Context}, $details->{Permissions});
    return $ans unless($ans == RET_OK);

    # Ensure cleanup handler exists
    return RET_NOTFOUND if (!defined($info->{CodeRefCleanup}));
    
    log_msg("[$details->{ID}] Cleaning up action");
	log_debug("STARTING CLEANUP ACTION SERIALLY");

	# Create a POE-Like arguments list
	my @args;
	for (my $i=0; $i<ARG0; $i++) {
		if ($i == OBJECT) { push @args, $info->{ClassRef}; } 
		elsif ($i == HEAP) { push @args, $_[HEAP]; } 
		elsif ($i == KERNEL) { push @args, $_[KERNEL]; } 
		elsif ($i == SESSION) { push @args, $_[SESSION]; } 
		else { push @args, undef; }
	}

	# Store arguments: ARG0, ARG1
	push @args, $details->{Context};
	push @args, $details->{LogDir};
	push @args, $details->{ID};

	# Redirect stdout/err
	my $result;
	my $sub = $info->{CodeRefCleanup};
	my $logdir = $details->{LogDir};
	do {
		local *STDOUT;
		local *STDERR;
		
		# Switch STDOUT/ERR to the logfiles
		open STDOUT, ">>", "$logdir/STDOUT";
		open STDERR, ">>", "$logdir/STDERR";

		# Call the function with the specified context
		$result = &{$sub}(@args);
		
		# Close STDOUT/ERR
		close STDOUT;
		close STDERR;
		
	}; # STDOUT/ERR Restored here

    # This should always succeed since it's cleanup
    return RET_OK;
    
}

####################################################################
# Delegate function that handles the workflow_action_invoke event
#-------------------------------------------------------------------

=head2 workflow_action_invoke ACTION, [ HASHREF ]

Invoke a predefined workflow action. The first argument is the name of the action you want to invoke, the second argument
is a hash reference that contains any of the following parameters:

 {
 	Context => { .. },				# The context variables for this action. If not specified { } will be used
 	Permissions => { read => 1 },	# The permissions that the invoking user have. Usually that's the 'permissions' hash received from the LDAP module
	ID => 'UUID',					# The unique ID for this action. If not specified, it will be generated
	LogDir => "/tmp"				# The directory that will hold all the log information for this action
 }

=cut

#-------------------------------------------------------------------
sub DELEGATE_ACTION_INVOKE {
####################################################################

	my ($heap, $action, $details) = @_[ HEAP, ARG0, ARG1 ];
	return RET_PASSTHRU unless defined($heap->{WORKFLOW}->{$action}); # Skip undefined actions

	# Fetch action information
	my $info = $heap->{WORKFLOW}->{$action};
	
	# Validate some input parameters
	$details->{Context} = { } 						unless defined($details->{Context});
	$details->{Permissions} = { } 					unless defined($details->{Permissions});
	$details->{ID} = Data::UUID->new()->create_str 	unless defined($details->{ID});
	$details->{LogDir} = "/tmp" 					unless defined($details->{LogDir});

	# Validate action
	my $ans = validate_action($heap, $info->{ClassRef}, $action, $details->{Context}, $details->{Permissions});
	return $ans unless($ans == RET_OK);

	# "Reserve" a new instance slot
	$STORE->{INSTANCES}->{$action}++;
	
	# Store instance information
	$STORE->{UIDS}->{$details->{ID}} = {
		Action => $action
	};
	
	# Invoke the action depending on the chosen mode
	if ($info->{Threaded}) {
		$poe_kernel->yield('__wfa__invoke_thread',
				$details->{ID}, $details->{LogDir}, $details->{Context}, $info->{ClassRef}, $info->{CodeRef}
			);
	} else {
		$poe_kernel->yield('__wfa__invoke_serial', 
				$details->{ID}, $details->{LogDir}, $details->{Context}, $info->{ClassRef}, $info->{CodeRef}
			);
	}
	
	# Return OK
	return RET_OK;
	
}

####################################################################
# Delegate function that handles the workflow_action_abort event
#-------------------------------------------------------------------

=head2 workflow_action_abort ID

Abort a previously invoked action, addressed by the unique ID specified (or generated) by workflow_action_invoke.
This action makes sense only on threaded execution mode. 

=cut

#-------------------------------------------------------------------
sub DELEGATE_ACTION_ABORT {
####################################################################
	my ($heap, $uid) = @_[ HEAP, ARG0 ];
	return RET_OK unless defined($STORE->{UIDS}->{$uid});
	
	# Fetch information
	my $inf = $STORE->{UIDS}->{$uid};
	
	# Switch PID to point at the process group if we are not using windows
	if (!$inf->{Wheel}->[25]) { # 25=MSWIN32_GROUP_PID, 4=CHILD_PID
    	$inf->{Wheel}->[4] = -abs($inf->{Wheel}->[4]);
	}
	
	# Kill process(es)
	if ($inf->{Wheel}->kill(SIGINT) > 0) {
		return RET_OK;
	} else {
		return RET_ERROR;
	}
	
	# (The child reaping will be triggered)
	
}


####################################################################
# Delegate function that handles the workflow_action_validate event
#-------------------------------------------------------------------

=head2 workflow_action_validate ACTION, CONTEXT, PERMISSIONS

This function returns RET_OK if the specified action is valid under the specified context. This function can return
one of the following values:

B<RET_OK> If the action is valid and ready to be invoked.

B<RET_BUSY> If the action is valid, but all the execution slots are taken.

B<RET_INCOMPLETE> If there are one or more missing context parameters.

B<RET_INVALID> If the validation function of this action failed to complete successfully.

B<RET_DENIED> If the invoking entity has no permissions for the specified action.

B<RET_UNHANDLED> If the specified action does not exist.

C<ACTION> is the name of the action you want to check. C<CONTEXT> is a hash that contains the action's context
variables. C<PERMISSIONS> is a hash of permissions in { permission => 1 } format of the entity that wants to
invoke this action.

=cut

#-------------------------------------------------------------------
sub DELEGATE_ACTION_VALIDATE {
####################################################################
	my ($heap, $object, $action, $context, $permissions) = @_[ HEAP, OBJECT, ARG0..ARG2 ];

	# Check if it doesn't exist
	return RET_PASSTHRU unless (defined($heap->{WORKFLOW}) && defined($heap->{WORKFLOW}->{$action}));

	# Return validation status
	return validate_action($heap, $object, $action, $context, $permissions);

}

####################################################################
# Delegate function that handles the workflow_actions_list event
#-------------------------------------------------------------------

=head2 workflow_actions_list

This function returns an array with all the registered actions. This can be used with iAgent::Kernel::Query to
collect all the registered actions in the agent.

Each array element is a hash reference in the following syntax:

 {
 	Name => "ActionName",					# The name of the action
	Module => "Package::Name",				# The name of the package that hosted this action
	Description => "User-defined descr.",	# A User-defined description
	MaxInstances => undef | 1~MAX           # The number of maximum concurrent instances to allow or undef for unlimited
	Permissions => [ 'read', 'write' ],     # Optionally you can specify the permissions required in order to invoke this action
	RequiredParameters => [ 'name' ]        # Which parameters are mandatory to be present
 } 

=cut

#-------------------------------------------------------------------
sub DELEGATE_ACTIONS_LIST {
####################################################################
	my $heap = $_[HEAP];
	my @ans;
	
	# Process workflow definitions
	if (defined($heap->{WORKFLOW})) {
		foreach (keys %{$heap->{WORKFLOW}}) {
			my $a = $heap->{WORKFLOW}->{$_};
			push @ans, {
				Name => $_,                                     # The full name of the action
				Module => $heap->{CLASS},                       # The module that provides this action
				Description => $a->{Description},               # The description of the action
				MaxInstances => $a->{MaxInstances},             # The maximum number of instances
				Permissions => $a->{Permissions},               # The permissions allowed on this action
				RequiredParameters => $a->{RequiredParameters}  # The required parameters for this action
			};
		}
	}
	
	# Return array
	return \@ans;
	
}

##===========================================================================================================================##
##                                           PRIVATE POE MESSAGE HANDLERS                                                    ##
##===========================================================================================================================##

####################################################################
# Delegate function that handles the __wfa__invoke_completed event
sub DELEGATE_ACTION_COMPLETED {
####################################################################
	my ($uid, $result, $context) = @_[ ARG0..ARG2 ];
	return unless defined($STORE->{UIDS}->{$uid});
	
	# Fetch details
	my $details = $STORE->{UIDS}->{$uid};
	delete $STORE->{UIDS}->{$uid};
	
	# Decrease instances
	$STORE->{INSTANCES}->{$details->{Action}}--;

	# Notify
	log_msg("Action $uid ($details->{Action}) completed with result $result");
	
	# Dispatch completion message
	iAgent::Kernel::Dispatch("workflow_action_completed", $uid, $result, $context);

}


####################################################################
# Delegate function that handles the __wfa__invoke_serial event
sub DELEGATE_INVOKE_SERIAL {
####################################################################
	my ($uid, $logdir, $context, $class, $sub) = @_[ ARG0..ARG5 ];
	log_debug("STARTING ACTION SERIALLY");

	# Create a POE-Compatible arguments list
	my @args;
	for (my $i=0; $i<ARG0; $i++) {
		if ($i == OBJECT) { push @args, $class; } 
		elsif ($i == HEAP) { push @args, $_[HEAP]; } 
		elsif ($i == KERNEL) { push @args, $_[KERNEL]; } 
		elsif ($i == SESSION) { push @args, $_[SESSION]; } 
		else { push @args, undef; }
	}

	# Store arguments: ARG0, ARG2
	push @args, $context;
	push @args, $logdir;
	push @args, $uid;

	# Redirect stdout/err
	my $result;
	do {
		local *STDOUT;
		local *STDERR;
		
		# Switch STDOUT/ERR to the logfiles
		open STDOUT, ">", "$logdir/STDOUT";
		open STDERR, ">", "$logdir/STDERR";

		# Call the function with the specified context
		$result = &{$sub}(@args);
		
		# Close STDOUT/ERR
		close STDOUT;
		close STDERR;
		
	}; # STDOUT/ERR Restored here
	
	# Call the function completion
	$poe_kernel->yield('__wfa__invoke_completed', $uid, $result, $context);	
}

####################################################################
# Delegate function that handles the __wfa__invoke_thread event
sub DELEGATE_INVOKE_THREAD {
####################################################################
	my ($uid, $logdir, $context, $class, $sub) = @_[ ARG0..ARG5 ];
	log_debug("STARTING ACTION IN PARALLEL");
	
	# Open logfiles
	open my $out, ">", "$logdir/STDOUT";
	open my $err, ">", "$logdir/STDERR";
	
	# Start a runner wheel
	my $child = new POE::Wheel::Run(
			Program => sub { # Use a delegate
					my ($class, $heap, $sub, $context, $logdir, $id) = @_;
					
					# Inform POE kernel that we forked
					$poe_kernel->has_forked();
					
					# Remove signal handlers that we broght from the parent
					$SIG{INT} = 'DEFAULT';
					
					# Make this process a process leader
					use POSIX 'setsid';
					setsid();

					# Create a POE-Compatible arguments list
					my @args;
					for (my $i=0; $i<ARG0; $i++) {
						if ($i == OBJECT) { push @args, $class; } 
						elsif ($i == HEAP) { push @args, $heap; }
						else { push @args, undef; }
					}

					# Store arguments: ARG0, ARG1
					push @args, $context;
					push @args, $logdir;
					push @args, $uid;
					
					# Run user code
					my $ans = &{$sub}(@args);

					# Dump context on STDOUT
					print "\n___DATA___\n".Dumper($context);
					# ^ That's a lame, but quick way of cross-thread communication
					#   It dumps the context data in the STDOUT and the output handler
					#   picks it up and reconstructs the new context hash.

					# Return result
					$ans -= 255 if ($ans>255); # Clear a weird flag...
					exit($ans);
				},
			CloseOnCall => 1,
			ProgramArgs => [ $class, $_[HEAP], $sub, $context, $logdir, $uid ],
			StdoutEvent => '__wfa__thread_stdout',
			StderrEvent => '__wfa__thread_stderr',
		);
	
	# Trap termination signal
	$_[KERNEL]->sig_child($child->PID, "__wfa__thread_sigchild");
	
	# Store the action information
	$STORE->{PIDS}->{$child->PID} = {
		Wheel => $child,
		LogDir => $logdir,
		FDErr => $err,
		FDOut => $out,
		UID => $uid,
		WID => $child->ID,
		PID => $child->PID,
		DataBuffer => ""
	};
	
	# Add mapping with Wheel ID
	$STORE->{WIDS}->{$child->ID} = 
		$STORE->{PIDS}->{$child->PID};

    # Add child on the UUIDS
    $STORE->{UIDS}->{$uid}->{Wheel} = $child;
    
}

####################################################################
# Delegate function that handles the __wfa__thread_stdout event
sub DELEGATE_THREAD_STDOUT {
####################################################################
    my ($line, $wid) = @_[ ARG0, ARG1 ];
	my $inf = $STORE->{WIDS}->{$wid};
	my $FD = $inf->{FDOut};
	
	# If we have a data tag, start collecting the updated
	# context information
	if (($line eq '___DATA___') && ($inf->{DataBuffer} eq '')) {
		# If we have previously buffered data, they are not really data, they were
		# literal from the called function. Dump it to the file
		if ($inf->{DataBuffer} ne '') {
			print $FD $inf->{DataBuffer}."\n";
		}
		
		# And start piling up data
		$inf->{DataBuffer} = "return "; # Just non-blank will enable next statement
		
	} 
	
	# If we are collecting context information, pile up the
	# lines in the data buffer
	elsif ($inf->{DataBuffer} ne '') {
		$inf->{DataBuffer} .= $line;
	}
	
	# Otherwise, just dump the output to the file
	else {
		print $FD "$line\n";
	}	
}

####################################################################
# Delegate function that handles the __wfa__thread_stderr event
sub DELEGATE_THREAD_STDERR {
####################################################################
    my ($line, $wid) = @_[ ARG0, ARG1 ];
	my $inf = $STORE->{WIDS}->{$wid};
	my $FD = $inf->{FDErr};

	# Just log STDERR to the file
	print $FD "$line\n";
}

####################################################################
# Delegate function that handles the __wfa__thread_sigchild event
sub DELEGATE_THREAD_SIGCHILD {
####################################################################
    my ($heap, $signal, $pid, $result) = @_[ HEAP, ARG0..ARG2 ];
	my $inf = $STORE->{PIDS}->{$pid};
	
	# Close file handlers
	close $inf->{FDOut};
	close $inf->{FDErr};
	
	# Parse data buffer
	$inf->{DataBuffer} =~ s/\$VAR1 =//;
	my $context = eval($inf->{DataBuffer});
	
	# Delete unused components
	delete $STORE->{WIDS}->{$inf->{WID}};
	delete $STORE->{PIDS}->{$pid};
	
	log_debug("Completed. Result = $signal / $pid / $result");
	
	# Notify completion
	$result -= 255 if ($result>255); # Clear a weird flag
	$poe_kernel->yield('__wfa__invoke_completed', $inf->{UID}, $result, $context);
}


##===========================================================================================================================##
##                                           MODULE SESSION INITIALIZATIONS                                                  ##
##===========================================================================================================================##

sub __workflow_action_details {
    my ($self, $action, $details) = @_[ OBJECT, ARG0..ARG1 ];
    return RET_NOTFOUND unless defined($self->{DEFINITIONS}->{$action});
    
    # Fetch details for this action
    my %info = %{$self->{DEFINITIONS}->{$action}};
    $info{Instances} = $self->{INSTANCES}->{$action} | 0;

    # Update details hash
    map { $details->{$_} = $info{$_} } keys( %info );
    
    # Return OK
    return RET_OK;
}

sub __ready {
    my $self = $_[OBJECT];
	
	# Eveything is ready. Fetch the exposed actions of every module
	foreach my $mod (@{iAgent::Kernel::SESSIONS}) {
		my $MF = $mod->{manifest};
		my $SESSION = $mod->{session};
		my $HEAP = $SESSION->get_heap;
		
		# Get the exposed actions
		if (defined $MF->{WORKFLOW}) {
			my $DEF = { };
			
			# Process action names
			foreach (keys %{$MF->{WORKFLOW}}) {
				
				# Get info hash
				my $inf = $MF->{WORKFLOW}->{$_};

				# Ensure mandatory fields
				if (!defined($inf->{ActionHandler})) {
					log_error("Undefined ActionHandler for action $_!");
					next;
				}
				
				# Update missing values
				$inf->{Threaded} = 1 unless defined($inf->{Threaded});
				$inf->{Provider} = 0 unless defined($inf->{Provider});
				$inf->{RequiredParameters} = [ ] unless defined($inf->{RequiredParameters});
				$inf->{Permissions} = [ ] unless defined($inf->{Permissions});
				$inf->{MaxInstances} = 10 unless defined($inf->{MaxInstances});
				$inf->{Description} = "Undescribed action with the following required parameters: ".join(",",@{$inf->{RequiredParameters}}) 
					unless defined($inf->{Description});
				
				# Create useful values
				no strict qw(refs);
				$inf->{CodeRef} = \&{ $mod->{class}.'::'.$mod->{hooks}->{$inf->{ActionHandler}} };
				$inf->{CodeRefCleanup} = \&{ $mod->{class}.'::'.$mod->{hooks}->{$inf->{CleanupHandler}} } if defined($inf->{CleanupHandler});
				$inf->{ClassRef} = $mod->{instance};
				use strict qw(refs);
				
				# Store information for this action
				$DEF->{$_} = $inf;
				
				# Store on definitions
				$self->{DEFINITIONS}->{$_} = $inf;
				
			}
			
			log_debug("Registering workflow definition for class ".$mod->{class});
			
			# Store definitions to heap
			$HEAP->{WORKFLOW} = $DEF;
			
			# Register dynamic POE states
            $SESSION->_register_state('workflow_action_invoke', \&DELEGATE_ACTION_INVOKE );
            $SESSION->_register_state('workflow_action_provide', \&DELEGATE_ACTION_PROVIDE );
            $SESSION->_register_state('workflow_action_supported', \&DELEGATE_ACTION_ABORT );
            $SESSION->_register_state('workflow_action_abort', \&DELEGATE_ACTION_ABORT );
            $SESSION->_register_state('workflow_action_validate', \&DELEGATE_ACTION_VALIDATE );
            $SESSION->_register_state('workflow_action_cleanup', \&DELEGATE_ACTION_CLEANUP );
            $SESSION->_register_state('workflow_actions_list', \&DELEGATE_ACTIONS_LIST );
            
            $SESSION->_register_state('__wfa__invoke_serial', \&DELEGATE_INVOKE_SERIAL );
            $SESSION->_register_state('__wfa__invoke_thread', \&DELEGATE_INVOKE_THREAD );
            $SESSION->_register_state('__wfa__invoke_completed', \&DELEGATE_ACTION_COMPLETED );
            $SESSION->_register_state('__wfa__thread_stdout', \&DELEGATE_THREAD_STDOUT );
            $SESSION->_register_state('__wfa__thread_stderr', \&DELEGATE_THREAD_STDERR );
            $SESSION->_register_state('__wfa__thread_sigchild', \&DELEGATE_THREAD_SIGCHILD );


			# Expose public states
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_invoke');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_provide');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_supported');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_abort');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_validate');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_actions_list');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_cleanup');
			
		}
		
	}
	
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;