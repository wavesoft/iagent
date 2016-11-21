#
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

iAgent::Module::GroupQueue - A groupped queue Wheel

=head1 DESCRIPTION

This queue is the same to simple queue but groups the results based on the
second argument returned by the enqueue function. You can specify per-group
and global number of slots.

Entries are feeded again using the queue_feed function and you can define the
grouping key with the second returning argument. For example:

 function __queue_feed {
     my $self = $_[ OBJECT ];
     
     # Fetch the next job in queue
     my $job = shift(@{$self->{jobs}});
     
     # If there are no items, return undef
     return undef if !defined($job);
     
     # Return job and groupping key
     return ( $job, $job->{category} );
     
 }


=head1 USAGE

To create an instance of a queue use the following constructor syntax:

 $self->{queue} = iAgent::Wheel::GroupQueue->new(
     group_slots => 10,
     on_feed => 'queue_feed',
     on_handle => 'queue_handle'
 );

And here is an example queue handler:

 function __queue_handle {
     my ($queue, $context, $job) = @_[ ARG0..ARG2 ];
     
     .. do your stuf ..
     
     # Call next to inform the queue we are finished
     $queue->next();
 }

For an example feeder, check the L<DESCRIPTION>.

=head1 FUNCTIONS

=head2 new PARAMETERS

The constructor accepts the following parameters:

 global_slots  => 0         The maximum slots to allow globally in the queue.
                            0 means 'no limit' (Default).
                            
 group_slots  => 0          The maximum slots to allow per group
 
 context => { }             A hash reference to context information that
                            will be passed to all event handlers
 
 on_handle => "poe_handler" The job handler. The arguments passed to the handler are:
                              ARG0 : The iAgent::Wheel::Queue instance
                              ARG1 : Context reference
                              ARG2 : Job reference
                              ARG3 : The name of the group
                              
 on_feed => "poe_handler"   The job feeder. The handling function must return a list
                            of two items. The first is the item to enqueue and the second
                            is the groupping key. 
                            If the second argument is missing, the default group will be used. 
                            If there are no pending items the handler must return undef
                             
 on_empty => "poe_handler"          Broadcasted when queue is empty
 on_full => "poe_handler"           Broadcasted when queue is full
 on_start => "poe_handler"          Broadcasted before the first item is handled
 on_group_empty => "poe_handler"    Broadcasted when a group queue is empty
 on_group_full => "poe_handler"     Broadcasted when a group queue is full
 on_group_start => "poe_handler"    Broadcasted before the first item of a group queue is handled

Unless otherwise mentioned, on every handler ARG0 is the reference to the queue
instance and ARG1 is the reference to the context object.

Additionally, on _group_ event handlers, ARG2 is a reference to the group key, as passed
by the feed function.

Context hash may be updated at any time.

=cut

