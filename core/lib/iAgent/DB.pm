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

iAgent::DB - iAgent Database API

=head1 DESCRIPTION

This perl module provides a common interface to access the iAgent database. In principal
every module can use the same file, but it is better to do so using this module because
it uses a single instance of the database driver.

This module provides also a set of shortcuts for commonly used SQL queries.

=head1 USAGE

You can either use the internal DBI Module using the DB constant:

 # Either this way
 use iAgent::DB;
 DB->do('SELECT * FROM users');
 my $st = DB->prepare('SELECT * FROM users WHERE name = ?');

=head2 METHODS

The following methods are exposed from the DB module:

=cut

package iAgent::DB;
use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;
use Data::Dumper;
use DBI;

require Exporter;
our @ISA        = qw(Exporter);
our @EXPORT     = qw(DB DBQ AddSlashes);
our $DRIVER     = undef;

# The name of the DB jet
my $DRV_NAME    = '';

# Translation table for query macros
my %MACROS = (
    
    'AUTOINCREMENT' => {
        'mysql' => 'AUTO_INCREMENT',
        'sqlite' => 'AUTOINCREMENT'
    }
    
);

###################################################
# Initialize the iAgent database driver
sub Initialize {
###################################################
    my ($dbsn, $username, $password) = @_;
    log_msg("Connecting to database $dbsn");
    
    # Create a driver
     eval {

         # Connect to the DB
         if( !defined $username ) {
         	$DRIVER = DBI->connect($dbsn,{ AutoCommit => 1, RaiseError => 1 });
         } elsif( !defined $password ) {
         	$DRIVER = DBI->connect($dbsn, $username, { AutoCommit => 1, RaiseError => 1 });
         } else {
         	$DRIVER = DBI->connect($dbsn, $username, $password, { AutoCommit => 1, RaiseError => 1 });
         }

         # Check for failure
         if (!$DRIVER) {
             log_die("Error while trying to connecto to DSN $dbsn! $DBI::errstr");
             return RET_ERROR;
         }

    };
    if ($@) {
     	 log_die("Error trying to connect to DSN $dbsn!: ".$@);
         return RET_ERROR;
    }
    
    # Fetch the driver string
    my @parts = split(':', $dbsn);
    $DRV_NAME = lc($parts[1]);
    
    # Done!
    log_msg("Database connected and ready");
    return RET_OK;
    
}

###################################################
# Return an instance to the DBI instance
sub DB {
###################################################
    return $DRIVER;
}

###################################################
# Replace query macros to match the current adapter
# specifications

=head2 DBQ STRING

Replace some parameters that are different per implementation. The macros are replaced
based on the following translation table:

 +--------------------+------------+---------------------+
 |        Macro       |   Driver   |     Replacement     |
 +--------------------+------------+---------------------+
 | [[AUTOINCREMENT]]  |    mysql   |  AUTO_INCREMENT     |
 |                    |   sqlite   |  AUTOINCREMENT      |
 +--------------------+------------+---------------------+

=cut

sub DBQ {
###################################################
    my $query = shift;
    
    # Replace all the macros
    foreach my $tpl (keys %MACROS) {
        my $entry = $MACROS{$tpl} or next;
        my $match = $entry->{$DRV_NAME} or next;
        $query =~ s/\[\[$tpl\]\]/$match/gi;
    }
    
    # Replace all the leftover junk
    while ($query =~ m/\[\[(\w+)\]\]/i) {
        log_warn("Unknown query macro $1 for driver $DRV_NAME in query $query");
        $query =~ s/\[\[$1\]\]//;
    }
    return $query;
}

###################################################
# Add slashes to quotes
sub AddSlashes {
###################################################
	my $text = shift;
	# Make sure to do the backslash first!
	$text =~ s/\\/\\\\/g;
	$text =~ s/'/\\'/g;
	$text =~ s/"/\\"/g;
	$text =~ s/\\0/\\\\0/g;
	return $text;
}

1;