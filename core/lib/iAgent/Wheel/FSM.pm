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

iAgent::Wheel::FSM - iAgent Finite-State-Machine Helper

=head1 DESCRIPTION

This POE wheel simplifies the development of Finite-State-Machines inside the iAgent project. 
It generates automatically states and binds them to the state core by just parsing the given class.

=head1 USAGE

To use the iAgent::FSM you must first create a class file that will host your implementation. 
To handle a state, just prefix the state name with '_STATE_'. For instance:

 package FSM::MyImplementation
 
 # Create instance
 sub new {
     my ($class, $context) = @_;
     return bless({ context => $context }, $class);
 }
 
 # Handler of state 'setup'
 sub _STATE_setup {
     my ($self, $kernel, $machine, $context) = @_[ SELF, KERNEL, ARG0, ARG1 ];
     
     print "Entered state 'setup'\n";
     
     # Switch state
     $machine->goto( 'second' );
 }
 
 # Handler of state 'second'
 sub _STATE_second{
     my ($self, $kernel, $machine, $context) = @_[ SELF, KERNEL, ARG0, ARG1 ];
     
     print "Entered state 'second'\n";
     
     # Switch state after a timeout
     $machine->after( 5 => 'third' );
 }
 
 # Handler of state 'third'
 sub _STATE_third {
     my ($self, $kernel, $machine, $context) = @_[ SELF, KERNEL, ARG0, ARG1 ];

     print "Entering state 'third'\n";

     # Wait for event
     $machine->on( 'event' => 'completed' );
 }

Now to create an instance of this FSM you can use the following:

 iAgent::Wheel::FSM->new(
        class => 'FSM::MyImplementation',
        context => {
            ... some initial contet ...
        }
     )

You can also get feedback when the FSM reaches a particular state. For example:
 
 iAgent::Wheel::FSM->new(
       class => 'FSM::MyImplementation',
       context => { }
       
       # This will be fired when the FSM starts
       on_setup => 'do_action',
       
       # This will be fired when the FSM is completed
       on_completed => do_another_action'
    )

=head1 CONTEXT INTEGRITY

The FSM wheel will try it's best never to destroy any references stored in the context hash. You can 
rely on this as long as you are using only the FSM functions to alter your context.

All the updates performed by the FSM actions will only edit or create new entries in the context
hash, even when a state handler is running in a detached session. Values will never be derefrenced
or converted to scalar.

=head1 DEFINING FSM METHODS

Your FSM handling class is a regular perl package with an automatic hook resolver that handles 
the following methods:

=head2 _STATE_* methods

Each method prefixed with '_STATE_' will be registered as an FSM state handler. You can only 
switch between states that you have already defined using this prefix. 

For example:

 sub _STATE_setup {
     my ($self, $kernel, $machine, $context) = @_[ SELF, KERNEL, ARG0, ARG1 ];
     
     # Unless otherwise defined, 'setup' is the first state of the FSM
     
 }

=head2 _EVENT_* methods

Those methods provide real-time capture of events that are broadcasted via the FSMBroadcast method.
You can use these methods to provide input to your FSM instances without the need of directly addresing them.

For example:

 sub _STATE_message_arrived {
     my ($self, $kernel, $machine, $context, ... ) = @_[ SELF, KERNEL, ARG0, ARG1, ... ];
    
     # This will be immediately called when FSMBroadcast('message_arrived', ...) is used
    
 }

=head2 __* methods

Those methods are simmilar to iAgent Module hook handlers. They are used as an entry point where POE messages
are required. The FSM module will automatically populate a hash named 'CALLBACKS' in your FSM instance that maps
your desired name to the actual state name that is registered on POE.

For example:

 sub __a_late_message {
     print "This is delayed for 5 seconds\n";
 }
 
 sub _STATE_completed {
     my ($self, $kernel) = @_[ OBJECT, KERNEL ];
     
     $kernel->delay( $self->{CALLBACKS}->{a_late_message} => 5 );
 }

=head1 METHODS

The following methods are exposed from the iAgent::Wheel::FSM module:

=cut

package iAgent::Wheel::FSM;
use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;

use Data::Dumper;
use Hash::Merge qw( merge );

use POE;
use POE::Wheel;
use POE::Wheel::Run;
use POE::Filter::Line;
use POE::Filter::Reference;
use base qw( POE::Wheel );

use Scalar::Util qw(looks_like_number);

require Exporter;
our @ISA        = qw( Exporter );
our @EXPORT     = qw( MACHINE CONTEXT P_IGNORE P_BUFFER P_LOG P_PASSTHROUGH );
our @EXPORT_OK  = qw( FSMBroadcast FSMEvent );

sub POLL_INTERVAL           { 0.01 };

sub MACHINE                 { ARG0 };
sub CONTEXT                 { ARG1 };

sub P_IGNORE                { 0 };
sub P_BUFFER                { 1 };
sub P_LOG                   { 2 };
sub P_PASSTHROUGH           { 3 };

sub SELF_TRIGGERS           { 0  };
sub SELF_CLASS              { 1  };
sub SELF_INSTANCE           { 2  };
sub SELF_WHEEL_ID           { 3  };
sub SELF_CONTEXT            { 4  };
sub SELF_STATE              { 5  };
sub SELF_NEW_STATE          { 6  };
sub SELF_FINAL_STATE        { 7  };
sub SELF_STATES             { 8  };
sub SELF_LOCAL_STATE_TIMER  { 9  };
sub SELF_LOCAL_STATE_GOTO   { 10 };

