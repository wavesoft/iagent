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

package Module::Blinker;

=head1 NAME

Module::Blinker - A tiny module that operates my little blinker peripheral

=head1 DESCRIPTION

The blinker is a USB-Driven light+alarm peripheral. This module triggers the green signal if
a workflow action was completed or red+alarm if it fails.

Just an example of how fast you can write a module :)

=cut

use strict;
use warnings;
use POE;
use iAgent::Log;
use iAgent::Kernel;
use Data::Dumper;
use Device::SerialPort;

our $MANIFEST = {
    
    # Add binding to CLI
    CLI => {
        "blinker/send" => { 
            message => "cli_send",
            description => "Send cmdline to the blinker"
        }
    },
    
    WORKFLOW => {
        "blinker:blink" => {
            ActionHandler => 'wf_blink',
            Threaded => 0,
            
        }
    }
    
};

sub new { 
    my $class = shift;
    my $config = shift;
    my $self = { 
        WAS_OK => 1,
        DEVICE => "/dev/tty.usbmodem12341",
        SILENT => 0
    };

    $self->{DEVICE}=$config->{BlinkerDev} if defined($config->{BlinkerDev});
    $self->{SILENT}=$config->{BlinkerSilent} if defined($config->{BlinkerSilent});
    
    return bless $self, $class;
}


sub __ready {
    my $self = $_[OBJECT];
    return RET_PASSTHRU;
}

sub send {
    my ($self, $what) = @_;
    if (-c $self->{DEVICE}) {
        my $PortObj = Device::SerialPort->new($self->{DEVICE}) || return;
        $PortObj->baudrate(9600);
        $PortObj->write($what);
        $PortObj->write_done(0);
        undef $PortObj;
    }
}

sub __cli_send {
    my ($self, $cmd) = @_[ OBJECT, ARG0 ];
    log_error("Sending $cmd->{cmdline} to $self->{DEVICE}");
    $self->send($cmd->{cmdline});
    return RET_COMPLETED;
}

sub __wf_blink {
    my ($self, $context) = @_[ OBJECT, ARG0 ];
    if ($self->{SILENT}) {
        $self->send('iR') if ($context->{blink} eq 'ok');
        $self->send('iW') if ($context->{blink} eq 'warning');
        $self->send('iE') if ($context->{blink} eq 'error');
        $self->send('io') if ($context->{blink} eq 'panic');
    } else {
        $self->send('iRb') if ($context->{blink} eq 'ok');
        $self->send('iWB') if ($context->{blink} eq 'warning');
        $self->send('iED') if ($context->{blink} eq 'error');
        $self->send('iZ')  if ($context->{blink} eq 'panic');
    }
    return 0;
}


1;
