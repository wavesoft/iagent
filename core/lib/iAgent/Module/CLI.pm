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

iAgent::Module::CLI - CLI Bindings for the iAgent Module

=head1 DESCRIPTION

This module enables command-line capability to iAgent. 

If iAgent is invoked with command-line parameters, they are procesed directly by the 
registered module and then exit. If it is started without any parameters it enables
the interactive console.

=cut

# Core definitions
package iAgent::Module::CLI;

use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;
use Data::Dumper;
use Term::ReadKey;

use Getopt::Long qw(GetOptionsFromString);
use POE qw(Wheel::ReadLine);

our $MANIFEST = {
    oncrash => 'die',
    priority => 100,

    # CLI bindings for ourselves
    CLI => {
        "exit" => {
            message => "cli_exit",
            description => "Terminate CLI session"
        },
        "cli/clear" => {
            description => "Clear screen",
            options => [ 'who=s', 'a' ],
            message => "cli_clear"
        },
        "cli/verbosity" => {
            description => "Display/Set verbosity level",
            message => "cli_verbosity"
        },
        "cli/dumpconfig" => {
            description => "Dump the configuration file of iAgent",
            message => "cli_dumpconfig"
        },
        "cli/filter" => {
            description => "Display/define the display log filter",
            message => "cli_filter"
        }
    }
    
};

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { 

        # 1=Use Readline, 0=Use STDIN/OUT
        INTERACTIVE => 0,

        # 1= CLI Is initialized
        CLI_INITIALIZED => 0,

        # The current context path of the CLI
        PATH => "",

        # All the registered commands in the CLI
        #
        # 'path/path/command' => {
        #     message => 'target_poe_message',
        #     options => [ 'all|a', 'name=s' ] # GetOpt::Long - compatible options,
        #     description => "Description for the help",
        #     module => 'package::name' # Of the module that registered this command
        # }
        #
        COMMANDS => { },

        # All the registered command paths
        #
        #  'path' => 1,
        #  'path/path' => 1
        #  ...
        #
        VALID_PATHS => { },

        # Multiline information hash
        # This is used while processing multi-line commands
        MULTILINE => {
            cmd => '',      # The command that triggered the multi-line parsing
            params => '',   # The parameters of the triggering command,
            input => '',    # The entire input line (That's: "$cmd $params")
            buffer => '',   # The input buffer
            active => 0     # 1 if we are currently parsing multiple lines
        },

        # When this flag is 1, the CLI is blocked and cannot accept commands
        # This is used in order to allow response for every command sent.
        COMMAND_ACTIVE => 0,

        # The broadcast stack, used to schedule
        # a broadcast of a command when the module
        # becomes available
        BROADCAST_STACK => [ ],

        # The states of all the modules
        #
        # Depending on the messages we receive from the iAgent bus, we consider
        # the modules VALID or INVALID and FREE or BUSY.
        #
        # When a module is VALID it can receive commands, otherwise the commands
        # are scheduled to be transmitted when the module is again VALID.
        #
        # For example, you cannot send commands to XMPP unless it's connected.
        # So, XMPP Module can set the validation message to 'comm_ready' and the
        # invalidation message to 'comm_disconnect'. This effectively means that
        # if the module is not connected, the commands will be just scheduled and
        # sent when the module is connected again.
        #
        # When a module is BUSY it prohibits the entire system from exiting. Thus
        # the CLI will wait until all the modules are FREE before exiting...
        #
        # For example, when a workflow is started, the 'workflow_started' message is
        # sent. If the workflow registeres this as a BUSY message, it will 
        #
        # Format: 
        #   MODULE_STATES->{<PLUGIN PACKAGE NAME>}->{ VALID => 0, BUSY => 0 }
        #
        MODULE_STATES => { },

        # TRUE if we are just waiting for the plugins to be free before we shut
        # everything down and exit.
        PENDING_EXIT => 0
        
    };
    return bless $self, $class;
}