my $last_fsmevent_id        = 0;

##========================================================================================================================##
##                                                    BASIC WHEEL IMPLEMENTATION                                          ##
##========================================================================================================================##

=head2 new

FSM Constructor.

=cut

##################################################
# Create a new isntance to the iAgent Queue Wheel
sub new {
##################################################
    my $class = shift;
    my %config = @_;
    
    # Critical error if class is not defined
    log_die("Class was not specified for iAgent::Wheel::FSM!") unless defined($config{class});
    
    # Create/Ensure defaults
    $config{entry} = 'setup' unless defined($config{entry});
    $config{final_state} = 'completed' unless defined($config{final_state});
    $config{error_state} = 'failed' unless defined($config{error_state});
    $config{context} = {} unless defined($config{context});
    
    # Create a handler FSM class instance
    my $h_class = $config{class};
    my $inst = new $h_class($config{context});
    
    # Detect hooks and event handlers
    my $hooks = iAgent::Kernel::getClassHooks($config{class}, { hooks_prefix => '_STATE_' });
    my $events = iAgent::Kernel::getClassHooks($config{class}, { hooks_prefix => '_EVENT_' });
    my $poe_hooks = iAgent::Kernel::getClassHooks($config{class}, { hooks_prefix => '__' });
    
    # Generate unique names for the hooks
    # and setup states in the same time.
    my $uid = POE::Wheel::allocate_wheel_id();
    my $wheel_states = { };
    my $wheel_events = { };
    for my $k (keys %$hooks) {
        my $wk = "${class}\@${uid}->state_$k";
        $wheel_states->{$k} = $wk;
        $poe_kernel->state($wk, $inst, $hooks->{$k} );
    }
    for my $k (keys %$events) {
        my $wk = "${class}\@${uid}->event_$k";
        $wheel_events->{$k} = $wk;
        $poe_kernel->state($wk, $inst, $events->{$k} );
    }
    
    # Process event triggers from the config
    my $triggers = { };
    for my $k (keys %config) {
        if (substr($k,0,3) eq 'on_') {
            $triggers->{substr($k,3)} = $config{$k};
        }
    }
    
    # Setup POE Callbacks
    my $callbacks = { };
    for my $k (keys %$poe_hooks) {
        my $wk = "${class}\@${uid}->hook_$k";
        $callbacks->{$k} = $wk;
        $poe_kernel->state($wk, $inst, $poe_hooks->{$k} );
    }
    $inst->{CALLBACKS} = $callbacks;
    
    # Setup class
    my $self = {
        # Local variables
        triggers => $triggers,
        class => $config{class},
        instance => $inst,
        wheel_id => $uid,
        context => $config{context},
        
        # A flag to see if there are routes scheduled after an event handle
        scheduled => 0,
        
        # State switching
        state => "",
        new_state => $config{entry},
        new_state_args => [ ],
        final_state => $config{final_state},
        error_state => $config{error_state},
        
        # Dynamic states names for the FSM states
        states => $wheel_states,
        events => $wheel_events,
        temp => [ ],
        
        # Detached execution information
        detached => undef,
        detached_child => 0,
        detached_uid => "${class}\@{uid}::detach",
        
        # Registered POE states
        LOCAL_STATE_TIMER => "${class}\@${uid}->__fsm_timer",
        LOCAL_STATE_GOTO => "${class}\@${uid}->__fsm_goto",
        LOCAL_STATE_D_COMPLETED => "${class}\@${uid}->__detach_completed",
        LOCAL_STATE_D_REAP => "${class}\@${uid}->__detach_reaped",
        LOCAL_STATE_D_STDOUT => "${class}\@${uid}->__detach_stdout",
        LOCAL_STATE_D_STDERR => "${class}\@${uid}->__detach_stderr",
        LOCAL_STATE_X_COMPLETED => "${class}\@${uid}->__exec_completed",
        LOCAL_STATE_X_REAP => "${class}\@${uid}->__exec_reaped",
        LOCAL_STATE_X_STDOUT => "${class}\@${uid}->__exec_stdout",
        LOCAL_STATE_X_STDERR => "${class}\@${uid}->__exec_stderr",
    };
    
    # Instantiate
    $self = bless($self, $class);
    $inst->{MACHINE} = $self;
    
    # Setup timer
    $poe_kernel->state($self->{LOCAL_STATE_TIMER}, $self, '__fsm_timer' );
    $poe_kernel->state($self->{LOCAL_STATE_GOTO}, $self, '__fsm_goto' );
    $poe_kernel->state($self->{LOCAL_STATE_D_COMPLETED}, $self, '__detach_completed' );
    $poe_kernel->state($self->{LOCAL_STATE_D_REAP}, $self, '__detach_reaped' );
    $poe_kernel->state($self->{LOCAL_STATE_D_STDOUT}, $self, '__detach_stdout' );
    $poe_kernel->state($self->{LOCAL_STATE_D_STDERR}, $self, '__detach_stderr' );
    $poe_kernel->state($self->{LOCAL_STATE_X_COMPLETED}, $self, '__exec_completed' );
    $poe_kernel->state($self->{LOCAL_STATE_X_REAP}, $self, '__exec_reaped' );
    $poe_kernel->state($self->{LOCAL_STATE_X_STDOUT}, $self, '__exec_stdout' );
    $poe_kernel->state($self->{LOCAL_STATE_X_STDERR}, $self, '__exec_stderr' );
    $poe_kernel->delay($self->{LOCAL_STATE_TIMER}, 0);

    # Setup real-time event handlers
    my $session = $poe_kernel->get_active_session();
    my $heap = $session->get_heap();
    $heap->{_FSM_} = {} unless defined($heap->{_FSM_});
    $heap->{_FSM_}->{realtime} = {} unless defined($heap->{_FSM_}->{realtime});
    for my $event (keys %$wheel_events) {
        $heap->{_FSM_}->{realtime}->{$event} = {} unless defined($heap->{_FSM_}->{realtime}->{$event});
        $heap->{_FSM_}->{realtime}->{$event}->{$uid} = [ $session, $wheel_events->{$event}, $self ];
    }
    
    # Return an iAgent::FSM instance
    return $self;
}

