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

package Module::Workflow::Definition;

=head1 NAME

Module::Workflow::Definition - Workflow Representation Graph

=head1 DESCRIPTION

This class provides the storage for the entire workflow definition. It holds
all the possible actions, their state redirections and context transformations.

It also holds the current context and active action.

=head2 SAMPLE WORKFLOW

Here is a sample workflow definition. To get more details on how the workflows are
defined and work, see the L</WORKFLOW DEFINITION> section below.

 $workflowGraph->define( 
    
     # Define the actions and their nesting redirects
     ACTIONS => {
     
        1 => {
            action => 'iagent:build',
            parameters => {
                name => 'vm_{$id}_{date|%y-%m-%d}_',
                file => '{$dir_shared}/{$name}'
            },
            route => {
                R0 => 3,	# On result=0
				D => 2,		# Default,
				F => 2		# On failure to invoke
            },
			instances => {
				target => "@targets"	# Loop over the 'targets' array, found in the context
			}
        },
     
        2 => {
            action => 'iagent:log',
            parameters => {
                prefix => "Error: "
            }
        },
     
        3 => {
            action => 'iagent:test',
            parameters => {
                suite => "test_conary_project",
                file => '{$dir_shared}/{$name}{$builder_file}'
            },
            route => {
                R0 => 4,
				D => 2,
				F => 2
            }
        },
        
        4 => {
            action => 'iagent:release',
            parameters => {
                file => '{$dir_shared}/{$name}{$builder_file}',
                target => 'VM Release {$release}'
            },
			route => {
				D => 2,
				F => 2
			}
        }
        
     },
     
     # Start from action #1
     ACTION => 1
    
 });

=head1 WORKFLOW DEFINITION

Here are all the fields supported in a workflow definition. See the description that follows for more details:
 
 {
     ACTIONS => {                   # Action definition
         ..
     },
     ACTIVE => 1,                   # The initial action ID to start the workflow from
     NAME => 'My WF',               # The name of the workflow
     DESCRIPTION => '...',          # The description of the workflow
     CONTEXT => {                   # The initial contents of the workflow context
         ...
     },
     NOTIFY => [ 'me@domain.com' ], # The JIDs to notify for everything that happens in the workflow
     REQUIRED => [                  # The required variables the user must supply for this workflow
        'project', 'path'
     ],
     ERROR_MODE => 'endure'         # How to handle errors when multiple instances are invoked
 }

=head2 ACTIONS (Required)

The hash of the actions that define the workflow. (See L</ACTIONS SYNTAX> below)

=head2 ACTIVE

The initial action ID to start the workflow from (Defaults to 1)

=head2 NAME

The name of the workflow. This is used by the command line as the key name of the workflow, so try putting something
short. 

=head2 DESCRIPTION

A short description of the workflow.

=head2 CONTEXT

The initial value of the context hash.

 CONTEXT => {
     variable => 'value',
     complex_var => {
         'a' => 'hash',
         ...
     }
 }

=head2 NOTIFY

An array with the JIDs of the entities that should be notified for the progress of the workflow.

 NOTIFY => [ 'workflow_observer@domain.com' ]

By default the invoker and the workflow server are placed in this array.

=head2 REQUIRED

An array with the names of all the required context variables that the user MUST supply before invoking
the workflow.

B<NOTICE:> It is very important to put in this array all the variables required by all the involved actions. (Or
at least predefine them in the CONTEXT hash). Otherwise the workflow will fail!

=head2 ERROR_MODE

How to handle errors if something goes wrong in the workflow. (This only makes sense in workflows that spawn
multiple instances or fork).

 ERROR_MODE => 'abort' # or 'endure'

In C<abort> modde, if something goes wrong the entire workflow is aborted and all the running instances are
stopped.

In C<endure> mode, if something goes wrong, only the particular branch fails and the rest of the workflow continues.
Eventually the workflow WILL SUCCEED without triggering the workflow failure targets.

=head1 ACTIONS SYNTAX

The 'actions' hash can have the following fields. For each one of those fields, check the description that follows:

 ACTION_ID => {
     action     => '',      # The name of the action to invoke
     description => '',     # The user-friendly alias of this action
     parameters => { },     # Additional parameters to place in the context before invoking that action
     route      => { },     # Rounting information for this action
     instances  => { },     # Multiple instance information
     timeout    => 100      # How long to wait (in secods) for the action to complete
 }

=head2 ACTION (action)

