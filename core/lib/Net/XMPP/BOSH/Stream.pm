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

package Net::XMPP::BOSH::Stream;

=head1 NAME

Net::XMPP::BOSH::Stream - BOSH XML Stream

=head1 SYNOPSIS

Net::XMPP::BOSH::Stream is an extension to XML::Stream that wraps the standard
XMPP XML messages to BOSH.

For more usage details see Net::XMPP::Client

=head1 DESCRIPTION

This module re-blesses the XML::Stream object inherited from the Connection
with the Net::XMPP::BOSH::Stream that utilizes the BOSH protocol.

It is not intended to be used directly. It's a private package used by
the Net::XMPP::BOSH::Client. 

=head1 AUTHOR

Ioannis Charalampidis

=head1 COPYRIGHT

This module is free software, you can redistribute it and/or modify it
under the LGPL.

=cut

use warnings;
use strict;
use Switch;
use Carp;
use XML::Stream;
use base qw( XML::Stream );
use Data::Dumper;

##################################################################
# Constants of connection state
#-----------------------------------------------------------------
sub CONN_DOWN       { 0 };  # Disconnected
sub CONN_LISTEN     { 1 };  # Listening for connection
sub CONN_INIT       { 2 };  # Initialization phase (About to send/receive session initialization sequence)
sub CONN_AUTH       { 3 };  # Authentication phase (About to send/receive <auth />)
sub CONN_RESET      { 4 };  # Session reset phase (About to send/receive <body xmpp:reset=true />)
sub CONN_READY      { 5 };  # Connection is ready for I/O
sub CONN_ERROR      { -1 }; # An error occured

##################################################################
# Constants of send modes 
#-----------------------------------------------------------------
sub SEND_NORMAL     { 0 };  # Regular send mode (Wrap send request under BOSH + HTTP)
sub SEND_ATTRIB     { 1 };  # Sending attributes (Wrap send request inside <body ... /> + HTTP)
sub SEND_BODY       { 2 };  # Sending custom <body /> element (Still under HTTP wrap)
sub SEND_RAW        { 3 };  # Passing through data to XML::Stream as-is

##################################################################
# Adopts the specified instance
# This function re-blesses the (already initialized) instance of
# XML::Stream
sub adopt {
##################################################################
    my $class = shift;
    my $ref = shift;

    # Ensure integrity
    croak("Unable to adopt a ".ref($ref)." instance! It must be an XML::Stream!") 
        if (!UNIVERSAL::isa($ref, "XML::Stream"));        

    # Append BOSH configuration
    $ref->{BOSH} = {

        # Basic, BOSH parameters
        path =>  "/http-bind",
        hostname => "localhost",
        port => 5280,
        timeout => 60,
        secure => 0,
        route_host => "localhost",
        route_port => 5222,

        # Connection state
        state => CONN_DOWN,

        # Special send mode flag (used internally)
        send_mode => SEND_NORMAL,
        pending_response => 0,

        # Last RequestID and SessionID
        rid => $ref->NewSID(),
        sid => undef,

        # ReponseReceived callback
        cb_responsereceived => sub { }
    };

    ######## ENABLE DEBUG ###########
    $ref->{DEBUGFILE} = new FileHandle(">&STDERR");
    $ref->{DEBUGFILE}->autoflush(1);
    $ref->{DEBUG} = 1;
    $ref->{DEBUGLEVEL} = 1;
    ######## ENABLE DEBUG ###########

    # Re-bless the specified reference as this class
    return bless $ref, $class;
}


####################################################################################
#+----------------------------------------------------------------------------------
#| 
#|                            EXPOSED NEW FUNCTIONS
#|
#+----------------------------------------------------------------------------------
####################################################################################

