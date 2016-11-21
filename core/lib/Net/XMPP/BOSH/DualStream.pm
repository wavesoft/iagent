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

package Net::XMPP::BOSH::DualStream;

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
sub CONN_SECONDARY  { 6 };  # Initialization phase of the secondary socket
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

        # Last RequestID and SessionID
        rid => $ref->NewSID(),
        sid => undef,

        # The hash used to create a connection
        connect_config => { },
        pending_requests => 0
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
    $self->{BOSH}->{connect_config} = \%params;
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

    if ($self->{BOSH}->{state} == CONN_SECONDARY) { # We called Connect() to get a secondary socket
        # Do not perform any stream initialization, just fetch the socket
        my $sid=$self->{BOSH}->{sid};

        # Create an array for the two sockets
        $self->{SIDS}->{$sid}->{sockets} = [ 
            {
                sock => $self->{SIDS}->{$sid}->{sock},
                ready => 0,
                valid => 1
            },
            {
                sock => $self->{SIDS}->{newconnection}->{sock},
                ready => 0,
                valid => 1
            }
        ];
        $self->{SELECT}->add($self->{SIDS}->{newconnection}->{sock});
        $self->{SIDS}->{$sid}->{active_socket} = 0;

        # Update other vars
        $self->{SOCKETS}->{$self->{SIDS}->{newconnection}->{sock}} = $sid;
        delete $self->{SIDS}->{newconnection};

        # And we are ready
        $self->{BOSH}->{state} = CONN_READY;
        return 1;
    }

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
    return undef if (!defined $buf);

    # Check if it's an HTTP response, or just a partial packet
    if (!($buf =~ m/^HTTP\/1.1 /)) {
        return $buf;
        $self->debug(2, "Partial data ($buf)");
    } else {
        $self->debug(2, "HTTP Resonse ($buf)");
    }

    # Reduce requets
    $self->{BOSH}->{pending_requests}--;
    if ($self->{BOSH}->{pending_requests}<0) {
        $self->{BOSH}->{pending_requests}=0;
    }

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
    #my ($self, $sid, $string) = @_;
    my $self = shift;
    my $sid = shift;
    my $string = Encode::encode_utf8(join("",@_));
   
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

    # If we have multiple sockets and one of them is busy, send 
    # to the other
    my $socket=undef;
    if ((defined ($self->{SIDS}->{$sid}->{sockets})) && ($self->{BOSH}->{state} == CONN_READY)) {
        $socket=1;
    }

    # Send buffer
    $self->{BOSH}->{pending_requests}++;

    ############# IMPORTED CODE ###############
    #my $self = shift;
    #my $sid = shift;
    $self->debug(1,"Send: (@_)");
    $self->debug(3,"Send: sid($sid)");
    $self->debug(3,"Send: status($self->{SIDS}->{$sid}->{status})");
    
    $self->{SIDS}->{$sid}->{keepalive} = time;

    return if ($self->{SIDS}->{$sid}->{status} == -1);

    if (!defined($self->{SIDS}->{$sid}->{sock}))
    {
        $self->debug(3,"Send: socket not defined");
        $self->{SIDS}->{$sid}->{status} = -1;
        $self->SetErrorCode($sid,"Socket not defined.");
        return;
    }
    else
    {
        $self->debug(3,"Send: socket($self->{SIDS}->{$sid}->{sock})");
    }

    $self->{SIDS}->{$sid}->{sock}->flush();

    if ($self->{SIDS}->{$sid}->{select}->can_write(0))
    {
        $self->debug(3,"Send: can_write");
        
        $self->{SENDSTRING} = $buffer;

        $self->{SENDWRITTEN} = 0;
        $self->{SENDOFFSET} = 0;
        $self->{SENDLENGTH} = length($self->{SENDSTRING});
        while ($self->{SENDLENGTH})
        {
            if (!defined $socket) {
                $self->{SENDWRITTEN} = $self->{SIDS}->{$sid}->{sock}->syswrite($self->{SENDSTRING},$self->{SENDLENGTH},$self->{SENDOFFSET});
            } else {
                $self->{SENDWRITTEN} = $self->{SIDS}->{$sid}->{sockets}->[$socket]->{sock}->syswrite($self->{SENDSTRING},$self->{SENDLENGTH},$self->{SENDOFFSET});
            }

            if (!defined($self->{SENDWRITTEN}))
            {
                $self->debug(4,"Send: SENDWRITTEN(undef)");
                $self->debug(4,"Send: Ok... what happened?  Did we lose the connection?");
                $self->{SIDS}->{$sid}->{status} = -1;
                $self->SetErrorCode($sid,"Socket died for an unknown reason.");
                return;
            }
            
            $self->debug(4,"Send: SENDWRITTEN($self->{SENDWRITTEN})");

            $self->{SENDLENGTH} -= $self->{SENDWRITTEN};
            $self->{SENDOFFSET} += $self->{SENDWRITTEN};
        }
    }
    else
    {
        $self->debug(3,"Send: can't write...");
    }

    return if($self->{SIDS}->{$sid}->{select}->has_exception(0));

    $self->debug(3,"Send: no exceptions");

    $self->{SIDS}->{$sid}->{keepalive} = time;

    $self->MarkActivity($sid);

    return 1;
    
    #return $self->SUPER::Send($sid, $buffer);
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