############################################
# A delegate function that is forced into
# every plugin's POE session that handles
# the cli_command message and dispatches it
# to the module handlers accordingly.
#
# (This is used in order to preserve the
#  iAgents module's priority stack)
#
# AKA: We are using this function, in order
# to allow other modules with higher priority
# to trap the event and modify or abort it.
#
sub CLI_DELEGATE {
############################################
    my ($heap, $kernel, $session, $cmd) = @_[ HEAP, KERNEL, SESSION, ARG0 ];
    my $commands = $heap->{CLI};

    # Forward the command to the defined message
    if (defined $commands->{$cmd->{command}}) {
        return $kernel->call($session, $commands->{$cmd->{command}}->{message}, $cmd);
    }

    # Not handled? Pretend this never happened...
    return undef;
}

############################################
# Everything is ready
sub __ready {
############################################
    my ($self, $kernel, $heap, $session) = @_[ OBJECT, KERNEL, HEAP, SESSION ];

    # -------------------------------------------
    # |  LOAD CLI BINDINGS & INSTALL DELEGATES  |
    # -------------------------------------------
    my $CLI_COMMANDS = { }; my $CLI_PATHS = { };
    for my $inf (@iAgent::Kernel::SESSIONS) {
        my $heap = $inf->{session}->get_heap();
        	my $manifest = $heap->{MANIFEST};
        my $cache = { };
        my %module_commands = ();

        # Clear array
        %module_commands = ();
        
        # Fetch CLI messages
        	if (defined $manifest->{CLI}) {

        	    # Process CLI directives
        	    my $msg_validate = "ready";
        	    my $msg_invalidate = "_stop";
        	    my $msg_busy = "_stop";
        	    my $msg_free = "ready";
        	    if (defined $manifest->{CLI}->{VALIDATE_AT}) {  # Can receive commands after this message
            	    $msg_validate = $manifest->{CLI}->{VALIDATE_AT};
            	    delete $manifest->{CLI}->{VALIDATE_AT};
            	}
        	    if (defined $manifest->{CLI}->{INVALIDATE_AT}) { # Cannot receive commands after this message
            	    $msg_invalidate = $manifest->{CLI}->{INVALIDATE_AT};
            	    delete $manifest->{CLI}->{INVALIDATE_AT};
            	}
        	    if (defined $manifest->{CLI}->{BUSY_AT}) { # We MUST NOT exit after this message
            	    $msg_busy = $manifest->{CLI}->{BUSY_AT};
            	    delete $manifest->{CLI}->{BUSY_AT};
            	}
        	    if (defined $manifest->{CLI}->{FREE_AT}) { # We can exit after this message
            	    $msg_free = $manifest->{CLI}->{FREE_AT};
            	    delete $manifest->{CLI}->{FREE_AT};
            	}

        	    # Process module commands
        	    foreach my $cmd (keys %{$manifest->{CLI}}) {
    	            my $STDIN=''; # Changes to the parameter's name if the command reads from stdin

        	        # Fetch entire command hash
        	        $CLI_COMMANDS->{$cmd} = $manifest->{CLI}->{$cmd};

        	        # Ensure presence of some specific parameters
        	        $CLI_COMMANDS->{$cmd}->{description} = '(No description available)' 
        	            if (not defined $CLI_COMMANDS->{$cmd}->{description});

        	        # Update paths hash
        	        if ($cmd =~ m/^(.*)\/[\w\-_]+$/) {
        	            $CLI_PATHS->{$1} = 1;
        	        }

                if (defined $CLI_COMMANDS->{$cmd}->{options}) {
            	        # Build the autocompletion-compatible parameter list
            	        # and the parameter names hash from the 'options' array.
            	        #
            	        # The parameters in 'options' array are specified in the same
            	        # format as the GetOpt::Long, wich contains control characters.
            	        # 
            	        # This block of code converts it into the human-readable
            	        # input format that is expected (For auto-completion) and it's
            	        # actual name (For the creation of the parameters hash after
            	        # the command has been entered and the input has been parsed)
            	        #
            	        my @AC_LIST; my %PARAM_DEFINITION;
            	        foreach my $_cmd (@{$CLI_COMMANDS->{$cmd}->{options}}) {
            	            my $suffix='';
            	            my $negate=0;
            	            my $cmd=$_cmd;
            	            my $default = undef;
            	            my $use_stdin=0;

            	            # Check suffix
            	            if ($cmd =~ m/(=..?)$/) {
            	                my $p = $1;
                            $cmd = substr($cmd,0,-length($p));
                            $suffix='=';
                            $default=[] if ($p =~ '@');
                            $default={} if ($p =~ '%');
                            $default=0 if ($p =~ 'i');
                            $default='' if ($p =~ 's');
                            if ($p =~ '-') {
                                $use_stdin=1;
                                $default='';
                            }
            	            }
            	            if ($cmd =~ m/!$/) {
                            $negate=1;
                            $cmd = substr($cmd,0,-1);
            	            }

                        # Special handling of stdin variable
                        if ($use_stdin) {
                            $STDIN=$cmd;
                        } else {
                            # Check for multiple values
                            my $name=undef;
                            foreach my $c (split('\|',$cmd)) {
                                $name=$c if (!defined $name); # Keep the first one as name (The rest are aliases)
                                push @AC_LIST, "--$c$suffix";
                                push @AC_LIST, "--no$c$suffix" if ($negate);
                            }
                            $PARAM_DEFINITION{$_cmd} = [$name, $default]; # Define the name of the variable and the suggested default
                        }
                        
            	            
            	        }

            	        # Store auto-completion names and actual names
            	        $CLI_COMMANDS->{$cmd}->{options_ac} = \@AC_LIST;
            	        $CLI_COMMANDS->{$cmd}->{options_def} = \%PARAM_DEFINITION;
            	        
                }
                
                # Store this cli command also as a module command
                $module_commands{$cmd} = $CLI_COMMANDS->{$cmd};
        	        $CLI_COMMANDS->{$cmd}->{stdin} = $STDIN;
                $CLI_COMMANDS->{$cmd}->{module} = $heap->{CLASS};
                
        	    }
        	    

        	    # Save the module_commands to the module's heap
        	    # (Used by the CLI_DELEGATE function)
        	    $heap->{CLI} = \%module_commands;

        	    # Now register the CLI_DELEGATE into the module's POE Session
            $inf->{session}->_register_state('cli_command', \&CLI_DELEGATE);
			iAgent::Kernel::RegisterHandler($inf->{session}, 'cli_command');

        	    # Register the module state and validation/invalidation messages
        	    $self->{MODULE_STATES}->{$heap->{CLASS}} = {
        	        VALID => ($msg_validate eq 'ready')?1:0,
        	        FREE => 1
            };

            # DEBUG
    	        log_debug("Module $heap->{CLASS} is already valid")
    	            if ($self->{MODULE_STATES}->{$heap->{CLASS}}->{VALID});
           
            
        	    # Register some anonymous message handlers that will until the declared
        	    # message(s) is arrived on the target session
        	    #
        	    # (We put this code here - wich means at the target session and NOT on the CLI session - because
        	    #  we also want to trap messages that come from Response() and target directly that session, 
        	    #  that will probably not reach CLI)
        	    #
        	    $session->_register_state($msg_validate, sub { 
        	        log_debug("Module $heap->{CLASS} is valid"); 
        	        $self->{MODULE_STATES}->{$heap->{CLASS}}->{VALID}=1; 
        	        $self->check_broadcasts();
        	        }) 
        	        if ($msg_validate ne 'ready');
				iAgent::Kernel::RegisterHandler($session, $msg_validate);
        	        
        	    $session->_register_state($msg_invalidate,  sub { 
        	        log_debug("Module $heap->{CLASS} invalidated"); 
        	        $self->{MODULE_STATES}->{$heap->{CLASS}}->{VALID}=0; 
        	        })
        	        if ($msg_invalidate ne '_stop');
				iAgent::Kernel::RegisterHandler($session, $msg_invalidate);
        	    
        }
    }

    # Store detected commands and valid paths
    $self->{COMMANDS} = $CLI_COMMANDS;
    $self->{VALID_PATHS} = $CLI_PATHS;

    # Select activation mode
    if ($#ARGV>=0) {
        $self->{INTERACTIVE}=0;
    } else {
        $self->{INTERACTIVE}=1;
    }

    # If everything is valid, activate now
    if ($self->modules_valid()) {
        $self->initialize_cli();
    } else {
        log_inform("iAgent is not yet ready. Please wait for system initialization before the console is activated");
    }

}

