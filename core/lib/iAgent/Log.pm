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

iAgent::Log - The core logging module for iAgnet

=head1 DESCRIPTION

This module provides extended logging functionality to the iAgent system. It supports 5 levels of logging:

=head1 LOG LEVELS

=head2 Level 0 - Debug

Debug, really detailed messages. This log level also includes some extra debug information about the caller.

=head2 Level 1 - Log messages

Not-so important messages, usually used for more verbose information.

=head2 Level 2 - Information messages

That's the common message level for the really basic messages, like 'starting', 'quitting' etc.

=head2 Level 3 - Warnings

This level is used for warnings.

=head2 Level 4 - Errors

This level is used for non-fatal errors.

=head2 Level 5 - Critical Errors

This level is used for fatal, non-recoverable errors that usually stops the execution of the program.

=head1 FUNCTIONS

=cut

package iAgent::Log;
use strict;
use warnings;
use Term::ANSIColor;
use Data::Dumper;
use POSIX qw/strftime/;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT  = qw(log_err log_error log_warn log_warning log_info log_inform log_msg log_debug log_die log_rip EOL);

# Set to 1 to completely skip debug messages
sub DISABLE_DEBUG { 0 };

###############################################################
# Minimum verbosity levels:
#
# 0 - Debug
# 1 - Message
# 2 - Info
# 3 - Warning
# 4 - Error
#
###############################################################

# Default configuration options
my $config = {
   file => "iagent.log",
   verbosity => 1, # Default verbosity
   file_verbosity => 100,

   filter_display => undef,
   filter_file => undef,

   # If message not in filter tree, still display it if warning, error or die
   not_in_filter_tree_verbosity => 3
};

# Newline separator
our $EOL = "\n";
sub EOL { $EOL };

###############################################################
# Change display filter
#
sub filter {
###############################################################
    my ($filter) = @_;

    # No arguments? Return filter
    if (scalar(@_) == 0) {
        my @k=keys(%{$config->{filter_display}});
        return \@k;
    }

    # Reset filter?
    if (!defined $filter) {
        $config->{filter_display} = undef;
        return;
    }

    # Check if given array ref
    $filter=\@_ if (ref($filter) ne 'ARRAY');

    # Convert filter array to hash
    my %accept; @accept{@$filter} = @$filter;
    $config->{filter_display} = \%accept;
}

###############################################################
# Change display filter
#
sub filterLog {
###############################################################
    my $filter = shift;

    # Reset filter?
    if (!defined $filter) {
        $config->{filter_log} = undef;
        return;
    }

    # Check if given array ref
    $filter=\@_ if (ref($filter) ne 'ARRAY');

    # Convert filter array to hash
    my %accept; @accept{@$filter} = @$filter;
    $config->{filter_log} = \%accept;
}

###############################################################
# Change display verbosity
#
sub verbosity {
###############################################################
    my $verbosity = shift;
    if (defined $verbosity) {
        $config->{verbosity} = $verbosity;
    }
    return $config->{verbosity};
}

###############################################################
# Change logging verbosity
#
sub logVerbosity {
###############################################################
    my $verbosity = shift;
    if (defined $verbosity) {
        $config->{file_verbosity} = $verbosity;
    }
    return $config->{file_verbosity};
}

###############################################################
# Initialize Logging Object
#
sub init {
###############################################################
    my (%p_config) = @_;
    (defined $p_config{Verbosity})     and $config->{verbosity} = $p_config{Verbosity};
    (defined $p_config{LogFile})       and $config->{file} = $p_config{LogFile};
    (defined $p_config{LogVerbosity})  and $config->{file_verbosity} = $p_config{LogVerbosity};
    (defined $p_config{LogFilter})     and filter($p_config{LogFilter});
    
    # Select new line mode
    $EOL = "\n";
    if (defined($p_config{LoadModule})) {
        # If we are using CLI, the logged messages must be in \r\n not in \n
        # new line format.
    	foreach (@{$p_config{LoadModule}}) {
    	    if ($_ eq 'iAgent::Module::CLI') {
    	        $EOL = "\r\n";
    	        last;
    	    }
	    }
    }
}

###############################################################
# Check if the specified message can be displied
sub can_display {
###############################################################
    my ($source, $level) = @_;

    # Check verbosity
    return 0 if ($config->{verbosity} > $level);

    # Check filter tree
    if( defined $config->{filter_display} ) {
        # Is it in filter tree?
        my @source_parts = split( "::", $source );
        my $s = "";
        foreach( @source_parts ) {
            $s .= "::" . $_;
            $s =~ s/^::(.*)/$1/;
            return 1 if defined $config->{filter_display}->{$s};
        }

        # Not in filter tree,
        return ( $config->{not_in_filter_tree_verbosity} <= $level );
    } else {
        # It's OK
        return 1;
    }
}

