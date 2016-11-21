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

iAgent::Kernel - The main iAgent Kernel

=head1 DESCRIPTION

This perl module provides a simple interface to register plug-in modules and to dispatch system-wide messages.

=head1 FUNCTIONS

=cut

package iAgent::Kernel;
use strict;
use warnings;

use iAgent::Log;
use Data::Dumper;

#sub POE::Kernel::TRACE_SIGNALS { 1 };
#sub POE::Kernel::TRACE_SESSIONS { 1 };
#sub POE::Kernel::TRACE_EVENTS { 1 };
use POE;

require Exporter;
our @ISA        = qw(Exporter);
our @EXPORT     = qw(Dispatch Broadcast Reply Query RET_PASSTHRU RET_OK RET_ABORT RET_ABORTED RET_UNHANDLED RET_DENIED RET_NOTFOUND RET_AVAILABLE
                     RET_COMPLETED RET_SCHEDULED RET_BUSY RET_ERROR RET_INCOMPLETE RET_REJECTED RET_INVALID RET_SYNTAXERR RET_CANCEL);

#
# Common return values callbacks can return
#
sub RET_PASSTHRU    { undef };  # Passthru this command. Like it was never called...
sub RET_OK          { 1 };      # Everything was OK. Continue...
sub RET_ABORT       { 0 };      # Abort the message stack

#
# Additional values received from Dispatch or Broadcast
#
sub RET_UNHANDLED   { -1 };     # No plugin handled this event
sub RET_ABORTED      { 0 };     # The message was aborted

#
# Additional, not frequently used return values
# (Used in special cased by the modules. Not used by the kernel)
#
sub RET_COMPLETED    { 2 };     # The command was completed
sub RET_SCHEDULED    { 3 };     # The command was scheduled for future execution
sub RET_ERROR       { -3 };     # There was an error but it shouldn't abort the dispatch of the message
sub RET_REJECTED    { -4 };     # The command was rejected, but don't abort the dispatch of the message
sub RET_INCOMPLETE  { -5 };     # The command was incomplete
sub RET_BUSY        { -6 };     # The command handler was busy
sub RET_INVALID     { -7 };     # The command was invalid
sub RET_DENIED      { -8 };     # The command was denied
sub RET_UNSUPPORTED { -9 };     # The command was not supported
sub RET_SYNTAXERR   {-10 };     # Syntactical error on the command
sub RET_NOTFOUND    {-11 };     # Something was not found
sub RET_CANCEL      {-12 };     # The command was cancelled but it shouldn't abort the dispatch of the message
sub RET_AVAILABLE   {-13 };     # The command is available but was not executed

# The properly sorted array of the array sessions
our @SESSIONS;

# The names of all the registered callbacks in <name> => <number of references> format.
# This is used to avoid dispatching messages that will for sure have no
# receiver and will run a pointless dispatching loop.
our $REGISTERED_MESSAGES = {};

# The indexing hash between session instances (keys)
# and the appropriate index in @SESSIONS array (values)
# (Used for fast index resolving)
my $SESSION_INDEX = {};

# The last session that was active on the POE::Kernel
# when Query() or Dispatch() was called;
our $LAST_SOURCE;

# The stack of last sources, used to satisfy nested Dispatch calls
my @DISPATCH_STACK;

# That's the delay (in seconds) of the default NOP loops
# the sessions without main loop will have.
# --------------------------------------------------------------
# /!\ If the whole system is not responding fast, decrease this
# value. However, keep in mind that decreasing this value too much
# might cause higher un-needed CPU load 
# --------------------------------------------------------------
sub LOOP_DELAY 	{ 0.25 };

# Forward declerations
sub getClassHooks;

=head2 Register HASHREF

Register a module on the iAgent system.

This system instances the specified class, initializes it, wraps it in a POE session,
and registers it on the broadcast system.

Syntax:

  iAgent::Kernel::Register({
  	
  	class => "My::Module",       - The class name of the module to instance
  	args  => { .. args .. },     - The arguments passed to the C<new> function and C<_start> event
  	
  })

