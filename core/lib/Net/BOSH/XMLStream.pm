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

package Net::BOSH::XMLStream;
use strict;
use warnings;
use Encode;

use POE qw( Wheel );
use POE::Component::Client::HTTP;
use base qw(POE::Wheel);

use HTTP::Request;
use HTML::Entities;
use XML::Stream;
use XML::Stream::Parser;
use Authen::SASL;
use MIME::Base64;

use Data::Dumper;
use iAgent::Log;

my %XMLNS;

##############################################################################
# Define the namespaces in an easy/constant manner.
#-----------------------------------------------------------------------------
# 0.9
#-----------------------------------------------------------------------------
$XMLNS{'stream'}        = "http://etherx.jabber.org/streams";

#-----------------------------------------------------------------------------
# 1.0
#-----------------------------------------------------------------------------
$XMLNS{'xmppstreams'}   = "urn:ietf:params:xml:ns:xmpp-streams";
$XMLNS{'xmpp-bind'}     = "urn:ietf:params:xml:ns:xmpp-bind";
$XMLNS{'xmpp-sasl'}     = "urn:ietf:params:xml:ns:xmpp-sasl";
$XMLNS{'xmpp-session'}  = "urn:ietf:params:xml:ns:xmpp-session";
$XMLNS{'xmpp-tls'}      = "urn:ietf:params:xml:ns:xmpp-tls";
##############################################################################

sub ERR_UNAVAILABLE     { -1 };
sub ERR_SASL            { -2 };

#####################################################################################################################################
# +-------------------------------------------------------------------------------------------------------------------------------+ #
# |                                               POE::WHEEL INITIALIZATION                                                       | #
# +-------------------------------------------------------------------------------------------------------------------------------+ #
#####################################################################################################################################

