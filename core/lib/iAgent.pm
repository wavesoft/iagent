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

package iAgent;

use iAgent::Kernel;
use iAgent::Log;
use Data::Dumper;
use Config::General;
use Hash::Merge qw( merge );
use iAgent::DB qw(DB);
use iAgent::Crypt;
use File::Basename;
use POE;

use strict;
use warnings;
our $VERSION = v0.4.0;

=head1 NAME

iAgent  - iAgent Core

=head1 DESCRIPTION

F<iAgent.pm> contains the entry point for the iAgent system. In order to start an iAgent you need
to include this file and call the iAgent::start() function 

=head1 METHODS 

=head2 start

Initializes, and runs the iAgent system.

This function will load the F<iagent.conf> on the specified etc directory, load the
defined modules and their respective configuration files, connect to the defined IO endpoint, 
initialize the modules and start the kernel.  

There are two ways to call iAgent::start:

  start( "/iAgent/etc" )                - Specify the directory to look for iagent.conf into
  
  start(
          etc => "/iAgent/etc",         - Specify the etc directory
          modules => [ 'name', .. ]     - Explicitly specify the modules to load (override iagent.conf)
       )

=head1 MODULE STRUCTURE

Each module contains a MANIFEST variable that defines the hook names and some other 
initialization parameters that are handled by the kernel.

For example:

  package iAgent::Module::MyModule;
  use strict;
  
  sub new {
  	my ($class) = @_;
  	return bless {
  	}, $class;
  }
  
  sub hello {
  	print "Hello world";
  }
  
  sub start {
  	print "Started!";
  }
  
  #
  # !!! IMPORTANT !!!
  #
  # Here is the module manifest, that defines how each action is handled.
  # For a complete reference see iAgent::Kernel
  #
  # You should use function name (string) and not the
  # code reference.
  #
  
  our $MANIFEST = {
  	  	
  	# Standard hook handlers like POE::Session->Create(object_states => { }) syntax
  	hooks => {
	    _start => 'start',
	    hello => 'hello',
  	}
  	
  	# Module priority
  	priority => 10
  	
  }
  
  # Finally, return "1"
  1;

There is only a small set of variables that is used by the iAgent Kernel. The rest of them are exposed
to the rest of the modules and thus you can have other, per-module configuration.

=head2 config (default = '')

Defines the configuration file to be used for the modue. The specified file will be searched within the same folder where
F<iagent.conf> resides. 

=head2 priority (default = 5)

Defines the priority this module will have in the broadcast list. The priority can be any number but the range 0-10 is recommended.
If not specified the module will have a default priority of 5. Smaller priorities places the module higher in the broadcast
chain, meaning that they can intercept more messages.

This is used by some low-level modules (like LDAP Authentication) that should intercept the XMPP Broadcasts before they
reach the handling endpoints.

=head2 hook_prefix (default = '')

Defines the prefix for the automated hook detection mechanism. If you specify a prefix (Usually '__') the module loader will
search for functions within the package that starts with that prefix, strip the prefix and use them as handlers for the event
with the same name.

For example:

  # Handle the "_start" message
  sub ___start {
  	print "Module started!\n";
  }
  
  # Handle the "_stop" message
  sub ___stop {
  	print "Module stopped\n";
  }
  
  # Handle the "xmpp_iq" message
  sub __xmpp_iq {
  	my ($self, $packet) = @_;
  	print "IQ Packet arrived from ".$packet->getFrom()."\n";
  }
  
  # Setup module
  $_ {
  	__hook_prefix => '__'
  }

=head1 SEE ALSO

For a complete reference on the syntax of the MANIFEST file see L<iAgent::Kernel>

=cut

# The list of the registerd sessions
# (Used for broadcast)
our $IAGENT_CONFIG;
our $ETC = "";
our $RETURN = 0; # The return code of the start function
our $CONFIG = { }; # The global configuration obtained from all the loaded config files