##################################################
# Update the event handlers
sub event {
##################################################
    my $self = shift;
    my %events = @_;
    
    # Setup events
    for my $k (keys %events) {
        if (substr($k,0,3) eq 'on_') {
            $self->{triggers}->{substr($k,3)} = $events{$k};
        }
    }
}

##################################################
# Good ol' perl destructor...
sub DESTROY {
##################################################
  my $self = shift;
  
  log_debug("FSM Deleted");
  
  # Release wheel
  POE::Wheel::free_wheel_id($self->{wheel_id});
}

##========================================================================================================================##
##                                                      HELPER FUNCTIONS                                                  ##
##========================================================================================================================##

##################################################
# Forward-merge hash references without destroying
# the referenced components. This is not as powerful
# as hash-merge, but it keeps the references intact.
sub ___forward_merge {
##################################################
    my ($target, $updates) = @_;
    
    # Process only hashes
    foreach my $k (keys %$updates) {
        if (UNIVERSAL::isa($updates->{$k}, 'HASH')) {
            if (defined($target->{$k}) && UNIVERSAL::isa($target->{$k}, 'HASH')) {
                ___forward_merge($target->{$k}, $updates->{$k});
                next;
            }
        }
        $target->{$k} = $updates->{$k};
    }
}

##################################################
# Remove all the event handlers that are registered
# for the on() and onPOE() state change triggers.
sub __cleanup_events {
##################################################
    my ($self, $heap) = @_;
    return if !defined($heap->{_FSM_});
    return if !defined($heap->{_FSM_}->{events});
    
    # Remove all the events we are registered (for 'on')
    my $id = $self->{wheel_id};
    for my $event (values %{$heap->{_FSM_}->{events}}) {
        delete $event->{$id} if defined($event->{$id});
    }
    
    # Remove temporary events (for 'onPOE')
    for my $event (@{$self->{temp}}) {
        $poe_kernel->state($event);
        iAgent::Kernel::UnregisterHandler( $event );
    }

}

##################################################
# Remove all the timers associated with this FSM
# during a after() state change trigger.
sub __cleanup_timers {
##################################################
    my ($self, $heap) = @_;
    
    # Remove pending alarm
    $poe_kernel->delay($self->{LOCAL_STATE_GOTO});
}

##################################################
# Internal loop that switches between states and
# cleanups everything when done.
sub __fsm_timer {
##################################################
    my ($self, $kernel, $session, $heap) = @_[ OBJECT, KERNEL, SESSION, HEAP ];
    
    # Switch state if we are told to do so
    if ($self->{new_state} ne '') {
        
        # Switch state
        my $state = $self->{new_state};
        $self->{new_state} = "";
        $self->{state} = $state;
        
        # Cancel pending timers and unregister event handlers
        $self->__cleanup_timers($heap);
        $self->__cleanup_events($heap);
        
        # Notify event change triggers
        #   It will call the hook from current session and if not found it will use iAgent::Kernel to 
        #   Dispatch the message though all iAgent Modules.
        if( defined ( $self->{triggers}->{$state} ) ) {
            my $hr = $kernel->call( $session, $self->{triggers}->{$state}, $self, $self->{context} );
            # returns undef if hook not found
            Dispatch( $self->{triggers}->{$state}, $self, $self->{context} ) if not defined $hr;
        }
        
        # Reset schedule flag
        $self->{scheduled} = 0;
        
        # Call the state change with a security trap
        eval {
            $kernel->call($session, $self->{states}->{$state}, $self, $self->{context}, @{$self->{new_state_args}})
                if defined($self->{states}->{$state});
        };
        if ($@) {
            log_warn("FSM ".$self->{class}." failed! $@");
            $self->{context}->{error} = $@;
            $self->{context}->{error_code} = 500;
            $self->goto('failed');
        }
        
        # Reset new state arguments after being used
        $self->{new_state_args} = [ ];
        
        # If the flag is still reset it means that the programmer didn't
        # schedule any state change as he's supposed to. Let a warning and die
        if (!$self->{scheduled} && ($state ne $self->{final_state}) && ($state ne $self->{error_state})) {
            log_warn("The FSM ".$self->{class}." did not schedule any state change changes at $state");
            $self->($self->{error_state}, { error => "The FSM ".$self->{class}." did not schedule any state change changes at $state", error_code => "FSM_INTERNAL" });
        }
        
    }
    
    # If we are on the last state, break loop
    if (($self->{state} eq $self->{final_state}) || ($self->{state} eq $self->{error_state})) {
        
        # Unregister from our references in order to let POE kill us
        $self->__cleanup($heap);
        
        # Exit loop
        return;
    }
    
    # Otherwise, infinite loop
    $kernel->delay($self->{LOCAL_STATE_TIMER}, POLL_INTERVAL);
}

