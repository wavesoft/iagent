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

iAgent::Module::Queue - A simple unbuffered queue Wheel

=head1 DESCRIPTION

This module provides a simple, unbuffered interface to schedule jobs. This means that
there is no add/remove interface. The queue will call the 'feed' event every time it
is time to process new data and will call 'handle' immediately after. This loop blocks
when the number of active instances is equal to 'max_slots'. To feed the next item in queue
the handling function must call next() when it has done processing events.

=head1 USAGE

To create an instance of a queue use the following constructor syntax:

 $self->{queue} = iAgent::Wheel::Queue->new(
     slots => 10,
     on_feed => 'queue_feed',
     on_handle => 'queue_handle'
 );

Here is an example queue feeder:

 function __queue_feed {
     my $self = $_[ OBJECT ];
     
     # Return the next job or undef if there
     # is no item pending
     return shift(@{$self->{jobs}});
 }

And here is an example queue handler:

 function __queue_handle {
     my ($queue, $context, $job) = @_[ ARG0..ARG2 ];
     
     .. do your stuf ..
     
     # Call next to inform the queue we are finished
     $queue->next();
 }

=head1 FUNCTIONS

=head2 new PARAMETERS

The constructor accepts the following parameters:

 slots  => 0                The maximum slots to allow on this queue
 context => { }             A hash reference to context information that
                            will be passed to all event handlers
 
 on_handle => "poe_handler" The job handler. The arguments passed to the handler are:
                              ARG0 : The iAgent::Wheel::Queue instance
                              ARG1 : Context reference
                              ARG2 : Job reference
                              
  on_feed => "poe_handler"   The job feeder. The handling function must return the item to enqueue.
                             If there are no pending items the handler must return undef
  
 on_empty => "poe_handler"  Broadcasted when queue is empty
 on_full => "poe_handler"   Broadcasted when queue is full
 on_start => "poe_handler"  Broadcasted before the first item is handled

Unless otherwise mentioned, on every handler ARG0 is the reference to the queue
instance and ARG1 is the reference to the context object.

Context hash may be updated at any time.

=cut

package iAgent::Wheel::Queue;
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

    # Validate config
    log_die("The on_feed event is required for the iAgent::Wheel::Queue!") unless defined($config{on_feed});
    
    # Create/Ensure defaults
    $config{slots} = 1 unless defined($config{slots});
    $config{context} = { } unless defined($config{context});
    
    # Setup class
    my $uid = POE::Wheel::allocate_wheel_id();
    my $self = {
        
        # Local variables
        wheel_id => $uid,
        max_slots => $config{slots},
        slots => 0,
        stopped => 0,
        context => $config{context},
        
        # Events
        events => {
            on_empty =>     $config{on_empty},
            on_handle =>    $config{on_handle},
            on_feed =>      $config{on_feed},
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
    $self->{events}->{on_feed} = $events{on_feed}       if defined($events{on_feed});
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
        my $job = $kernel->call($session, $self->{events}->{on_feed}, $self, $self->{context});
        if (defined($job)) {
        
            # Acquire slot
            $self->{slots}++;
            
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
    
    # Release slot
    $self->{slots}--;
    $self->{slots}=0 if ($self->{slots}<0);
    
    # Check and notify for empty queue
    $poe_kernel->call($poe_kernel->get_active_session(), $self->{events}->{on_empty}, $self, $self->{context}) if (defined($self->{events}->{on_empty}) && ($self->{slots}==0));
    
}

##################################################
# Stop the queue and let it die.
sub stop {
##################################################
    my $self = shift;
    
    # Set the stop flag the loop will automatically stop
    $self->{stopped} = 1;
    
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2012 at PH/SFT, CERN

=cut

1;