###############################################################
# Check if the specified message can be saved to log
sub can_log {
###############################################################
    my ($source, $level) = @_;

    # Check verbosity
    return 0 if ($config->{file_verbosity} > $level);

    # Check filter
    return 0 if (defined($config->{filter_file}) && !defined($config->{filter_file}->{$source}));

    # It's OK
    return 1;
}

###############################################################
sub ilog {
###############################################################
    my ($message, $level) = @_;
    (defined($level)) or $level = 1;

    # Detect caller
    my $from = caller(1);
    
    # Convert new-lines
    $message =~ s/\n/$EOL/g if ($EOL ne "\n");
    
    # Display message
    if (can_display($from, $level)) {
        print STDERR "[".strftime('%D %T',localtime)."][$$][";
        if ($level == 0) {
            print STDERR color "white";
            print STDERR "DBG,$from";
            print STDERR color 'reset';
            print STDERR "] ";
            print STDERR color "white";
            print STDERR $message;
            print STDERR color 'reset';
        } elsif ($level == 1) {
            print STDERR color "blue";
            print STDERR "MSG,$from";
            print STDERR color 'reset';
            print STDERR "] ";
            print STDERR $message;
        } elsif ($level == 2) {
            print STDERR color "green";
            print STDERR "INF,$from";
            print STDERR color 'reset';
            print STDERR "] ";
            print STDERR $message;
        } elsif ($level == 3) {
            print STDERR color "yellow";
            print STDERR "WRN,$from";
            print STDERR color 'yellow';
            print STDERR color 'reset';
            print STDERR "] ";
            print STDERR color 'yellow';
            print STDERR $message;
            print STDERR color 'reset';
        } elsif ($level == 4) {
            print STDERR color "red";
            print STDERR "ERR,$from";
            print STDERR color 'reset';
            print STDERR "] ";
            print STDERR color 'red';
            print STDERR $message;
            print STDERR color 'reset';
        } elsif ($level == 5) {
            print STDERR color "bold red";
            print STDERR "ERR,$from";
            print STDERR color 'reset';
            print STDERR "] ";
            print STDERR color 'bold red';
            print STDERR $message;
            print STDERR color 'reset';
        }
        print STDERR "\r\n";
    }
    
    # Log message to file
    if (can_log($from, $level)) {
        if (!open LOGFILE, ">>".$config->{file}) {
            $config->{file_verbosity} = 255;
            log_error("Unable to open logfile $config->{file} for writing!");
            return;
        }
        print LOGFILE "[".strftime('%D %T',localtime)."][$$][";
        if ($level == 0) {
        	print LOGFILE "DBG,$from"
        } elsif ($level == 1) {
            print LOGFILE "MSG,$from"
        } elsif ($level == 2) {
            print LOGFILE "INF,$from"
        } elsif ($level == 3) {
            print LOGFILE "WRN,$from"
        } elsif ($level == 4) {
            print LOGFILE "ERR,$from"
        } elsif ($level == 5) {
            print LOGFILE "!!!,$from"
        } else {
            	print LOGFILE "???,$from"
        }
        print LOGFILE "] $message\n";
        close LOGFILE;
    }   
    
}

###############################################################
###############################################################

=head2 log_debug

Log a debug (Level 0) message

=cut

sub log_debug {
    return 0 if DISABLE_DEBUG;
    my ($message) = @_;
    ilog($message, 0);
	return 0;
}

=head2 log_msg

Log an message (Level 1) message.

=cut

sub log_msg {
    my ($message) = @_;
    ilog($message, 1);
	return 0;
}

=head2 log_info, log_inform

Log an information (Level 2) message.

=cut

sub log_inform {
    my ($message) = @_;
    ilog($message, 2);
	return 0;
}

sub log_info {
    my ($message) = @_;
    ilog($message, 2);
	return 0;
}

=head2 log_warn, log_warning

Log an warning (Level 3) message.

=cut

sub log_warn {
    my ($message) = @_;
    ilog($message, 3);
	return 1;
}

sub log_warning {
    my ($message) = @_;
    ilog($message, 3);
	return 1;
}

=head2 log_err, log_error

Log an error (Level 4) message.

=cut

sub log_err {
    my ($message) = @_;
    ilog($message, 4);
	return 1;
}

sub log_error {
    my ($message) = @_;
    ilog($message, 4);
	return 1;
}

=head2 log_die

Log an fatal (Level 5) message. And exit with error.

=cut

sub log_die {
    my ($message) = @_;
    ilog($message, 5);
    exit 1; 
}


# Just for fun, delete me!
# (Used by kernel Crash)
sub log_rip {
    log_error('  ______   _____    _____   ');
    log_error(' |_____/     |     |_____|  ');
    log_error(' |    \_ . __|__ . |       .');
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
