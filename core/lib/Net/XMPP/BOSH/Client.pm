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

package Net::XMPP::BOSH::Client;

=head1 NAME

Net::XMPP::BOSH::Client - BOSH XMPP Client Module

=head1 SYNOPSIS

Drop-in replacement for Net::XMPP::Client that provices BOSH connectivity.


=head1 DESCRIPTION

Net::XMPP::BOSH::Client is an extension to Net::XMPP::Client that provides
a BOSH connection layer for the Extensible Messaging and Presence Protocol (XMPP).
  
This module overwrites the XML::Stream object inherited from the Connection
with the Net::XMPP::BOSH::Stream that utilizes the BOSH wrapper.
  
The usage of this module is excactly the same as Net::XMPP::Client. It only
has an additional parameter on the constructor.

=head1 USAGE

The only change is in the connect function, where you have additionally the bosh_url parameter:

    use Net::XMPP;
    use Net::XMPP::BOSH;

    $Con = new Net::XMPP::BOSH::Client();
    $Con->Connect(
            hostname => "jabber.server.org",
            username => "bob",
            password => "XXXX",
            resource => "Work",

            bosh_url => "http://bosh.server.org:5280/http-bind"
        );

=head1 AUTHOR

Ioannis Charalampidis

=head1 COPYRIGHT

This module is free software, you can redistribute it and/or modify it
under the LGPL.

=cut

use warnings;
use strict;
use Carp;
use Net::XMPP::BOSH::DualStream;
use Net::XMPP::Client;
use base qw( Net::XMPP::Client );

############################################################
# Replacement of Net::XMPP::Client->new
#
# This function just instances a normal Net::XMPP::Client,
# blesses it as an instance of Net::XMPP::BOSH::Client and
# replaces the I/O Stream with a compatible BOSH Stream.
#
sub new {
############################################################
    my $class = shift;
    my $self=new Net::XMPP::Client(@_);
    my $stream = new Net::BOSH::XMLStream();

    # Re-bless stream
    $self->{STREAM} = adopt Net::XMPP::BOSH::DualStream($self->{STREAM});

    # Return an instance of ourselves
    return bless $self, $class;
}


####################################################################################
#+----------------------------------------------------------------------------------
#| 
#|                            OVERRIDEN FUNCTIONS
#|
#+----------------------------------------------------------------------------------
####################################################################################


################################################################
# Override Connect
#---------------------------------------------------------------
# In order to change the connect parameters depending on the
# BOSH URL, and in order to start a secondary stream, used 
# by BOSH for real-time communication.
sub Connect {
################################################################
    my $self = shift;
    my %params = @_;

    # Process BOSH parameters
    if (defined $params{bosh_url}) {
        my $url = $params{bosh_url};
        if ($url =~ m/(\w+):\/\/([\w\.]+)(:\d+)?(\/?.*)/) {
            $self->{STREAM}->{BOSH}->{hostname} = $2;
            if (!$3) {
                $self->{STREAM}->{BOSH}->{port} = 80;
            } else {
                $self->{STREAM}->{BOSH}->{port} = substr($3,1);
            }
            $self->{STREAM}->{BOSH}->{path} = $4 unless (!$4);
            $self->{STREAM}->{BOSH}->{secure} = 0;
            if ($1 eq 'https') {
                $self->{STREAM}->{BOSH}->{secure}=1;
            } elsif ($1 ne 'http') {
                croak("Invalid protocol specified on BOSH URL ($1)!");
            }
        } else {
            croak("No valid BOSH URL specified ($url)!");
        }
    } else {
        croak("No BOSH URl Specified!");
    }

    # Connect
    return $self->SUPER::Connect(%params);
}

1;
