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
package iAgent::Module::Reporter;
# Default packages
use warnings;
use strict;
# POE Library
use POE;
# iAgent
use iAgent;
use iAgent::Kernel;
use iAgent::Log;
# Dumper
use Data::Dumper;

our $MANIFEST = {};

######################################################################
# Module constructor
sub new {
######################################################################
	my ( $class, $config ) = @_;
	
	# Prepare self
	my $self = {};
	
	return bless( $self, $class );
}

######################################################################
# Setup hook - fired when all modules are loaded
# TODO: Implement
sub __setup {
######################################################################
	my $self = $_[OBJECT];
	
	return RET_OK;
}

######################################################################
# Fired when an error is reported
# TODO: Implement
sub __report_error {
######################################################################
	my ( $self, $msg ) = @_[ OBJECT, ARG0 ];
	
	# Prepare message
	my $log_message = $msg;
	
	# Get data
	my @args = @_[ ARG1..ARG9 ];
	foreach( @args ) {
		if( defined $_ ) {
			$log_message .= "\n====================\n";
			$log_message .= Dumper( $_ );
		}
	}
	
	# Log the message
	log_error( $log_message );
	
	return RET_OK;
}

######################################################################
# Fired when assertion is reported. It will check if assertion is true
# and if not it will log an error message
# TODO: Implement
sub __report_assertion {
######################################################################
	my ( $self, $assertion, $file, $line ) = @_[ OBJECT, ARG0..ARG2 ];
	
	if( not defined $assertion
		or not $assertion ) {
		# Assertion failed, should log that...
		my $resource_id = "";
		$resource_id = $file
			if defined $file and $file ne "";
		$resource_id .= ":$line"
			if defined $line and $line ne "";

		# Log appropriate message
		if( $resource_id ne "" ) {
			log_error( "Assertion in $resource_id FAILED!" );
		} else {
			log_error( "Assertion FAILED!" )
		}
		return RET_ERROR;
	} else {
		return RET_OK;
	}
}

1;