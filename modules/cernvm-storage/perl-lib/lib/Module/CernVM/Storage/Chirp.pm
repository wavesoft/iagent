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

Module::CernVM::Storage::Chirp - CHIRP submodule for the CernVM Storage Agent

=head1 DESCRIPTION

This submodule provides access to a CHIRP server. When the module starts, a chirp
server is started in the background. Every time a user requests a storage slot, it
creates a new folder for him and generates a ticket for the session.

Upon workflow completion, the module cleans both folders and tickets that
were used in the workflow.

=cut

# Core definitions
package Module::CernVM::Storage::Chirp;
use strict;
use warnings;
use Data::UUID;
use MIME::Base64;
use Data::Dumper;
use iAgent::Log;
use POE::Wheel::Run;

sub NAME        { "CHIRP" };
sub DESCRIPTION { "A CHIRP server that allocates tokens to users upon request" };

############################################
# Create new instance
sub new {
############################################
    my ($class, $config) = @_; 
    
    # Initialize instance
    my $self = {
        Leases => { },
        Root => $config->{Root},
        User => $config->{User},
        Hostname => $config->{Hostname},
        
        ChirpBin => ($config->{Config}->{ChirpBin} or '/usr/bin/chirp'),
        ChirpServerBin => ($config->{Config}->{ChirpServerBin} or '/usr/bin/chirp_server'),
        
		ChirpServerProc => undef
    };
    $self = bless $self, $class;
    
    # Return instance
    return $self;
}

##===========================================================================================================================##
##                                               STORAGE API FUNCTIONS                                                       ##
##===========================================================================================================================##

############################################
# Return 1 if the provider is available
sub is_available {
############################################
    my ($self) = @_;
    return 1; # Always :D
}

############################################
# Return an array with all the active leases
sub get_leases {
############################################
    my ($self) = @_;
    my @leases = values %{$self->{Leases}};
    return \@leases;
}

############################################
# Return the space (in MB used)
sub get_used_mb {
############################################
    my ($self) = @_;
    use File::Find;           
    my $size = 0;             
    find(sub { $size += -s if -f $_ }, $self->{Root});
    return $size/1048576;
}

############################################
# Return the free MB left (possibly also calculate quota)
sub get_free_mb {
############################################
    my ($self) = @_;
    my $root = $self->{Root};
    my $free = `df -Pm $root | grep -v '^Filesystem' | awk 'NF=6{print \$4}NF==5{print \$3}{}'`;
    return $free;
}

############################################
# Allocate a new lease. This function returns
# an array with the following fields:
#
# (
#   UUID,       : A unique ID used to refer to this allocation
#   URI         : A URI that refers to the allocation server configuration
# )
#
sub allocate {
############################################
    my ($self, $requirements) = @_;
    my $uuid = Data::UUID->new()->create_str;
    
    # Check for non-volatile storage reqest
    my $volatile=1;
    $volatile = $requirements->{volatile} if (defined($requirements->{volatile}));
    
    # Prefix volatile storages
    $uuid .= '.tmp' if ($volatile);
    my $dir = '/'.$uuid;

    # Create directory
    system( $self->{ChirpBin}, 'localhost',
          'mkdir', $dir
        );

    # Grant a ticket to the specified user
    my $ticket_file="/tmp/$uuid.ticket";
    system( $self->{ChirpBin}, 'localhost',
          'ticket_create',
          '-bits',      '1024',
          '-duration',  '3600',
          '-output',    $ticket_file,
          "/$uuid",     'rwl',
        );
    
    # Fetch the ticket contents
    open KEY, "<$ticket_file"; my @lines = <KEY>; close KEY;
    my $ticket = join("",@lines);
    
    # Save lease
    $self->{Leases}->{$uuid} = {
        Dir => $dir,
        StorageDir => $uuid,
        Volatile => $volatile,
        Ticket => $ticket_file
    };
    
    # Return ID & URI
    return (
        $uuid,
        'chirp:' . $self->{Hostname} . '/' . $uuid . '?' .encode_base64($ticket,'')
    );
    
}