##################################################
# A POE-Accessible equivalent of goto.
sub __fsm_goto {
##################################################
    my ($self, $state, $context, $arguments) = @_[ OBJECT, ARG0, ARG1, ARG2 ];
    $self->{new_state_args} = $arguments if ($arguments);
    $self->goto($state, $context);
}

##################################################
# Cleanup all our instances for shutdown
sub __cleanup {
##################################################
    my ($self, $heap) = @_;
    
    # Remove state bindings from instance
    foreach my $name (values %{$self->{instance}->{CALLBACKS}}) {
        $poe_kernel->state($name);
    }
    
    # Remove references to other instances
    delete $self->{instance}->{MACHINE};
    delete $self->{instance};
    
    # Remove state handlers
    $poe_kernel->state($self->{LOCAL_STATE_TIMER});
    $poe_kernel->state($self->{LOCAL_STATE_GOTO});
    $poe_kernel->state($self->{LOCAL_STATE_D_COMPLETED});
    $poe_kernel->state($self->{LOCAL_STATE_D_REAP});
    $poe_kernel->state($self->{LOCAL_STATE_D_STDOUT});
    $poe_kernel->state($self->{LOCAL_STATE_D_STDERR});
    $poe_kernel->state($self->{LOCAL_STATE_X_COMPLETED});
    $poe_kernel->state($self->{LOCAL_STATE_X_REAP});
    $poe_kernel->state($self->{LOCAL_STATE_X_STDOUT});
    $poe_kernel->state($self->{LOCAL_STATE_X_STDERR});
    
    # Remove all the dynamic states
    foreach my $name (values %{$self->{states}}) {
        $poe_kernel->state($name);
    }
    foreach my $name (values %{$self->{events}}) {
        $poe_kernel->state($name);
    }
    
    # Remove real-time event handlers
    foreach my $event (keys %{$self->{events}}) {
        delete $heap->{_FSM_}->{realtime}->{$event}->{$self->{wheel_id}};
    }
    
    # Cleanup timers
    $self->__cleanup_timers($heap);
    $self->__cleanup_events($heap);
    
}

##========================================================================================================================##
##                                                  FSM STATE CHANGE FUNTIONS                                             ##
##========================================================================================================================##

##################################################
# Schedule a state switch
# ------------------------------------------------

=head2 goto NEW_STATE [, CONTEXT_HASHREF ] [, ARGUMENTS_ARRAYREF ]

This function switches to the new given state. Anyfurther calls on this function will be ignored
until the next __fsm_timer tick.

The second argument is a hash reference to the values that you want to update in the FSM's context
before switching to that state.

=cut

# ------------------------------------------------
sub goto {
##################################################
    my ($self, $state, $context, $arguments) = @_;
    
    # If the state is already changed, do nothing
    return if ($self->{new_state} ne '');
    
    # Validate state
    if (($state ne $self->{final_state}) && ($state ne $self->{error_state}) && !defined($self->{states}->{$state})) {
        log_warn("State $state was not implemented by the FSM ".$self->{class});
        return;
    }

    # If we are detached child, just put the event
    # in the detached stack
    return __detach_send_event('goto', $state, $context) if ($self->{detached_child});
    
    # Mark state for switch on the next timer cycle
    log_debug("Switched to state $state");
    $self->{new_state} = $state;
    $self->{new_state_args} = $arguments if ($arguments);
    
    # We are about to switch state, kill detached process if it's still running
    $self->__kill_detached if defined($self->{detached});
    
    # Update context
    ___forward_merge($self->{context}, $context)
        if defined($context);
    
    # Set scheduled flag
    $self->{scheduled} = 1;
    
}

##################################################
# Schedule a state switch after a timeout
# ------------------------------------------------

=head2 after DURATION_SECONDS => NEW_STATE [, CONTEXT_HASHREF ]

This function will set a timer that will switch the FSM to NEW_STATE after
DURATION_SECONDS.

The third argument is a hash reference to the values that you want to update in the FSM's context
before switching to that state.

=cut

# ------------------------------------------------
sub after {
##################################################
    my ($self, $delay, $state, $context) = @_;
    
    # Validate state
    if (($state ne $self->{final_state}) && ($state ne $self->{error_state}) && !defined($self->{states}->{$state})) {
        log_warn("State $state was not implemented by the FSM ".$self->{class});
        return;
    }

    # If we are detached child, just put the event
    # in the detached stack
    return __detach_send_event('after', $delay, $state, $context) if ($self->{detached_child});
    
    # Set timer
    $poe_kernel->delay($self->{LOCAL_STATE_GOTO}, $delay, $state, $context);
    
    # Set scheduled flag
    $self->{scheduled} = 1;
    
}

##################################################
# Schedule a state switch on event
# ------------------------------------------------

=head2 on EVENT => NEW_STATE, [ FILTER_CODEREF [, CONTEXT_HASHREF ]]

This function will listen for events (broadcasted using iAgent::Wheel::FSM::FSMBroadcast)
and will switch to NEW_STATE upon arrival. 

You can optionally specify a filter function. This function sould return a true value
if the message broadcasted is valid. For example:

 $machine->on( 'xmpp_request' => 'reply', sub {
     my ($self, $message) = @_;
     return ($message->{action} eq 'chat');
 } )

The fourth argument is a hash reference to the values that you want to update in the FSM's context
before switching to that state.

=cut