##===========================================================================================================================##
##                                             HELPERS FOR READLINE                                                          ##
##===========================================================================================================================##

############################################
# A helper function to provide the auto-
# completion parameters for the current CLI
# command.
sub autocomplete {
############################################
    my ($self, $text, $line, $start) = @_;

    # Check what stuff are we trying to auto-complete

    # No space found? Command...
    if (index(substr($line,0,$start),' ') == -1) {
    
        # Build an appropriate absolute path
        my $path=$self->{PATH};
        if (substr($text,0,1) eq '/') {
            $path='';
            $text = substr($text,1);
        }
        $path.=$text;

        # Find all the commands starting at this path
        my @ans;
        foreach my $cmd (keys %{$self->{COMMANDS}}) {
            if ($cmd =~ m/^$path/) {
                push @ans, substr($cmd,length($self->{PATH})).' '; # (Strip path)
            }
        }

        # Return the commands found
        return @ans;

    # Space found? Parameter..
    } else {
    
        my ($cmd, $params) = split(' ',$line,2); # Split tokens of the command-line
    
        # Build an appropriate absolute path
        my $path=$self->{PATH};
        if (substr($cmd,0,1) eq '/') {
            $path='';
            $cmd = substr($cmd,1);
        }
        $cmd=$path.$cmd;

        # Fetch the auto-completion list for the parameters
        if (defined $self->{COMMANDS}->{$cmd}) {
            if (!$self->{COMMANDS}->{$cmd}->{options_ac}) {
                return ( );
            } else {
                return @{$self->{COMMANDS}->{$cmd}->{options_ac}};
            }
        } else {
            return ( );
        }
        
    }
    
}