The name of the action to invoke. This must be the name of the action as defined in the MANIFEST of a workflow-compatible
module. The appropriate module will be discovered at run-time. There is no need (and no support) to explicitly specify a target.

=head2 VISUAL DESCRIPTION (description)

This field specifies a user-friendly alias for the action. If specified this name will be used, in the User Interface instead
of the action name.

=head2 ACTION TIMEOUT (timeout)

Usually it is not needed, but some times you need an explicit timeout for an action. You can specify it through this value.
If the timeout is reached, the 'TO' target will be selected on routing.

=head2 ROUTING (route)

Actions are connected with eachother through routing information (the 'route' hash). The syntax of the routing hash
is simple:

 {
     <state> => <action index>
 }

The possible states are:

=over

=item D

The default target for cases that are not handled.

=item R0 ~ R255

Where to go if the action returned with a value of 0 (R0), 1 (R1) ... till 255(R255)

=item F

Where to go if for some reason the action has failed and you don't want to abort the entire workflow.

=item TL

Where to go if we timed out while trying to lookup a handler for the action.

=item TO

Where to go if the action timed out. (The timeout value must be specified by the 'timeout' parameter of the action).

=back

The possible action indices:

=over

=item 0

Complete the workflow.

=item -1

Abort the workflow.

=item Any other number

Jump to that action.

=back

=head2 PARALLEL INSTANCES (fork)

It is possible to fork the workflow into multiple instances running in parallel. To do so, you just have to define
a fork array. For details see the next secion L</FORKS AND PARALLEL EXECUTION>.

This field is an array refference of hash references. Each hash must have the following fields:

 fork => [
    {
        action => <number>,         # The ID of the action to fork
        parameters => {             # Context parameters to add before execution (Optional)
            'variable' => '{$value}',
            'variable' => {
                complex => '{$value|default}
            }
        }
    }
    ...
 ]

=cut

# Core definitions
use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;
use POE;
use Data::Dumper;
use Data::UUID;
use Date::Format;
use Hash::Merge qw( merge );

##===========================================================================================================================##
##                                                   INITIALIZATION                                                          ##
##===========================================================================================================================##

#######################################################
# Register custom merging function that overrides the
# Array-Array merging: That's because it adds two
# 
#######################################################
Hash::Merge::specify_behavior( # RIGHT_PRECEDENT defaults
    {
        'SCALAR' => {
                'SCALAR' => sub { $_[1] },
                'ARRAY'  => sub { [ $_[0], @{$_[1]} ] },
                'HASH'   => sub { $_[1] },
        },
        'ARRAY' => {
                'SCALAR' => sub { $_[1] },
                ### The entry on the right dominates ###
                'ARRAY'  => sub { \@{$_[1]} },
                ### -------------------------------- ###
                'HASH'   => sub { $_[1] },
        },
        'HASH' => {
                'SCALAR' => sub { $_[1] },
                'ARRAY'  => sub { [ values %{$_[0]}, @{$_[1]} ] },
                'HASH'   => sub { Hash::Merge::_merge_hashes( $_[0], $_[1] ) }, 
        },
    },
    'MERGE_CONTEXT'
);


#######################################################
# Create a new instance to Module::Workflow::Definition
sub new {
#######################################################
    my ($class, $config) = @_;
    
    # Check for cloning
    if (UNIVERSAL::isa($config, "Module::Workflow::Definition")) {
        my %hash = %{$config};
        return bless \%hash, $class;
    }
    
    my $self = bless { 

        # The hash that holds the actions map
        ACTIONS => { },

        # The currently active action
        ACTIVE  => 0,

        # The current context variables
        CONTEXT => { },

        # The unique ID of the workflow definition
        DID => "WD-".Data::UUID->new()->create_str(),

        # The unique ID of the workflow instance
        IID => "WI-".Data::UUID->new()->create_str(),
        
        # Targets to notify on update events
        NOTIFY => [ ],

        # The user-friendly name of the workflow
        NAME => "undef",

        # The workflow mode
        MODE => "distributed", # 'single'       = Run everything on a single node - Abort if an action does not exist (Not used any more)
                               # 'distributed'  = Dynamic node discovery and distributed execution

        # The user who invoked the workflow
        INVOKER => '', 

        # The last result passed to completed() function
        RESULT => 0,
        
        # The required parameters
        REQUIRED => [ ],
        
        # Error mode
        ERROR_MODE => 'abort', # 'abort'    = Fail the entire workflow with all of it's instances
                               # 'endure'   = Fail that particular branch and continue the rest of the workflow
        
    }, $class;

    # Allocate new id
    $self->new_iid();

    # Define workflow if we got a config argument
    $self->define($config) if defined($config);

    return $self;
}

