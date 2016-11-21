#!/usr/bin/perl -w -I ../core/lib
#
# iAgent Bootstrap
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

use strict;
use warnings;
use iAgent;
use iAgent::Log;

# Select an ETC folder
my $etc = '';
if (scalar @ARGV != 0) { # Use ETC folder provided by the user
    $etc = shift(@ARGV);
    
} elsif (-d '/etc/cernvm-agent') { # Check global ETC
    $etc='/etc/cernvm-agent';
    
} elsif (-d '/usr/etc/cernvm-agent') { # Check user ETC
    $etc='/usr/etc/cernvm-agent';

} elsif (-d '/usr/local/etc/cernvm-agent') { # Check local ETC
    $etc='/usr/local/etc/cernvm-agent';

} elsif (-d "$ENV{HOME}/.iagent/etc") { # Check for user's iagent & etc
    $etc = "$ENV{HOME}/.iagent/etc";
    push @INC, "$ENV{HOME}/.iagent/lib" if (-d "$ENV{HOME}/.iagent/lib");
    
} else {
    print("Unable to locate the configuration folder! Please specify it as the first command-line parameter!\n");
    exit 1;
}

# Ensure we have at least iagent.conf there
log_die("Unable to find iagent.conf in '$etc'!") unless (-f "$etc/iagent.conf");

# Start iAgent
exit(iAgent::start( etc => $etc, LoadModule => [
        'iAgent::Module::CLI',
        'Module::WorkflowCLI',
        'Module::WorkflowServer'
    ], Verbosity => 0, LogFilter => ['Module::WorkflowAgent','Module::WorkflowActions']));
