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
package iAgent::Module::Testing::TestController;
# Default packages
use warnings;
use strict;
# iAgent Framework
use iAgent;
use iAgent::Kernel;

sub new {
	my ( $class ) = @_;
	
	# Prepare self
	my $self = {
		blocks => []
	};
	
	return bless( $self, $class );
}

sub register_block {
	my ( $self, $block_instance, $block_class ) = @_;
	
	# Is inheriting TestBlock class?
	if( not UNIVERSAL::isa( $block_instance, "iAgent::Module::Testing::TestBlock" ) ) {
		return 0;
	} else {
		# Store it to blocks list
		push( @{$self->{blocks}}, { 
			ob => $block_instance,
			name => $block_class } );
		return 1;
	}
}

sub run {
	my ( $self, $params ) = @_;
	
	Dispatch( "cli_write", "Start testing..." );
	
	# Iterate through blocks
	foreach( @{$self->{blocks}} ) {
		Dispatch( "cli_write", "==========================================" );
		Dispatch( "cli_write", "About to start testing block: $_->{name}" );
		if( not $_->{ob}->run( $params ) ) {
			Dispatch( "cli_error", "Failed to run testing block: $_->{name}" );
		}
		Dispatch( "cli_write", "==========================================" );
	}
	
	Dispatch( "cli_write", "End of testing!" );
	
	return 1;
	
}

1;