=head3 Module manifests

All the special information regarding the module priority, the handled POE Events, the config etc. are
provided by the module manifest. To define a module manifest, you should create a global MANIFEST variable
in the class with the following syntax:

  package mySystem::myModule;
  use strict;
  
  our $MANIFEST = {
  	
  	#
  	# [1] Define the hooks for the PoE events
  	#     You have 3 options:
  	#
  	# a) Use automatic detection (default)
  	#     
  	# In this mode, the Kernel will scan the class subroutines and will
  	# convert the ones prefixed with the specified prefix into event
  	# handlers of the omonymous event. For example:
  	# 
  	#  sub __random_event () { }
  	#
  	# Will be called when the 'random_event' is dispatched.
  	#
  	# You can change the default prefix ('__') with your own, using the
  	# hooks_prefix field.
  	#
  	
  	hooks => 'AUTO',
  	hooks_prefix => '__',
  	
  	#
  	# b) Use only specified event handlers that have the same name
  	#     with the event
  	#
  	
  	hooks => [ 'start', 'stop', 'msg_arrived', 'msg_dispatched' ],
  	
  	#
  	# c) Explicitly define what subs handle what event
  	#
  	
  	hooks => {
  		'start' => 'start_handler',
  		'msg_arrived' =>  'data_handler',
  		'data_arrived' => 'data_handler'
  	}
  	
  	#
  	# [2] Define the (optional) configuration file associated with this module
  	#
  	# This configuration file must be located on iAgent's etc folder.
  	#
  	
  	config => 'my_config.conf',
  	
  	#
  	# [3] Define the module priority
  	#
  	# Each module has a specific priority. When a event is dispatched it starts from
  	# the module with the highest priority until it reaches the target. This helps
  	# adding pre/post processing modules for the events. Some typical priorities follow:
  	#
  	# +----------+--------------------------------------------+
  	# | Priority |                  Typical use               |
  	# +----------+--------------------------------------------+
  	# |  0 ~ 1   | I/O Modules, such as the XMPP module       |
  	# |  2 ~ 4   | Filtering modules such as authentication,  |
  	# |          | authorization etc, such as LDAP Module     |
    # |    5     | Default module priority                    |
    # |  6 ~ 10  | Post-processing modules                    |
    # +----------+--------------------------------------------+  	 
    #
    
    priority => 6
    
  };

A typical manifest will have the following structure:

  our $MANIFEST = {
  	config => 'your config here.conf',
  	priority => 5
  };

If nothing specified (not even the $MANIFEST variable), the defaults are:

  our $MANIFEST = {
  	hooks => 'AUTO',
  	hooks_prefix => '__',
  	priority => 5
  };

=head3 POE Compatibility

The kernel creates a POE Session for each module. It uses an intuitive design in order to require less
code while designing modules.

First of all, you never create the PoE Session yourself. You only define the class for your module, and
provide the required hook handlers. The system will then analyze your class, instance it and register it
on the PoE and Broadcast system.

The instance is performed that way:

  $instance = new YOURCLASS ( \%CONFIG_FILE_HASH );

And then registered in a dedicated POE session that way:

  POE::Session::Create(
  
    args => \%CONFIG_FILE_HASH,
    
    object_states => {
    	
    	$YOUR_OBJECT_INSTANCE => {
    		
    		# Automatically detected or manually
    		# defined (from the MANIFEST) hooks
    		...
    		
    	}
    	 
    },
    
    heap => {
    	CLASS => 'Your::class::package::name',
    	MANIFEST => \%YOUR_CLASS_MANIFEST
    }
    
  )

=cut

