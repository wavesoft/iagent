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

# Core definitions
package iAgent::Module::iBuildPilot;
use strict;
use warnings;

# Basic inclusions
use iAgent::Log;
use POE;

# Functional inclusions
use File::Basename;
use Data::Dumper;
use Config::General qw(SaveConfig);
use HTML::Entities; 
use XML::Simple;
use DBI;
use Sys::Hostname;

# The iBuilder Manifest
our $MANIFEST = {
    config => 'ibuilder.conf'    
};

# The currently running job's queue ID
my $WORKER_QID = 0;
my $WORKER_PID = 0;

# The users that are monitoring the status of the build
my @MONITOR_USERS;

# Some constants
my $XMLNS_IBUILDER_BUILD     = "archipel:ibuilder:builds";


############################################
# New instance
sub new {
############################################
    my ($class, $config) = @_;
    
    # Prepare my instance 
    my $self = {
        config => $config,
        
    };
    $self = bless $self, $class;
    
    # Load config files
    $self->connect_db();
    
    # Return instance
    return $self;
}

############################################
# New instance
sub connect_db {
############################################
    my ($self) = @_;
    
    # Prepare the DBI
    eval {
    
        # Connect to the DB
        my $dbh = DBI->connect($self->{config}->{IBuildDBDSN},{
                             AutoCommit => 1,
                             RaiseError => 1
                           });
    
        # Check for failure
        if (!$dbh) {
            log_warn("Error while trying to connecto to DSN ".$self->{config}->{IBuildDBDSN}."! $DBI::errstr");
            return 0;
        }
        
        # Prepare tables
        $dbh->do("CREATE TABLE IF NOT EXISTS queue (qid   INTEGER PRIMARY KEY,
                   project     VARCHAR(60),
                   stage       VARCHAR(60),
                   actions     VARCHAR(255),
                   status      VARCHAR(20),
                   message     VARCHAR(255),
                   output      TEXT,
                   queued      DATE,
                   processed   DATE,
                   finished    DATE,
                   mdate       DATE)");  

        # Save connection
        $self->{dbh} = $dbh;

    };
    
    # OK!
    return 1;
}

############################################
# Get a list of the projects
sub projects_list {
############################################
    my ($self, $filter) = @_;
    
    # Prepare stuff
    my @response;
    my $selector = '';
    $selector = '' if ($filter eq 'all');
    $selector = 'WHERE status ="running"' if ($filter eq 'active'); 
    $selector = 'WHERE status ="pending"' if ($filter eq 'pending'); 
    $selector = 'WHERE status ="failed"' if ($filter eq 'failed'); 
    $selector = 'WHERE status ="done"' if ($filter eq 'successful'); 
    $selector = 'WHERE status = "done" OR status = "failed"' if ($filter eq 'completed'); 
    
    # Query for projects
    my $sth = $self->{dbh}->prepare("SELECT qid,project,status,queued,processed,finished,actions,message,stage,mdate FROM queue ".$selector);
    return 0 if (!$sth);
    
    # Apply filter
    $sth->execute();
    while (my $r = $sth->fetchrow_hashref()) {
          push @response, $r;
    }
    
    # Return response
    return \@response;

}

############################################
# Update a job with the specified status
sub job_set_status {
############################################
    my ($self, $qid, $status, $message) = @_;

    # Ensure database connection
    if (!$self->{dbh}) {
        if (!$self->connect_db()) {
            iAgent::Kernel::Crash('Unable to connect to the BuildPilot database! Could not continue!');
            return 0;
        }
    }
    
    # Depending on status, update the appropriate dates
    my $extras = '';
    if ($status eq 'running') {
    	$extras.=", processed = DATETIME('now')";
    } elsif ($status eq 'done') {
        $extras.=", finished = DATETIME('now')";
    } elsif ($status eq 'failed') {
        $extras.=", finished = DATETIME('now')";
    }
    
    # Update job info
    my $sth = $self->{dbh}->prepare("UPDATE queue SET status = ?, message = ?, mdate = DATETIME('now')$extras WHERE qid = ?");
    return 0 if (!$sth);    
    $sth->execute($status, $message, $qid);
    
    # Shout the changes to all of the users that are registered
    # to receive notifications
    for my $user (@MONITOR_USERS) {
    	iAgent::Kernel::Broadcast('comm_send', { to => $user, context => 'chat:shout', data => 'Job #'.$qid.' is now '.$status.': '.$message });
    }
    
}