##===========================================================================================================================##
##                                                    HELPER FUNCTIONS                                                       ##
##===========================================================================================================================##

############################################
# Called when all the modules are ready for
# any kind of CLI commands
sub initialize_cli {
############################################
    my $self = shift;
    my $session = POE::Kernel->get_active_session();
    my $heap = $session->get_heap();

    # If CLI is ready, exit
    return if ($self->{CLI_INITIALIZED});
    $self->{CLI_INITIALIZED}=1;

    # Notify that console started
    iAgent::Kernel::Dispatch("cli_started", $self->{INTERACTIVE});
    
    # If we have a command-line, handle the command now
    if (!$self->{INTERACTIVE}) {
    
        # -----------------------------------------
        # |  SINGLE-USE, COMMAND-LINE INVOCATION  |
        # -----------------------------------------
        #
        # In an asynchronously asynchronous world... 
        # that's quite difficult. Solution:
        #
        #  1) Wait for all the modules to become valid
        #  2) Send the command
        #  3) Wait for message(s) that will satisfy exit
        #  4) Exit
        #

        # If we have a command line, dispatch the command now
        my $input = join(' ',@ARGV);
        my ($cmd, $params) = split(' ', $input,2);
        log_die("Unknown command $cmd specified!") if (!defined $self->{COMMANDS}->{$cmd});

        # And we are waiting for exit
        $self->{PENDING_EXIT} = 1;
        
        log_debug("Console started in non-interactive mode. Exit is pending...");

        # Multiline parsing?
        if ($self->{COMMANDS}->{$cmd}->{stdin} ne '') {

            # Read stdin NOW!
            my $buffer=''; my $line;
            while (defined($line =  <STDIN>)) {
                $buffer.=$line;
            }

            # Handle command (Or schedule if module not yet valid)
            $self->handle_command($cmd, $params, $input, $buffer);
            

        # Normal command?
        } else {
        
            # Handle command (Or schedule if module not yet valid)
            $self->handle_command($cmd, $params, $input, '');
            
        }

        
    } else {

        # ------------------------------
        # |  INTERACTIVE CONSOLE MODE  |
        # ------------------------------
        #
        # Everything is asynchronous. Everthing is handled
        # by POE messages asynchronously....
        #
        # And life is now simple :]
        #

        # Create a readline wheel to read stdin
        $heap->{console} = new POE::Wheel::ReadLine(
          InputEvent => '_int_cli_command',
        );

        # Setup auto-completion
        my $attribs = $heap->{console}->attribs();
        $attribs->{completion_function} = sub {
            return $self->autocomplete(@_);
        };

        # Prepare CLI    
        $heap->{console}->put("===========================================");
        $heap->{console}->put(" Welcome to iAgent Command-line interface");
        $heap->{console}->put("===========================================");
        $heap->{console}->get("AGENT> ");
        
    }
    
}

