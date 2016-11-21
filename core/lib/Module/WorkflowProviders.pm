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

package Module::WorkflowProviders;

=head1 NAME

Module::WorkflowProviders - Workflow Providers invocation module

=head1 DESCRIPTION

This module provides ability to instance on demand agents that will handle a specified workflow action. Like
the regular actions, this module uses the same structure.

=head1 MANIFEST DEFINITION

In order to register your own custom workflow provider-capable actions, in your module you have to define the following
manifest parameter:

 our $MANIFEST = {
     
 	WORKFLOW_PROVIDER => {
 	
 		"action_name" => {
 	
 			ActionHandler => "action_handler",      # The function that will handle this action
 			ValidateHandler => "validate_handler",  # The handler that will verify the integrity of the context [Optional]
			Description => "A short description",   # A short description that describes what this function does [Optional]
 			Threaded => 1 | 0,                      # Set to 1 (Default) to run the handler in a separate thread [Optional]
			MaxInstances => undef | 1~MAX           # Set the number of maximum concurrent instances to allow or undef for unlimited [Optional]
 			Permissions => [ 'read', 'write' ],     # Optionally you can specify the permissions required in order to invoke this action [Optional]
 			RequiredParameters => [ 'name' ]        # Which parameters are mandatory to be present [Optional]
 			
 		}
 		
 	}
 };

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
	if (!defined($info->{AllocateHandler})) {
        # This action cannot be run in any way
        return RET_INVALID;
	}
	
	# Passed by everything? Return OK
	return RET_OK;
		
}

##===========================================================================================================================##
##                                     DELEGATE FUNCTIONS INSERTED TO MODULES                                                ##
##===========================================================================================================================##

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
sub DELEGATE_ACTION_ALLOCATE {
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

				# Skip action handlers
				next if (defined($inf->{ActionHandler}));
				if (!defined($inf->{AllocateHandler})) {
					log_error("Undefined AllocateHandler for action $_!");
					next;
				}
				
				# Update missing values
				$inf->{Threaded} = 1 unless defined($inf->{Threaded});
				$inf->{RequiredParameters} = [ ] unless defined($inf->{RequiredParameters});
				$inf->{Permissions} = [ ] unless defined($inf->{Permissions});
				$inf->{Description} = "Undescribed action with the following required parameters: ".join(",",@{$inf->{RequiredParameters}}) 
					unless defined($inf->{Description});
				
				# Create useful values
				no strict qw(refs);
				$inf->{CodeRefAllocate} = \&{ $mod->{class}.'::'.$mod->{hooks}->{$inf->{AllocateHandler}} };
				$inf->{CodeRefDeallocate} = \&{ $mod->{class}.'::'.$mod->{hooks}->{$inf->{DeallocateHandler}} };
				$inf->{ClassRef} = $mod->{instance};
				use strict qw(refs);
				
				# Store information for this action
				$DEF->{$_} = $inf;
				
				# Store on definitions
				$self->{DEFINITIONS}->{$_} = $inf;
				
			}
			
			log_debug("Registering workflow provider definition for class ".$mod->{class});
			
			# Store definitions to heap
			$HEAP->{WORKFLOW} = $DEF;
			
			# Register dynamic POE states
            $SESSION->_register_state('workflow_action_allocate', \&DELEGATE_ACTION_ALLOCATE );
            $SESSION->_register_state('workflow_action_deallocate', \&DELEGATE_ACTION_DEALLOCATE );
            $SESSION->_register_state('workflow_action_canallocate', \&DELEGATE_ACTION_CANALLOCATE );

			# Expose public states
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_allocate');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_deallocate');
			iAgent::Kernel::RegisterHandler($SESSION, 'workflow_action_canallocate');
			
		}
		
	}
	
}

1;