##===========================================================================================================================##
##                                                  HELPER FUNCTIONS                                                         ##
##===========================================================================================================================##


#######################################################
# Evaluate a parameter line. 
#------------------------------------------------------

=head2 ADDITIONAL PARAMETERS (parameters)

This hash provides additional parameters to place in the action's context before invoking it.
Keep in mind that theese parameters will also be available to the other upcoming workflow actions.
Syntax:

 {
     parameter      => 'value',
     parameter      => { hash },
     parameter      => [ array ],
     parameter      => '{$macro}'
 }

There is also support for simple macros (Available only on string) parameters.
The following macros are supported:

  {$var[|default]}       = A (previously defined) context variable
                           or a default value to use if it wasn't found
 
  {date[|format]}        = A timestamp. You can specify a custom
                           format. By default it's "%a %b %e %T %Y"
 
  {uuid[|format]}        = Create a Universally-unique ID in one of the
                           following formats: str (default), hex, b64
 
  {iif|[1|0],true,false} = Check if the first parameter is 0. If yes, evaluate the false
                           part as macro. Otherwise, evaluate the true part as macro.
 

=cut

# -------------------------------
# A helper to evaluate a tag of
# the script syntax.
sub eval_macro {
# -------------------------------
    my ($ctx,$tag) = @_;

    # Check for variables
    if (substr($tag,0,1) eq '$') {
        my ($tag, $default) = split('\|',substr($tag,1));
        $default='' unless defined($default);
        return $ctx->{$tag} if defined($ctx->{$tag});
        return eval_script($ctx, $default);

    } else {
        # Check for function
        my ($func, $args) = split('\|',$tag,2);

        # 1) {date[|format]} tag
        if ($func eq 'date') {
            $args='%a %b %e %T %Y' unless defined($args);
            return time2str($args,time);
        }

        # 2) {uuid} tag
        elsif ($func eq 'uuid') {
            $args='str' unless defined($args);
            return Data::UUID->new()->create_hex() if ($args eq 'hex');
            return Data::UUID->new()->create_b64() if ($args eq 'b64');
            return Data::UUID->new()->create_str();
        }

        # 3) {iif|a,b,c} tag
        elsif ($func eq 'iif') {
        
            # We need additional parsing
            my ($statement, $true, $false) = split(',',$args);
            if (eval_script($ctx, $statement)) {
                return eval_script($ctx, $true);
            } else {
                return eval_script($ctx, $false);
            }
            
        }
                
    }

    # Default...
    return '';
}
#------------------------------------------------------
sub eval_script {
#######################################################
    my ($context, $script) = @_;
    
    # Lookup entire tags
    # This code searches for { ... } tags with nesting capability, something quite tricky
    # to implement only with regular expressions. (Aka: It detects { { .. } .. { .. { .. } .. } } )
    my $nest=0;
    my $ans=''; my $tag='';
    for (my $i=0; $i<length($script); $i++) { # If you count the sub-loops required for other techniques, you'll see
        my $c=substr($script,$i,1);           # that char-by-char parsing is the most efficient.
        $nest++ if ($c eq '{');
        if ($nest == 0) {
            $ans.=$c;
        } else {
            if (($c eq '}') && (--$nest == 0)) { # Second statement is executed only if the first is true
                $ans.=eval_macro($context,substr($tag,1));$tag=''; # $tag contains also the first '{', that's why we strip it
            } else {
                $tag.=$c;
            }
        }
    }

    # Return result
    return $ans;
}


#######################################################
# Traverse the a structure and evaluates all the
# string leaves as macros. 
sub eval_complex {
#######################################################
    my ($context, $structure) = @_;
    
    # String -> Run macro
    if (ref($structure) eq '') {
        return eval_script($context, $structure);
    }
    
    # Array -> Loop over items
    elsif (ref($structure) eq 'ARRAY') {
        my @ans;
        for my $item (@$structure) {
            push @ans, eval_complex($context, $item);
        }
        return \@ans;
    }
    
    # Hash -> Loop over leaves
    elsif (ref($structure) eq 'HASH') {
        my %ans;
        for my $k (keys %$structure) {
            $ans{$k} = eval_complex($context, $structure->{$k});
        }
        return \%ans;
    }
    
    # Uh? What's that!?
    else {
        return $structure;
    }
    
}