############################################
# Free a previous release 
sub free {
############################################
    my ($self, $uuid) = @_;
    my $entry = $self->{Leases}->{$uuid};
    return unless defined($entry);

    # Remove ticket
    if (-f $entry->{Ticket}) {
        
        # Delete ticket
        system( $self->{ChirpBin}, 'localhost',
              'ticket_delete',
              $entry->{Ticket}
            );
    
        # Remove ticket file
        unlink($entry->{Ticket});

        # Delete folder if the lease is volatile
        if ($entry->{Volatile}) {
            system( $self->{ChirpBin}, 'localhost',
                  'rm', $entry->{StorageDir}
                );
        }
    
    }
        
    # Clean directory
    # TODO: Do this only after global switch option
    
    # Remove lease
    delete $self->{Leases}->{$uuid};

    # Return ok
    return 1;
    
}

############################################
# Purge all the non-active storage 
sub purge {
############################################
    my $self = shift;

    # Remove all volatile storages
    system( $self->{ChirpBin}, 'localhost',
          'rm', '*.tmp'
        );

    # Return ok
    return 1;
}

############################################
# Start the provider
sub start {
############################################
    my ($self) = @_;
    
    # Start CHIRP server
    return 0 if (!$self->start_chirp_server);
    
    # Return ok
    return 1;
    
}

############################################
# Stop the provider
sub stop {
############################################
    my ($self) = @_;

    # Stop the CHIRP server
    $self->stop_chirp_server;

    # Return ok
    return 1;
    
}

##===========================================================================================================================##
##                                                  HELPER FUNCTIONS                                                         ##
##===========================================================================================================================##

############################################
# Return the process table - UNIX ONLY
sub get_proc_table {  
############################################
   open(PSEF_PIPE,"ps -ef|");  
   my $procs = { }; my $skip=1;
   while (<PSEF_PIPE>) {  
      chomp;  
      my @psefField      = split(/\s+/, $_, 9);

      # Skip first line (headers)
      if ($skip) { $skip=0; next };

      # Store process
      $procs->{$psefField[1]} = {
          UID => $psefField[0],
          PID => $psefField[1],
          PPID => $psefField[2],
          C => $psefField[3],
          STIME => $psefField[4],
          TTY => $psefField[5],
          TIME => $psefField[6],
          CMD => $psefField[7],
          PARM => $psefField[8]
      };
   }  
   close(PSEF_PIPE);  
   return $procs;
} 

############################################
# Start a CHIRP server
sub start_chirp_server {
############################################
    my ($self) = @_;
    
    # Check if CHIRP server is already running
    my $proc = get_proc_table;    
    foreach (values %$proc) {
        if ($_->{CMD} =~ m/chirp_server$/) {
			iAgent::Kernel::Dispatch( "cli_error", "Chirp Server already runs!" );
            return 0;
        }
    }
    
    # Chirp is not running so start
	$self->{ChirpServerProc} = new POE::Wheel::Run( 
		Program => [ 
			$self->{ChirpServerBin},
			'-u', '-',					# Do not send updates
			#'-i', $self->{User},		# Use safe user
			'-r', $self->{Root}			# Use that folder as root
		],
		StdinEvent => "",
		StdoutEvent => "",
		StderrEvent => ""
	);  	   

    # Return OK
    return 1;

}

############################################
# Stop the observing CHIRP server
sub stop_chirp_server {
############################################
    my ($self) = @_;
    
    # Kill CHIRP server
	if( defined $self->{ChirpServerProc} ) {	
		my $ret = $self->{ChirpServerProc}->kill();		
		if( $ret ) {
			# Wait for process to be reaped
			waitpid( $self->{ChirpServerProc}->PID, 0 );
			
			log_info( "Process " . $self->{ChirpServerProc}->PID() . " was killed." );	
		} else {
			log_error( "Failed to kill process " . $self->{ChirpServerProc}->PID() );
		}
	} else {
		log_error( "Problem finding the chirp_server process!" );
	}
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;