sub Register {
	my ($params) = @_;
	
	# Set option defaults
	log_die("Class not specified on Kernel::Register")	unless defined $params->{class};
	$params->{args} = {}			unless defined $params->{args};
	$params->{hooks} = 'AUTO'  		unless defined $params->{hooks};
	$params->{hooks_prefix}='__'	unless defined $params->{hooks_prefix};
	$params->{priority} = 5			unless defined $params->{priority};

	# Extract some options to local space
	my $class = $params->{class};
	my $args = $params->{args};
	
	# Build hooks table from the class
	my $hooks = { };
    if (UNIVERSAL::isa($params->{hooks}, 'HASH')) {
        
        # Just move the reference as-is
        $hooks = $params->{hooks};
        
    } elsif (UNIVERSAL::isa($params->{hooks}, 'ARRAY')) {
        
        # Register the hook names
        foreach (@$params->{hooks}) {
            $hooks->{$_} = $_;
        }
        
    } elsif ($params->{hooks} eq "AUTO") {
        
        # Search class's symbol table and look
        # for subs that are prefixed with hooks_prefix
        log_debug("Automatic hook detection requested");

        # Fetch all the hooks for this class
        $hooks = iAgent::Kernel::getClassHooks($class, $params);
        
    } else {
        log_die("Unable to detect how to handle hooks for module $class! (Defined as ".$params->{hooks}.")");
    }

	# Update the REGISTERED_MESSAGES hash
	foreach (keys %$hooks) {
		$REGISTERED_MESSAGES->{$_}=0 unless defined($REGISTERED_MESSAGES->{$_});
		$REGISTERED_MESSAGES->{$_}++;
	}
	
	# Instance class
	my $inst = new $class($args);
    
    # If we don't have a start hook, create some extra logic
    # for an infinite loop
    my $sess;
    if (!defined $hooks->{_start}) {

        #
		# Create session with an additional
		# Infinite core loop
		#
		$sess = POE::Session->create(
			args => $args,
			object_states => [
				$inst => $hooks
			],
			inline_states => {
				_start => sub {
					$_[KERNEL]->delay( ___dummy_loop___ => LOOP_DELAY );
					$_[KERNEL]->yield("_setup"); # Allow user to register '_setup' to do initialization, if he doesn't care about the loop
				},
				___shutdown___ => sub {
				    log_debug("Killing session of module ".$_[HEAP]->{CLASS});
				    $_[HEAP]->{ALIVE}=0;
				    $_[KERNEL]->call($_[SESSION], '_cleanup');
				    $_[KERNEL]->signal($_[SESSION],'QUIT');
				},
				___dummy_loop___ => sub {
				    return if (defined ($_[HEAP]->{ALIVE})) && ($_[HEAP]->{ALIVE}==0);
					$_[KERNEL]->delay( ___dummy_loop___ => LOOP_DELAY );
				}
			},
			heap => {
				CLASS => $class,
				MANIFEST => $params,
				ALIVE => 1
			}
		);    	
    	
    } else {
    
		# Create session the usual way
		$sess = POE::Session->create(
			args => $args,
			object_states => [
				$inst => $hooks
			],
            inline_states => {
				___shutdown___ => sub {
				    log_debug("Killing session of module ".$_[HEAP]->{CLASS});
				    $_[HEAP]->{ALIVE}=0;
				    $_[KERNEL]->signal($_[SESSION],'QUIT');
				}
            },
            heap => {
                CLASS => $class,
                MANIFEST => $params,
                ALIVE => 1
            }
		);
    	
    }	
	
	# Store object
	my $_info = {
		class => $class,
		session => $sess,
		instance => $inst,
		manifest => $params,
		priority => $params->{priority},
		hooks => $hooks
	};
	
	# Stack 'n sort
	push @SESSIONS, $_info;
	@SESSIONS = sort { $a->{priority} <=> $b->{priority}} @SESSIONS;
	
	# Update session indexes for quick reference
	for (my $i=0; $i<=$#SESSIONS; $i++) {
        $SESSION_INDEX->{$SESSIONS[$i]->{session}} = $i;
	}
		
	log_msg("Plugin $class loaded");
	
	# Return the new object
	return $_info;
	
}

=head2 Broadcast MESSAGE, ...

Asynchronously broadcast a message.

This function posts a message to all the registered sessions (using the Register function). This 
function exits immediately with return value '1', so no further processing can be done
on the result. 

  iAgent::Kernel::Broadcast(
    'message',
    .. args ..
  )