############################################
# Update the STDERR and STDOUT buffers
# kept for reference in the database
sub job_set_output {
############################################
    my ($self, $qid, $buffer) = @_;

    # Ensure database connection
    if (!$self->{dbh}) {
        if (!$self->connect_db()) {
            iAgent::Kernel::Crash('Unable to connect to the BuildPilot database! Could not continue!');
            return 0;
        }
    }
    
    # Update job info
    my $sth = $self->{dbh}->prepare("UPDATE queue SET output = ? WHERE qid = ?");
    return 0 if (!$sth);
    $sth->execute($buffer, $qid);

}

############################################
# Check if there are any pending jobs and
# fetch the next one
sub job_next {
############################################
    my ($self) = @_;

    # Ensure database connection
    if (!$self->{dbh}) {
        if (!$self->connect_db()) {
        	iAgent::Kernel::Crash('Unable to connect to the BuildPilot database! Could not continue!');
        	return 0;
        }
    }
    
    # Query database for the next queued item
    my $sth = $self->{dbh}->prepare("SELECT * FROM queue WHERE status = 'pending' ORDER BY qid DESC LIMIT 0,1");
    return 0 if (!$sth);
    $sth->execute();
    
    # Fetch row
    my $r = $sth->fetchrow_hashref();
    return 0 if (!$r);
    
    # Update row status
    $self->job_set_status($r->{qid}, 'pending', 'Preparing to start');
    
    # Return item
    return $r;

}

############################################
# Get the the job row
sub job_get_all {
############################################
    my ($self, $qid) = @_;

    # Ensure database connection
    if (!$self->{dbh}) {
        if (!$self->connect_db()) {
            iAgent::Kernel::Crash('Unable to connect to the BuildPilot database! Could not continue!');
            return 0;
        }
    }
    
    # Query database for the next queued item
    my $sth = $self->{dbh}->prepare("SELECT * FROM queue WHERE qid = ?");
    return 0 if (!$sth);    
    $sth->execute($qid);
    
    # Fetch row
    my $r = $sth->fetchrow_hashref();
    return 0 if (!$r);
        
    # Return item
    return $r;
    
}

############################################
# The actual thread that runs the job
sub job_thread {
############################################
    my ($self, $job_row) = @_;
    
    # Prepare the variables for the job
    my $folder = $self->{config}->{IBuildProjects}.'/'.$job_row->{project}.'/'.$job_row->{stage};
    my $bin = $self->{config}->{IBuildCmd}.' ';
    my @cmds = split(',', $job_row->{actions});
    
    # We acquired the job
    $self->job_set_status($job_row->{qid}, 'running', 'Job acquired by node '.hostname);

    # Output buffers
    my $buf_out = '';
    
    # Enter folder and start doing stuff
    log_debug("Entering folder $folder");
    chdir $folder;
    
    for my $cmd (@cmds) {

        # Prepare entry for output buffers
        $buf_out .= "IBuilder started with arguments: $cmd\n----------------------------------------\n";

        # We are about to start processing
        $self->job_set_status($job_row->{qid}, 'processing', "Executing action $cmd");

        # Start the process and capture output
        log_debug("Starting process $bin $cmd");
        my $out = `$bin $cmd 2>&1`;
        if (not defined $out) {
            # Check for invokation errors
            log_warn("Unable to execute: '$bin $cmd 2>&1'");
            $self->job_set_status($job_row->{qid}, 'failed', "Unable to execute builder for arguments '$cmd'");
            $self->job_set_output($job_row->{qid}, $buf_out);
            return 0;
        	
        } else {
            # Collect stdout/err
            $buf_out .= $out."\n";
            
        	# Check for execution errors
        	if ($? != 0) {
	            log_warn("Error while executing: '$bin $cmd 2>&1'. Returned: $?");
	            $self->job_set_status($job_row->{qid}, 'failed', "Executing builder for arguments '$cmd' returned error code $?");
                $self->job_set_output($job_row->{qid}, $buf_out);
	            return 0;
        		
        	} else {
        		
        		# Everything was ok
        		log_msg("Command $cmd for job ".$job_row->{qid}." executed successfuly");
        		
        	}
        	
        }
        
    }

    # Update status
    $self->job_set_status($job_row->{qid}, 'done', "Building completed");
    $self->job_set_output($job_row->{qid}, $buf_out);
    
}


############################################
# Engueue a job
sub job_enqueue {
############################################
    my ($self, $job) = @_;
    
    # Prepare SQL statement
    my $stm = $self->{dbh}->prepare("INSERT INTO queue (project,stage,actions,status,message,queued,mdate) VALUES (?,?,?,'pending','Job enqueued',DATETIME('now'),DATETIME('now'))");
    return 0 if (!$stm);
        
    # Place the job
    $stm->execute($job->{project}, $job->{stage}, $job->{actions});
    
    # Done!
    return 1;
}