############################################
# Returns TRUE if all the modules are valid
sub modules_valid {
############################################
    my $self = shift;
    foreach (keys %{$self->{MODULE_STATES}}) {
        return 0 if (!$self->{MODULE_STATES}->{$_}->{VALID});
    }
    return 1;
}

############################################
# If a module is still invalid, we call this
# function in order to place the message that
# needs to be sent into the output stack.
#
# When the message arrives it pops the message
# from stack and sends it to the appropriate 
# plugin
#
sub schedule_broadcast {
############################################
    my ($self, $command, $parameter) = @_;

    # Schedule broadcast
    log_debug("Scheduling broadcast for '$command'");        
    push @{$self->{BROADCAST_STACK}}, [ $command, $parameter ];

    if ($self->modules_valid()) { # If everything is valid, send it now
        $self->check_broadcasts();
    }
    
}

############################################
# A module has been validated. 
#
# Wheck if ALL of them are now valid, and if
# true, broadcast the pending messages.
#
sub check_broadcasts {
############################################
    my $self = shift;

    # Are ALL the modules active?
    return if (!$self->modules_valid);

    log_debug("All modules have been successfully validated. Executing pending commands:");

    # Initialize CLI if not yet initialized
    $self->initialize_cli();

    # Broadcast and remove the compatible entries
    my $handled=0;
    for (my $i=0; $i<=$#{$self->{BROADCAST_STACK}}; $i++) {
        my @entry = @{$self->{BROADCAST_STACK}->[$i]};

        # Process message
        my $ans = iAgent::Kernel::Dispatch($entry[0], $entry[1]);
        splice @{$self->{BROADCAST_STACK}}, $i, 1;

        # Handle error responses
        if ($ans == RET_UNHANDLED) { # No plugin received this or no plugin responded (-1 or -2)
            if ($self->{PENDING_EXIT}) { # 
                iAgent::Kernel::Dispatch("cli_exit", 100);
            } else {
                iAgent::Kernel::Dispatch("cli_error", "The command was not handled by any plugin!");
            }

            # Command is NOT active. Display prompt again...
            $self->{COMMAND_ACTIVE}=0;
            
        } elsif ($ans == RET_ABORTED) { # Aborted by some plugin
            if ($self->{PENDING_EXIT}) { # 
                iAgent::Kernel::Dispatch("cli_exit", 101);
            } else {
                iAgent::Kernel::Dispatch("cli_error", "Unable to run the specified command!");
            }

            # Command is NOT active. Display prompt again...
            $self->{COMMAND_ACTIVE}=0;
            
        } elsif ($ans == RET_COMPLETED) { # Completed in the same call
            if ($self->{PENDING_EXIT}) { # 
                iAgent::Kernel::Dispatch("cli_exit", 0);
            }

            # Command is NOT active. Display prompt again...
            $self->{COMMAND_ACTIVE}=0;
            
        } elsif ($ans == RET_ERROR) { # An error occured in the same call
            if ($self->{PENDING_EXIT}) { # 
                iAgent::Kernel::Dispatch("cli_exit", 1);
            }

            # Command is NOT active. Display prompt again...
            $self->{COMMAND_ACTIVE}=0;
            
        }

    }
    
}

############################################
# Initiate a multiline reading
sub start_multiline {
############################################
    my ($self, $cmd, $params, $input) = @_;
    $self->{MULTILINE} = {
        input => $input,
        cmd => $cmd,
        params => $params,
        active => 1,
        buffer => ''
    };
}