=cut

sub Broadcast {
	my $msg = shift;
	my @args = @_;
    $LAST_SOURCE = $poe_kernel->get_active_session;

	if ($LAST_SOURCE == $poe_kernel) {
		log_debug("Broadcasting '$msg' from KERNEL");
	} else {
		log_debug("Broadcasting '$msg' from ".$LAST_SOURCE->get_heap()->{CLASS});
	}

	# Prohibit sending private messages
	return RET_ABORT if (substr($msg,0,1) eq '_');

	# Do not send anything if this message is not handled by anybody
	return RET_UNHANDLED if (!defined($REGISTERED_MESSAGES->{$msg}));

	foreach my $_info (@SESSIONS) {
		
		# Do not send this message to the session if the latter do not support it
		next if (!defined($_info->{hooks}->{$msg}));
		
		# Post message
		POE::Kernel->post($_info->{session}, $msg, @args);
		
	};
	return 1;
}

=head2 Dispatch MESSAGE, ...

Synchronously broadcast a message.

This function calls the specified message handler on each registered session, waits for a reply
and continues accordingly:

If the message handler returns B<0> the message broadcasting stops. No upcoming plugin receives that
message.

If the message handler returns B<1> the message broadcast continues. (Thats usually what you should
always return)

If the message handler returns any other value, the broadcast continues, and additionally the return
value of the function is set to that value.

  my $result = iAgent::Kernel::Dispatch(
    'message',
    .. args ..
  )

The function retuns the following values:

=over

=item -1

If no plugin received the event 

=item -2

If no plugin responded

=item 0

If the message dispatch was canceled

=item 1

If the message was processed successfuly

=item Anything else

If the message was processed successfuly, and the return value is the return value of the last handler's return value.

=back

=cut

our @_DEBUG_DISPATCH_STACK;

sub Dispatch {
	my $msg = shift;
	my @args = @_;
	my $ans = RET_UNHANDLED;

	# Fetch last source
	$LAST_SOURCE = $poe_kernel->get_active_session;
	
	if ($LAST_SOURCE == $poe_kernel) {
		log_debug("Dispatching '$msg' from KERNEL");
	} else {
		log_debug("Dispatching '$msg' from ".$LAST_SOURCE->get_heap()->{CLASS});
	}
	
	# Prohibit sending private messages
	return RET_ABORT if(substr($msg,0,1) eq '_');

	# Do not send anything if this message is not handled by anybody
	return RET_UNHANDLED if (!defined($REGISTERED_MESSAGES->{$msg}));

	# Push last used source on stack
	push @DISPATCH_STACK, $LAST_SOURCE;
	
	# Show the current state of the stack
    push @_DEBUG_DISPATCH_STACK, $msg;
    my $d_msg = join('->',@_DEBUG_DISPATCH_STACK);
	log_debug("   Stack: [ $d_msg ]");

	foreach my $_info (@SESSIONS) {
		
		# Do not send this message to the session if the latter do not support it
		next if (!defined($_info->{hooks}->{$msg}));
		
		# Send the message
        log_debug("Dispatching '$d_msg' to ".$_info->{class});
		my $cans = POE::Kernel->call($_info->{session}, $msg, @args);
		$cans = RET_UNHANDLED unless defined $cans;
		log_debug(" > Result = $cans");

		# Handle answer
		if (defined $cans)  {
			if ($cans == RET_ABORT) { # Dispatch aborted
				log_debug("Dispatch of '$d_msg' aborted by ".$_info->{class});
                pop @_DEBUG_DISPATCH_STACK;
				$LAST_SOURCE = pop(@DISPATCH_STACK);
				return RET_ABORTED;
				
			} elsif ($cans == RET_UNHANDLED) { # Not responded
			    # Keep the response to 'not handled'
			    # unless a different value is already set

            } elsif ($cans == RET_OK) { # We got OK

                # If we got OK, switch to "OK" unless a different
                # value was already returned
                $ans=RET_OK if ($ans==RET_UNHANDLED);
			    
			} else { # Everything else is a value we should return
				$ans = $cans;
			}
		}
		
	}
	log_debug("$d_msg dispatch successful: $ans");

	# Update dispatch source
	$LAST_SOURCE = pop(@DISPATCH_STACK);
    pop @_DEBUG_DISPATCH_STACK;

	return $ans;
}