################################################################
# Override StreamHeader
#---------------------------------------------------------------
# In order
#
sub SASLClientSuccess {
################################################################
    my $self = shift;
    my ($sid, $node) = @_;
    my $ans = $self->SUPER::SASLClientSuccess(@_);
    
    # We had a successful SASL Authentication. From this point
    # we can start our second socket 
    $self->{BOSH}->{sid} = $sid;    
    $self->{BOSH}->{state} = CONN_SECONDARY;
    $self->SUPER::Connect(%{$self->{BOSH}->{connect_config}});

    # Return whatever SASLClientSuccess returned
    return $ans;   
}
####################################################################################
#+----------------------------------------------------------------------------------
#| 
#|                              IMPORTED FUNCTIONS
#|
#+----------------------------------------------------------------------------------
####################################################################################

##############################################################################
#
# Process - checks for data on the socket and returns a status code depending
#           on if there was data or not.  If a timeout is not defined in the
#           call then the timeout defined in Connect() is used.  If a timeout
#           of 0 is used then the call blocks until it gets some data,
#           otherwise it returns after the timeout period.
#
##############################################################################
sub Process
{
    my $self = shift;
    my $timeout = shift;
    $timeout = "" unless defined($timeout);

    $self->debug(4,"Process: timeout($timeout)");
    #---------------------------------------------------------------------------
    # We need to keep track of what's going on in the function and tell the
    # outside world about it so let's return something useful.  We track this
    # information based on sid:
    #    -1    connection closed and error
    #     0    connection open but no data received.
    #     1    connection open and data received.
    #   array  connection open and the data that has been collected
    #          over time (No CallBack specified)
    #---------------------------------------------------------------------------
    my %status;
    foreach my $sid (keys(%{$self->{SIDS}}))
    {
        next if ($sid eq "default");
        $self->debug(5,"Process: initialize sid($sid) status to 0");
        $status{$sid} = 0;
    }

    #---------------------------------------------------------------------------
    # Either block until there is data and we have parsed it all, or wait a
    # certain period of time and then return control to the user.
    #---------------------------------------------------------------------------
    my $block = 1;
    my $timeEnd = ($timeout eq "") ? "" : time + $timeout;
    while($block == 1)
    {
        $self->debug(4,"Process: let's wait for data");

        my $now = time;
        my $wait = (($timeEnd eq "") || ($timeEnd - $now > 10)) ? 10 :
                    $timeEnd - $now;

        foreach my $connection ($self->{SELECT}->can_read($wait))
        {
            $self->debug(4,"Process: connection($connection)");
            $self->debug(4,"Process: sid($self->{SOCKETS}->{$connection})");
            $self->debug(4,"Process: connection_status($self->{SIDS}->{$self->{SOCKETS}->{$connection}}->{status})");

            next unless (($self->{SIDS}->{$self->{SOCKETS}->{$connection}}->{status} == 1) ||
                         exists($self->{SIDS}->{$self->{SOCKETS}->{$connection}}->{activitytimeout}));

            my $processit = 1;
            if (exists($self->{SIDS}->{server}))
            {
                foreach my $serverid (@{$self->{SIDS}->{server}})
                {
                    if (exists($self->{SIDS}->{$serverid}->{sock}) &&
                        ($connection == $self->{SIDS}->{$serverid}->{sock}))
                    {
                        my $sid = $self->ConnectionAccept($serverid);
                        $status{$sid} = 0;
                        $processit = 0;
                        last;
                    }
                }
            }
            if ($processit == 1)
            {
                my $sid = $self->{SOCKETS}->{$connection};
                $self->debug(4,"Process: there's something to read");
                $self->debug(4,"Process: connection($connection) sid($sid)");
                my $buff;
                $self->debug(4,"Process: read");
                $status{$sid} = 1;
                $self->{SIDS}->{$sid}->{status} = -1
                    if (!defined($buff = $self->Read($sid)));
                $buff = "" unless defined($buff);
                $self->debug(4,"Process: connection_status($self->{SIDS}->{$sid}->{status})");
                $status{$sid} = -1 unless($self->{SIDS}->{$sid}->{status} == 1);
                $self->debug(4,"Process: parse($buff)");
                $status{$sid} = -1 unless($self->ParseStream($sid,$buff) == 1);
            }
            $block = 0;
        }

        if ($timeout ne "")
        {
            if (time >= $timeEnd)
            {
                $self->debug(4,"Process: Everyone out of the pool! Time to stop blocking.");
                $block = 0;
            }
        }

        $self->debug(4,"Process: timeout($timeout)");

        if (exists($self->{CB}->{update}))
        {
            $self->debug(4,"Process: Calling user defined update function");
            &{$self->{CB}->{update}}();
        }

        $block = 1 if $self->{SELECT}->can_read(0);

        #---------------------------------------------------------------------
        # Check for connections that need to be kept alive
        #---------------------------------------------------------------------
        $self->debug(4,"Process: check for keepalives");
        foreach my $sid (keys(%{$self->{SIDS}}))
        {
            next if ($sid eq "default");
            next if ($sid =~ /^server/);
            next if ($status{$sid} == -1);
            if ((time - $self->{SIDS}->{$sid}->{keepalive}) > 10)
            {
                $self->IgnoreActivity($sid,1);
                $self->{SIDS}->{$sid}->{status} = -1
                    if !defined($self->Send($sid," "));
                $status{$sid} = -1 unless($self->{SIDS}->{$sid}->{status} == 1);
                if ($status{$sid} == -1)
                {
                    $self->debug(2,"Process: Keep-Alive failed.  What the hell happened?!?!");
                    $self->debug(2,"Process: connection_status($self->{SIDS}->{$sid}->{status})");
                }
                $self->IgnoreActivity($sid,0);
            }
        }
        #---------------------------------------------------------------------
        # Check for connections that have timed out.
        #---------------------------------------------------------------------
        $self->debug(4,"Process: check for timeouts");
        foreach my $sid (keys(%{$self->{SIDS}}))
        {
            next if ($sid eq "default");
            next if ($sid =~ /^server/);

            if (exists($self->{SIDS}->{$sid}->{activitytimeout}))
            {
                $self->debug(4,"Process: sid($sid) time(",time,") timeout($self->{SIDS}->{$sid}->{activitytimeout})");
            }
            else
            {
                $self->debug(4,"Process: sid($sid) time(",time,") timeout(undef)");
            }
            
            $self->Respond($sid)
                if (exists($self->{SIDS}->{$sid}->{activitytimeout}) &&
                    defined($self->GetRoot($sid)));
            $self->Disconnect($sid)
                if (exists($self->{SIDS}->{$sid}->{activitytimeout}) &&
                    ((time - $self->{SIDS}->{$sid}->{activitytimeout}) > 10) &&
                     ($self->{SIDS}->{$sid}->{status} != 1));
        }

        #---------------------------------------------------------------------
        # If any of the connections have status == -1 then return so that the
        # user can handle it.
        #---------------------------------------------------------------------
        foreach my $sid (keys(%status))
        {
            if ($status{$sid} == -1)
            {
                $self->debug(4,"Process: sid($sid) is broken... let's tell someone and watch it hit the fan... =)");
                $block = 0;
            }
        }

        $self->debug(2,"Process: block($block)");
    }

    #---------------------------------------------------------------------------
    # If the Select has an error then shut this party down.
    #---------------------------------------------------------------------------
    foreach my $connection ($self->{SELECT}->has_exception(0))
    {
        $self->debug(4,"Process: has_exception sid($self->{SOCKETS}->{$connection})");
        $status{$self->{SOCKETS}->{$connection}} = -1;
    }

    #---------------------------------------------------------------------------
    # If there are data structures that have not been collected return
    # those, otherwise return the status which indicates if nodes were read or
    # not.
    #---------------------------------------------------------------------------
    foreach my $sid (keys(%status))
    {
        $status{$sid} = $self->{SIDS}->{$sid}->{nodes}
            if (($status{$sid} == 1) &&
                ($#{$self->{SIDS}->{$sid}->{nodes}} > -1));
    }

    return %status;
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
    if ($rid>9007199254740991) { $rid=$self->NewSID() }; # Max RID (From RFC)
    $self->{BOSH}->{rid}=$rid;
    return $rid;
}

1;
