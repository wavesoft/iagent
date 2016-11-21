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
package iAgent::SchemaValidator;
# Default packages
use warnings;
use strict;
# Array utilities
use List::Util qw( first );

# Exporter
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( validate 
	T_SCALAR T_CLASS
	FLAG_REQUIRED FLAG_NOT_EMPTY FLAG_NUMERIC );

# Types
sub T_SCALAR { return "SCALAR" };
sub T_CLASS { return "CLASS" };

# Flags
sub FLAG_REQUIRED { return "R" };
sub FLAG_NOT_EMPTY { return "N" };
sub FLAG_NUMERIC { return "n" }; #TODO: Use


=head1 NAME

Schema validator

=head1 DESCRIPTION

Define and validate Perl struct schemas

=head1 METHODS

=head2 validate HASHREF, MIXEF, ARRAY, STRINGREF

This method tests the target data with given schema.

=head3 Input params

=over

=item * schema: The hashref that defined the schmea to use

=item * target: The data struture to validate

=item * flags: Array of flags, by default empty

=item * error_message: Reference to string where validator will place error message in case of failure

=back

=head3 Output

True or false as the result of validation (1 or 0)

=cut
sub validate {
	my ( $schema, $target, $flags, $error_message ) = @_;
	# Set default flags
	$flags = []
		if not defined $flags;
		
	# Something ain't right...
	if( not defined $schema ) {
		return 0;
	}
	
	# Change validation given the type of schema
	if( UNIVERSAL::isa( $schema, "HASH" ) ) {
		return _validate_hash( $schema, $target, $flags, $error_message );
	} elsif( UNIVERSAL::isa( $schema, "ARRAY" ) ) {
		return _validate_array( $schema, $target, $flags, $error_message );
	} elsif( $schema eq T_SCALAR ) {
		return _validate_scalar( $schema, $target, $flags, $error_message );
	} elsif( $schema eq T_CLASS ) {
		return _validate_instance( $schema, $target, $flags, $error_message );
	} else {
		# Invalid schema type...
		return 0;
	}
}

####################################################################################################
# VALIDATORS
####################################################################################################

######################################################################
# Validates scalar values
sub _validate_scalar {
######################################################################
	my ( $schema, $target, $flags, $error_message ) = @_;
	# Set default flags
	$flags = []
		if not defined $flags;		
	# Get flags hash
	my %flags_hash = map { $_ => 1 } @$flags;
		
	# Something ain't right...
	if( not defined $schema ) {
		return 0;
	}
	
	# Target defined?
	if( not defined $target ) {
 		if( defined $flags_hash{FLAG_REQUIRED()} ) {
 			_append_to_error( $error_message, "Required scalar value not set" ); 
			return 0;
		} else {
			return 1;
		}
	}
	
	# Empty?
	if( $target eq "" ) {
		if( defined $flags_hash{FLAG_NOT_EMPTY()} ) {
			_append_to_error( $error_message, "Scalar value is empty" );
			return 0;
		} else {
			return 1;
		}
	}
	
	# Check type
	if( ref( $target ) eq "SCALAR"
		or ref( \$target ) eq "SCALAR" ) {
		# Valid...
		return 1;		
	} else {
		_append_to_error( $error_message, "Scalar value is... not scalar" ); 
		return 0;
	}
}

######################################################################
# Validates class instances
sub _validate_instance {
######################################################################
	my ( $schema, $target, $flags, $error_message ) = @_;
	# Set default flags
	$flags = []
		if not defined $flags;
		
	# Something ain't right...
	if( not defined $schema ) {
		return 0;
	}
	
	# Target defined?
	if( not defined $target ) {
		if( first { $_ eq FLAG_REQUIRED() } @$flags ) {
			return 0;
		} else {
			return 1;
		}
	}
	
	# Valid...
	return 1;
}