sub new {
	my $class = shift;
	my %config = @_;
	my $id = POE::Wheel::allocate_wheel_id();
    
	# Initialize and bless hash
	my $self = {

        URL => '',
        TLS => 1,
		
		CB => { },          # Callbacks
		IDCOUNT => 0,       # The last ID for NewSID
		WAITING => { },     # Flags all the requests that are explicitly waiting for response
		
		SIDS => { },        # The different started streams
		LAST_UID => 0,      # Unique indexing ID to map requests to responses
		
		PENDING => [ ],     # Pending callbacks to be called by Process when needed
		
		# Unique aliases in order to have multiple instances in the 
		# same session without collisions.
		POE_UA => "$class($id) -> UserAgent",
		SELF_LOOP => "$class($id) -> loop",
		SELF_RESPONSE => "$class($id) -> response"
		
	};
	$self = bless $self, $class;
	
	# Create the XML Parser
	$self->{PARSER} = new XML::Stream::Parser(
        style=> 'node',
        Handlers=>{
            startElement=>sub{ $self->_handle_start(@_) },
            endElement=>sub{ $self->_handle_end(@_) },
            characters=>sub{ $self->_handle_cdata(@_) }
        }
    );
	
    # Instantiate the HTTP Client
    POE::Component::Client::HTTP->spawn(
        Agent           => 'iAgentBOSH/0.10',
        Alias           => $self->{POE_UA},
        FollowRedirects => 2
      );
      	
	# Define callbacks
	{
		# We are using the same trick from POE::Wheel::ReadLine
		# in order to weaken the reference to self to avoid
		# circular reference.
		
	    my $weak_self = $self;
	    use Scalar::Util qw(weaken);
	    weaken $weak_self;

	    $poe_kernel->state(
	      $self->{SELF_LOOP},
	      sub { _loop($weak_self, @_[1..$#_]) }
	    );
	    $poe_kernel->state(
	      $self->{SELF_RESPONSE},
	      sub { _http_response($weak_self, @_[1..$#_]) }
	    );
	
	}
	
	# Start main loop
	$poe_kernel->delay($self->{SELF_LOOP} => 1);
	
	# Return instance
	return $self;
}

sub DESTROY {
	my $self = shift;
	
	# Shutdown HTTP agent
	$poe_kernel->post($self->{POE_UA}, 'shutdown');
	
	# Release wheel
	POE::Wheel::free_wheel_id($self->{WHEEL_ID});
	
}

sub ID {
	my $self = shift;
	return $self->{WHEEL_ID};
}

#####################################################################################################################################
# +-------------------------------------------------------------------------------------------------------------------------------+ #
# |                                                INTERNAL WHEEL CALLBACKS                                                       | #
# +-------------------------------------------------------------------------------------------------------------------------------+ #
#####################################################################################################################################

sub _http_response {
    my ($self, $request_packet, $response_packet) = @_[OBJECT, ARG0, ARG1];
    my $response_object = $response_packet->[0];
    my $body = $response_object->content;
    my $request = $request_packet->[0];
    
    # Fetch details we hacked into the request object
    my $sid = $request->{_sid};
    my $uid = $request->{_uid};
    
    # Parse XML to XML::Stream::Node
    log_warn("<<< ($uid, $sid) $body");
    my $xml = $self->ParseXML($body);
    if (!defined($xml)) {
        log_error("INVALID/UNPARSABLE XML: $body\n");
    } else {
        #log_warn("<<<< ($uid) ".$xml->GetXML);        
    }
    
    # If request response is required, update the content
    if (defined($self->{WAITING}->{$uid})) {
        #log_warn("<<<< ".$xml->GetXML);
        if (!defined $xml) { # Failed? Store -1 
            $self->{WAITING}->{$uid}=-1;
        } else {
            #log_warn("<<< ($uid) ".$xml->GetXML);
            $self->{WAITING}->{$uid}=$xml;
        }
        return;
    }
    
    # Trigger node callback if it's there
    #log_warn("<<< ".$xml->GetXML);
    if (defined($xml) && defined($self->{CB}->{node})) {
        my @kids = $xml->children();
        foreach (@kids) {
            #log_error("<<<< ".$_->GetXML);
            push(@{$self->{PENDING}}, { cb => 'node', sid => $sid, args => [$sid, $_ ] }) ;
        }
    }

    
}

# Infinite slow loop to keep wheel alive. When done with this, just DESTROY
sub _loop {
    my $self = $_[OBJECT];
	$poe_kernel->delay($self->{SELF_LOOP} => 1);
}

#####################################################################################################################################
# +-------------------------------------------------------------------------------------------------------------------------------+ #
# |                                                   HELPER FUNCTIONS                                                            | #
# +-------------------------------------------------------------------------------------------------------------------------------+ #
#####################################################################################################################################

################################################################
# Generate a new locally-unique ID
sub NewUID {
################################################################
    my $self = shift;
    return ++$self->{LAST_UID};
}

################################################################
# Generate a new Request ID
sub NewRID {
################################################################
    my $self = shift;
    my $sid = shift;
    my $rid = $self->{SIDS}->{$sid}->{rid};
    $rid+=1;
    if ($rid>9007199254740991) { $rid=$self->NewSID() };
    $self->{SIDS}->{$sid}->{rid}=$rid;
    return $rid;
}

################################################################
# Generate a new session ID
sub NewSID {
################################################################
    my $self = shift;
    return &{$self->{CB}->{sid}}() if (exists($self->{CB}->{sid}) && defined($self->{CB}->{sid}));
    return $$.time.$self->{IDCOUNT}++;
}

################################################################
# Send an HTTP Request and scheduled callback
sub SendRequest {
################################################################
    my ($self, $sid, $data, $uid) = @_;
    $uid=0 unless defined($uid);
    
    # Fetch config from this SID
    my $config = $self->{SIDS}->{$sid};
    return undef unless defined($config);
        
    # Build request object
    my $req = HTTP::Request->new( POST => $config->{URL} );
    if ($data) {
        $data =~ s/\s+/ /msg; # Compress junk spaces
        log_info("SENDING (SID=$sid): $data");
        $req->content(encode("iso-8859-1", $data)); # TODO: Check what happens with UTF-8
    }
    
    # Hack some details in the request object
    $req->{_sid} = $sid;
    $req->{_uid} = $uid;
    
    # Send the request and set callback
    $poe_kernel->post(
      $self->{POE_UA},          # posts to client component
      'request',                # posts to ua's 'request' state
      $self->{SELF_RESPONSE},   # which of our states will receive the response
      $req                      # an HTTP::Request object
    );
    
    # Return the request object
    return $req;
    
}

################################################################
# Wait for response without blocking the POE Kernel
sub WaitForResponse {
################################################################
    my $self = shift;
    my $uid = shift;
    my $timeout = shift;
    my $time = time;
    $timeout=0 unless defined($timeout);
    
    # Define waiting hash
    $self->{WAITING}->{$uid} = 0;
    
    # Run POE kernel while waiting for HTTP Response
    while (!$self->{WAITING}->{$uid}) { 
        $poe_kernel->run_one_timeslice();
        return undef if (($timeout>0) && (time - $time > $timeout));
    }
    
    # Got still scalar in the request? Then it's -1 wich means
    # the process failed
    if (ref($self->{WAITING}->{$uid}) eq '') {
        delete $self->{WAITING}->{$uid};
        return undef;
    }
    
    # Pop the response and return it
    my $obj = $self->{WAITING}->{$uid};
    delete $self->{WAITING}->{$uid};
    return $obj;
    
}

################################################################
# Send an HTTP request and wait for response
sub SendAndReceive {
################################################################
    my ($self, $sid, $data) = @_;
    my $uid = $self->NewUID();
    my $req = $self->SendRequest($sid, $data, $uid);
    return $self->WaitForResponse($uid);
}


#####################################################################################################################################
# +-------------------------------------------------------------------------------------------------------------------------------+ #
# |                                                  XML PARSING FUNCTIONS                                                        | #
# +-------------------------------------------------------------------------------------------------------------------------------+ #
#####################################################################################################################################
# The following block of code is copied from the XML::Stream::Node package from Ryan Eatmon. This script does not detect chunked
# responses. You must specify the entire XML object. 
# If someting fails it returns undef.
#####################################################################################################################################

# Static variables for the process (Its synchronous)
my @PARSING_NODE;
my $PARSING_FINAL;

################################################################
# Parse the specified block of XML into a XML::Stream::Node
# element
sub ParseXML {
################################################################
    my ($self, $buffer) = @_;
    
    # Reset nodes
    @PARSING_NODE = ( );
    $PARSING_FINAL = undef;
    
    # Start parser
    $self->{PARSER}->parse($buffer);
    
    # Return parsed data
    return $PARSING_FINAL;
}

sub _handle_start {
    my ($self, $sax, $tag, %att) = @_;
    my $sid = $sax->getSID();
    my $node = new XML::Stream::Node($tag);
    $node->put_attrib(%att);
    $PARSING_NODE[$#PARSING_NODE]->add_child($node) if ($#PARSING_NODE >= 0);
    push(@PARSING_NODE,$node);

}

sub _handle_cdata {
    my ($self, $sax, $cdata) = @_;
    my $sid = $sax->getSID();
    return if ($#PARSING_NODE == -1);
    $PARSING_NODE[$#PARSING_NODE]->add_cdata($cdata);
}

sub _handle_end {
    my ($self, $sax, $tag) = @_;
    my $CLOSED = pop @PARSING_NODE;
    if($#PARSING_NODE == -1) {
        push @PARSING_NODE, $CLOSED;
        $PARSING_FINAL = $PARSING_NODE[0];
    }
}

#####################################################################################################################################
# +-------------------------------------------------------------------------------------------------------------------------------+ #
# |                                             XML::STREAM SIMULATION FUNCTIONS                                                  | #
# +-------------------------------------------------------------------------------------------------------------------------------+ #
#####################################################################################################################################

sub PrepareConnect {
    my $self = shift;
    my %config = @_;
    
    $self->{ConnectConfig} = \%config;
    
}

sub Connect {
    my $self = shift;
    my %config = %{$self->{ConnectConfig}};
    
    # Populate config with default parameters
    $config{Server}='localhost' unless defined($config{Server});
    $config{Port}=5280 unless defined($config{Port});
    $config{Path}='/http-bind' unless defined($config{Path});
    $config{SSL}=0 unless defined($config{SSL});
    $config{Wait}=15 unless defined($config{Wait});
    
    # Generate some custom parameters
    $config{URL} = (($config{SSL})?'https':'http')."://$config{Server}:$config{Port}$config{Path}";
    $config{rid} = $self->NewSID();
    
    # Save stream config
    $self->{SIDS}->{newconnection} = \%config;
    
    # Open stream
    return $self->OpenStream('newconnection');
}

# OK
sub SetCallBacks {
    my $self = shift;
    while($#_ >= 0) {
        my $func = pop(@_);
        my $tag = pop(@_);
        if (!defined($func)) {
            log_debug("Removing $tag callback");
            delete $self->{CB}->{$tag};
        } else {
            #$self->debug(1,"SetCallBacks: tag($tag) func($func)");
            log_debug("Setting $tag callback");
            $self->{CB}->{$tag} = $func;
        }
    }
}

sub StartTLS {
    my $self = shift;
    my $sid = shift;
    my $timeout = shift;
    $timeout = 120 unless defined($timeout);
    $timeout = 120 if ($timeout eq "");
    
    print "STARTING TLS\n";
    
    return 0;
}

sub GetErrorCode {
    my $self = shift;
    my $sid = shift;
    $sid = "newconnection" unless defined($sid);
    return $self->{SIDS}->{$sid}->{ErrorCode};
}

sub Process {
    my $self = shift;
    my $timeout = shift;
    my %status;
    $timeout=0 unless defined($timeout);

    eval {

    # Call POE message loop for cases like WaitForID
    $poe_kernel->run_one_timeslice();

    # Call user-defined update function
    if (exists($self->{CB}->{update})) {
        &{$self->{CB}->{update}}();
    }
    
    # Dispatch pending callback triggers
    foreach (@{$self->{PENDING}}) {
        if (defined($self->{CB}->{$_->{cb}})) {
            #log_error("Sending callback to $_->{cb}");
            &{$self->{CB}->{$_->{cb}}}(@{$_->{args}});
        }
    }
    
    # Update status to OK
    foreach (keys %{$self->{SIDS}}) {
        $status{$_}=1;        
    }
    
    # Flush pending
    $self->{PENDING} = [ ];
    
    };
    if ($@) {
        log_error("ERROR!!! $@");
    }
    
    # The good thing with POE is that we don't have actual Process :)
    # Returns weird stuff only if something failed
    return %status;
    
}

sub Disconnect {
    my $self = shift;
    my $sid = shift;    
    return undef unless defined($self->{SIDS}->{$sid});
    
    # Just delete the session definition and we are done
    delete $self->{SIDS}->{$sid};
    return 1;
}

sub Send {
    my $self = shift;
    my $sid = shift;
    my $xml = join("", @_);
    return unless defined($self->{SIDS}->{$sid});
    
    # Generate RID
    my $rid = $self->NewRID($sid);
    
    # Wrap send command with the body BOSH element
    $self->SendRequest($sid, 
        "<body rid='$rid'
          sid='$sid'
          xmlns='http://jabber.org/protocol/httpbind'>" .
          $xml .
        "</body>");
    
}

sub IgnoreActivity {
    my $self = shift;
    my $sid = shift;
    my $ignoreActivity = shift;
    $ignoreActivity = 1 unless defined($ignoreActivity);
    
    # Yeah, whateva
}

sub SASLClient {
    my $self = shift;
    my $sid = shift;
    my $username = shift;
    my $password = shift;

    my $mechanisms = $self->GetStreamFeature($sid,"xmpp-sasl");
    return unless defined($mechanisms);
    
    # Here we assume that if 'to' is available, then a domain is being
    # specified that does not match the hostname of the jabber server
    # and that we should use that to form the bare JID for SASL auth.
    my $domain .=  $self->{SIDS}->{$sid}->{To}
        ? $self->{SIDS}->{$sid}->{To}
        : $self->{SIDS}->{$sid}->{Server};
    my $authname = $username . '@' . $domain;
    
    my $sasl = new Authen::SASL(mechanism=>join(" ",@$mechanisms),
                                callback=>{
                                           authname => $authname,
                                           user     => $username,
                                           pass     => $password
                                          }
                               );
    
    # Update SASL information of this session
    $self->{SIDS}->{$sid}->{sasl} = {
        client => $sasl->client_new('xmpp', $domain),
        username => $username, password => $password,
        authed => 0, done => 0
    };

    # Prepare first step
    my $first_step = $self->{SIDS}->{$sid}->{sasl}->{client}->client_start();
    log_warn("First step $first_step");
    my $first_step64 = MIME::Base64::encode_base64($first_step,"");

    # +-----------------------------------------+
    # | STEP 1 - Send authentication request    |
    # +-----------------------------------------+

    # Send first step of SASL authentication
    my $rid = $self->NewRID($sid);
    my $ans = $self->SendAndReceive($sid, 
        "<body rid='$rid'
               sid='$sid'
               xmlns='http://jabber.org/protocol/httpbind'>
            <auth xmlns='".$XMLNS{'xmpp-sasl'}."' mechanism='".$self->{SIDS}->{$sid}->{sasl}->{client}->mechanism()."'>".$first_step64."</auth>
        </body>");
    
    # +-----------------------------------------+
    # | STEP 2 - Process request/get challenge  |
    # +-----------------------------------------+

    while (1) {

        # Handle response
        return undef unless defined($ans);
        my @c = $ans->children();
        $ans = shift @c;
        if ($ans->get_tag eq 'failure') {
            $self->{SIDS}->{$sid}->{sasl}->{done} = 1;
            $self->{SIDS}->{$sid}->{sasl}->{authed} = 0;
            $self->{SIDS}->{$sid}->{ErrorCode} = ERR_SASL;
            $self->{SIDS}->{$sid}->{ErrorMessage} = "SASL Authentication: Failure while receiving auth response";
            return undef;
        } elsif ($ans->get_tag eq 'success') { # Completed for SIMPLE auth
            $self->{SIDS}->{$sid}->{sasl}->{done} = 1;
            $self->{SIDS}->{$sid}->{sasl}->{authed} = 1;
            return 1;
        } elsif ($ans->get_tag ne 'challenge') { # We need to contingue for CHALLENGE
            $self->{SIDS}->{$sid}->{sasl}->{done} = 1;
            $self->{SIDS}->{$sid}->{sasl}->{authed} = 0;
            $self->{SIDS}->{$sid}->{ErrorCode} = ERR_SASL;
            $self->{SIDS}->{$sid}->{ErrorMessage} = "SASL Authentication: Unexpected response tag ".$ans->get_tag;
            return undef;
        }

        # We got a challenge request, generate response
        my $challenge64 = $ans->get_cdata;
        my $challenge = MIME::Base64::decode_base64($challenge64);

        #-------------------------------------------------------------------------
        # As far as I can tell, if the challenge contains rspauth, then we authed.
        # If you try to send that to Authen::SASL, it will spew warnings about
        # the missing qop, nonce, etc...  However, in order for jabberd2 to think
        # that you answered, you have to send back an empty response.  Not sure
        # which approach is right... So let's hack for now.
        #-------------------------------------------------------------------------
        my $response = "";
        if ($challenge !~ /rspauth\=/) {
            $response = $self->{SIDS}->{$sid}->{sasl}->{client}->client_step($challenge);
        }
        log_warn("Next step $response");
        my $response64 = MIME::Base64::encode_base64($response,"");

        # +-----------------------------------------+
        # | STEP 3 - Send challenge request         |
        # +-----------------------------------------+

        # Send challenge response
        $rid = $self->NewRID($sid);
        $ans = $self->SendAndReceive($sid, 
            "<body rid='$rid'
                   sid='$sid'
                   xmlns='http://jabber.org/protocol/httpbind'>
                <response xmlns='".$XMLNS{'xmpp-sasl'}."'>$response64</response>
            </body>");

        
    }

    # Completed :)
    $self->{SIDS}->{$sid}->{sasl}->{done} = 1;
    $self->{SIDS}->{$sid}->{sasl}->{authed} = 1;
    return 1;


}

sub SASLClientDone {
    my $self = shift;
    my $sid = shift;
    return $self->{SIDS}->{$sid}->{sasl}->{done};
}

sub SASLClientAuthed {
    my $self = shift;
    my $sid = shift;
    return $self->{SIDS}->{$sid}->{sasl}->{authed};
}

sub OpenStream {
    my $self = shift;
    my $currsid = shift;
    my $timeout = shift;
    $timeout = "" unless defined($timeout);
    $currsid = 'newconnection' unless defined($currsid);

    # Fetch config from this SID
    my $config = $self->{SIDS}->{$currsid};
    return undef unless defined($config);
    
    # Restart stream if we have specified a SID and it's currently in use
    if ($currsid ne 'newconnection') {
        log_error("***CLOSING CONNECTION $currsid***");
        
        # Requesting a BOSH Restart for that SID
        my $rid = $self->NewRID($currsid);
        my $ans = $self->SendAndReceive($currsid, 
            "<body content='text/xml; charset=utf-8'
              hold='1'
              rid='$rid'
              to='$config->{Server}'
              ver='1.6'
              wait='$config->{Wait}'
              xml:lang='en'
              xmpp:version='1.0'
              sid='$currsid'
              xmpp:restart='true'
              xmlns='http://jabber.org/protocol/httpbind'
              xmlns:xmpp='urn:xmpp:xbosh' />");
        
        # We don't care much for the response. Just make sure there was no error
        # TODO: Check if there was an error

        my @features = $ans->children();
        if ($#features > -1){
            $self->ProcessStreamFeatures($currsid, $features[0]); # Add missing features
        }
        
        # Switch to newconnection
        $self->{SIDS}->{'newconnection'} = $self->{SIDS}->{$currsid};
        delete $self->{SIDS}->{$currsid};
        $currsid = 'newconnection';
        $self->{SIDS}->{'newconnection'}->{rid} = $self->NewSID();
        
    }
    
    # Requesting a new session
    my $rid = $self->NewRID($currsid); # << For this session
    my $ans = $self->SendAndReceive($currsid, 
        "<body content='text/xml; charset=utf-8'
          hold='1'
          rid='$rid'
          to='$config->{Server}'
          ver='1.6'
          wait='$config->{Wait}'
          xml:lang='en'
          xmpp:version='1.0'
          xmlns='http://jabber.org/protocol/httpbind'
          xmlns:xmpp='urn:xmpp:xbosh' />");
    
    # Check for failure
    if (!defined($ans)) {
        $self->{SIDS}->{$currsid}->{ErrorCode} = ERR_UNAVAILABLE;
        $self->{SIDS}->{$currsid}->{ErrorMessage} = "Unable to send the stream initialization request";
        return undef;
    }
        
    # Extract root attrib that will be used as the SESSION info inside XMPP::Client
    my %session = $ans->attrib();
    
    # Move under the new session ID
    my $sid = $ans->get_attrib('sid');
    log_error("***OPPENED CONNECTION $sid***");
    $session{id} = $sid;
    $self->{SIDS}->{$sid} = $self->{SIDS}->{$currsid};
    delete $self->{SIDS}->{$currsid};

    # Get features
    my @features = $ans->children();
    if (scalar @features == 0) {
        $self->{SIDS}->{$currsid}->{ErrorCode} = ERR_UNAVAILABLE;
        $self->{SIDS}->{$currsid}->{ErrorMessage} = "Unable to detect stream features on the response";
        return undef;
    }
    $self->ProcessStreamFeatures($sid, $features[0]);
    
    # Everything was good!
    return \%session;
    
}

##############################################################################
#
# ProcessStreamFeatures - process the <stream:featutres/> block.
#
##############################################################################
sub ProcessStreamFeatures {
    my $self = shift;
    my $sid = shift;
    my $node = shift;
    my $features = {};
    $features=$self->{SIDS}->{$sid}->{streamfeatures} if defined($self->{SIDS}->{$sid}->{streamfeatures});

    #-------------------------------------------------------------------------
    # SASL - 1.0
    #-------------------------------------------------------------------------
    my @sasl = $node->XPath('*[@xmlns="'.$XMLNS{'xmpp-sasl'}.'"]');
    if ($#sasl > -1) {
        if ($sasl[0]->XPath("name()") eq "mechanisms") {
            my @mechanisms = $sasl[0]->XPath("mechanism/text()");
            $features->{'xmpp-sasl'} = \@mechanisms;
        }
    }

    #-------------------------------------------------------------------------
    # XMPP-TLS - 1.0
    #-------------------------------------------------------------------------
    my @tls = $node->XPath('*[@xmlns="'.$XMLNS{'xmpp-tls'}.'"]');
    if ($#tls > -1) {
        if ($tls[0]->XPath("name()") eq "starttls") {
            $features->{'xmpp-tls'} = 1;
            my @required = $tls[0]->XPath("required");
            if ($#required > -1) {
                $features->{'xmpp-tls'} = "required";
            }
        }
    }
    
    #-------------------------------------------------------------------------
    # XMPP-Bind - 1.0
    #-------------------------------------------------------------------------
    my @bind = $node->XPath('*[@xmlns="'.$XMLNS{'xmpp-bind'}.'"]');
    if ($#bind > -1) {
        $features->{'xmpp-bind'} = 1;
    }

    # DO NOT USE SESSION -- NOT USED ON BOSH
    #-------------------------------------------------------------------------
    # XMPP-Session - 1.0
    #-------------------------------------------------------------------------
    #my @session = $node->XPath('*[@xmlns="'.$XMLNS{'xmpp-session'}.'"]');
    #if ($#session > -1) {
    #    $features->{'xmpp-session'} = 1;
    #}
    
    # Update features
    $self->{SIDS}->{$sid}->{streamfeatures} = $features;
    
}

##############################################################################
#
# GetStreamFeature - Return the value of the stream feature (if any).
#
##############################################################################
sub GetStreamFeature {
    my $self = shift;
    my $sid = shift;
    my $feature = shift;
        
    return unless exists($self->{SIDS}->{$sid}->{streamfeatures}->{$feature});
    return $self->{SIDS}->{$sid}->{streamfeatures}->{$feature};
}


##############################################################################
#
# ReceivedStreamFeatures - Have we received the stream:features yet?
#
##############################################################################
sub ReceivedStreamFeatures {
    my $self = shift;
    my $sid = shift;
    my $feature = shift;

    return defined($self->{SIDS}->{$sid}->{streamfeatures});
}


1;