# ------------------------------------------------
sub on {
##################################################
    my ($self, $event, $state, $filter, $context) = @_;
    
    # Validate state
    if (($state ne $self->{final_state}) && ($state ne $self->{error_state}) && !defined($self->{states}->{$state})) {
        log_warn("State $state was not implemented by the FSM ".$self->{class});
        return;
    }

    # If we are detached child, just put the event
    # in the detached stack
    return __detach_send_event('on', $event, $state, $filter, $context) if ($self->{detached_child});
    
    # Get (the common) heap
    my $session = $poe_kernel->get_active_session();
    my $heap = $session->get_heap();
    
    # Prepare session
    $heap->{_FSM_} = {} unless defined($heap->{_FSM_});
    $heap->{_FSM_}->{events} = {} unless defined($heap->{_FSM_}->{events});
    $heap->{_FSM_}->{events}->{$event} = {} unless defined($heap->{_FSM_}->{events}->{$event});
    
    # Expose this event via session's heap
    $heap->{_FSM_}->{events}->{$event}->{$self->{wheel_id}} = [ $self, $state, $filter, $context ];
    
    # Set scheduled flag
    $self->{scheduled} = 1;
}

##################################################
# Schedule a state switch on a POE event
# ------------------------------------------------

=head2 onPOE EVENT => NEW_STATE [, CONTEXT_HASHREF ]

This function will register a POE listener for the specified event. When the event is received
the appropriate state handler will be called. 

All the arguments passed on the POE event will be forwarded to the state handler starting at ARG2,
since ARG0 is a reference to the FSM and ARG1 is a reference to the context.

The third argument is a hash reference to the values that you want to update in the FSM's context
before switching to that state.

=cut

# ------------------------------------------------
sub onPOE {
##################################################
    my ($self, $event, $state, $context) = @_;
    
    # Validate state
    if (($state ne $self->{final_state}) && ($state ne $self->{error_state}) && !defined($self->{states}->{$state})) {
        log_warn("State $state was not implemented by the FSM ".$self->{class});
        return;
    }

    # If we are detached child, just put the event
    # in the detached stack
    return __detach_send_event('onPOE', $event, $state, $context) if ($self->{detached_child});
    
    # Register a temporary state for the given event
    my $goto_state = $self->{LOCAL_STATE_GOTO};
    $poe_kernel->state($event, sub {
        my ($self, $kernel, $session) = @_[ OBJECT, KERNEL, SESSION ];
        my @args = @_[ARG0..ARG9];
        log_debug("Proxying event $event to $goto_state");
        $kernel->yield($goto_state, $state, $context, \@args);
    });
    
    # Register to receive iAgent events
    iAgent::Kernel::RegisterHandler( $event );
    
    # Mark this as temporary
    push @{$self->{temp}}, $event;
    
    # Set scheduled flag
    $self->{scheduled} = 1;
}

##################################################
# Detach from current process but keep the FSM context
# ------------------------------------------------

=head2 detach CODEREF [, PARAMETERS ...]

Invoking this function will create a POE::Wheel::Run that will
start the given sub in the background. The function will be
started with excactly the same arguments as the parent and the
$machine reference will still work if you want to switch states.

You can also register state changes in the parent FSM using
the appropriate parameters.

For example:

 $machine->detach(
     
     on_completed => "<The state to switch when completed>",
     on_error => "<The state to switch on error>",

     parameters => [ <Additional user parameters> ],
     
     sub {
         my ($self, $machine, $context) = @_[ OBJECT, ARG0, ARG1 ];
     }

     );

If a state switch occurs before this function is finished, the
instance will be killed and it's output will be ignored.

Inside the function STDOUT will be redirected to STDERR. That's because
a POE::Filter::Reference is created to receive information from the instance
and it will use STDOUT for that. STDERR will be used for logging.

Any output on STDERR will be echoed to STDOUT of the agent.

=cut

# ------------------------------------------------
sub detach {
##################################################
    my $self = shift;
    my $sub = undef;
    my @args = @_;
    my $i=0;

    # We cannot have multiple children detached
    if ($self->{detached_child}) {
        log_error("You cannot nest detached processes!");
        return;
    }
    
    # Find the code reference
    for my $arg (@args) {
        if (ref($arg) eq 'CODE') {
            $sub = $arg;
            splice @args, $i, 1;
            $i++;
        }
    }
    
    # The rest is configuration
    my $user_args = [ ];
    my %config= @args;
    $user_args = $config{parameters} if defined($config{parameters});
    
    # Make sure the states exist
    # (Brace yourself, heavily nested code is coming!)
    if (defined($config{on_completed}) && 
         (($config{on_completed} ne $self->{final_state}) && ($config{on_completed} ne $self->{error_state}) && !defined($self->{states}->{$config{on_completed}})) ) {
        log_warn("State ".$config{on_completed}." was not implemented by the FSM ".$self->{class});
        return;
    }
    if (defined($config{on_error}) &&
        (($config{on_error} ne $self->{final_state}) && ($config{on_error} ne $self->{error_state}) && !defined($self->{states}->{$config{on_error}})) ) {
        log_warn("State ".$config{on_error}." was not implemented by the FSM ".$self->{class});
        return;
    }
    
    # Prepare async wheel
    my $child = POE::Wheel::Run->new(
        ProgramArgs => [ $sub, $self, $user_args ],
        Program => sub {
            my $sub = shift;
            my $machine = shift;
            my $user_args = shift;

            # STDOUT will go to STDERR (logfiles) because
            # it is used by the IPC.
            my $STDEVENT = select(*STDERR);

            # Notify the machine clone that it's detached
            # This will automatically redirect state change events
            # to STDOUT and will be handled by the parent process.
            $machine->{detached_child} = 1;

            # Fetch some useful information from the POE Kernel
            my $session = $poe_kernel->get_active_session();
            my $heap = $session->get_heap();

            # Invoke the child function with the same argument stack as POE
            my @args = ( 
                $machine->{instance},                 # SELF
                $session,                             # SESSION
                $poe_kernel,                          # KERNEL
                $heap,                                # HEAP
                $poe_kernel->get_active_event(),      # STATE
                undef,                                # TODO: SENDER
                undef,                                # -unused-
                undef,                                # TODO: CALLER_FILE
                undef,                                # TODO: CALLER_LINE
                undef,                                # TODO: CALLER_STATE
                $machine,                             # ARG0 - MACHINE
                $machine->{context},                  # ARG1 - CONTEXT
            );
          
            # Push user arguments if defined
            push(@args, @{$user_args}) if defined($user_args);

            # Call the function
            &{$sub}( @args );

            # Send the updated state information
            #__detach_send_event( 'context', $machine->{context} );
          
      },
      StdioFilter =>  POE::Filter::Reference->new(),
      CloseEvent  => $self->{LOCAL_STATE_D_COMPLETED},
      StdoutEvent => $self->{LOCAL_STATE_D_STDOUT},
      StderrEvent => $self->{LOCAL_STATE_D_STDERR},
    );
    
    # Get current session and heap
    my $session = $poe_kernel->get_active_session();
    my $heap = $session->get_heap();
    
    # Schedule child reaper
    $poe_kernel->sig_child($child->PID, $self->{LOCAL_STATE_D_REAP});
    
    # Store child in heap to keep it alive
    $heap->{$self->{detached_uid}} = $child;
    
    # Keep the configuration for use by the event handlers
    $self->{detached} = {
        child => $child,
        config => \%config
    };
    
    # The user must specify at least the on_completed handler
    if (defined($config{on_completed})) {
        $self->{scheduled} = 1;
    }
    
}