############################################
# Start an the iAgent system
sub start {	
############################################

    # Prepare default hash
    $IAGENT_CONFIG = {
        	etc => "./etc",
        	modules => 0,
        	args => {
        	    flags => { },
        	    value => { },
        	    num => [ ]
        	}
    };
    
    # Notify startup
    log_inform("Initializing iAgent v".sprintf("%vd",$VERSION));

    # Avoid "did not call run()" messages from POE kernel.
    # This function in this moment does nothing at all.
    POE::Kernel->run();

    # Adapt config hash based on the arguments
    my %parameters;
    if ($#_ == 0) {
        $IAGENT_CONFIG->{etc} = $_[0];
    } else {
        %parameters = @_;
        if (defined $parameters{etc}) {
         	$IAGENT_CONFIG->{etc} = $parameters{etc};
         	delete $parameters{etc};
        }
        if (defined $parameters{modules}) {
            $IAGENT_CONFIG->{modules} = $parameters{modules};
         	delete $parameters{modules};
        }
    }
    
    # Load the config file
    if (!$parameters{SkipConfig}) {
        my $f_conf = $IAGENT_CONFIG->{etc};
        foreach my $f (eval("<$f_conf/*.conf>")) {
            my $bn = basename($f);
            load_config($f) if (substr($bn,0,1) ne '.');
        }
    }
    $CONFIG = merge(\%parameters, $CONFIG); # Override config parameters
    
    # Initialize sub-components based on config file entries
    iAgent::Log::init(%{$CONFIG});
    
    # Make ETC folder public
    $ETC = $IAGENT_CONFIG->{etc};
    
    # Check if we should start in safe mode
    if ((defined $CONFIG->{CrashSafe}) && ($CONFIG->{CrashSafe} == 1)) {
    	
	    # Enable iAgent safe wrapper
    	log_info("Enabling iAgent safe mode wrappers");
    	
    	
        # Register a crash handler
        #$SIG{CHLD} = sub {
        #    log_inform("SIGCHLD Received. Assuming that child pid=$pid died!");
        #    die("Child died");
        # 	return if ($interrupted==1);
        #    $crashed = 1;
        #};
        
        # Register graceful shutdown
        $SIG{INT} = sub {
            	return;
        };
        #    log_inform("SIGINT Received. Forwarding to child pid=$pid");
        #    $interrupted=1;
        #    # kill 2, $pid; # Send SIGINT to child
        #};
        
        # Fetch frequent-crash prevention variables from config
        my $restart_delay = 30; # Seconds
        my $restart_tries = 5; # How many times should we retry
        $restart_delay = $CONFIG->{CrashSafeDelay} if defined $CONFIG->{CrashSafeDelay};
        $restart_tries = $CONFIG->{CrashSafeTries} if defined $CONFIG->{CrashSafeTries};

        # Prepare frequent-crash prevention variables
        my $spawn_time = time() - $restart_delay;
        my $tries_left = $restart_tries;

        # Main protective loop
        my $crashed=1;
        	while ($crashed==1) {
        		
        		# Check if we were called too frequenly and apply the
        		# appropriate delay between restarts. 
        		if (time() - $spawn_time < $restart_delay) {
        			# Wait for the required delay
        			my $delay = $restart_delay - (time() - $spawn_time);
        			log_warn("Retrying restart too frequently! Waiting for $delay sec");
        			sleep $delay;
        			
        		} else {
        			# If we had time to rest between two concurrent restarts, 
        			# reset the tries left
        			$tries_left = $restart_tries;
        		}
        		
        		# Nop, we are not crashed any longer
        		$crashed=0;
        		
	        	# Create child
	        	my $pid = fork();
	        	if (!defined $pid) {
	        		
	        		# Definitely dying....
	        		log_die("Unable to fork child process!");
	        		
	        	} elsif ($pid == 0) {
	        		# We are within the child
	        		
	        		# Run the main thread under an error
	        		# wrapper
	        		eval {
	        			_mainThread($CONFIG);
	        		};	    		
	        		if ($@) {
	        			# Log the fault and die
	        			log_die("iAgent crashed: ".$@);
	        		}
	        		# Finished cleanly
	        		exit(0);
	        		
	        	} else {
	        		# Wait until child finishes
	        		waitpid($pid,0);
	        		
	        		# Check result code
	        		if ($? != 0) {
	        			# Something went wrong...
	        			$crashed=1;
	        			
                    # Check if we ran out of retries
                    if ($tries_left-- <= 0) {
                        log_die("Too many retries. Unable to recover from failure!");
                    }
                    
                    # If we still have tries left, reset timer
                    $spawn_time = time();
	        		}
	        	}
	        	
	        	# Ok, if the child finished successfuly,
	        	# $crashed should be 0 and the while()
	        	# loop will exit.
	        	# If the child crashed, return code was
	        	# non-zero and the $crashed variable is
	        	# now 1. Thus, loop again!
	        	
        	}

        # Exit log
        log_info("Exiting iAgent safe mode wrappers normally");
    	
    } else {
    
        	# Otherwise, start main thread unprotected
        	_mainThread($CONFIG);

    }

    # Return the return value
    $RETURN-=511 if ($RETURN>=512); # Fix overflow BUG
    return $RETURN;
}