########################################################
# Evalue the instance expression into an array of values
#------------------------------------------------------

=head2 MULTIPLE ACTION INSTANCES (instances)

There might be cases that you need to run more than one actions concurrently. Multiple instances can be defined
for the same action. They can vary from pre-defined repeat loops to custom iteration over the keys of a hash.

To define such an action you need to specify the C<instances> parameter in a workflow node. The syntax of this
hash is the following:

 instances => {
	context_variable_to_update => "<loop expression>"
 }

The loop expression is a string that define where and how to fetch the different values for the specifeid variable
of each instance. It's syntax is one of the following:

 instances => {
	target_variable => "@array",    # Loop over the elements of $context->{array} and store it to context
                                    # variable 'target_variable' of each instance.
	target_variable => "#hash",     # Loop over the keys of the hash $context->{hash}.
	target_variable => "%hash",     # Loop over the values of the hash $context->{hash}.
	target_variable => "{$hash}|,"  # Split string $context->{hash} with delimiter ',' and loop over the array elements
	target_variable => "1..10",     # Loop from 1 to 10
	target_variable => "1..{$max}"  # Loop from 1 to the value of variable $max
 }

=cut

sub eval_instance_exp {
########################################################
	my ($context, $expression) = @_;
	my @ans;
	
	# If we have '..' inside the string use a for loop
	if ($expression =~ m/\.\./) {
		my ($start, $stop) = split(/\.\./, $expression);
		$start = eval_script($context,$start); # Macros are allowed in the range
		$stop = eval_script($context,$stop);
		
		# Build the array
		for (my $i=$start; $i<=$stop; $i++) {
			push @ans, $i;
		}
	
	# If we have '|' inside the string use the array splitting mode
	} elsif ($expression =~ m/\|/) {
		my ($str, $delim) = split(/\|/, $expression);
		$str = eval_script($context,$str); # Macros are allowed in the string
		
		# Split the string
		@ans = split($delim, $str);
		
	# If the expression starts with '@' fetch the array value from the context
	} elsif ($expression =~ m/^\@/) {
		my $var = substr($expression,1);
		
		# Set default values if does not exist
		return [ ] unless defined($context->{$var});
		
		# Store array
		@ans = @{$context->{$var}};
		
	# If the expression starts with '#' fetch the hash keys from the hash in the context
	} elsif ($expression =~ m/^\#/) {
		my $var = substr($expression,1);

		# Set default values if does not exist
		return [ ] unless defined($context->{$var});

		# Store keys of the hash
		@ans = keys %{$context->{$var}};
		

	# If the expression starts with '%' fetch the hash values from the hash in the context
	} elsif ($expression =~ m/^\%/) {
		my $var = substr($expression,1);

		# Set default values if does not exist
		return [ ] unless defined($context->{$var});

		# Store keys of the hash
		@ans = values %{$context->{$var}};
		
	}

	# Return array
	return \@ans;

}

#######################################################
# Evaluate an 'instances' hash and return an array whith
# the values we have to loop over.
#
# This function returns an array of hashes. Each hash
# contains the name of the variable that needs to be
# updated and it's value.
#
# For example the instance definition:
#  {
#		i => '0..2',
#  }
#
# Will produce:
#
# [ { i => 0 }, { i => 1 }, { i => 2 }]
#
# More complex structures can be also generated if more
# than one instance definitions are present.
#
sub eval_instance {
#######################################################
	my ($context, $instance) = @_;
	my %value;
	my %index;
	my %length;
	my $last;
	my @ans;
	# (This is actually an n-ary cartesian product problem)

	# Build the values for each defined variable
	my @keys = sort(keys(%$instance));
	foreach (@keys) {
		$value{$_} = eval_instance_exp($context, $instance->{$_}); # Evaluate variable expression
		$index{$_} = 0;
		$length{$_} = scalar @{$value{$_}};
		$last = $_;
	}
	
	# Flatten all the value hashes
	my $looping=1;
	while ($looping) {
		my $h = { };
		
		# Put all of the values
		foreach (@keys) {
			$h->{$_} = $value{$_}->[$index{$_}];
		}
		push @ans, $h;
		
		# Increment the values
		foreach (@keys) {
			if (++$index{$_} >= $length{$_}) {
				$index{$_}=0;
				$looping=0 if ($_ eq $last); # Exit outer loop if we reached the last element
			} else {
				last;
			}
		}
	}
	
	# Return the flat array
	return @ans;
	
}