##################################################
# Execute a process in a detached context
# ------------------------------------------------

=head2 exec ARRAYREF [, PARAMETERS ...]

=head2 exec STRING [, PARAMETERS ...]

Invoking this function will create a POE::Wheel::Run that will
start the given process in the background. You can also register
the state changes that will occur upon completion or failure.

An execution is failed if the application returns a non-zero
exit code, or if POE::Wheel::Run was unable to launch the process.

For example:

 $machine->exec(
     
     [ '/usr/bin/ping', '-c3', '8.8.8.8' ],
     
     # State changes
     on_completed   => "<The state to switch when completed>",
     on_error       => "<The state to switch on error>",
 
     # Configuration
     stdout         => P_IGNORE,
     stderr         => P_LOG
 
     );

The state handlers of on_completed and on_error are called with 3 additional parameters.
ARG2 will be an array reference to STDOUT buffer, ARG3 will be the same for STDERR and
ARG4 is the exit code of the process.

STDOUT and STDERR can be handled in many ways. You can use one of the
following constants or a callback function:

 P_IGNORE       : Discard any input from that pipe
 P_BUFFER       : Buffer the response and pass it on the on_complete or
                  on_error state handler.
 P_LOG          : Wrap each line with log_msg (stdout) or log_warn (stderr)
 P_PASSTHROUGH  : Passthrough each line directly to the parent STDOUT/STDERR

If you specify a string, it will be registered as an event handler for
the given pipe. For example, if you have your own stdout and stderr handlers,
you can use:
 
$machine->exec(
    
    [ '/usr/bin/ping', '-c3', '8.8.8.8' ],
    
    stdout => $self->{CALLBACKS}->{stdout},
    stderr => $self->{CALLBACKS}->{stderr}
 
    );

If nothing is specified, STDOUT is ignored and STDERR is logged.

=cut

# ------------------------------------------------
sub exec {
##################################################
    my $self = shift;
    my $program = shift;
    my %config = @_;

    # We cannot have multiple children detached
    if ($self->{detached_child}) {
        log_error("You cannot nest detached processes!");
        return;
    }

    # Make sure the states exist
    # (Brace yourself, heavily nested code is coming!)
    if (defined($config{on_completed}) && 
         (($config{on_completed} ne $self->{final_state}) && ($config{on_completed} ne $self->{error_state}) && !defined($self->{states}->{$config{on_completed}})) ) {
        log_warn("State ".$config{on_completed}." was not implemented by the FSM ".$self->{class});
        return;
    }
    if (defined($config{on_error}) &&
        (($config{on_error} ne $self->{final_state}) && ($config{on_error} ne $self->{error_state}) && !defined($self->{states}->{$config{on_error}})) ) {
        log_warn("State ".$config{on_error}." was not implemented by the FSM ".$self->{class});
        return;
    }

    # Prepare async wheel
    my $child = POE::Wheel::Run->new(
            Program => $program,
            StdoutFilter => POE::Filter::Line->new(),
            StderrFilter => POE::Filter::Line->new(),
            CloseEvent   => $self->{LOCAL_STATE_X_COMPLETED},
            StdoutEvent  => $self->{LOCAL_STATE_X_STDOUT},
            StderrEvent  => $self->{LOCAL_STATE_X_STDERR},
        );
    
    # Get current session and heap
    my $session = $poe_kernel->get_active_session();
    my $heap = $session->get_heap();

    # Schedule child reaper
    $poe_kernel->sig_child($child->PID, $self->{LOCAL_STATE_X_REAP});

    # Store child in heap to keep it alive
    $heap->{$self->{detached_uid}} = $child;

    # Keep the configuration for use by the event handlers
    $self->{detached} = {
        child => $child,
        config => \%config,
        buffers => {
            stdin => [ ],
            stdout => [ ]
        }
    };

    # The user must specify at least the on_completed handler
    if (defined($config{on_completed})) {
        $self->{scheduled} = 1;
    }
    
}