######################################################################
# Validates hashes
sub _validate_hash {
######################################################################
	my ( $schema, $target, $flags, $error_message ) = @_;
	# Set default flags
	$flags = []
		if not defined $flags;
		
	# Something ain't right...
	if( not defined $schema ) {
		return 0;
	}
	
	# Target defined?
	if( not defined $target ) {
		if( first { $_ eq FLAG_REQUIRED() } @$flags ) {
			_append_to_error( $error_message, "Required hash not defined" );
			return 0;
		} else {
			return 1;
		}
	}
	
	# Type validation
	if( not UNIVERSAL::isa( $target, "HASH" ) ) {
		_append_to_error( $error_message, "Required hash is... not a hash" );
		return 0;
	}
	
	# Validate all keys
	my $inner_schema;
	my $inner_flags;
	my $key;
	foreach( keys %{$schema} ) {
		$inner_schema = $schema->{$_};				
		$inner_flags = _get_flags( $_ );
		$key = _get_key( $_ );
				
		if( $key =~ /^\/(.*)\/$/ ) {
			my $regex = $1;
			
			# Key is a regular expression
			my $keys_found = 0;		
			foreach( keys %{$target} ) {
				if( $_ =~ /$regex/ ) {
					if( not validate( $inner_schema, $target->{$_}, $inner_flags, $error_message ) ) {
						_append_to_error( $error_message, "Failed to validate element $_" ); 
						return 0;
					}			
					$keys_found++;		
				}
			}
			
			# Were keys found?
			if( $keys_found == 0 
				and first { $_ eq FLAG_REQUIRED() } @$inner_flags ) {
				return 0;
			}
		} else {								
			# Key is specific
			if( not validate( $inner_schema, $target->{$key}, $inner_flags, $error_message ) ) {
				_append_to_error( $error_message, "Failed to validate element $key" );
				return 0;
			}
		}
	}
	
	# Valid...
	return 1;
}

######################################################################
# Validates arrays
sub _validate_array {
######################################################################
	my ( $schema, $target, $flags, $error_message ) = @_;
	# Set default flags
	$flags = []
		if not defined $flags;
	# Get flags hash
	my %flags_hash = map { $_ => 1 } @$flags;
		
	# Something ain't right...
	if( not defined $schema ) {
		return 0;
	}
	
	# Target defined?
	if( not defined $target ) {
		if( defined $flags_hash{FLAG_REQUIRED()} ) {
			_append_to_error( $error_message, "Required array is not found" );
			return 0;
		} else {
			return 1;
		}
	}
	
	# Type validation
	if( not UNIVERSAL::isa( $target, "ARRAY" ) ) {
		_append_to_error( $error_message, "Required array is... not an array" );
		return 0;
	}
	
	# Empty validation
	if( scalar @{$target} == 0 ) {
		if( defined $flags_hash{FLAG_NOT_EMPTY()} ) {
			_append_to_error( $error_message, "Array is empty" );
			return 0;
		} else {
			return 1;
		}
	}
	
	# Get inner schema
	my $inner_schema = shift @{$schema};
	my $inner_flags = $schema;
	
	# Validate all
	my $i = 0;
	foreach( @{$target} ) {
		if( not validate( $inner_schema, $_, $inner_flags ) ) {
			_append_to_error( $error_message, "Array's element $i is invalid" );
			return 0;
		}
		$i++;
	}
	
	# Valid...
	return 1;
}

####################################################################################################
# HELPERS
####################################################################################################

######################################################################
# Given a schema key, it parses it and get's an array of setted flags
sub _get_flags {
######################################################################
	my ( $key ) = @_;	
	if( $key =~ /^([A-Za-z]+):.*$/ ) {
		my @flags = split( '', $1 );
		return \@flags;	
	} else {
		return [];
	}
}

######################################################################
# Given a schema key, it returns the key without the flags
sub _get_key {
######################################################################
	my ( $key ) = @_;	
	if( $key =~ /^([A-Za-z]+):(.*)$/ ) {
		return $2;	
	} else {
		return $key;
	}
}

######################################################################
# Sets error message to reference passed
sub _append_to_error {
######################################################################
	my ( $error_message, $msg ) = @_;
	if( ref $error_message eq "SCALAR" ) {
		if( ${error_message} ne "" ) {
			${$error_message} = $msg . ". " . ${$error_message};
		} else {
			${$error_message} = $msg;
		}
	}
}

=head1 SCHEMA FORMAT

TODO

=cut

1;