#######################################################
# Detect recursion in actions definition
sub detect_recursion {
#######################################################
    my ($graph, $pos, $marks) = @_;
    $marks={ } unless defined($marks);
    $pos=1 unless defined($pos);
    
    # Mark our position
    my %marks=%{$marks};
    $marks{$pos}=1;
    
    # Process links
    foreach my $to (values %{$graph->{$pos}->{route}}) {
        if ($to != 0) { # 0 is considered the end of the workflow, so don't scan it
            if (defined($marks->{$to})) { # Found recursion
                return 1
            } else { # Scan deeper
                return 1 if (detect_recursion($graph, $to, \%marks));
            }
        }
    }
    
    # Process forks (if we are a forkable workflow)
    if (defined($graph->{$pos}->{fork})) {
        foreach my $fork (@{$graph->{$pos}->{fork}}) {
            my $to = $fork->{action};
            
            # Check for recursive actions
            if ($to != 0) { # 0 is considered the end of the workflow, so don't scan it
                if (defined($marks->{$to})) { # Found recursion
                    return 1
                } else { # Scan deeper
                    return 1 if (detect_recursion($graph, $to, \%marks));
                }
            }
            
        }
    }

    # No recursion found
    return 0;
    
};

##===========================================================================================================================##
##                                                 SHORTHAND FUNCTIONS                                                       ##
##===========================================================================================================================##

#######################################################
# Get the workflow definition ID
sub DID {
#######################################################
    my $self = shift;
    return $self->{DID};
}

#######################################################
# Get the workflow instance ID
sub IID {
#######################################################
    my $self = shift;
    return $self->{IID};
}

#######################################################
# Get the workflow NAME
sub NAME {
#######################################################
    my $self = shift;
    return $self->{NAME};
}

#######################################################
# Get the active action ID
sub ACTIVE {
#######################################################
    my $self = shift;
    return $self->{ACTIVE};
}

#######################################################
# Get the workflow MODE
sub MODE {
#######################################################
    my $self = shift;
    return $self->{MODE};
}

#######################################################
# Get the workflow ERROR_MODE
sub ERROR_MODE {
#######################################################
    my $self = shift;
    return $self->{ERROR_MODE} or 'abort';
}

#######################################################
# Get an array with the targets to notify
sub NOTIFY {
#######################################################
    my $self = shift;
    return @{$self->{NOTIFY}};
}

#######################################################
# Get the name of the invoker
sub INVOKER {
#######################################################
    my $self = shift;
    return $self->{INVOKER};
}

#######################################################
# Get the definition of the active action
sub ACTION {
#######################################################
    my $self = shift;
    return $self->{ACTIONS}->{$self->{ACTIVE}};
}

#######################################################
# Get the updated context for the specified action
sub CONTEXT {
#######################################################
    my ($self, $context) = @_;
    my $action = $self->ACTION;
    $context = $self->{CONTEXT} unless defined($context);
    $context = { } unless (defined $context);
    my %_context = %$context; # Clone

    # Update context if we have parameters
    if (defined $action->{parameters}) {
        foreach my $var (keys %{$action->{parameters}}) {
            $_context{$var} = eval_complex($context, $action->{parameters}->{$var});
        }
    }

    # Return the (cloned) context reference
    return \%_context;
    
}