##################################################
# Adopt the entry points of another FSM and convert
# them in local state changes.
# ------------------------------------------------

=head2 adopt iAgent::Wheel::FSM

Adopts the given FSM by converting the on_xxxx state handlers
into local state switches.

This is equivalent of creating an anonymous callback using
FSMEvent(), then passing it as an on_xxxx handler of the FSM
and registering it as a onPOE event.

For example, instead of doing:

 my $callback = FSMEvent('completed');
 iAgent::Wheel::FSM->new(
        class => 'FSM::Foo,
        on_completed => $callback
     );
 $machine->onPOE($callback => "handle_completion");

You can simply do:

 $machine->adopt(
     iAgent::Wheel::FSM->new(
         class => 'FSM::Foo,
         on_completed => "handle_completion"
     )
 );

=cut

# ------------------------------------------------
sub adopt {
##################################################
    my ($self, $fsm) = @_;
    
    # Replace events with anonymous handlers
    foreach my $k (keys %{$fsm->{triggers}}) {
        my $v = $fsm->{triggers}->{$k};
        my $ev = FSMEvent($v);
        $self->onPOE( $ev => $v );
        $fsm->{triggers}->{$k} = $ev;
    }

    # ... that finished quicky ...
    
}

##################################################
# Update context in a detach-friendly way
# ------------------------------------------------

=head2 context HASHREF

This function merges the given hash reference with the current
context. This is a less intrusive way to update context than
using directly the context hash.

While in detached context this function allows direct
update of the parent context hash.

=cut

# ------------------------------------------------
sub context {
##################################################
    my ($self, $context) = @_;
    
    # Merge contexts
    ___forward_merge($self->{context}, $context)
        if defined($context);
    
    # ALSO notify the parent context if we are a detached fork
    __detach_send_event('context', $context) if ($self->{detached_child});

}

##################################################
# Schedule a state switch to completion
# ------------------------------------------------

=head2 complete

Switch to final state.

=cut

# ------------------------------------------------
sub complete {
##################################################
    my ($self, $context) = @_;
    $self->goto($self->{final_state}, $context);
}

##################################################
# Schedule a state switch to failure
# ------------------------------------------------

=head2 fail

Switch to failed state.

=cut

# ------------------------------------------------
sub fail {
##################################################
    my ($self, $context) = @_;
    $self->goto($self->{error_state}, $context);
}

##========================================================================================================================##
##                                                 DETACHED EXECUTION HELPERS                                             ##
##========================================================================================================================##

##################################################
# Kill a currently running, detached instance
sub __kill_detached {
##################################################
    my $self = shift;
    return if !defined($self->{detached});
    
    # Kill child
    $self->{detached}->{child}->kill();
    
    # (Let reaping functions to cleanup)
}

##################################################
# (Called from the child process) Sends a new event
# to the parent process. This will automatically 
# call __detach_stdout in the parent with the appropriate
# event in the first parameter.
sub __detach_send_event {
##################################################
    my $name = shift;
    my @args = @_;
    my $filter = POE::Filter::Reference->new();
    
    # Notify parent that we are done
    my $data = $filter->put([{
        event => $name,
        args => \@args
    }]);

    # Dump to stdout the data
    print main::STDOUT @$data;
}

##################################################
# A detached process has completed successfuly
sub __detach_completed {
##################################################
    my ($self, $wheel_id) = @_[ OBJECT, ARG0 ];
    log_debug("Wheel $wheel_id completed");
}

##################################################
# STDOUT is used for passing information. Update
# my context accordingly.
sub __detach_stdout {
##################################################
    my ($self, $event) = @_[OBJECT, ARG0];
    log_debug("Handling child event ".Dumper($event));
    
    if ($event->{event} eq 'context') {
        # Update context
        ___forward_merge($self->{context}, $event->{args}->[0]);
        
    } elsif ($event->{event} eq 'goto') {
        # Switch state
        $self->goto(@{$event->{args}});
    
    } elsif ($event->{event} eq 'after') {
        # Switch state
        $self->after(@{$event->{args}});

    } elsif ($event->{event} eq 'on') {
        # Switch state
        $self->on(@{$event->{args}});

    } elsif ($event->{event} eq 'onPOE') {
        # Switch state
        $self->onPOE(@{$event->{args}});

    }
}

##################################################
# STDERR is used for logging. Just passthrough 
# the lines.
sub __detach_stderr {
##################################################
    my ($stderr_line, $wheel_id) = @_[ARG0, ARG1];
    print($stderr_line."\n");
}

##################################################
# The wheel was completed and must be reaped
sub __detach_reaped {
##################################################
    my ($self, $heap, $pid, $result) = @_[ OBJECT, HEAP, ARG1, ARG2 ];
    log_debug("Reaped detached child $pid = $result");
    
    # Release child from heap
    delete $heap->{$self->{detached_uid}};
    
    # If we had an error and we had an error state defined, switch there
    if (($result !=0 ) && defined($self->{detached}->{config}->{on_error})) {
        $self->goto($self->{detached}->{config}->{on_error});
    } else {
        # In any other case, go to the complete state
        $self->goto($self->{detached}->{config}->{on_completed});
    }
    
    # Cleanup detached info
    delete $self->{detached};

}


