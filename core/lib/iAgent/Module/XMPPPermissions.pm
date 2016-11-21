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

iAgent::Module::XMPPPermissions - Permisssions database on XMPP

=head1 DESCRIPTION

This module provides a permissions discovery mechanism for new users.

In contrast to LDAPAuth, this module fetches/stores permissions stored in a pubsub
storage key in the server. This enables permissions/authentication mechanism while
still in XMPP environment.

=cut

# Core definitions
package iAgent::Module::XMPPPermissions;

use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;
use Data::Dumper;

our $MANIFEST = {
    oncrash => 'die',
    priority => 1
};

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { 
        PERMISSIONS => { }
    };
    return bless $self, $class;
}


sub lookup_permissions_for {
    my ($self, $user) = @_;
    
}