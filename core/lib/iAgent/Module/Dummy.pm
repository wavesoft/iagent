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

package iAgent::Module::Dummy;
use iAgent::Kernel;
use iAgent::Log;
use strict;
use warnings;
use POE;
use Data::Dumper;

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { };
    return bless $self, $class;
}

my $single = 1;
sub __comm_action {
    my ($self, $msg) = @_[ OBJECT, ARG0 ];
    my $FROM = $msg->{from};
    my $ACTION = $msg->{action};
    my $PARAMETERS = $msg->{parameters};
    my $DATA = $msg->{data};
    my $PERM = $msg->{permissions};

    log_info("Got action $ACTION from $FROM. Parameters: ".Dumper($PARAMETERS)." Data: $DATA");
    
    # Just flip src/dst and send back
    my $to = $msg->{to};
    $msg->{to} = $msg->{from};
    $msg->{from} = $to;
    $msg->{context} = "chat:command";
    
    # Reply with an archipel to the currently active IQ message
    Reply('comm_send', $msg);
    
    return 1;	
}

## Ps. Use default manifest, that's quite OK
1;