=head2 Query MESSAGE, ...

Query all the plugins

This function is simmilar to C<Dispatch>. However, this function just collects all the return
values and stacks them in an array.

The return value of this function is an array reference that conains the results of the called
message handlers.

  my $results = iAgent::Kernel::Query('message', ...);
  
  # The result is something like:
  $results = {
  	
  	$object => # Return Value #
  	
  };

=cut

sub Query {
    my $msg = shift;
    my @args = @_;
    my @ans;
    $LAST_SOURCE = $poe_kernel->get_active_session;
	log_debug("Querying modules with '$msg' from ".$LAST_SOURCE->get_heap()->{CLASS});

	# Prohibit sending private messages
	return RET_ABORT if(substr($msg,0,1) eq '_');

	# Do not send anything if this message is not handled by anybody
	return RET_UNHANDLED if (!defined($REGISTERED_MESSAGES->{$msg}));

	# Query plugins
    foreach my $_info (@SESSIONS) {

		# Do not send this message to the session if the latter do not support it
		next if (!defined($_info->{hooks}->{$msg}));

		# Call the message handler
        my $cans = POE::Kernel->call($_info->{session}, $msg, @args);
        $cans = RET_UNHANDLED unless defined $cans;
		next if ($cans == RET_UNHANDLED);
		last if ($cans == RET_ABORT);

		# Collect result
		if (UNIVERSAL::isa($cans, 'ARRAY')) { # Merge array elements
        	push @ans, @{$cans};
		} else {
			if (ref($cans) ne '') { # Objects and hashes go as-is...
	        	push @ans, $cans;
			} else { # Scalars are checked for numeric values
				if ($cans =~ m/-?\d+/) {
					next if ($cans < 0)
				}
	        	push @ans, $cans;
			}
		}
    }

    return \@ans;
}

=head2 Reply MESSAGE, ...

Reply to a currently active message.

It is recommended to use this function to reply to C<Dispatch> or C<Broadcast>, rather than using directly POE,
becuase this function also processes the message through the plugin stack.

This function detects the target and caller's position in the hierectary and then dispatches the event
to all the plugins inbetween.

  my $result = iAgent::Kernel::Reply(
    'message',
    .. args ..
  )

=cut

sub Reply {
    my $msg = shift;
    my @args = @_;
    my $ans = RET_UNHANDLED;

    return undef if (!$LAST_SOURCE);

	# Prohibit sending private messages
	return RET_ABORT if(substr($msg,0,1) eq '_');
    
    my $target = $LAST_SOURCE;
    my $clsname = ref($target);
    my $target_heap = $target->get_heap();
    if (defined $target_heap->{CLASS}) { $clsname=$target_heap->{CLASS}; };
    log_debug("Replying '$msg' to plugin ".$clsname);
    
    # Locate the hierectary of the src/dst plugins
    my $caller = $poe_kernel->get_active_session;
    my $cls_src = $caller->get_heap()->{CLASS};
    my $cls_dst = $target->get_heap()->{CLASS};
    my $h_src = $SESSION_INDEX->{$caller};
    my $h_dst = $SESSION_INDEX->{$target};
    log_debug("Calller ($cls_src) has hierectary=".$h_src." bubbling up/down to target ($cls_dst) hierectary=".$h_dst);
    
    # Detect bubbling direction
    my $direction = ($h_dst>$h_src)?1:-1;
    
    # Bubble up/down the event on the plugin chain
    for (my $i=$h_src+$direction; (($i>=$h_dst) && ($direction<0)) || (($i<=$h_dst) && ($direction>0)) ; $i+=$direction) {
        	my $_info = $SESSIONS[$i];
    	
        log_debug("Replying '$msg' to ".$_info->{class});
        my $cans = POE::Kernel->call($_info->{session}, $msg, @args);
		$cans = RET_UNHANDLED unless defined $cans;

        # Handle answer
		if (defined $cans)  {
			if ($cans == RET_ABORT) { # Dispatch aborted
				log_debug("Replying of '$msg' aborted by ".$_info->{class});
				return RET_ABORTED;
				
			} elsif ($cans == RET_UNHANDLED) { # Not responded
			    # Keep the response to 'not handled'
			    # unless a different value is already set

            } elsif ($cans == RET_OK) { # We got OK

                # If we got OK, switch to "OK" unless a different
                # value was already returned
                $ans=RET_OK if ($ans==RET_UNHANDLED);
			    
			} else { # Everything else is a value we should return
				$ans = $cans;
			}
		}

    }
    
    log_debug("Replying successful: $ans");
    return $ans;
}