#######################################################
# Return an array of workflow definitions depending on the
# currently active action's instance definition
#
# This function returns an array of Module::Workflow::Definition
# objects with their context properly updated in order to run
# the uncoming action.
#
sub INSTANCES {
#######################################################
	my ($self) = @_;
    my $action = $self->ACTION;
	my $context = $self->CONTEXT;
	
	# New stuff!!!
	# If we have 'fork' directive, do something more advanced
	if (defined($action->{fork})) {
	    
	    # Prepare instances array
	    my @instances;
	    
	    # Fork contains the workflow nodes to fork to
	    # for parallel execution
	    foreach my $fork (@{$action->{fork}}) {

		    # Prepare new context
            my %_context = %$context; # Clone
            
            # Update context if we have parameters specified
            if (defined $fork->{parameters}) {
                foreach my $var (keys %{$fork->{parameters}}) {
                    $_context{$var} = eval_complex($context, $fork->{parameters}->{$var});
                }
            }
		
    		# Single instance
    		my $wf = new Module::Workflow::Definition($self);
    		
    		# Allocate new ID and a new context
    		$wf->new_iid;
    		$wf->{CONTEXT} = \%_context;
    		$wf->{ACTIVE} = $fork->{action};
    		
    		log_msg("Prepared fork instance: ".Dumper($wf->DEFINITION));
    		
    		# Put it in the instances array
	        push @instances, $wf;
	        
	    }

        # Return instances
		return \@instances;
	    
	}

	# Non-fork techniques - old syntax
	else {

    	# If we don't have instance information the action
    	# is a single instance
    	if (!defined $action->{instances}) {
		
    		# Single instance, default context
    		my $wf = new Module::Workflow::Definition($self);
    		$wf->new_iid;
    		return [ $wf ];
		
    	} else {
		
    		# Fetch instance values
    		my @values = eval_instance($context, $action->{instances});
		
    		# Build actions
    		my @ans;
    		foreach (@values) {
		    
    			# Update context variables from the new context
                my $merge = Hash::Merge->new('MERGE_CONTEXT');
    			my $ctx = $merge->merge($context,$_);
    			my $wf = new Module::Workflow::Definition($self);
    			$wf->{CONTEXT} = $ctx;
        		$wf->new_iid;
    			push @ans, $wf;
			
    		}
		
    		# Return array
    		return \@ans;
				
    	}

    }

}

#######################################################
# Get the definition of the workflow, ready to be re-
# used with the define function of another workflow...
sub DEFINITION {
#######################################################
    my $self = shift;
    return {
        ACTIONS => $self->{ACTIONS},
        ACTIVE => $self->{ACTIVE},
        DID => $self->{DID},
        IID => $self->{IID},
        NAME => $self->{NAME},
        NOTIFY => $self->{NOTIFY},
        INVOKER => $self->{INVOKER},
        MODE => ($self->{MODE} or 'distributed'),
        CONTEXT => $self->{CONTEXT},
        REQUIRED => $self->{REQUIRED},
        ERROR_MODE => ($self->{ERROR_MODE} or 'abort')
    };
}

#######################################################
# Check if we are completed
sub COMPLETED {
#######################################################
    my $self = shift;

    # We are completed only if the current workflow action is '0'
    return ($self->{ACTIVE} == 0);
       
}

##===========================================================================================================================##
##                                                REQUESTING FUNCTIONS                                                       ##
##===========================================================================================================================##

#######################################################
# Initialzie our context with the specified parameters
# and validate them. If everything goes smoothly, it
# returns 1 and updates the context. Otherwise
# it returns 0.
sub init_context {
#######################################################
    my ($self, $context) = @_;
    return 1 unless defined($self->{REQUIRED});
    
    # Create a hash map from the array
    my %hash = map { $_ => 1 } @{$self->{REQUIRED}};
    foreach (keys %$context) {
        delete $hash{$_} if (defined($hash{$_})); # Remove it from the require list
        $self->{CONTEXT}->{$_} = $context->{$_};  # Update context variable
    }
    
    # If we have entries left in the hash, we have mising
    # parameters
    return 0 if (scalar keys %hash);
    return 1
    
}

#######################################################
# Check what's the maximum number of steps we can walk 
# inside the action graph, starting from the specified
# action ID.
sub depth {
#######################################################
    my ($self, $action) = @_;
	$action=1 unless defined($action);
    return 0 unless defined($self->{ACTIONS}->{$action});

    # Start depth
    my $depth = 0;

    # Scan result branches
    foreach my $k (keys %{$self->{ACTIONS}->{$action}->{route}}) {
        my $a = $self->{ACTIONS}->{$action}->{route}->{$k};
        my $d = $self->depth($a);
        $depth=$d if ($d>$depth);
    }

    # Return the depth
    return $depth+1;    
}