############################################
# Process a multiline command
sub handle_multiline {
############################################
    my ($self, $input) = @_;

    if ($input =~ m/(.*);\s*$/) { # Finished
        $self->{MULTILINE}->{active} = 0;

        # Add remaining buffer
        $self->{MULTILINE}->{buffer} .= "$1\n";

        # Handle the multi-line command
        $self->handle_command(
            $self->{MULTILINE}->{cmd},
            $self->{MULTILINE}->{params},
            $self->{MULTILINE}->{input},
            $self->{MULTILINE}->{buffer}
        );

        # We are done
        return 0;
        
    } else { # Store buffer
        $self->{MULTILINE}->{buffer} .= "$input\n";

        # We are still inside
        return 1;
    }
}

############################################
# Handle a complete command
sub handle_command {
############################################
    my ($self, $cmd, $params, $line, $stdin) = @_;

    # Is this a command?
    if (defined $self->{COMMANDS}->{$cmd}) {

        log_debug("Got $line / $stdin");

        # Process command-line according to options (if available)
        my $command = $self->{COMMANDS}->{$cmd};
        my $options = { };
        my $unparsed_options = { };
        if (defined $command->{options}) {
              my %getoptions_args;

              # Build the GetOptions arguments
              #
              # ( <The GetOpt-compatible syntax of the option> ,
              #   <A reference to the variable (inside the hash $options) that will hold the value> ,
              #   ... )
              #
              foreach my $option (keys %{$command->{options_def}}) { 
                  my ($name, $default) = @{$command->{options_def}->{$option}};
                  $options->{$name} = $default; # Default value is what's suggested
                  $getoptions_args{$option} = \$options->{$name}
              }

              # Trap warn only for the next call
              local $SIG{__WARN__};
              
              # Get options
              my ($ret, $rargs) = GetOptionsFromString($params, %getoptions_args);
              $unparsed_options = $rargs;

              # Update stdin
              $options->{$command->{stdin}} = $stdin if ($command->{stdin} ne '');
              
        }
        
        # Schedule a broadcast, when the plugin becomes available
        $self->schedule_broadcast('cli_command',{
            command => $cmd,
            cmdline => $params,
            options => $options,
            unparsed => $unparsed_options,
            interactive => $self->{INTERACTIVE},
            raw => $line
        });

        # Succeeded
        return 1;

    } else {

        # Failed
        return 0;
        
    }

}

##===========================================================================================================================##
##                                                 POE Callbacks                                                             ##
##===========================================================================================================================##

############################################
# Display/set the log filter
sub __cli_filter {
############################################
    my ($cmd, $kernel) = @_[ ARG0, KERNEL ];
    if (defined $cmd->{cmdline}) {
        if ($cmd->{cmdline} eq '-') {
            iAgent::Log::filter(undef);
        } else {
            my @FLT = split(" ", $cmd->{cmdline});
            iAgent::Log::filter(\@FLT);
        }
    }
    my $filter = iAgent::Log::filter();
    if (defined($filter)) { 
        $kernel->yield("cli_write","Verbosity filter is: " . join(", ",@$filter) );
    } else {
        $kernel->yield("cli_write","Verbosity filter is not set" );
    }
    return RET_COMPLETED;
}

############################################
# Change verbosity log level
sub __cli_verbosity {
############################################
    my ($cmd, $kernel) = @_[ ARG0, KERNEL ];
    if (!defined $cmd->{cmdline}) {
        $kernel->yield("cli_write","Verbosity level: " . iAgent::Log::verbosity() );
    } else {
        my $level = $cmd->{cmdline};
        $kernel->yield("cli_write","Verbosity level set to: " . iAgent::Log::verbosity($level));
    }

    return RET_COMPLETED;
}