############################################
# This sub is the main processing thread
# of the iAgent system. It is either called
# in the same thread as the parent, or
# run under error-protected environment if 
# CrashSafe is enabled.
sub _mainThread { 
############################################
    my $config = shift;
        
    # Initialize database
    my $dbsn = "dbi:SQLite:iagent.sqlite3";
    $dbsn=$config->{AgentDBDSN} if defined $config->{AgentDBDSN};
    # Credentials
    my $username = undef;
    $username = $config->{AgentDBUsername} if defined $config->{AgentDBUsername};
    my $password = undef;
    $password = $config->{AgentDBPassword} if defined $config->{AgentDBPassword};
    iAgent::DB::Initialize($dbsn, $username, $password);
    
    # Initialize cryptographic routines (After database)
    iAgent::Crypt::Initialize($config->{Crypto});
    delete $config->{Crypto};

    # Load the modules the user specified
    if (UNIVERSAL::isa($IAGENT_CONFIG->{modules}, 'ARRAY')) {
        
        log_debug("Module loading specified by the user. Overriding iagent.conf");
        foreach my $module (@{$IAGENT_CONFIG->{modules}}) {
            log_debug("Loading module $module");
            loadModule($module);
        }
        
    } else {
        
        # Nothing specified,
        # Load modules specified from the config
        log_debug("Loading modules according to iagent.conf");
        if (ref($config->{LoadModule}) eq 'ARRAY') {
            foreach my $module (@{$config->{LoadModule}}) {
                log_debug("Loading module $module");
                loadModule($module);        
            }
        } else {
            log_debug("Loading module ".$config->{LoadModule});
            loadModule($config->{LoadModule});        
        }       
    }
    
    # Register graceful shutdown on ctrl-c
    $SIG{INT} = sub {
        log_inform("SIGINT Received. Performing graceful shutdown in a few seconds. Send again to force.");
        $SIG{INT} = 'DEFAULT';
        
        my $ans = iAgent::Kernel::Dispatch("interrupt");
        return unless (($ans == RET_UNHANDLED) || ($ans == RET_OK));
        
        iAgent::Kernel::Exit(1);
    };
    
    # Broadcast the _run message
    # that informs that everything is up and running
    log_inform("Starting iAgent v".sprintf("%vd",$VERSION));
    iAgent::Kernel::Broadcast('ready');
    POE::Kernel->run();

}

