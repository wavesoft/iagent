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

package iAgent::Utilities;

use strict;
use warnings;
require Exporter;
our @ISA        = qw(Exporter);
our @EXPORT     = qw(ParseCmdline);

sub ParseCmdline {
    my $cmdline = shift;

    # (Step 1) Parse input string into numeric parameters
    # by also grouping the string arguments
    my @args = split " ", $cmdline;

}

1;