############################################
# Display help message for the current path
sub __cli_help {
############################################
    my ($self, $heap) = @_[OBJECT, HEAP];
    my $console = $heap->{console};

    # Build command names and their description
    my @texts; my @cmds; my %paths; my $pad_size=10; my $path=$self->{PATH};
    foreach my $cmd (keys %{$self->{COMMANDS}}) {
        if ($cmd =~ m/^$path[\w\-_]+$/) {
            $pad_size=length($cmd)+1 if (length($cmd)+1>$pad_size);
            push @cmds, $cmd;
            push @texts, $self->{COMMANDS}->{$cmd}->{description};
        }
        if ($cmd =~ m/^$path([\w\-_]+)\/([\w\-_]+)$/) {
            $pad_size=length($1) if (length($1)>$pad_size);
            $paths{$1} = 1;
        }
    }

    # Introduction
    $console->put("Available commands for the current context:");
    $console->put("");
    $console->put(' '.sprintf("%-${pad_size}s", '..').' - Go to the parent context')
        if ($self->{PATH} ne '');

    # Preety-print the results
    my ($columns, $rows) = $console->terminal_size;
    my $columns_padded = $columns-$pad_size-4;
    
    foreach my $path (keys %paths) {
        $console->put(' '.sprintf("%-${pad_size}s", $path).' - Change to '.$path.'/ context');
    }
    for (my $i=0; $i<=$#cmds; $i++) {
        my $cmdname = substr($cmds[$i],length($self->{PATH}));
    
        # Prepare line
        my $line = ' '.sprintf("%-${pad_size}s", ' '.$cmdname).' - '.$texts[$i];

        # Split into many lines with the appropriate padding
        # if it goes beyond the terminal width
        if (length($line)>$columns) {
            $console->put(substr($line,0,$columns));
            $line = substr($line,$columns);
            while (length($line)>$columns_padded) {
                $console->put(' '.sprintf("%-${pad_size}s", '').'   '.substr($line,0,$columns_padded));
                $line = substr($line,$columns_padded);
           }
           $console->put(' '.sprintf("%-${pad_size}s", '').'   '.$line);
        } else {
           $console->put($line);
        }
    }
    $console->put(' '.sprintf("%-${pad_size}s", ' help').' - Display help for the current context');
    $console->put("");

}

############################################
# Exit the command-line interface
sub __cli_exit {
############################################
    my ($self, $heap, $code) = @_[OBJECT, HEAP, ARG0];
    my $console = $heap->{console};

    # Brace yourselves....    
    $console->put("Exiting") if ($self->{INTERACTIVE});
    ReadMode 0; # Reset tty mode before exiting

    # Exit
    iAgent::Kernel::Exit($code);

    # Return OK
    return RET_OK;
    
}

############################################
# Clear CLI display
sub __cli_clear {
############################################
    my ($self, $heap) = @_[OBJECT, HEAP];
    my $console = $heap->{console};
    
    $console->clear()  if ($self->{INTERACTIVE});

    # Completed
    return RET_COMPLETED;
}

############################################
# Write something on CLI
sub __cli_write {
############################################
    my ($self, $heap, $message) = @_[OBJECT, HEAP, ARG0];

    if ($self->{INTERACTIVE}) {
        my $console = $heap->{console};
        $console->put($message);
    } else {
        log_inform("$message");
    }

    return 1;

}

############################################
# Dump iAgent global config
sub __cli_dumpconfig {
############################################
    my ($self, $heap, $cmd) = @_[ OBJECT, HEAP, ARG0 ];
    my @config = split("\n", Dumper($iAgent::CONFIG));
    my $console = $heap->{console};
    foreach (@config) {
        $console->put($_);
    }
    
    return RET_COMPLETED;
}

############################################
# Write an error on CLI
sub __cli_error {
############################################
    my ($self, $heap, $message) = @_[OBJECT, HEAP, ARG0];

    if ($self->{INTERACTIVE}) {
        my $console = $heap->{console};
        $console->put("ERROR: $message");
    } else {
        log_error("$message");
    }

    return 1;

}

############################################
# Command completed (Sent by the plugins)
sub __cli_completed {
############################################
    my ($self, $result) = @_[ OBJECT, ARG0 ];

    # Exit the infinite loop
    $self->{COMMAND_ACTIVE} = 0;

    # If we are pending an exit, exit now...
    if ($self->{PENDING_EXIT}) {
        # The command is completed... EXIT!
        iAgent::Kernel::Dispatch("cli_exit", $result);
    }

    return 1;
    
}

