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

iAgent::Module::PriorityQueue - A priority queue Wheel

=head1 DESCRIPTION

This module provides a bit more complex interface to schedule jobs.

=head1 USAGE

=cut

package iAgent::Wheel::PriorityQueue;
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
    $config{global_slots} = 0 unless defined($config{global_slots});
    $config{slots} = { undef => 1 } unless defined($config{slots});
    $config{context} = { } unless defined($config{context});
    
    # Prepare slots and queues
    my $slots = { };
    my $queues = { };
    foreach my $k (keys %{$config{slots}}) {
        $slots->{$k} = 0;
        $queues->{$k} = [ ];
    }
    
    # Setup class
    my $uid = POE::Wheel::allocate_wheel_id();
    my $self = {
        
        # Local variables
        wheel_id => $uid,
        max_slots => $config{slots},
        slots =>  $slots,
        max_global_slots => $config{global_slots},
        global_slots => 0,
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
        
        # Queues
        queues => $queues,
        
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
    
    # Optimization flag
    my $has_feeder = defined($self->{events}->{on_feed});
        
    # No global slots? Dont bother...
    log_warn("GLOBAL=".$self->{global_slots}."/".$self->{max_global_slots});
    if (($self->{max_global_slots} == 0) || ($self->{global_slots} < $self->{max_global_slots})) {
        
        # Start looping over our queues
        foreach my $pri (keys %{$self->{queues}}) {
            my $max_slots = $self->{max_slots}->{$pri};

            # Check if queue is empty
            my $is_empty = (scalar(@{$self->{queues}->{$pri}}) == 0);
        
            # If the queue is empty and there is no feeder, go to the next priority
            next if ($is_empty && !$has_feeder);
        
            # Check for free slots
            log_warn("Q${pri}=".$self->{slots}->{$pri}."/".$max_slots);
            if (($max_slots == 0) || ($self->{slots}->{$pri} < $max_slots)) {
            
                # Ask feeder for input if we are using it
                if ($has_feeder) {
                    my $ans = $kernel->call($session, $self->{events}->{on_feed}, $self, $self->{context}, $pri);
                    log_info("Got job for pri $pri");
                    $self->enqueue($ans, $pri) if (defined($ans));
                }
        
                # Fetch and process next item in queue
                my $job = shift(@{$self->{queues}->{$pri}});
                if (defined($job)) {
                
                    # Acquire slots
                    $self->{global_slots}++;
                    $self->{slots}->{$pri}++;
                
                    # Check and notify for fresh queue
                    $kernel->call($session, $self->{events}->{on_start}, $self, $self->{context}, $pri) if (defined($self->{events}->{on_start}) && ($self->{slots}==1));

                    # Check and notify for full queue
                    $kernel->call($session, $self->{events}->{on_full}, $self, $self->{context}, $pri) if (defined($self->{events}->{on_full}) && ($self->{slots}->{$pri}==$max_slots));

                    log_debug("Processing job ".Dumper($job));

                    # Handle input (async)
                    $kernel->post($session, $self->{events}->{on_handle}, $self, $job, $self->{context}, $pri);

                    # Increase the frequency
                    $interval = POLL_INTERVAL;
                
                }
            }
            
            # Ran out of global slots? Just exit
            last if (($self->{max_global_slots} != 0) && ($self->{global_slots} >= $self->{max_global_slots}));
        
        }
    }
            
    # Infinite loop
    $kernel->delay($self->{STATE_TIMER} => $interval);
}

##========================================================================================================================##
##                                                    QUEUE IMPLEMENTATION                                                ##
##========================================================================================================================##

##################################################
# Call this function if you are not using polling
# and you just want to push an item in the queue
sub enqueue {
##################################################
    my ($self, $object, $pri) = @_;
    
    # Skip invalid queues
    if (!defined($self->{queues}->{$pri})) {
        log_warn("Priority queue '".$pri."' was not found!");
        return;
    }
    
    # Push item in queue
    push @{$self->{queues}->{$pri}}, $object;
}

##################################################
# Call this function when you are done processing
# a queue event. This will schedule the next item
# for processing.
sub next {
##################################################
    my ($self, $pri) = @_;
    
    # Release global slot
    $self->{global_slots}--;
    $self->{global_slots}=0 if ($self->{global_slots}<0);
    
    # Release queue slot
    $self->{slots}->{$pri}--;
    $self->{slots}->{$pri}=0 if ($self->{slots}->{$pri}<0);
    
    log_msg("Release slot $pri");
    log_msg("GLOBAL=".$self->{global_slots}."/".$self->{max_global_slots});
    log_msg("Q${pri}=".$self->{slots}->{$pri}."/".$self->{max_slots}->{$pri});
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