##========================================================================================================================##
##                                                   ASYNC EXECUTION HELPERS                                              ##
##========================================================================================================================##

##################################################
# An exec process has completed successfuly
sub __exec_completed {
##################################################
    my ($self, $wheel_id) = @_[ OBJECT, ARG0 ];
    log_debug("Wheel $wheel_id completed");
}

##################################################
# STDOUT line received
sub __exec_stdout {
##################################################
    my ($self, $line) = @_[OBJECT, ARG0];
    if (defined($self->{detached}->{config}->{stdout})) {
        my $c = $self->{detached}->{config}->{stdout};
        if (looks_like_number $c) { 
            if ($c == P_IGNORE) {
                return;
            } elsif ($c == P_PASSTHROUGH) {
                print "$line".EOL;
            } elsif ($c == P_BUFFER) {
                push @{$self->{detached}->{buffers}->{stdout}}, $line;
            } elsif ($c == P_LOG) {
                log_msg($line);
            }
        } else {
            $poe_kernel->yield( $c, $line );
        }
    }
}

##################################################
# STDERR is used for logging. Just passthrough 
# the lines.
sub __exec_stderr {
##################################################
    my ($self, $line) = @_[OBJECT, ARG0];
    if (defined($self->{detached}->{config}->{stderr})) {
        my $c = $self->{detached}->{config}->{stderr};
        if (looks_like_number $c) { 
            if ($c == P_IGNORE) {
                return;
            } elsif ($c == P_PASSTHROUGH) {
                print STDERR "$line".EOL;
            } elsif ($c == P_BUFFER) {
                push @{$self->{detached}->{buffers}->{stderr}}, $line;
            } elsif ($c == P_LOG) {
                log_warn($line);
            }
        } else {
            $poe_kernel->yield( $c, $line );
        }
    }
}

##################################################
# The wheel was completed and must be reaped
sub __exec_reaped {
##################################################
    my ($self, $heap, $pid, $result) = @_[ OBJECT, HEAP, ARG1, ARG2 ];
    log_debug("Reaped exec child $pid = $result");
    
    # Release child from heap
    delete $heap->{$self->{detached_uid}};
    
    # Collect STDOUT and STDERR buffers
    my $buf_out = $self->{detached}->{buffers}->{stdout};
    my $buf_err = $self->{detached}->{buffers}->{stderr};
    
    # If we had an error and we had an error state defined, switch there
    if (($result !=0 ) && defined($self->{detached}->{config}->{on_error})) {
        $self->goto($self->{detached}->{config}->{on_error}, undef, [ $buf_out, $buf_err, $result ]);
    } else {
        # In any other case, go to the complete state
        $self->goto($self->{detached}->{config}->{on_completed}, undef, [ $buf_out, $buf_err, $result ]);
    }
    
    # Cleanup detached info
    delete $self->{detached};

}

##========================================================================================================================##
##                                                  EXTERNAL STATIC FUNCTIONS                                             ##
##========================================================================================================================##

##################################################
# Schedule a state switch on event
# ------------------------------------------------

=head2 iAgent::Wheel::FSM::FSMEvent [EVENT]

This static function (also exported as FSMEvent) generates a unique event name. This function can
be used in conjunction with onPOE to generate a unique triggable event.

If the first string parameter is missing, a random event name will be generated.

For example:

 sub _STATE_setup {
     my ($self, $kernel, $machine, $context) = @_[ SELF, KERNEL, ARG0, ARG1 ];
     
     # Create a unique POE message
     my $POE_MSG = FSMEvent("async_callback");
     
     # Setup a callback of an asynchronous event
     Dispatch("async_event", { callback => $POE_MSG }) 
     
     # Change state when this message is arrived
     $machine->onPOE( $POE_MSG => 'completed' );
 }


=cut

# ------------------------------------------------
sub FSMEvent {
##################################################
    my $name = shift;
    my $id = $last_fsmevent_id++;
    $name='anon' unless defined($name);
    return "FSMPOEEvent\#${id}=>$name";
}

##################################################
# Schedule a state switch on event
# ------------------------------------------------

=head2 iAgent::Wheel::FSM::FSMBroadcast EVENT [, PARAMETERS ...]

This static function (also exported as FSMBroadcast) will trigger all the currently running
FSM instances that are listening for this particular event. 

=cut

# ------------------------------------------------
sub FSMBroadcast {
##################################################
    my $event = shift;
    my @args = @_;
    my $session = $poe_kernel->get_active_session();
    my $heap = $session->get_heap();
    
    # Skip missing events
    return if !defined($heap->{_FSM_});
    
    # Check for real-time event handlers
    if (defined($heap->{_FSM_}->{realtime}) && defined($heap->{_FSM_}->{realtime}->{$event})) {
        
        # Call each one of them
        for my $msg (values %{$heap->{_FSM_}->{realtime}->{$event}}) {
            $poe_kernel->call($msg->[0], $msg->[1], $msg->[2], $msg->[2]->{context}, @args);
        }
        
    }
    
    # Check for dynamic event handlers
    if (defined($heap->{_FSM_}->{events}) && defined($heap->{_FSM_}->{events}->{$event})) {
        
        # Call each one of them
        for my $event (values %{$heap->{_FSM_}->{events}->{$event}}) {
            my ($object, $state, $filter, $context) = @$event;

            # Skip the entries for which the validator faile
            next if (defined($filter) && !&{$filter}($object->{instance}, @args));

            # Otherwise, switch state of that object
            $object->goto($state, $context);
        }
        
    }

    
}

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2012 at PH/SFT, CERN

=cut

1;