############################################
# Cleanup completed jobs
sub jobs_cleanup {
############################################
    my ($self) = @_;
    
    # Do it!
    $self->{dbh}->do("DELETE FROM queue WHERE status = 'done'");
    
    # Done!
    return 1;
}

############################################
# Remove the specified job
sub job_remove {
############################################
    my ($self, $qid) = @_;
    
    
    # Prepare SQL statement
    my $stm = $self->{dbh}->prepare("DELETE FROM queue WHERE qid = ?");
    return 0 if (!$stm);
        
    # Place the job
    $stm->execute($qid);    
    # Done!
    return 1;
}

###########################################
#+---------------------------------------+#
#|            EVENT HANDLERS             |#
#|                                       |#
#| All the functions prefixed with '__'  |#
#| are handling the respective event     |#
#+---------------------------------------+#
###########################################

############################################
# When the plugin is started, schedule the
# cron job 
sub ___start {
############################################
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    
    # Just call cron. Cron will loop
    $kernel->yield('cron');
    
}

############################################
# Called once in a while (To be precice, 
# every 10 seconds, when a new job is 
# queued and when a job is finished) to 
# check if there is any pending job.
sub __cron {
############################################
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    
    log_debug("iBuildPilot CRON: Active job: $WORKER_QID");
    
    # Schedule a delay call to myself after 10"
    $kernel->delay( cron => 10 , 0);

    # Do we have a running job?
    if ($WORKER_QID != 0) {
    	# Yes, but it should not stay there for ever!
    	# Here is some clean-up:
    	
    	# 1) Check if the job is actually invalid!
    	my $row = $self->job_get_all($WORKER_QID);
    	if ($row == 0) {
            log_warn("The running job #$WORKER_QID was not found in the database!");
    		$WORKER_QID = 0;
    		return;
    	} else {
    		
    		# 2) Check if the job is finished...
	    	if (($row->{status} eq 'done') or ($row->{status} eq 'failed')) {
	    		log_warn("The running job #$WORKER_QID found to be ".$row->{status}.'!');
	    		$WORKER_QID = 0;
	    		
	    		# Try to reap the child also here...
	    		if ($WORKER_PID != 0) {
	    			log_debug("Found active worker PID. Reaping...");
	    		    my $res = waitpid $WORKER_PID, 0;
	    		    log_debug("Child $WORKER_PID reaped. Waitpid=$res, Result=$?");
	    		    $WORKER_PID = 0;
	    		}
	    		
	    		return;
	    	}
    	}
    	
    	# 3) Check if the job is timed out
    	# TODO: Implement this
    	
    } else {
    	# Nope.. fetch a new job
    	
    	my $job = $self->job_next();
    	log_debug("Got job entry: ".Dumper($job));
    	if ($job != 0) {
    		
    		# Yup, we got a job
    		log_msg("Job shifted from DB: Queue item #".$job->{qid}.': '.$job->{actions}.' for project '.$job->{project});
    		$WORKER_QID = $job->{qid};
    		
    		# Start the job in a new thread  
    		log_debug("Forking a job handler for Queue item #".$job->{qid});
    		my $pid = fork();
    		if (!defined $pid) {
    			iAgent::Kernel::Crash("Unable to fork while trying to spawn a worker for job #".$job->{qid});
    			return;
    			
    		} elsif ($pid == 0) {
    			
    			# Child? Start the worker
                log_debug("Starting worker thread for job #".$job->{qid}." with pid $$");
    			$self->job_thread($job);
    			
    			# Successfuly completed
                log_debug("Child $$ finished execution");
    			exit(0);
    			
    		} else {
    			
    			# Parent? Yeah.. we don't care any more...
                log_debug("Child $pid forked successfuly");
                $WORKER_PID = $pid;
    			
    		}
    		
    	}
    	
    }
}