=head2 Crash ERROR_MESSAGE, [ HASHREF ]

Notify a plugin crash

This function is either called by an error trap or by the plugin itself when an unrecoverable error occured.
This function will unregister the plugin from the message queue, do the appropriate cleanup and log/reporting
and if possible, try to reload the plugin.

If there was a successful restart, the event 'recovered' will be sent to the plugin, passing as first argument
the hash that was passed to this function as a second argument. This enables a custom recovery handling
mechanism for the plugins.

This function should be called from within the plugin class and has the following syntax:

  iAgent::Kernel::Crash(
    'crash message',
    { .. details hash .. } # Optional
  )

=cut

sub Crash {
    my $msg = shift;
    my $h_details = shift;
        
    # Locate the hierectary of the src/dst plugins
    my $caller = $poe_kernel->get_active_session;
    if ($caller == $poe_kernel) {

        # Called while initializing. That's serious...
        log_die("Unable to start iAgent because a plugin crashed during start-up! Error: $msg");
    
    }
    my $cls_src = $caller->get_heap()->{CLASS};
    my $mfst_src = $caller->get_heap()->{MANIFEST};
    my $idx_src = $SESSION_INDEX->{$caller};
    
    # Fetch the detailed info from the session hash
    my $details = $SESSIONS[$idx_src];

	# Remove handled messages
	foreach (keys %{$details->{hooks}}) {
		$REGISTERED_MESSAGES->{$_}--;
		delete($REGISTERED_MESSAGES->{$_}) if($REGISTERED_MESSAGES->{$_}<=0);
	}
    
    # Do the logging
    log_error("The plugin ".$cls_src." crashed because of an unrecoverable error: $msg");
    log_debug("=== POST MORTEM FOR PLUGIN ".$cls_src." ===\nACTIVE_EVENT=".$poe_kernel->get_active_event."\nINSTANCE=".Dumper($details->{instance}));
    log_rip(); # Just for fun, and to detect crash positions. Delete me
    
    # Shutdown plugin's session (synchronously)
    POE::Kernel->signal($caller, '___shutdown___');
    
    # Remove plugin from existance
    splice @SESSIONS, $idx_src, 1;
    delete $SESSION_INDEX->{$caller};    
    
    # Re-sort sessions
    @SESSIONS = sort { $a->{priority} <=> $b->{priority}} @SESSIONS;
    
    # ---------------------------------- #
    # Now the plugin rests in peace :)   #
    # ---------------------------------- #
    
    # Check what we should do after...
    my $oncrash = 'unload'; # Default? Unload!
    $oncrash = $mfst_src->{oncrash} unless not defined $mfst_src->{oncrash};
    if ($oncrash eq 'reload') {
    	# Reload the plugin after a crash
    		    
        # Register a new session that will only register
        # the plugin back to the iAgent Kernel and then die
        my $sess = POE::Session->create(
            inline_states => {
            	_start => sub {
                    my ($heap, $kernel) = @_[HEAP, KERNEL];
                    log_msg("Recovering the plugin that just died in 3 seconds");
            		$_[KERNEL]->delay( respawn => 3, 0);
            	},
            respawn => sub {
                	
                	# Fetch heap
                	my ($heap, $kernel) = @_[HEAP, KERNEL];

			        # Re-register the plugin
			        my $info = iAgent::Kernel::Register($heap->{MANIFEST});
			        
			        # Broadcast the 'recovered' message only to this plugin
			        $kernel->post($info->{session}, '_recover', $heap->{DETAILS});
			        
			        # Do not make any attempt to keep the session
			        # alive, just let it die...
                }
            },
            heap => {
                DETAILS => $h_details,
                MANIFEST => $mfst_src
            }
        );
        
        # Don't forget to detach from the current session!
        # It's going to die!
        POE::Kernel->detach_child($sess);
        

    } elsif ($oncrash eq 'die') {
        	# Exit after a plugin crash
        	log_die("iAgent died because of an unrecoverable error on ".$cls_src.": $msg");

    } elsif ($oncrash eq 'restart') {
        	# Restart the whole application (!)
        	
    	
    }
    
    # Otherwise we are done here.
    # Return an error code
    return -1;
    
}


