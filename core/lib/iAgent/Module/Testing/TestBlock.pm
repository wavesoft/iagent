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
package iAgent::Module::Testing::TestBlock;
# Default packages
use warnings;
use strict;
# iAgent Framework
use iAgent;
use iAgent::Kernel;

sub new {
	my ( $class, $controller ) = @_;
	
	# Prepare self
	my $self = {
		cases => [],
		controller => $controller
	};
	
	return bless( $self, $class );
}

sub register_case {
	my ( $self, $case_code, $name ) = @_;
	
	# Store it to cases list
	push( @{$self->{cases}}, { 
		"sub" => $case_code,
		name => $name } );
	
	return 1;
}

sub run {
	my ( $self, $params ) = @_;
	
	# Iterate through cases
	my $result;
	foreach( @{$self->{cases}} ) {
		$result = $_->{"sub"}->( $self, $params );
		if( $result ) {
			Dispatch( "cli_write", "$_->{name} ... SUCCESS!" );
		} else {
			Dispatch( "cli_error", "$_->{name} ... ERROR!" );
		}
	}
	
	return 1;
	
}

1;