package iAgent::Wheel::GroupQueue;
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
    $config{global_slots} = 1 unless defined($config{global_slots});
    $config{group_slots} = 1 unless defined($config{group_slots});
    $config{context} = { } unless defined($config{context});
    $config{default_group} = "default" unless defined($config{default_group});
    
    # Setup class
    my $uid = POE::Wheel::allocate_wheel_id();
    my $self = {
        
        # Local variables
        wheel_id => $uid,
        max_slots => $config{global_slots},
        slots => 0,
        stopped => 0,
        context => $config{context},
        
        # The group queues
        groups => { },
        group_slots => $config{group_slots},
        default_group => $config{default_group},
        
        # Events
        events => {
            on_handle =>        $config{on_handle},
            on_feed =>          $config{on_feed},
            on_start =>         $config{on_start},
            on_empty =>         $config{on_empty},
            on_full =>          $config{on_full},
            on_group_start =>   $config{on_group_start},
            on_group_empty =>   $config{on_group_empty},
            on_group_full =>    $config{on_group_full}
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
    $self->{events}->{on_feed} = $events{on_feed}                   if defined($events{on_feed});
    $self->{events}->{on_handle} = $events{on_handle}               if defined($events{on_handle});
    $self->{events}->{on_empty} = $events{on_empty}                 if defined($events{on_empty});
    $self->{events}->{on_start} = $events{on_start}                 if defined($events{on_start});
    $self->{events}->{on_full} = $events{on_full}                   if defined($events{on_full});
    $self->{events}->{on_group_empty} = $events{on_group_empty}     if defined($events{on_group_empty});
    $self->{events}->{on_group_start} = $events{on_group_start}     if defined($events{on_group_start});
    $self->{events}->{on_group_full} = $events{on_group_full}       if defined($events{on_group_full});
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
    
    # If we ran out of global slots, don't do anything
    if (($self->{max_slots} == 0) || ($self->{slots} < $self->{max_slots})) {
    
        # Ask feeder to input data
        my ($job, $group) = $kernel->call($session, $self->{events}->{on_feed}, $self, $self->{context});
        if (defined($job)) {
        
            # Set default group if group is not defined
            $group = $self->{default_group} unless defined($group);
            
            # Create group if it doesn't exist
            if (!defined($self->{groups}->{$group})) {
                $self->{groups}->{$group} = {
                    slots => 0,
                    queue => [ ]
                };
            }
            
            # Put job in queue
            push @{$self->{groups}->{$group}->{queue}}, $job;
            
        }
        
        # Check for pending jobs in the queues
        for my $group_name (keys %{$self->{groups}}) {
            my $group = $self->{groups}->{$group_name};
            
            # If group has free slots, start job
            if ($group->{slots} < $self->{group_slots}) {
                
                # Acquire slots
                $group->{slots}++;  # Group
                $self->{slots}++;   # Global
                
                # Fetch job
                my $job = shift(@{$group->{queue}});
                
                # Check and notify for fresh queue (global)
                $kernel->call($session, $self->{events}->{on_start}, $self, $self->{context}) if (defined($self->{events}->{on_start}) && ($self->{slots}==1));

                # Check and notify for full queue (global)
                $kernel->call($session, $self->{events}->{on_full}, $self, $self->{context}) if (defined($self->{events}->{on_full}) && ($self->{slots}==$self->{max_slots}));
                
                # Check and notify for fresh queue (group)
                $kernel->call($session, $self->{events}->{on_group_start}, $self, $self->{context}, $group_name) if (defined($self->{events}->{on_group_start}) && ($group->{slots}==1));

                # Check and notify for full queue (group)
                $kernel->call($session, $self->{events}->{on_group_full}, $self, $self->{context}, $group_name) if (defined($self->{events}->{on_group_full}) && ($group->{slots}==$self->{group_slots}));

                log_debug("Processing job of group '$group_name': ".Dumper($job));
                
                # Handle input (async)
                $kernel->post($session, $self->{events}->{on_handle}, $self, $self->{context}, $job, $group_name);

                # Invrease the frequency
                $interval = POLL_INTERVAL;

            }
            
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
    my ($self, $group_name) = @_;
    
    # If group is missing, use default
    $group_name = $self->{default_group} unless defined($group_name);
    
    # Release global
    $self->{slots}--;
    $self->{slots}=0 if ($self->{slots}<0);
    
    # Release group
    my $group = $self->{groups}->{$group_name};
    $group->{slots}--;
    $group->{slots}=0 if ($group->{slots}<0);
    
    # Check and notify for empty queue (global)
    $poe_kernel->call($poe_kernel->get_active_session(), $self->{events}->{on_empty}, $self, $self->{context}) if (defined($self->{events}->{on_empty}) && ($self->{slots}==0));
    
    if (scalar @{$group->{queue}} == 0) {
        
        # Check and notify for empty queue (group)
        $poe_kernel->call($poe_kernel->get_active_session(), $self->{events}->{on_group_empty}, $self, $self->{context}, $group_name) if (defined($self->{events}->{on_group_empty}));
        
        # Delete group
        delete $self->{groups}->{$group_name};
        
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


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2012 at PH/SFT, CERN

=cut

1;