=head2 RegisterHandler SESSION, MESSAGE, [ MESSAGE, ... ]

=head2 RegisterHandler MESSAGE, [ MESSAGE, ... ]

Inform the iAgent kernel that the calling session will handle the specified event(s) even though it's 
not specified through the manifest. 

In order to optimize iAgent internal message dispatching mechanism, it's keeping a table of all the
registered messages and dispatches them only on targets that can handle it. If a session registeres a
POE message during run-time, the kernel will not be aware of this fact and will not deliver the message
there. In order to bypass this, you need to call this function to update the module's capabilities. 

  $_[SESSION]->_register_state('dynamic_event', \&_dyn_event );
  iAgent::Kernel::RegisterHandler( 'dynamic_event' );

If your script is registering a handler on a different session, you can specify it as a first argument:

  $other_session->_register_state('dynamic_event', \&_dyn_event );
  iAgent::Kernel::RegisterHandler( $other_session, 'dynamic_event' );

=cut

sub RegisterHandler {
	my @messages = @_;
    
    # Locate the caller
	my $caller = undef;
	if (UNIVERSAL::isa($messages[0], 'POE::Session')) {
		$caller = shift(@messages);		
	} else {
	    $caller = $poe_kernel->get_active_session;
	    if ($caller == $poe_kernel) {
	        log_error("Unable to register global message handler! Please call RegisterHandler from within your session!");
			return RET_ERROR;
	    }
	}
    
    # Fetch the detailed info from the session hash
    my $idx_src = $SESSION_INDEX->{$caller};
    my $details = $SESSIONS[$idx_src];

	# Register extra messages
	foreach (@messages) {
		
		# To the REGISTERED_MESSAGES
		$REGISTERED_MESSAGES->{$_}=0 unless defined($REGISTERED_MESSAGES->{$_});
		$REGISTERED_MESSAGES->{$_}++;
		
		# And to the session information
		$details->{hooks}->{$_} = $_;
	}
	
	# And we are done!
	return RET_OK;

}


=head2 UnregisterHandler SESSION, MESSAGE, [ MESSAGE, ... ]

=head2 UnregisterHandler MESSAGE, [ MESSAGE, ... ]

Unregister a message handler previously registered with RegisterHandler. Here is a usage exampl

  $_[SESSION]->state('dynamic_event');
  iAgent::Kernel::UnregisterHandler( 'dynamic_event' );

If your script is registering a handler on a different session, you can specify it as a first argument:

  $other_session->state('dynamic_event' );
  iAgent::Kernel::UnregisterHandler( $other_session, 'dynamic_event' );

=cut

