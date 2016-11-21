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

# Core definitions
package Module::ReleaseManager;
use strict;
use warnings;

# Basic inclusions
use iAgent::Log;
use POE;

# The ReleaseManager Manifest
our $MANIFEST = {

    XMPP => {

        "iagent:releases" => {
            "get" => {
                PERMISSIONS => [ 'read' ],
                "list" => "MSG_list"
            },
            "set" => {
                PERMISSIONS => [ 'publisher' ],
                "push" => "MSG_push"
            }
        }

    }

};

############################################
# New instance
sub new {
############################################
    my ($class, $config) = @_;
    
    # Prepare my instance 
    my $self = {
        
    };
    $self = bless $self, $class;
        
    # Return instance
    return $self;
}