################################################################
# Override Connect
#---------------------------------------------------------------
# Provide an interface to register custom callbacks for BOSH
sub SetBOSHCallBacks {
################################################################
    my $self = shift;
    my %callbacks = @_;
    if (defined $callbacks{ResponseReceived}) {
        $self->{BOSH}->{cb_responsereceived} = $callbacks{ResponseReceived};
    }
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
# Used to initialize both BOSH and XML::Stream with the appropriate
# parameters
sub Connect {
################################################################
    my $self = shift;
    my %params = @_;

    # Fetch parameters from Net::Stream to BOSH
    $self->{BOSH}->{timeout} = $params{timeout} if (defined $params{timeout});
    $self->{BOSH}->{route_host} = $params{hostname};
    if (defined $params{port}) {
        $self->{BOSH}->{route_port} = $params{port};
    } else {
        $self->{BOSH}->{route_port} = "5222";
    }

    $self->debug(1, "Initialized BOSH with hostname=" . $self->{BOSH}->{hostname} .
                    " port=" . $self->{BOSH}->{port} .
                    " path=" . $self->{BOSH}->{path} .
                    " secure=" . $self->{BOSH}->{secure});

    # Override some parameters of XML::Stream
    $params{connectiontype} = 'http';
    $params{hostname} = $self->{BOSH}->{hostname};
    $params{port} = $self->{BOSH}->{port};
    $params{tls}=1 if ($self->{BOSH}->{secure});

    # Mark connection as INIT
    $self->{BOSH}->{state} = CONN_INIT;

    # Forward to original function
    return $self->SUPER::Connect(%params);
}

################################################################
# Override OpenStream
#---------------------------------------------------------------
# This function initializes a BOSH/XMPP Session. If a SID is
# specified, we consider it as 'reseting' an existing stream.
sub OpenStream {
################################################################
    my $self = shift;
    my ($currsid, $timeout) = @_;
    $self->debug(1, "OpenStream");

    if ($currsid eq 'newconnection') {
        $self->{BOSH}->{state} = CONN_INIT; # SID 'newconnection' is called by Connect
        $self->debug(1, "Setting state to CONN_INIT");
    } else {
        $self->{BOSH}->{state} = CONN_RESET; # OpenStream is called again by Client::Auth() with last session's SID
        $self->{BOSH}->{sid} = $currsid;
        $self->debug(1, "Setting state to CONN_RESET");
        
        # (Keep the SID because after reset server isn't going to reply the SID again, but
        # XML::Stream expects an id= attribute on the stream)

    }

    return $self->SUPER::OpenStream($currsid, $timeout);
}


################################################################
# Override Read
#---------------------------------------------------------------
# This function reads a BOSH response
# and converts it to a jabber:client 
# XMP Stream. 
#
# It lets Net::XML to do the processing
#
sub Read {
################################################################
    my $self = shift;

    # Read response
    my $buf = $self->SUPER::Read(@_);

    # Check if it's an HTTP response, or just a partial packet
    #if (!($buf =~ m/^HTTP\/1.1 /)) {
    #    return $buf;
    #    $self->debug(2, "Partial data ($buf)");
    #} else {
        $self->debug(2, "HTTP Resonse ($buf)");
    #}

    # Get header information and split them from body
    my @parts = split("\r\n\r\n", $buf, 2);
    my @hdr = split("\r\n", $parts[0]);
    my @response = split(" ",shift(@hdr));
    my $code = $response[1];
    my %headers = map{ split(": ",$_) } @hdr;
    my $body = $parts[1];

    # Error? Exit
    return "" if ($code != 200);

    # Cut body and fetch attributes
    $body =~ s/<\/body>$//;
    $body =~ s/<body (.*?)>//;
    my %attrib = map { split /=['"]/,substr($_,0,-1) } split /\s+/,$1;

    # Extract SID from attributes
    my $sid = undef;
    $sid = $attrib{sid} if defined $attrib{sid};

    # If we got response, reset pending_response
    $self->{BOSH}->{pending_response} = 0;
    if (defined $self->{BOSH}->{cb_responsereceived}) {
        &{$self->{BOSH}->{cb_responsereceived}}( );
    };

    # Check in which phase are we currently in
    if (($self->{BOSH}->{state} == CONN_INIT) || ($self->{BOSH}->{state} == CONN_RESET)) {
    
        # We are initializing a stream, so send the appropriate stream
        # initialization respond that regular XMPP stream will understand
        my $stream = "<?xml version='1.0'?><stream:stream xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'";
        for my $k (keys %attrib) {
            switch ($k) {
                case 'xmpp:version'     { $stream.=" version='".$attrib{$k}."'" }
                case 'xml:lang'         { $stream.=" xml:lang='".$attrib{$k}."'" }
                case 'from'             { $stream.=" from='".$attrib{$k}."'" }
            }
        }

        # If we are in RESET phase, we don't have any SID response from the server.
        # But since se need an 'id' response, we fetch the last SID used.
        $sid=$self->{BOSH}->{sid} if ($self->{BOSH}->{state} == CONN_RESET);

        # If we still have no SID, something's wrong
        if (!defined $sid) {
            croak("Something's wrong! We didn't got a SID from server while expecting it!");
        }

        # Append ID (SessionID in BOSH case) and close stream
        $stream .= " id='$sid'>";

        # Upon receiving these messages, we consider the connection READY
        # Subsequent requests might change this value again...
        $self->{BOSH}->{state} = CONN_READY;

        # Return the stream, plus any excess body (ex. stream features)
        $self->debug(2, "Translated stream: ($stream$body)");
        return $stream.$body;
        
    } else {

        # Otherwise, what we get is what we must send back
        $self->debug(2, "Translated stream: ($body)");
        return $body;
        
    }
}


################################################################
# Override Send
#---------------------------------------------------------------
# Depending on the current operation
# this function converts the jabber:client
# stream to a bosh-compatible HTTP request.
# 
sub Send {
################################################################
    my ($self, $sid, $string) = @_;

    # Prepare Buffer
    my $buffer='';
    
    # Check if we have custom send flags
    if ($self->{BOSH}->{send_mode} != SEND_NORMAL) {
        if ($self->{BOSH}->{send_mode} == SEND_ATTRIB) {
            # Send only attributes
            my $rid = $self->NewRID();
            $buffer  = "<body rid='$rid'";
            $buffer .= " sid='$sid'" unless (!$sid || ($sid eq 'newconnection'));
            $buffer .= "$string xmlns='http://jabber.org/protocol/httpbind' xmlns:xmpp='urn:xmpp:xbosh' />";
            $buffer = $self->_http_wrap($buffer);
        } elsif ($self->{BOSH}->{send_mode} == SEND_BODY) {
            # Send custom body
            $buffer = $self->_http_wrap($string);
        } elsif ($self->{BOSH}->{send_mode} == SEND_RAW) {
            # Send RAW data
            $buffer = $string;
        }

        # Reset send mode
        $self->{BOSH}->{send_mode} = SEND_NORMAL;
        
    } else {
        # Send regular BOSH-Encapsulated data
        my $rid = $self->NewRID();
        $buffer = "<body rid='$rid' sid='$sid' xmlns='http://jabber.org/protocol/httpbind'";
        $string =~ s/\s+$//;
        if ($string eq '') {
            $buffer .= " />";
        } else {
            $buffer .= ">$string</body>";
        }
        $buffer = $self->_http_wrap($buffer);
    }

    # Se sent an HTTP request. Pending response
    $self->{BOSH}->{pending_response} = 1;

    # Send buffer
    return $self->SUPER::Send($sid, $buffer);

}

################################################################
# Override StreamHeader
#---------------------------------------------------------------
# Prepares the header that initializes the stream
#
sub StreamHeader {
################################################################
    my $self = shift;
    my (%args) = @_;
    my $stream='';
    $self->debug(1, "Fetching StreamHeader");
    
    if ($self->{BOSH}->{state} == CONN_INIT) {
        ## Stream Initialization Request ##

        # We are about to send only attributes
        $self->{BOSH}->{send_mode} = SEND_ATTRIB;

        # Build requests (Namespaces, RID and SID are already there)
        $stream .=  " xmpp:version='1.0'";
        $stream .=  " xml:lang='$args{xmllang}'" if exists($args{xmllang});
        $stream .=  " hold='1'";
        $stream .=  " ver='1.6'";
        $stream .=  " content='text/xml; charset=utf-8'";
        $stream .=  " secure='true'" if ($self->{BOSH}->{secure}!=0);
        $stream .=  " wait='".$self->{BOSH}->{timeout}."'";
        $stream .=  " to='$args{to}'" if exists($args{to});
        

    } elsif ($self->{BOSH}->{state} == CONN_RESET) {
        ## Stream Reset Request ##

        # We are about to send only attributes
        $self->{BOSH}->{send_mode} = SEND_ATTRIB;

        # Build requests (Namespaces, RID and SID are already there)
        $stream .=  " xmpp:version='1.0'";
        $stream .=  " xml:lang='$args{xmllang}'" if exists($args{xmllang});
        $stream .=  " xmpp:restart='true'";
        $stream .=  " to='$args{to}'" if exists($args{to});

    }

    # Return the newly created stream
    $self->debug(1, "Prepared StreamHeader($stream)");
    return $stream;
    
}

####################################################################################
#+----------------------------------------------------------------------------------
#| 
#|                            UTILITY FUNCTIONS
#|
#+----------------------------------------------------------------------------------
####################################################################################

################################################################
# Wrap the specified payload under an proper HTTP request
sub _http_wrap {
################################################################
    my ($self, $content) = @_;

    # Update port string
    my $port = "";
    $port = ":".$self->{BOSH}->{port} if defined($self->{BOSH}->{port});

    # Build HTTP Request
    my $buf = "POST ".$self->{BOSH}->{path}." HTTP/1.1\r\n";
    $buf .=   "Host: ".$self->{BOSH}->{hostname}. $port ."\r\n";
    $buf .=   "User-Agent: PerlBOSH/0.1 (Perl; Net::XMPP::BOSH)\r\n";
    $buf .=   "Content-Type: application/xml\r\n";
    $buf .=   "Accept-Encoding: gzip, deflate\r\n";
    $buf .=   "Content-Length: ". length($content) ."\r\n";
    $buf .=   "Connection: keep-alive\r\n";
    $buf .=   "\r\n";
    $buf .=   $content;

    # Return the wrapped content
    return $buf;
}


################################################################
# Generate a new Request ID
sub NewRID {
################################################################
    my $self = shift;
    my $rid = $self->{BOSH}->{rid};
    $rid+=1;
    if ($rid>9007199254740991) { $rid=$self->NewSID() };
    $self->{BOSH}->{rid}=$rid;
    return $rid;
}

1;