#######################################################
# Define the workflow graph from the specified hash
sub define {
#######################################################
    my $self = shift;
    my $hash = $_[0];
    if (ref($hash) ne 'HASH') {  # Fetch parameters as hash if the first argument is not hash
        my %hash = @_;
        $hash=\%hash;
    }
    
    # Manually process actions in order to fill missing
    # fields with defaults    
    if (defined($hash->{ACTIONS})) {
        my %ACTIONS;
        foreach my $k (keys %{$hash->{ACTIONS}}) {
            my $a = $hash->{ACTIONS}->{$k};

            # Fill common fields
            $a->{route} = { } unless defined ($a->{route});
            $a->{route}->{D} = 0 unless defined ($a->{route}->{D});
            $a->{distributed} = 1 unless defined($a->{distributed});
            $a->{description} = '' unless defined ($a->{description});
            
            # Check for fork actions
            if (defined($a->{fork})) {

                # Validate fork syntax
                return RET_SYNTAXERR if (ref($a->{fork}) ne 'ARRAY');

                # Validate fork children
                foreach (@{$a->{fork}}) {
                    return RET_SYNTAXERR if (!defined($_->{action}));
                }

                # Fill missing fields
                $a->{type} = 'fork';
                $a->{action} = 'Fork::#'.$k; # Pseudo-name TODO: Cleanup code to remove the need of this
                
            } else {

                # Fill missing fields
                $a->{type} = 'workflow';
                $a->{parameters} = { } unless defined ($a->{parameters});
                
            }

            # Store action
            $ACTIONS{$k}=$a;
        }
        
        # Ensure we don't have recursion in our actions
        if (detect_recursion(\%ACTIONS, $hash->{ACTIVE})) {
            return RET_DENIED;
        }
        
        # Update actions
        $self->{ACTIONS} = \%ACTIONS;
    }
    
    # Defaults
    $self->{ACTIVE} = 1;

    # Update from definition
    $self->{ACTIVE} = $hash->{ACTIVE} if defined($hash->{ACTIVE});
    $self->{CONTEXT} = $hash->{CONTEXT} if defined($hash->{CONTEXT});
    $self->{DID} = $hash->{ID} if defined($hash->{ID});
    $self->{DID} = $hash->{DID} if defined($hash->{DID});
    $self->{IID} = $hash->{IID} if defined($hash->{IID});
    $self->{NAME} = $hash->{NAME} if defined($hash->{NAME});
    $self->{NOTIFY} = $hash->{NOTIFY} if defined($hash->{NOTIFY});
    $self->{INVOKER} = $hash->{INVOKER} if defined($hash->{INVOKER});
    $self->{MODE} = $hash->{MODE} if defined($hash->{MODE});
    $self->{REQUIRED} = $hash->{REQUIRED} if defined($hash->{REQUIRED});
    $self->{ERROR_MODE} = $hash->{ERROR_MODE} if defined($hash->{ERROR_MODE});

    # Fix some possible bugs
    $self->{NOTIFY}=[$self->{NOTIFY}] unless(ref($self->{NOTIFY}) eq 'ARRAY');
    
    # Return OK
    return RET_OK;
}

#######################################################
# Merge a response context with my context
sub merge_context {
#######################################################
    my ($self, $ctx) = @_;

    # Update new fields
    my $merge = Hash::Merge->new('MERGE_CONTEXT');
	$self->{CONTEXT} = $merge->merge($self->{CONTEXT}, $ctx);
    
}

#######################################################
# Check if the specified action ID is being used (and
# thus not free to be released).
sub id_used {
#######################################################
    my ($self, $id, $chosen_result) = @_;

    # Active ID is used, yes :)
    return 1 if ($id == $self->{ACTIVE});

    # Scan connections
    foreach my $i (keys %{$self->{ACTIONS}}) {
        foreach my $r (keys %{$self->{ACTIONS}->{$i}->{route}}) {
            # If we have a connection, assume it's used
            return 1 if ($self->{ACTIONS}->{$i}->{route}->{$r} == $id);
        }
    }
    return 0;
}

#######################################################
# Track the used IDs:
# Start from the specified node ID and traverse the tree
# locating the used action IDs
sub track_used {
#######################################################
    my ($self, $id, $used) = @_;
    $used ={ } unless defined($used);
    return { } unless defined($self->{ACTIONS}->{$id});

    # Scan result branches
    foreach my $k (keys %{$self->{ACTIONS}->{$id}->{route}}) {
        my $a = $self->{ACTIONS}->{$id}->{route}->{$k};
        if (!defined($used->{$a}) && defined($self->{ACTIONS}->{$a})) {

            # I am now used :)
            $used->{$a}=1;

            # Fetch the usage of the specified target action
            $self->track_used( $a, $used );
            
        }
    }

    # Return the used IDs
    return $used;
    
}

#######################################################
# Purge orphan actions
sub purge {
#######################################################
    my ($self) = @_;

    # Purge the nodes that are not used any more
    my $used = $self->track_used($self->{ACTIVE});
    $used->{$self->{ACTIVE}}=1; # 'ACTIVE' id is used!
    $used->{0}=1; # Action '0' is the error sink. Keep it!
    foreach my $id (keys %{$self->{ACTIONS}}) {
        delete $self->{ACTIONS}->{$id} if (!$used->{$id});
    }

}

