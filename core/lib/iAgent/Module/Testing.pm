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
package iAgent::Module::Testing;
# Default packages
use warnings;
use strict;
# Use POE
use POE;
# iAgent Framework
use iAgent;
use iAgent::Kernel;
use iAgent::Log;
# Schema validator
use iAgent::SchemaValidator;

our $MANIFEST = {
	CLI => {
		"testing/run" => {
			description => "Run testing procedure",
            message => "testing_cli_run",
            options => [ "id=s" ]
		}
	}
};

=head1 Module Configuration
	{
		...,
		TestRun => {
			<Run ID> => {
				ModulePath => <Tested module path>,
				TestController => <The controller that is used for testing the module>
				Params => { ... } # Parameters to pass to the controller	
			}
		},
		...
	}
=cut

# Configuration prototype
sub CONFIG_PROTO {
	return {
		FLAG_REQUIRED .":TestRun" => {
			FLAG_REQUIRED . FLAG_NOT_EMPTY . ":/.*/" => {
				FLAG_REQUIRED . FLAG_NOT_EMPTY . ":ModulePath" => T_SCALAR,
				FLAG_NOT_EMPTY . ":ModuleName" => T_SCALAR,
				FLAG_REQUIRED . FLAG_NOT_EMPTY . ":TestController" => T_SCALAR,
				Params => {}
			}
		}
	}
}

######################################################################
# Module constructor
sub new {
######################################################################	
	my ( $class, $config ) = @_;
	
	# Validate
	my $error_message = "";
	if( not validate( CONFIG_PROTO, $config, [FLAG_REQUIRED], \$error_message ) ) {
		if( $error_message ne "" ) {
			log_die( "TestRun elements are not well strucutred in configuration file: " . $error_message );
		} else {
			log_die( "TestRun elements are not well strucutred in configuration file!" );
		}
	}

	# Preapare object
	my $self = {
		controllers => {}
	};

	# Load test controller
	my $run;
	foreach( keys %{$config->{TestRun}} ) {
		$run = $config->{TestRun}->{$_};
		
		if( ! -d $run->{ModulePath} ) {
			# Module path does not exist...
			log_die( "$run->{ModulePath} does not exits!" );
		}
		
		# Set INC appropriately
		push( @INC, $run->{ModulePath} );
		
		# Load controller
		my $class_name = $run->{TestController};
		my $class_path = $class_name;
		$class_path =~ s/::/\//g;
		$class_path .= ".pm";
		require( $class_path );
		
		# Instantiate
		my $controller = new $class_name();
		if( defined $controller ) {
			$self->{controllers}->{$_} = {
				ob => $controller,
				module => $run->{ModuleName},
				params => $run->{Params}
			};
		}
	}
	
	# Return the blessing...
	return bless( $self, $class );
}

######################################################################
# Event handler called when iAgent is "ready"
sub __testing_cli_run {
######################################################################
	my ( $self, $command ) = @_[ OBJECT, ARG0 ];
	
	# Is test id specified?
	if( not defined $command->{options}->{id}
		or $command->{options}->{id} eq "" ) {
		Dispatch( "cli_error", "Please specify test id!" );
		return RET_ERROR;		
	}
	
	# Get the id
	my $id = $command->{options}->{id};
	
	# Find the test controller
	if( not defined $self->{controllers}->{$id} ) {
		Dispatch( "cli_error", "Controller for id $id not found!" );
		return RET_ERROR;
	}
	my $controller = $self->{controllers}->{$id};
	
	# Load module
	if( defined $controller->{module} ) {
		iAgent::loadModule( $controller->{module} );
	}
	
	# Run controller
	$controller->{ob}->run( $controller->{params} );
	
	return RET_COMPLETED;
}