############################################
# Handle the arrived actions
sub __comm_action { # Handle action arrival
############################################
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];
    
    # Trap errots
    eval {
    
    # Command switching....
    if ($packet->{context} eq $XMLNS_IBUILDER_BUILD) {
        log_debug("Got ".$packet->{type}.'/'.$packet->{action}.' under '.$packet->{context});
        
        #### GET - QUEUE           = Return a list of all the items in the queue
        if (($packet->{action} eq 'queue') && ($packet->{type} eq 'get'))  {
            # List projects in queue
            
            # Get the filter
            my $filter = '';
            $filter = $packet->{parameters}->{filter} if (defined $packet->{parameters}->{filter});
            
            # Return the listing
            my $ans = $self->projects_list($filter);
            if ($ans == 0) {
                iAgent::Kernel::Reply('comm_reply_error', { type => 'internal-server-error', message=>'Unable to list the projects in queue due to an internal error' }); # Got error!
            } else {
                iAgent::Kernel::Reply('comm_reply', { data => { projects => $ans } });
            }

        #### GET - OUTPUT          = Return the output of the script that ran a job
        } elsif (($packet->{action} eq 'output') && ($packet->{type} eq 'get'))  {
            if (not defined $packet->{parameters}->{qid}) {
                iAgent::Kernel::Reply('comm_reply_error', {type=> 'bad-request', message=> 'Missing "qid" attribute from get/output action', code=>400 });
                return 0;
            }
            
            # Return the listing
            my $row = $self->job_get_all($packet->{parameters}->{qid});
            if ($row == 0) {
                iAgent::Kernel::Reply('comm_reply_error', { type => 'internal-server-error', message=>'Unable to fetch the output of the job due to an internal error' }); # Got error!
            } else {
                iAgent::Kernel::Reply('comm_reply', { data => $row->{output} });
            }

        #### SET - INSERT          = Place a project on the build queue
        } elsif (($packet->{action} eq 'insert') && ($packet->{type} eq 'set'))  {
            
            # Put the project in the queue
            my $ans = $self->job_enqueue($packet->{parameters});
            if ($ans == 0) {
                iAgent::Kernel::Reply('comm_reply_error', { type => 'internal-server-error', message=>'Unable to list the build\'s files due to an internal error' }); # Got error!
            } else {
                iAgent::Kernel::Reply('comm_reply', { }); # OK!
            };


        #### SET - CLEANUP         = Cleanup the finished jobs
        } elsif (($packet->{action} eq 'cleanup') && ($packet->{type} eq 'set'))  {
            
            # Put the project in the queue
            my $ans = $self->jobs_cleanup();
            if ($ans == 0) {
                iAgent::Kernel::Reply('comm_reply_error', { type => 'internal-server-error', message=>'Unable to list the build\'s files due to an internal error' }); # Got error!
            } else {
                iAgent::Kernel::Reply('comm_reply', { }); # OK!
            };


        #### SET - REMOVE          = Remove a project from the build queue
        } elsif (($packet->{action} eq 'remove') && ($packet->{type} eq 'set'))  {
            if (not defined $packet->{parameters}->{qid}) {
                iAgent::Kernel::Reply('comm_reply_error', {type=> 'bad-request', message=> 'Missing "qid" attribute from set/remove action', code=>400 });
                return 0;
            }
            
            # Put the project in the queue
            my $ans = $self->job_remove($packet->{parameters}->{qid});
            if ($ans == 0) {
                iAgent::Kernel::Reply('comm_reply_error', { type => 'internal-server-error', message=>'Unable to remove the queue with ID '.$packet->{parameters}->{qid}.'! An internal error occured!' }); # Got error!
            } else {
                iAgent::Kernel::Reply('comm_reply', { }); # OK!
            };

        #### SET - NOTIFY_ADD       = Register the client on a notification queue
        } elsif (($packet->{action} eq 'notify_add') && ($packet->{type} eq 'set'))  {

            # Add notifications
            my $from = $packet->{from};
            for my $user (@MONITOR_USERS) {
                if ($user eq $from) {
                    if ($user eq $from) {
                        # Already there
                        iAgent::Kernel::Reply('comm_reply', { }); # OK!
                        return 1;
                    }
                }
            }
              
            # Put in queue
            push @MONITOR_USERS, $from;
            iAgent::Kernel::Reply('comm_reply', { }); # OK!

        #### SET - NOTIFY_REMOVE    = Register a notification client
        } elsif (($packet->{action} eq 'notify_remove') && ($packet->{type} eq 'set'))  {

            # Remove notifications
            my $from = $packet->{from};
            my $i=0;
            for my $user (@MONITOR_USERS) {
                if ($user eq $from) {
                    if ($user eq $from) {
                        # Remove it
                        splice @MONITOR_USERS, $i, 1;
                        iAgent::Kernel::Reply('comm_reply', { }); # OK!
                        return 1;
                    }
                }
                $i++;
            }
            
            # Not found? Ok...
            iAgent::Kernel::Reply('comm_reply', { }); # OK!
            
        }
                
    }
    
    # Error trap
    };
    if ($@) {
        # Gotcha!
        iAgent::Kernel::Reply('comm_reply_error', { type => 'internal-server-error', code=>500, message=>$@ }); # Got error!
    }
    
    return 1; # Allow further execution
}


############################################
# When someone goes offline, remove him from
# the notification queue.
sub __comm_unavailable {
############################################
    my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];
	
	# Get the user
	my $from = $packet->{from};
	
	# Remove him from the monitor users
	my $i=0;
	for my $user (@MONITOR_USERS) {
		if ($user eq $from) {
			# Remove the user
			splice @MONITOR_USERS, $i, 1;
			return 1;			
		}
		$i++;
	}
	
}

1;