sub UnregisterHandler {
	my @messages = @_;
    
    # Locate the caller
	my $caller = undef;
	if (UNIVERSAL::isa($messages[0], 'POE::Session')) {
		$caller = shift(@messages);		
	} else {
	    $caller = $poe_kernel->get_active_session;
	    if ($caller == $poe_kernel) {
	        log_error("Unable to register global message handler! Please call RegisterHandler from within your session!");
			return RET_ERROR;
	    }
	}
    
    # Fetch the detailed info from the session hash
    my $idx_src = $SESSION_INDEX->{$caller};
    my $details = $SESSIONS[$idx_src];

	# Register extra messages
	foreach (@messages) {
    	
		# Remove this hook
		delete $details->{hooks}->{$_};
		
		# Decrease/delete state information
		if (defined($REGISTERED_MESSAGES->{$_})) {
		    $REGISTERED_MESSAGES->{$_}--;
		    delete $REGISTERED_MESSAGES->{$_} if ($REGISTERED_MESSAGES->{$_} <= 0);
		}
		
	}
	
	# And we are done!
	return RET_OK;

}

=head2 ModuleLoaded STRING

Check if the specified module is loaded. Example:

 if (!iAgent::Kernel::ModuleLoaded('iAgent::Module::XMPP')) {
    log_die("You need an XMPP module!");
 }

=cut

sub ModuleLoaded {
    my $module = shift;

    # Scan sessions and check for this name
	foreach (@SESSIONS) {
	    return 1 if ($_->{class} eq $module);
    }

    # Not found
    return 0;
}

=head2 Exit CODE

Shut down iAgent Kernel.

Shuts down gracefully the kernel and all the sessions by sending the SIGQUIT signal to all of the active
sessions.

=cut

my $EXITING = 0;
sub Exit {
    
    my $code = shift;
    return if $EXITING;
    $EXITING=1;

    # Store the code as the iAgent's return code
    if (defined $code) {
        $iAgent::RETURN = $code;
    } else {
        $iAgent::RETURN = 0;
    }

    # Notify everybody that we are going for shutdown
    iAgent::Kernel::Dispatch("exit");

    # Send SIGTERM to all of the active sessions
	foreach (@SESSIONS) {
	    log_debug("Sending SIGQUIT to session ".$_->{session}->get_heap()->{CLASS});
	    POE::Kernel->post($_->{session}, '___shutdown___'); 
	    # ^ Originally, I was using Kernel->signal(session,'QUIT'), but it was not working properly, because
	    #   when a modules invokes Exit, it's own session also will be killed synchronously and the modules that comes
	    #   after it will remain alive. Additionally, modules with __dummy_loop__ that were trapping SIGINT improperly
	    #   were not terminated...
	    #
	    #   Solution: On every session, a custom event: ___shutdown___ is registered by the kernel. This event terminates the 
	    #   __dummy_loop__ (if exists) and sends in the session itself the 'QUIT' signal.
	    #
    }
    
}

    
################################################################
# Recursive helper function to detect all the package subs and 
# automatically build hooks. (This function also traverses the
# superclasses of the packages)
#
sub getClassHooks {
#################################################################
    my ($class, $params) = @_;
    my $hooks = { };
    
    # Disable warnings 
    no strict 'refs';

    # Prepare prefixes
    my $cname = $class.'::';
    my $pfx = $params->{hooks_prefix};
    my $lpfx = length $pfx;

    # Subclassed? Fetch subclass subs....
    if (defined @{$cname.'ISA'}) {
        foreach (@{$cname.'ISA'}) {
            # Fetch and merge sub-hooks
            my $sub_hooks = iAgent::Kernel::getClassHooks($_, $params);
            foreach (keys %$sub_hooks) {
                $hooks->{$_} = $sub_hooks->{$_};
            }
        }
    }
    
    # Traverse all the symbols in class's symbol table
    for(keys %$cname) {
      my $func = $_;
      if (defined &{$cname.$func}) { # We found a method
        if (substr($func, 0, $lpfx) eq $pfx) {
            log_debug("Hook detected: ".substr($func, $lpfx)." => $cname$func");
            $hooks->{substr($func, $lpfx)} = $func;
        }
      }
    }
    
    # Enable strict again 
    use strict 'refs';  

    # Return hooks
    return $hooks;  
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
