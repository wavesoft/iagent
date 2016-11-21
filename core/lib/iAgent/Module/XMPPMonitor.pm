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
# Developed by George Lestaris 2012 at PH/SFT, CERN
# Contact: <george.lestaris[at]cern.ch>
#
package iAgent::Module::XMPPMonitor;
# Default packages
use warnings;
use strict;
# Use POE
use POE;
# iAgent Framework
use iAgent;
use iAgent::Kernel;
use iAgent::Log;
# Formating output
use Data::Dumper;

our $MANIFEST = {
	CLI => {		
		"xmpp/start_monitor" => {
			description => "Start XMPP Monitor",
			message => "xmpp_monitor_start"
		},
		"xmpp/stop_monitor" => {
			description => "Stop XMPP Monitor",
			message => "xmpp_monitor_stop"
		}
	}
};

=head1 NAME

XMPP Monitor

=head1 DESCRIPTION

This module when enabled is loging all the XMPP messages that were send or received from agent.

=cut

my $LOG_INFO = {
	from => "Sender",
	to => "Recipient",
	node => "PubSub Node",
	type => "Packet type",
	context => "Packet context",
	action => "Packet action"
};

##################################################
# Module constructor
sub new {
##################################################	
	my ( $class, $config ) = @_;
	
	# Prepare self
	my $self = {
		active => 0
	};
	
	# Check config for XMPPMonitorEnable
	if( defined $config->{XMPPMonitorEnable}
		and $config->{XMPPMonitorEnable} ) {
		$self->{active} = 1;
	}
	
	# Return the blessing...
	return bless( $self, $class );
}

##################################################
# Logs a package given it's type and the packet
##################################################
sub log_packet {
	my ( $self, $type, $packet ) = @_;
	
	if( not $self->{active} ) {
		return;
	}
	
	my $msg = "$type:\n";
	foreach( keys %$LOG_INFO ) {
		if( defined $packet->{$_} ) {
			$msg .= "\t$LOG_INFO->{$_}: $packet->{$_}\n";
		}
	}
	if( defined $packet->{parameters} ) {
		$msg .= "\tParameters: " . Dumper( $packet->{parameters} ) . "\n";
	}
	if( defined $packet->{data} ) {
		$msg .= "\tData: " . Dumper( $packet->{data} ) . "\n";
	}
	
	log_msg( $msg );
}

####################################################################################################
# MONITORING HOOKS
####################################################################################################

sub __comm_send {
	my ( $self, $packet ) = @_[ OBJECT, ARG0 ];
	$self->log_packet( "Sended packet", $packet );
	return RET_OK;
}

sub __comm_action {
	my ( $self, $packet ) = @_[ OBJECT, ARG0 ];
	$self->log_packet( "Received packet", $packet );
	return RET_OK;
}

sub __comm_packet {
	my ( $self, $packet ) = @_[ OBJECT, ARG0 ];
	$self->log_packet( "Received packet", $packet );
	return RET_OK;
}

sub __comm_pubsub_publish {
	my ( $self, $packet ) = @_[ OBJECT, ARG0 ];
	$self->log_packet( "PubSub sended packet", $packet );
	return RET_OK;
}

sub __comm_pubsub_event {
	my ( $self, $packet ) = @_[ OBJECT, ARG0 ];
	$self->log_packet( "PubSub received packet", $packet );
	return RET_OK;
}

####################################################################################################
# CLI HOOKS
####################################################################################################

##################################################
# Start XMPP Monitoring 
sub __xmpp_monitor_start {
##################################################
	my ( $self ) = @_;
	if( $self->{active} == 0 ) {
		$self->{active} = 1;
	} else {
		Dispatch( "cli_write", "XMPP Monitor is active!" );
	}
	return RET_OK;
}

##################################################
# Stop XMPP Monitoring
sub __xmpp_monitor_stop {
##################################################
	my ( $self ) = @_;
	if( $self->{active} == 1 ) {
		$self->{active} = 0;
	} else {
		Dispatch( "cli_write", "XMPP Monitor is inactive!" );
	}
	return RET_OK;
}

=head1 AUTHOR

Developed by George Lestaris <george.lestaris@cern.ch> 2012 at PH/SFT, CERN

=cut

1;