############################################
#
# Load the file of the specified class,
# and load it's manifest. 
#
# If there are subclasses, traverse all of
# them, and merge their independent manifests 
# with the main one.
#
sub loadAllClassFiles {
############################################
    my ($package) = @_;
    
    # Convert package to path name
    my $path = $package;
    $path =~ s!::!/!sg;
    $path .= ".pm";

    # Load file
    log_debug("Requiring file $path");
    require($path);

    # Prepare manifest
    my $manifest = { };

    # Check and load parent classes
    no strict qw(refs);
    if (defined @{$package.'::ISA'}) {
        foreach (@{$package.'::ISA'}) {
            log_debug("Loading dependency $_");
            $manifest = merge( $manifest, loadAllClassFiles( $_ ));
        }
    }

    # Check and load manifest
    my $M = ${$package."::MANIFEST"};    
    $manifest = merge( $M, $manifest) if (defined $M);
    use strict qw(refs);

    # Return manifest
    return $manifest;
        
}

############################################
# Load a module to the iAgent system
sub loadModule { 
############################################
    my ($package) = @_;
    
    # Convert package to path name
    my $path = $package;
    $path =~ s!::!/!sg;
    $path .= ".pm";
    
    # If it's already loaded, exit
    if (iAgent::Kernel::ModuleLoaded($package)) {
        log_info("Already loaded. Skipping module $package");
        return;
    }
        
    # Load the modules and their manifest
    my $_init = {};
    eval {
	    $_init = loadAllClassFiles($package);
    };
	if ($@) {
		my ($msg) = $@;
		chop $msg;
		log_warn($msg);
		log_die("Error while loading $package!");
	};
    
    # Setup defaults for missing
    # special vars
    (!defined $_init->{config}) and $_init->{config} = undef;
    
    # Try to load the config file for that module
    if (defined $_init->{config}) {
    	my $c_file = $IAGENT_CONFIG->{etc}.'/'.$_init->{config};
        log_debug("Trying to load config file $c_file as specified by the init hash");
    	if (!-f $c_file) {
            log_warn("Unable to find the config file $c_file of module $package!");
    	} else{
            load_config($c_file);
    	}
    }
    
    # Unset excess parameters from hash
    delete $_init->{config};
    
    # Put some overriden information
    $_init->{class} = $package;
    $_init->{args} = $CONFIG;
    
    # Register module on kernel
    log_debug("Registering $package to kernel");
    iAgent::Kernel::Register($_init);
    
}

## ---------------------------------------------------------------------------------------------------------------------
##                                          PRIVATE HELPER FUNCTIONS
## ---------------------------------------------------------------------------------------------------------------------

my $LOADED_CONFIG_FILES = { };

############################################
# Load configuration and return the merged hash
sub load_config {	
############################################
    my ($file) = @_;
    return $CONFIG if (defined($LOADED_CONFIG_FILES->{$file}));
    log_debug("Loading config file $file");

    # Load config from that file
    my $_conf = new Config::General($file);
    my %f_config = $_conf->getall;
    
    # Convert LoadModule to array to enable proper merging
    if (defined($f_config{LoadModule})) {
        if (!UNIVERSAL::isa($f_config{LoadModule}, 'ARRAY')) {
            $f_config{LoadModule} = [ $f_config{LoadModule} ];
        }
    }

    # Mark file as loaded
    $LOADED_CONFIG_FILES->{$file} = 1;

    # Merge config
    $CONFIG = merge( $CONFIG, \%f_config );

    # Check and execute 'Include' directives
    while (defined ($CONFIG->{Include})) {
        my @files;
        if (UNIVERSAL::isa($CONFIG->{Include},'ARRAY')) {
            @files = @{$CONFIG->{Include}};
        } else {
            @files = ( $CONFIG->{Include} );
        }
        delete $CONFIG->{Include};
        
        # Fetch config files specified by the files
        foreach my $match (@files) {
            
            # Prefix with the etc folder if the path is not absolute
            $match = dirname($file).'/'.$match unless (substr($match,0,1) eq '/');
            
            # Process the matches of the 'Include' directive
            foreach my $f (eval("<$match>")) {
                my $bn = basename($f);
                $CONFIG = load_config($f) if ((substr($bn,0,1) ne '.') && (substr($bn,-5) eq '.conf'));
            }
            
        }
        
    }
    
    # Return config
    return $CONFIG;

}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
