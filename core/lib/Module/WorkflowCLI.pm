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

package Module::WorkflowCLI;

=head1 NAME

Module::WorkflowCLI - Command-Line-Interface for the workflow actions

=head1 DESCRIPTION

This module provides the command-line bindings for the workflow actions

=cut

use strict;
use warnings;
use POE;
use iAgent::Kernel;
use iAgent::Log;
use Data::Dumper;
use Module::Workflow::Definition;

our $MANIFEST = {
	CLI => {
		
		"wf/actions/list" => {
			description => "List the available actions on the current node",
			message => "cli_a_list"
		},
		"wf/actions/invoke" => {
			description => "Invoke an action",
			message => "cli_a_invoke"
		},
		"wf/invoke" => {
		    description => "Invoke a workflow loading it's definition from file",
		    message => "cli_wf_invoke",
            options => [ 'file=s' ]
		}
		
	}

};

sub new {
	my $class = shift;
	my $self = {
		CLI_INVOKED => { },
		ME => ''
	};
	
	$self = bless $self, $class;
	return $self;
}

sub __comm_ready {
    my ($self, $me) = @_[ OBJECT, ARG0 ];
    $self->{ME} = $me;
}

sub __cli_a_list {
	my ($self, $parm) = @_[ OBJECT, ARG0 ];
	
	my $ans = iAgent::Kernel::Query("workflow_actions_list");
	if (ref($ans) eq '') { # Got error code?
		iAgent::Kernel::Dispatch("cli_error", "No workflow actions were defined!");
		return RET_ERROR;
	}
	
	# Process actions
	foreach (@{$ans}) {
		iAgent::Kernel::Dispatch("cli_write", " * ".$_->{Name}." \t".$_->{Description}." (".$_->{Module}.")")
	}
	
	return RET_COMPLETED;
}

sub __workflow_completed {
	my ($self, $uid, $wf, $result, $context) = @_[ OBJECT, ARG0..ARG3 ];
	iAgent::Kernel::Dispatch("cli_write", "Completed with result: $result");
	iAgent::Kernel::Dispatch("cli_completed", $result);
}

sub __workflow_failed {
	my ($self, $uid, $wf, $result, $context, $reason) = @_[ OBJECT, ARG0..ARG4 ];
	iAgent::Kernel::Dispatch("cli_error", "Failed! Error: $reason");
	iAgent::Kernel::Dispatch("cli_completed", $result);
}

sub __cli_a_invoke {
	my ($self, $parm) = @_[ OBJECT, ARG0 ];
	my ($action, $parameters) = split(" ",$parm->{cmdline},2);
	
	my %simple_params = split(/[ =]/, $parameters);
	
	my $ans = iAgent::Kernel::Dispatch("workflow_action_validate", $action, \%simple_params, { any => 1, cli => 1 });
	if ($ans != RET_OK) {
		iAgent::Kernel::Dispatch("cli_error", "Unable to validate the specified action!");
		return RET_ERROR;
	}
	
	$ans = iAgent::Kernel::Dispatch("workflow_action_invoke", $action, {
		Context => \%simple_params,
		Permissions => { any => 1, cli => 1 }
	});
	
	return RET_OK;
}

sub __cli_wf_invoke {
	my ($self, $cmd) = @_[ OBJECT, ARG0 ];
	
    # Check if the file is loadable
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
    
    # Design a new workflow
    my $wf = new Module::Workflow::Definition($def);

    # Mark workflow as invoked from CLI
    $self->{CLI_INVOKED}->{$wf->DID} = 1; 

    # Start workflow...
    iAgent::Kernel::Dispatch("cli_write", "Starting workflow ".$wf->NAME);
    return iAgent::Kernel::Dispatch("workflow_invoke", $wf, $self->{ME});
    
}

sub __interrupt {
    my $self = $_[OBJECT];
    log_debug("ABORTING ALL WORKFLOW INSTANCES");
    
    foreach (keys %{$self->{CLI_INVOKED}}) {
        iAgent::Kernel::Dispatch("workflow_abort", $_);
    }
    
    return RET_OK;
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;