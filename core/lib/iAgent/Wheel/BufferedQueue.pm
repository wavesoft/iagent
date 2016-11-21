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

iAgent::Wheel::BufferedQueue - A simple buffered queue Wheel

=head1 DESCRIPTION

This wheel provides a simple interface to dispatch events for every item in the queue. Items
can be pushed in the queue dynamically.

Unless otherwise specified, if all the objects in the queue have been processed the wheel will 
automatically exit.

=head1 USAGE

To create an instance of a queue use the following constructor syntax:

 $self->{queue} = iAgent::Wheel::Queue->new(
     slots => 10,
     on_feed => 'queue_feed',
     on_handle => 'queue_handle'
 );

Here is an example queue handler:

  function __queue_handle {
      my ($queue, $context, $job) = @_[ ARG0..ARG2 ];

      .. do your stuf ..

      # Call next to inform the queue we are finished
      $queue->next();
  }

It is important to call next() when you are done processing the item.

=head1 FUNCTIONS

=head2 new PARAMETERS

The constructor accepts the following parameters:

 slots  => 0                The maximum slots to allow on this queue
 context => { }             A hash reference to context information that
                            will be passed to all event handlers
 
 objects => [ ]             The starting set of objects in the queue
 
 exit_on_empty => 1         Set to 0 to keep the wheeel alive even if
                            it ran out of items.
 
 on_handle => "poe_handler" The job handler. The arguments passed to the handler are:
                              ARG0 : The iAgent::Wheel::Queue instance
                              ARG1 : Context reference
                              ARG2 : Job reference
                              
 on_empty => "poe_handler"  Broadcasted when queue is empty
 on_full => "poe_handler"   Broadcasted when queue is full
 on_start => "poe_handler"  Broadcasted before the first item is handled

Unless otherwise mentioned, on every handler ARG0 is the reference to the queue
instance and ARG1 is the reference to the context object.

Context hash may be updated at any time.

=cut

package iAgent::Wheel::BufferedQueue;
use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;
use Data::Dumper;

use POE;
use POE::Wheel;
use base qw( POE::Wheel );

sub POLL_INTERVAL { 0.05 };
sub IDLE_INTERVAL { 2 };

##========================================================================================================================##
##                                                    BASIC WHEEL IMPLEMENTATION                                          ##
##========================================================================================================================##

##################################################
# Create a new isntance to the iAgent Queue Wheel
sub new {
##################################################
    my $class = shift;
    my %config = @_;
    
    # Create/Ensure defaults
    $config{slots} = 1 unless defined($config{slots});
    $config{context} = { } unless defined($config{context});
    $config{exit_on_empty} = 1 unless defined($config{exit_on_empty});
    $config{objects} = [ ] unless defined($config{objects});
    
    # Setup class
    my $uid = POE::Wheel::allocate_wheel_id();
    my $self = {
        
        # Local variables
        wheel_id => $uid,
        max_slots => $config{slots},
        slots => 0,
        stopped => 0,
        context => $config{context},
        
        # The objects in the queue
        objects => $config{objects},
        exit_on_empty => $config{exit_on_empty},
        
        # Events
        events => {
            on_empty =>     $config{on_empty},
            on_handle =>    $config{on_handle},
            on_start =>     $config{on_start},
            on_full =>      $config{on_full}
        },
        
        # Registered POE states
        STATE_TIMER => "${class}\@${uid}->__queue_timer"
    };
    
    # Instantiate
    $self = bless($self, $class);
    
    # Setup states
    log_msg("Registering state ".$self->{STATE_TIMER});
    $poe_kernel->state($self->{STATE_TIMER}, $self, '__queue_timer' );
    $poe_kernel->delay($self->{STATE_TIMER}, 0);
    
    # Return an iAgent::FSM instance
    return $self;
}


##################################################
# Update the event handlers
sub event {
##################################################
    my $self = shift;
    my %events = @_;
    
    # Update event handlers
    $self->{events}->{on_handle} = $events{on_handle}   if defined($events{on_handle});
    $self->{events}->{on_empty} = $events{on_empty}     if defined($events{on_empty});
    $self->{events}->{on_start} = $events{on_start}     if defined($events{on_start});
    $self->{events}->{on_full} = $events{on_full}       if defined($events{on_full});
}

##################################################
# Cleanup everything so POE can kill us
sub _cleanup {
##################################################
  my $self = shift;

  # Delete context
  delete $self->{context};

  # Cancel timers
  $poe_kernel->delay($self->{STATE_TIMER});
  
  # Remove registered states
  $poe_kernel->state($self->{STATE_TIMER});
  
}

##################################################
# Good ol' perl destructor...
sub DESTROY {
##################################################
  my $self = shift;
  POE::Wheel::free_wheel_id($self->{wheel_id});
}

##========================================================================================================================##
##                                                      HELPER FUNCTIONS                                                  ##
##========================================================================================================================##

##################################################
# Called every POLL_INTERVAL to check the queue
sub __queue_timer {
##################################################
    my ($self, $kernel, $session) = @_[ OBJECT, KERNEL, SESSION ];
    my $interval = IDLE_INTERVAL;
    
    # If we are stopped, exit
    if ($self->{stopped}) {
        $self->_cleanup();
        return;
    }
    
    # Check for free slots
    if (($self->{max_slots} == 0) || ($self->{slots} < $self->{max_slots})) {
    
        # Ask feeder to input data
        my $job = shift( @{$self->{objects}} );
        if (defined($job)) {
        
            # Acquire slot
            $self->{slots}++;
            log_msg("Pushed item in BQ. Slots: ".$self->{slots});
            
            # Check and notify for fresh queue
            $kernel->call($session, $self->{events}->{on_start}, $self, $self->{context}) if (defined($self->{events}->{on_start}) && ($self->{slots}==1));
            
            # Check and notify for full queue
            $kernel->call($session, $self->{events}->{on_full}, $self, $self->{context}) if (defined($self->{events}->{on_full}) && ($self->{slots}==$self->{max_slots}));
            
            log_debug("Processing job ".Dumper($job));
            
            # Handle input (async)
            $kernel->post($session, $self->{events}->{on_handle}, $self, $self->{context}, $job);
            
            # Invrease the frequency
            $interval = POLL_INTERVAL;
            
        }
        
    }
    
    # Infinite loop
    $kernel->delay($self->{STATE_TIMER} => $interval);
}

##========================================================================================================================##
##                                                    QUEUE IMPLEMENTATION                                                ##
##========================================================================================================================##

##################################################
# Call this function when you are done processing
# a queue event. This will schedule the next item
# for processing.
sub next {
##################################################
    my $self = shift;
    log_msg("Popping item from BQ. Slots: ".$self->{slots});
    
    # Release slot
    $self->{slots}--;
    $self->{slots}=0 if ($self->{slots}<0);
    
    # Check and notify for empty queue
    log_msg("Next item in BQ. Slots: ".$self->{slots});
    if ($self->{slots} == 0) {
        
        # Stop queue
        $self->stop();
        
        # And call on_empty event
        $poe_kernel->call($poe_kernel->get_active_session(), $self->{events}->{on_empty}, $self, $self->{context}) if defined($self->{events}->{on_empty});
        
    }
    
}

##################################################
# Stop the queue and let it die.
sub stop {
##################################################
    my $self = shift;
    
    # Set the stop flag the loop will automatically stop
    $self->{stopped} = 1;
    
}

##################################################
# Push item(s) in the queue
sub push {
##################################################
    my $self = shift;

    # Push objects in queue
    push @{$self->{objects}}, @_;
    
}

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2012 at PH/SFT, CERN

=cut

1;