#######################################################
# Push an entity that needs to be notified in the 
# notification stack.
sub notify {
#######################################################
    my ($self, $entity) = @_;

    # Ensure it's not already there
    foreach (@{$self->{NOTIFY}}) {
        return if ($_ eq $entity);
    }

    # Add entity
    my @entries = @{$self->{NOTIFY}};
    push @entries, $entity;
    $self->{NOTIFY} = \@entries;
    
}

#######################################################
# Switch to a different action ID, and if the parent
# action is not used any more, release it...
sub switch {
#######################################################
    my ($self, $id) = @_;
    $id=0 unless defined($id);
    return unless defined($self->{ACTIONS}->{$id});

    # Switch to new action
    $self->{ACTIVE} = $id;

    # Purge unused nodes
    # TODO: Fix purge
    #$self->purge;
    
}

#######################################################
# Allocate a new unique instance ID for this workflow
sub new_iid {
#######################################################
    my $self = shift;
    $self->{IID} = "WI-".Data::UUID->new()->create_str();
}

#######################################################
# Allocate a new unique definition ID for this workflow
sub new_did {
#######################################################
    my $self = shift;
    $self->{DID} = "WD-".Data::UUID->new()->create_str();
}

#######################################################
# Notify that the action was unable to be invoked. Check
# if the currently active action has an 'F' routing
# rule and if it does, switch current action there
sub fail {
#######################################################
	my ($self, $type) = @_;
	my $action = $self->ACTION;
	$type='F' unless defined($type);
	
	# If we have no 'F' rule, return 0
	return 0 unless (defined($action->{route}->{$type}));

	# If we have 'F' rule, switch to there
	my $nid = $action->{route}->{$type};
	if ($nid == 0) {
		
        # Switch to 0
        $self->{ACTIVE}=0;

        # Purge evertrhing
        $self->{ACTIONS}={ };
			
	} else {
    	$self->switch($action->{route}->{$type});
	}

	# Return OK
	return 1;
}

#######################################################
# Notify that the action is completed with the specified
# return code. This automatically switches to the 
# appropriate action.
sub completed {
#######################################################
    my ($self, $code, $mode) = @_;
    $mode="R" unless defined($mode);

    # Keep the last result value passed to this function
    $self->{RESULT} = $code;

    # Pick a proper action ID
    my $nid = 0; # Defaults to the sink

    # Pick default
	if (defined($self->{ACTIONS}->{$self->{ACTIVE}})) {

        # Use default action ID if nothing is found
        $nid = $self->{ACTIONS}->{$self->{ACTIVE}}->{route}->{D};

        # Lookup for the appropriate handler for the return code
        if (defined($self->{ACTIONS}->{$self->{ACTIVE}}->{route}) &&
            defined($self->{ACTIONS}->{$self->{ACTIVE}}->{route}->{"$mode$code"})) {

            # Pick a new ID
            $nid = $self->{ACTIONS}->{$self->{ACTIVE}}->{route}->{"$mode$code"};
        }
        
    }

    # If we are now at 0, we are done
    if ($nid == 0) {

        # Switch to 0
        $self->{ACTIVE}=0;

        # Purge evertrhing
        $self->{ACTIONS}={ };

        # Return 1 as a signal that we are done
        return 1;
    }

    # Switch there
    $self->switch($nid);

    # And we are still ongoing
    return 0;

}

=head1 FORKS AND PARALLEL EXECUTION

There is a special kind of action node, called 'fork' node, that is capable of forking multiple childs that wiill run
concurrently. Every time a fork happens, a new workflow context is created, thus children will not share context updates
but they will rather continue their own path.

To define a fork node, define an action using the following format:

 {
      ACTIONS => {
          ...
          
          '<number>' => {
              description => 'Fork description',    # The user-friendly alias of the node
              fork => [                             # The actions to run in parallel
                
                  {
                      action => <number>,
                      parameterss => {
                          <context>
                      }
                  },
                  
                  ...
                  
              ],
              route => {                            # The routing to be performed when all the forked instances complete
                  D => <next action id>,
                  R1 => <failure action id>,
                  ...
              }              
          }
      }
 }

The forking works by duplicating the workflow definition, updating the context with the specified parameters and setting
the active action to the defined action. Then the same code that handles L<MULTIPLE ACTION INSTANCES (instances)> takes control.

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