############################################
# CLI command sent
sub ___int_wait_completion {
############################################
    my ($self, $heap) = @_[ OBJECT, HEAP ];
    my $console = $heap->{console};

    # Keep waiting until the CLI command is completed
    if ($self->{COMMAND_ACTIVE}) {

        # Infinite loop
        $_[KERNEL]->delay( '_int_wait_completion' => 0.01);
        
    } else {

        # Calculate prompt
        my $PRMPT = "AGENT";
        if ($self->{PATH} ne '') {
            $PRMPT = 'AGENT/'.uc(substr($self->{PATH},0,-1));
        }
    
        # Show prompt
        $console->get("$PRMPT> ");
        
    }
}

############################################
# CLI command sent
sub ___int_cli_command {
############################################
    my ($self, $input, $exception, $heap, $kernel) = @_[OBJECT, ARG0, ARG1, HEAP, KERNEL];
    my $console = $heap->{console};
    
    unless (defined $input) {
        $console->put("Interrupted");
        
        ReadMode 0; # Reset tty mode before exiting
        iAgent::Kernel::Exit(1);
        return;
    }

    # If we are in multiline mode, keep reading
    if ($self->{MULTILINE}->{active}) {
        $self->{COMMAND_ACTIVE}=1;

        # If we are still inside multiline mode, use the multiline
        # prompt
        if ($self->handle_multiline($input)) {
            $console->get(">");
            $self->{COMMAND_ACTIVE}=0;
            return;
        } else {
            $input=''; # << Processed, skip next block
            
            # Enter 'active command' mode
            $kernel->yield('_int_wait_completion');
            return;
            
        }

    }

    # Skip empty lines
    if ($input ne '') {

        # Store the command in history
        $console->addhistory($input);

        my ($acmd, $params) = split(' ', $input, 2);
        my $cmd=$acmd;

        # Properly format CMD path
        my $path = $self->{PATH};
        if (substr($cmd,0,1) eq '/') {
            $path='';
            $cmd=substr($cmd,1);
        }
        $cmd = $path.$cmd;

        # Is this help?
        if (($acmd eq 'help') || ($acmd eq 'ls') || ($acmd eq '?')) {

            # Display help for the current context
            $kernel->yield("cli_help");

        # Is this 'change to root?'
        } elsif ($acmd eq '/') {

            # Change path to root
            $self->{PATH} = '';


        # Is this 'go back' ?
        } elsif ($acmd eq '..') {

            # Change to the parent context
            if ($self->{PATH} ne '') {
                my @parts = split '/',$self->{PATH};
                pop @parts;
                $self->{PATH} = join('/',@parts);
                $self->{PATH}.='/' unless $self->{PATH} eq '';
            }

        # Is this a path?
        } elsif (defined $self->{VALID_PATHS}->{$cmd}) {
        
            # Change path if we found a path
            $self->{PATH} = $cmd.'/';

        # Then it's a command...
        } else {

            # Check if this command exists
            if (defined $self->{COMMANDS}->{$cmd}) {

                # Check if the command requires STDIN
                if ($self->{COMMANDS}->{$cmd}->{stdin} ne '') {

                    # Start multi-line command                    
                    $self->start_multiline($cmd, $params, $input);

                    # Use different promt for multi-line
                    $console->put("This command requires additional input. Type ';' when finished");
                    $console->get(">");
                    return;
                    
                } else { # No, regular command handling
                
                    # Enter 'active command' mode
                    $self->{COMMAND_ACTIVE}=1;
                    $kernel->yield('_int_wait_completion');

                    # Invoke command
                    $self->handle_command($cmd, $params, $input, '');
                    return;
                    
                }

            } else { # Not found...
                $console->put("Unknown command. Type 'help' to list the available commands");
            }

        }
        
    }

    # Calculate prompt
    my $PRMPT = "AGENT";
    if ($self->{PATH} ne '') {
        $PRMPT = 'AGENT/'.uc(substr($self->{PATH},0,-1));
    }

    # Show prompt
    $console->get("$PRMPT> ");
}

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
