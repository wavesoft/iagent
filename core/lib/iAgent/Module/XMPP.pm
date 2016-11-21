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

iAgent::Module::XMPP - XMPP Connectivity module for iAgent

=head1 DESCRIPTION

This module provides the XMPP/Jabber transport layer for the rest of the system. This module has 0 priority, wich
means it will be in the top of the module list by default.

=head1 PROVIDED EVENTS

This module broadcasts/dispatches communication events (prefixed with 'comm_'). Please note the difference between
'dispatching' and 'broadcasting' events! Dispatched events can be intercepted, while broadcasts cannot! 

This module provides following events:

=head2 comm_ready HASHREF

This message is broadcasted when the transport system is ready to accept/provide messages.
First argument is a hash reference:

  {
  	me => 'xmpp_name_of_myself@domain/resource'
  }

=head2 comm_disconnect

This message is broadcasted when there was an error on the transport system that caused a disconnection. 

=head2 comm_error HASHREF

This message is broadcasted when there was an error on the transport system.
First argument is a hash reference:

 {
 	message => 'Error message',
 	recoverable => 0 or 1
 }

=over

=item MESSAGE

The first argument passed to the event is the human-readable representation of the message. 

=item RECOVERABLE

The second argument is B<1> if the error is recoverable and will most probably recover itself or B<0> if the error
is not recoverable and the system should prepare for more drastic actions.

=back

If there was an active connection, this event is always broadcasted AFTER C<comm_disconnect>.

=head2 comm_action HASHREF

This message is dispatched when a command is arrived.
The hash has the following structure:

 {
 	from => 'user@domain/resource', 
 	action => 'doit', 
 	data =>  'message payload', 
 	parameters => { param => ..} or [ 'param', 'param' ], 
 	context => 'archipel:vm', 
 	type => 'get', 
 	raw => REF(Net::XMPP::Stanza)
 }

B<Keep in mind that hash contents may change during mesage propagation!>

=over

=item FROM

The transport-dependant string representation of the source (in XMPP case the 'from' JID). 

=item ACTION

The action name. In Archipel protocol, that's the action="" of the 'archipel' tag.

=item DATA

That's the string represnetation of the payload of the message. In Archipel protocol, that's the
HTML contents of the <archipel> .. </archipel> tag

=item PARAMETERS

The simple parameters to be passed along with the action. In Archipel protocol, that's the hash of
all the <param>='<value>' attibutes that exist within the <archipel /> tag.

=item CONTEXT

The context of the action. In XMPP that's the XMLNS of the query node.

=item TYPE

The type of the action 'set', 'get', 'result' etc..

=item RAW

The raw L<Net::XMPP::IQ> or L<Net::XMPP::Message> packet, as received from the transport

=back 

=head2 comm_available HASHREF

This message is Dispatched when the specified user has become available.
The hash has the following structure:

  {
  	from => 'user@domain/resource',
  	status => 'online',
  	show => 'I am back',
  	raw => REF(Net::XMPP::Stanza)
  }

=over

=item FROM

The transport-dependant string representation of the source (in XMPP case the 'from' JID). 

=item STATUS

The actual status of the new user.

=item SHOW

How wants the user his status to be like.  

=item RAW

The raw L<Net::XMPP::Presence> packet.

=back

=head2 comm_unavailable HASHREF

This message is Dispatched when the specified user has become unavailable.
The hash has the following structure:

  {
  	from => 'user@domain/resource',
  	raw => REF(Net::XMPP::Stanza)
  }

=over

=item SOURCE

The transport-dependant string representation of the source (in XMPP case the 'from' JID). 

=item RAW

The raw L<Net::XMPP::Presence> packet.

=back

=head1 ACCEPTED EVENTS

=head2 comm_reply HASHREF

=head2 comm_send HASHREF

=head2 comm_send REF(Net::XMPP::Stanza)

Sends the defined message on the network. This function accepts either a hash or an object that (usually) subclasses
Net::XMPP::Stanza (Like Net::XMPP::IQ, Net::XMPP::Presence etc).

The hash structure must be like this:

  {
  	    
    # Required
    to => 'user[@domain[/resource]]',
    action => 'action',
    
    # Optional (Defaults follows)
    data => '',
    parameters => { },
    context => 'archipel',
    type => 'set'
  }

Here are the accepted parameters

=over

=item TO

The transport-dependant string representation of the destination (in XMPP case the 'to' JID). 

=item ACTION

The action name. In Archipel protocol, that's the action="" of the 'archipel' tag.

=item DATA

That's the string represnetation of the payload of the message. In Archipel protocol, that's the
HTML contents of the <archipel> .. </archipel> tag

=item PARAMETERS

The simple parameters to be passed along with the action. In Archipel protocol, that's the hash of
all the <param>='<value>' attibutes that exist within the <archipel /> tag.

=item CONTEXT

The context of the action. In XMPP that's the XMLNS of the query node.

=item TYPE

The type of the action 'set', 'get', 'result' etc..

=item RAW

If a raw packet is specified, the rest of the parameters are ignored and the message
is transfered as-is on the network.

=back 

=head3 Packet Contexts

By default, the packet is sent as an archipel IQ Request. However, if you set C<context> field to one of: 'chat:text', 
'chat:json' or 'chat:command' the message will be sent as a chat message.

Here is how those chat messages behave:

=head4 chat:text

In this context the contents of the 'data' field will be sent as-is.

For example:
  
  # Sending
  {
    context => 'chat:text',
  	data => 'Here are some data to send
  }

Will send:
  
    Here are some data to send

=head4 chat:json

In this context, the parameters/action or data variables are encoded in JSON format and sent
to the client.

For example:

  # Sending
  {
  	context => 'chat:json',
  	parameters => {
  		'parm1' => 'parm1 value',
  		'parm2' => [ 1, 2, 3 ]
  		# Any other parameter here
  	},
  	action => 'my action'
  	# No other entries are processed
  }
  
  # Or sending
  {
    context => 'chat:json',
    data => {
	    parameters => {
	        'parm1' => 'parm1 value',
	        'parm2' => [ 1, 2, 3 ]  
	    },
	    action => 'my action'
	    
	    # Any structure is valid here...
	    
    }  	
  }

Will send:

  {"parameters":{"parm1":"parm1 value","parm2":[1,2,3]},"action":"my action"}

=head4 chat:command

In this context, the action/parameters are encoded as in a command-line-like syntax.

For example:

  # Sending:
  {
  	context => 'generic:chat',
  	action => 'start',
  	parameters => {
  		'job' => 'mine',
  		'where' => 'there',
  		'how' => 'in a weird way'
  	}
  }

Will send:

  start -job mine -where there -how "in a weird way"

=head4 Anything else

Anything else will be assumed to be the XMLNS of the archipel IQ Message.

For example:

    # Sending
    {
    	context => 'archipel:ibuilder',
    	action => 'list_projects',
    	parameters => {
    		filter => '*ed'
    	}
    }

Will send:

    <query type="archipel" xmlns="archipel:builder">
        <archipel action="list_projects" filter="*ed" />
    </query>

You can also specify a payloads for the message:

    {
    	context => 'archipel:ibuilder',
    	type => 'result',
    	
    	# The payload can be either be a string... 
    	data => 'some CDATA <escaped> data here',
    	
    	# .. or a properly formatted XML string ...
    	data => '<proper>XML</proper>',
    	
    	# .. a hash ..
    	data => {
    		error => {
    			code => 410,
    			message => "Failure"
    		}
    	}
    	
    	# .. or an instance of an XML::Stream::Node
    	
    }

The above will send (accordingly):

    <!-- Unstructured string will create -->
    <query type="archipel" xmlns="archipel:builder" type="result">
        some CDATA &lt;escaped&gt; here
    </query>

    <!-- Structured string will create -->
    <query type="archipel" xmlns="archipel:builder" type="result">
        <proper>XML</proper>
    </query>

    <!-- Hash will create -->
    <query type="archipel" xmlns="archipel:builder" type="result">
        <error code="410" message="Failure" />
    </query>

=cut

# Basic definitions
package iAgent::Module::XMPP;
use strict;
use warnings;

# For connection with iAgent
use iAgent;
use iAgent::Kernel;
use iAgent::Log;

# The actually usable stuff
use POE;
use Data::Dumper;
use Net::XMPP;
use Sys::Hostname;
use HTML::Entities;
use MIME::Base64;
use Digest::MD5 qw(md5_hex);

# For the advanced parsing options
use JSON;
use XML::Simple;

# Extensions
use iAgent::Module::XMPP::Namespaces;
use base qw( 
    iAgent::Module::XMPP::PubSub 
    iAgent::Module::XMPP::Roster 
    iAgent::Module::XMPP::MUC 
    iAgent::Module::XMPP::VCard 
);

# The last message arrived
my  $LAST_MESSAGE = undef;
my  $LAST_MESSAGE_TYPE = 0;
my  $LAST_IQ_ID = undef;
my  $PENDING_REPLY = 0;

our $MANIFEST = {
	
    # Use autodetection for the events, 
    # using the '__' for event prefix
    hooks => 'AUTO',
    
    # Highest priority
    priority => 0,
	
    # On crash, reload module
    oncrash => 'reload',
    
    # CLI Bindings
    CLI => {

        # When to enable/disable console for this module
        VALIDATE_AT => "comm_ready",
        INVALIDATE_AT => "comm_disconnect",

        # The commands
        "xmpp/send" => {
            description => "Send a message to the specified target",
            message => "cli_send",
            options => [ 'to=s', 'action=s', 'context=s', 'payload=-' ]
        },
        "xmpp/action" => {
            description => "Send an action request to the specified user",
            message => "cli_action"
        },
        "xmpp/me" => {
            description => "Display my JID",
            message => "cli_me"
        }
    }
	
};


## +-------------------------------------------------------------------------------------------------------------------------------------+ ##
## | =================================================================================================================================== | ##
## | =================================================================================================================================== | ##
## |                                                        BEGIN CODE HERE                                                              | ##
## | =================================================================================================================================== | ##
## | =================================================================================================================================== | ##
## +-------------------------------------------------------------------------------------------------------------------------------------+ ##

############################################
# New instance
# Check the CALLBACK_* functions below for
# more details on the XMPP callbacks
sub new { 
############################################
    my ($class, $config) = @_;

    # Ensure some default config parameters
    $config->{XMPPStrict}=0 if (!defined $config->{XMPPStrict});

    # Generate resource
    if (!defined($config->{XMPPResource})) {
        my $host = hostname;
        
        # Randomize resource if needed (but only once)
        if ((defined $config->{XMPPRandomResource}) && ($config->{XMPPRandomResource} == 1)) {
            $host.= "-";
            for (my $i=0; $i<10; $i++) {
                $host.= ("a".."z")[rand 26];
            }
        }
        $config->{XMPPResource}=$host;
    }

    # Init self and saved the passed
    # configuration information
    my $self = {
        config => $config,
        ready => 0,
        killed => 0,        
        XMPPCon => undef,

        # Reply vectors for specified IQ IDs
        DATA_ID2REPLY => { },

        # Information storage
        DATA_CHATROOMS => { },

        # Manifest cache
        MANIFEST_CACHE => { }
        
    };
    
    # Instance me
    $self = bless $self, $class;
 
    # And return my blessed instance
    return $self;
}

sub ___setup {
    my $self = $_[OBJECT];
    my $config = $self->{config};
    
    # Setup XMPP (This requires a live POE Kernel)
  
   # Create XMPP Object
   log_debug("Creating XMPP Object");
   my $XMPPCon = new Net::XMPP::Client( );
   $XMPPCon->{DEBUG}->{LEVEL}=0;
   $self->{XMPPCon} = $XMPPCon;

   # Initialize XMPP Callbacks
   log_debug("Setting up XMPP Callbacks");
   $XMPPCon->SetCallBacks(

       iq => sub {
       	
           	# Handle archipel IQs
           	my ($id, $packet) = @_;
           	log_debug("Got incoming IQ from ".$packet->GetFrom()." type: ".$packet->GetType());
           	
           	if (!$self->validate_source($packet)) {
               $XMPPCon->Send($packet->Reply( type => 'error', errorCode => 404, error => "Permission Denied" ));
       	        log_warn("Incoming message from ".$packet->GetFrom()." was rejected because was is originated from an untrusted source");
       	        return;
           	}
           	
           	# Extract some useful info
           	my $xml_iq = $packet->GetTree();
           	my @xml_iq_nodes = $xml_iq->children();
           	my $pID = $packet->GetID();

           # BEFORE DOING ANYTHING ELSE, explicitly reply to messages
           # hooked on the reply map
           if (defined $self->{DATA_ID2REPLY}->{$pID}) {

               log_debug("Found reply for ID $pID: SESSION: ".$self->{DATA_ID2REPLY}->{$pID}->[1]->get_heap()->{CLASS}.", MESSAGE: ".$self->{DATA_ID2REPLY}->{$pID}->[0]);
               
               POE::Kernel->call($self->{DATA_ID2REPLY}->{$pID}->[1], $self->{DATA_ID2REPLY}->{$pID}->[0], {
                   from => $packet->GetFrom(),
                   type => $packet->GetType(),
                   raw => $packet,
                   id => $pID,
                   data => $packet->GetXML(),
                   timeout => 0
               });

               # Done!
               delete $self->{DATA_ID2REPLY}->{$pID};   

           } else {
                       	
               	# Locate the query node(s)
               	my $query = undef;
               	foreach (@xml_iq_nodes) {
                   my $XMLNS = $_->get_attrib('xmlns');
                   $XMLNS = "" if not defined $XMLNS;
               		log_debug(" IQ Contains a ".$_->get_tag()." xmlns=".$XMLNS);

               		if ($_->get_tag() eq 'query') {
               			$query = $_;
               				
                           # We might have more than one actions
                           log_debug('Processing query: '.$query->GetXML());
                           foreach my $cmd ($query->children()) {
                               
                               log_debug("Got ".$cmd->get_tag());
                               
                               # Check for action nodes
                               if ($cmd->get_tag() eq 'archipel') {
                                   
                                   log_debug("Got archipel node on IQ");
               
                                   # Extract attrib
                                   my %attrib = $cmd->attrib();
                                   my $action = $attrib{action};
                                   
                                   # No action? Not valid :)
                                   if (not defined $action) {
                                       log_warn("Archipel IQ message arrived, but contains no action= attribute!");
                                       next;
                                   };
                                   
                                   # Prepare for parameters
                                   delete $attrib{action};
               
                                   # Get XML
                                   my $xml_data = '';
                                   if ($cmd->XPathCheck("opt")) {

                                       # Revert numeric tags and attributes
                                       my $xml = $cmd->XPath('opt')->GetXML;
                                       	$xml =~ s/num\:d(\d+)/$1/g;

                                       # Parse data
                                       $xml_data = XMLin($xml);

                                   } elsif ($cmd->XPathCheck("json")) {

                                       # Fetch object from json
                                       $xml_data = decode_json($cmd->XPath('json')->get_cdata);
                                       
                                   } elsif ($cmd->get_cdata ne '') {
                                       $xml_data = $cmd->get_cdata;
                                       
                                   } else {
                                       $xml_data = $cmd->GetXML;
                                   }

                                   # Save the last message
                                   $LAST_MESSAGE = {
                                          from => $packet->GetFrom(),
                                          action => $action,
                                          data => $xml_data,
                                          parameters => \%attrib,
                                          context => $XMLNS,
                                          type => $packet->GetType(),
                                          raw => $packet,
                                          raw_query => $query,
                                          id => $packet->GetID()
                                     };
                                   $LAST_MESSAGE_TYPE = 2;
               
                                   # Mark that we have a pending reply only if we got a set or get request
                                   $PENDING_REPLY = ($packet->GetType() eq 'get') || ($packet->GetType() eq 'set');
               
                                   # Dispatch a command structure for the chat
                                   # Satisfy: [ SOURCE, ACTION, DATA, PARAMETERS, CONTEXT, TYPE, RAW ] 
                                   my $ans = Dispatch('comm_action', $LAST_MESSAGE);
                                   
                                   # Not handled by any plugin? Reply 'unimplemented' to the sender
                                   if ($PENDING_REPLY) {
                                       if ($ans == RET_UNHANDLED) {
                                           	$self->send_iq($packet, 'error', '', '', $query->GetXML()."<error type='cancel' code='501'><feature-not-implemented xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'><text xmlns='url:ietf:params:xml:ns:xmpp-stanzas' xml:lang='en'>The requested feature: ".encode_entities($LAST_MESSAGE->{type}."/".$LAST_MESSAGE->{action})." is not implemented!</text></feature-not-implemented></error>");
                                       } elsif (($ans == RET_ABORTED) || ($ans == RET_ERROR)) {
                                           POE::Kernel->yield('comm_reply_error', { type => 'internal-server-error', code => 500, message=>'Action failed with unspecified reason!' }); # Got error!
                                       } elsif (($ans != RET_SCHEDULED) && ($ans != RET_COMPLETED)) {
                                           POE::Kernel->yield('comm_reply', { }); # OK
                                       }
                                   }
                                   
                               }
                                           				
               			    }

               		} else {

                       # Unknown node arrived, re-publish it as-is
                       $LAST_MESSAGE = {
                           from => $packet->GetFrom(),
                           type => $packet->GetType(),
                           nodeName => $_->get_tag(),
                           context => $XMLNS,
                           raw => $packet,
                           raw_node => $_,
                           id => $packet->GetID(),
                           data => $_->GetXML()
                       };
                       $LAST_MESSAGE_TYPE = 3;
                       $PENDING_REPLY = 0;

                       # Dispatch incomming message
                       Dispatch('comm_packet', $LAST_MESSAGE);

               		} 
               	}
               	
               	return unless defined $query;        	
           	        	
           }

       }
       
   );


   # Register presence callbacks
   $XMPPCon->SetPresenceCallBacks(
       available =>    sub { return $self->CALLBACK_PRESENCE_AVAILABLE(@_) },
       unavailable =>  sub { return $self->CALLBACK_PRESENCE_UNAVAILABLE(@_) },
       subscribe =>    sub { return $self->CALLBACK_PRESENCE_SUBSCRIBE(@_) },
       unsubscribe =>  sub { return $self->CALLBACK_PRESENCE_UNSUBSCRIBE(@_) },
       subscribed =>   sub { return $self->CALLBACK_PRESENCE_SUBSCRIBED(@_) },
       unsubscribed => sub { return $self->CALLBACK_PRESENCE_UNSUBSCRIBED(@_) },
       error =>        sub { return $self->CALLBACK_PRESENCE_ERROR(@_) }
   );
           
   # Register message callbacks
   $XMPPCon->SetMessageCallBacks(
       chat =>         sub { return $self->CALLBACK_MESSAGE_CHAT(@_) },
       headline =>     sub { return $self->CALLBACK_MESSAGE_HEADLINE(@_) },
       normal =>       sub { return $self->CALLBACK_MESSAGE_NORMAL(@_) }
   );

   # Register custom XPath callbacks
   $XMPPCon->SetXPathCallBacks(

       # Core XMPP callbakcs
       "/iq/query[\@xmlns='http://jabber.org/protocol/disco#info']" => sub { shift; return $self->CALLBACK_IQ_DISCOVERY(@_) },
       "/iq/query[\@xmlns='jabber:iq:version']"                     => sub { shift; return $self->CALLBACK_IQ_VERSION(@_) },
       "/iq/query[\@xmlns='jabber:iq:last']"                        => sub { shift; return $self->CALLBACK_IQ_LAST(@_) },
       "/iq/ping[\@xmlns='urn:xmpp:ping']"                          => sub { shift; return $self->CALLBACK_IQ_PING(@_) },
       "/iq/time"                                                   => sub { shift; return $self->CALLBACK_IQ_TIME(@_) },

   );

   # Initialize submodules
   iAgent::Module::XMPP::PubSub::init($self, $XMPPCon);
   iAgent::Module::XMPP::VCard::init($self, $XMPPCon);
    
}

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                            CALLBACKS FOR XMPP CONNECTION                                                    | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

#######################################
sub CALLBACK_PRESENCE_AVAILABLE {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    
	log_msg("User ".$packet->GetFrom()." became available");

	# Update roster information 
	my $jid = $packet->GetFrom();
	$self->user_state_changed($jid, 'online');

	# Broadcast event
	Broadcast('comm_user_online', {
        from => $packet->GetFrom(),
        status => $packet->GetStatus(),
        show => $packet->GetShow(),
        raw => $packet
	});

	# Schedule an event that will notify we are ready after 1 second
	# If we got another presence within the second it will refresh the timer
	# (This is used in order to send 'comm_ready' ONLY when we have also 
	#  received the presence of all the users of my roster that are online)
	POE::Kernel->delay('_notify_ready' => 0.5);

}

#######################################
sub CALLBACK_PRESENCE_UNAVAILABLE {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

    log_msg("User ".$packet->GetFrom()." became unavailable");

	# Update roster information 
	my $jid = $packet->GetFrom();
	$self->user_state_changed($jid, 'offline');

    # Broadcast event
    Broadcast('comm_user_offline', {
      from => $packet->GetFrom(),
      raw => $packet
    });

}

#######################################
sub CALLBACK_PRESENCE_SUBSCRIBE {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

    # Check if we should accept the subscription
    my $ans = Broadcast('comm_request_subscribe', { from => $packet->GetFrom(), raw => $packet });
    if ($ans != 0) {
    
        $XMPPCon->Send($packet->Reply(type=>"subscribed"));
        log_msg("Accepted subscription from ".$packet->GetFrom());

	    # Update roster information 
	    my $jid = $packet->GetFrom();
        $XMPPCon->RosterAdd( jid => $jid );
	    $self->user_state_changed($jid, 'offline');

        # Unsubscribe
        Broadcast('comm_subscribed', {
          from => $packet->GetFrom(),
          raw => $packet
        });
        
    } else {
	    $XMPPCon->Send($packet->Reply(type=>"unsubscribed"));
        log_warn("Subscription request from user ".$packet->GetFrom()." was rejected");
    }

}

#######################################
sub CALLBACK_PRESENCE_UNSUBSCRIBE {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

    # Accept unsubscription
    $XMPPCon->Send($packet->Reply(type=>"unsubscribed"));
    log_msg("Accepted unsubscription from ".$packet->GetFrom());

    # Update roster information
	my $jid = $packet->GetFrom();
    $XMPPCon->RosterRemove( jid => $jid );
	if (defined $self->{USERS}->{$jid}) {
	    delete $self->{USERS}->{$jid};
	}

    # Broadcast event
    Broadcast('comm_unsubscribed', {
      from => $packet->GetFrom(),
      raw => $packet
    });
                
}

#######################################
sub CALLBACK_PRESENCE_ERROR {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

    # Extract error information
    my $from = $packet->GetFrom();
    	my $xml_presence = $packet->GetTree();
    	my @xml_presence_nodes = $xml_presence->children();
    	my $error_type='';
    	foreach (@xml_presence_nodes) {
    	    if ($_->get_tag() eq 'error') {
    	        my ($err_tag) = $_->children();
    	        $error_type = $err_tag->get_tag();
    	        last;
    	    } 
    	}

    	# If that's a chatroom error, send it there
    if (defined $self->{DATA_CHATROOMS}->{$from}) {
        $self->{DATA_CHATROOMS}->{$from}->{error} = $error_type;
        Broadcast('comm_group_error', {
            from => $packet->GetFrom(),
            group => $self->{DATA_CHATROOMS}->{$from}->{group},
            error => $error_type,
            raw => $packet
        });
    }

}

#######################################
sub CALLBACK_MESSAGE_CHAT {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

    # Check for some data 
    	return if ($packet->GetBody() eq '');

    # Check source validity
    	if (!$self->validate_source($packet)) {
        log_warn("Incoming message from ".$packet->GetFrom()." was rejected because it was originated from an untrusted source");
        $XMPPCon->Send($packet->Reply( body => "forbidden! (Code 404) You are not authorized to perform this operation" ));
        return;
    }

    # Parse command-line parameters
    my ($cmd, $parms) = parse_cmdline($packet->GetBody());

    # Save the last message
    $LAST_MESSAGE = {
           from => $packet->GetFrom(),
           data => $packet->GetBody(),
           context => 'chat:text',
           type => 'chat',
           action => $cmd,
           parameters => $parms,
           raw => $packet,
           id => $packet->GetID()
       };
    $LAST_MESSAGE_TYPE = 1;
    $PENDING_REPLY = 1;

    # Dispatch a command-like structure for the chat command arrived
    log_debug("Got CHAT message from ".$packet->GetFrom().": ".$packet->GetBody()); 
    my $ans = Dispatch('comm_action',$LAST_MESSAGE) if ($packet->GetType() eq 'chat');

    # Not handled by any plugin? Reply 'unimplemented' to the sender
    if ($PENDING_REPLY>0) {
        if ($ans == RET_UNHANDLED) {
            $XMPPCon->Send($packet->Reply( body => 'feature-not-implemented! (Code 501) The requested feature is not implemented: '.$LAST_MESSAGE->{context}."::".$LAST_MESSAGE->{action}."/".$LAST_MESSAGE->{type} ));
        } elsif ($ans == RET_ABORTED) {
            $XMPPCon->Send($packet->Reply( body => 'internal-server-error! (Code 500) Action failed with unspecified reason' ));
        }
    }

}

#######################################
sub CALLBACK_MESSAGE_GROUPCHAT {
#######################################

}

#######################################
sub CALLBACK_MESSAGE_HEADLINE {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};

}

#######################################
sub CALLBACK_MESSAGE_NORMAL {
#######################################
    my ($self, $id, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    log_debug("Message callback: ".$packet->GetXML);

    # We got a 'normal' message (non-chat)
    # Dispatch it to the plugins....
    iAgent::Kernel::Dispatch('comm_message', {
        from => $packet->GetFrom(),
        message => $packet->GetBody(),
        subject => $packet->GetSubject(),
        thread => $packet->GetThread()
    });

}

#######################################
sub CALLBACK_IQ_DISCOVERY {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    log_debug("IQ Discovery callback: ".$packet->GetXML);

    # Prepare response
    my $p = $packet->Reply(
        type => 'result'
    );

    # Prepare features (Query already contains the required <query /> object
    my $e_features = $p->GetQuery();

    # Place Identity
    my $id=$e_features->NewChild(JABBER_DISCOVERY_IDENTITY);
    $id->SetName("iAgent-".sprintf("%vd",$iAgent::VERSION));
    $id->SetCategory('client');
    $id->SetType('pc');

    # Place features
    $e_features->NewChild(JABBER_DISCOVERY_FEATURE)->SetVar("http://jabber.org/protocol/disco#info");
    $e_features->NewChild(JABBER_DISCOVERY_FEATURE)->SetVar("http://jabber.org/protocol/muc");
    $e_features->NewChild(JABBER_DISCOVERY_FEATURE)->SetVar("jabber:iq:register");
    $e_features->NewChild(JABBER_DISCOVERY_FEATURE)->SetVar("jabber:iq:version");
    $e_features->NewChild(JABBER_DISCOVERY_FEATURE)->SetVar("vcard-temp");

    # Also expose the registered modules as 'features'
    foreach (@iAgent::Kernel::SESSIONS) {
        my $nm = lc($_->{session}->get_heap()->{CLASS});
        $nm =~ s/::/\//g;
        $e_features->NewChild(JABBER_DISCOVERY_FEATURE)->SetVar($nm);
    }

    # Send response
    $XMPPCon->Send($p);

}

#######################################
sub CALLBACK_IQ_VERSION {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    log_debug("IQ Version callback: ".$packet->GetXML);

    # Prepare response packet
    my $p = $packet->Reply(
        type => 'result'
    );

    # Prepare version query
    my $e_version = $p->NewChild('jabber:iq:version');
    $e_version->SetName('iAgent XMPP Module');
    $e_version->SetVersion(sprintf("%vd",$iAgent::VERSION));
    $e_version->SetOS($^O);

    # Send response
    $XMPPCon->Send($p);

}

#######################################
sub CALLBACK_IQ_PING {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    log_debug("IQ Ping callback: ".$packet->GetXML);

    # Prepare response packet
    my $p = $packet->Reply(
        type => 'result'
    );

    # Log the ping/pong
    log_debug("XMPP ping reply");

    # Send response
    $XMPPCon->Send($p);
}

#######################################
sub CALLBACK_IQ_TIME {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    log_debug("IQ Time callback: ".$packet->GetXML);

    # Prepare fields
    my ($sec, $min, $h, $dom, $m, $yOfs, $dow, $doy, $dl_sav) = gmtime();
    my $y = 1900 + $yOfs;

    # Prepare response packet
    my $p = $packet->Reply(
        type => 'result'
    );

    # Prepare time result
    my $e_time = $p->NewChild('url:xmpp:time');
    $e_time->SetTZO('00:00');
    $e_time->SetUTC("$y-$m-$dom".'T'."$h:$min:$sec".'Z');

    # Send response
    $XMPPCon->Send($p);
    
}

#######################################
sub CALLBACK_IQ_LAST {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    log_debug("IQ Last callback: ".$packet->GetXML);

    # Prepare reply (No last command appliable here)
    my $p = $packet->Reply(
        type => 'result'
    );

    # Send it
    $XMPPCon->Send($p);

}

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                               PRIVATE HELPER FUNCTIONS                                                      | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

#######################################
# Extract a bit more descriptive error  
# on what happened, because GetErrorCode
# returns nothing important/
sub real_error {
#######################################
    my $self = shift;
    my $xmpp = $self->{XMPPCon};
    my $sid = $xmpp->{SESSION}->{id};
    return undef unless defined($sid);
    return undef unless defined($xmpp->{STREAM}->{SIDS}->{$sid});
    my $error = $xmpp->{STREAM}->{SIDS}->{$sid}->{errorcode};
    return undef unless defined($error);
    if (ref $error) {
        my $text = $error->{text};
        my $type = $error->{type};
        return "$text ($type)";
    } else {
        return $error;
    }
}

#######################################
# Parse command-line from a string
# Returns an array with the command and
# a hash reference to the parameters
sub parse_cmdline {
#######################################
    my $cmdline = shift;

    	# Initialize
    	my @parts = split ' ', $cmdline;
    	my $cmd = shift @parts;

    	# Parse command-line (Simple mode)
    	my $parms = { }; my $key=undef; my $index=0;
    	for ( my $i=0; $i<=$#parts; $i++) {
    	    my $p = $parts[$i];
    	    if ($p =~ m/-?-([A-Za-z0-9_-]+)= (.*)/) {
    	        $parms->{$1} = $2;
    	        $key = undef;
    	    } elsif (substr($p,0,2) eq '--') {
    	        $key = substr $p,2;
    	    } elsif (substr($p,0,1) eq '-') {
    	        $key = substr $p,1;
    	    } elsif (defined $key) {
    	        $parms->{$key} = $p;
    	        $key = undef;
    	    } elsif (!defined $key) {
            $parms->{++$index} = $p;
    	    }
    	}

    	return ( $cmd, $parms );

}

#######################################
# Validates the specified user
sub validate_source {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    my $config = $self->{config};
    my $host = $config->{XMPPResource};
    
    return 1 if (!$config->{XMPPStrict});

    return 1 if ($packet->GetFrom() eq $config->{XMPPUser}.'@'.$config->{XMPPServer});
    return 1 if ($packet->GetFrom() eq $self->{me});
    return 1 if ($packet->GetFrom() eq $config->{XMPPServer});
    return 1 if ($self->{ROSTER}->exists($packet->GetFrom('jid')));

    return 0;
}


#######################################
# Bind a reply ID to a specified
# message broadcast.
#
# This is usually used when you are
# waiting for a reply after you have
# sent the IQ message.
#
# And all these in asynchronous mode
#
sub bind_id_reply {
#######################################
    my ($self, $id, $message) = @_;
    my $SESSION = $iAgent::Kernel::LAST_SOURCE;

    log_debug("Setting reply vector for ID=$id to SESSION: ". $SESSION->get_heap()->{CLASS}.", MESSAGE: ".$message);
    $self->{DATA_ID2REPLY}->{$id} = [ $message, $SESSION ];

    # Schedule a timeout
    POE::Kernel->delay('timeout_reply', 30, $id);
    
}

#######################################
# Timeout a message that is waiting
# for reply
sub __timeout_reply {
#######################################
    my ($self, $id) = @_[ OBJECT, ARG0 ];

    # If this reply is defined, reply now
    # Otherwise, just ignode
    if (defined $self->{DATA_ID2REPLY}->{$id}) {

        log_debug("Found reply for ID $id: SESSION: ".$self->{DATA_ID2REPLY}->{$id}->[1]->get_heap()->{CLASS}.", MESSAGE: ".$self->{DATA_ID2REPLY}->{$id}->[0]);

        # Reply with timeout
        POE::Kernel->call($self->{DATA_ID2REPLY}->{$id}->[1], $self->{DATA_ID2REPLY}->{$id}->[0], {
            from => "",
            type => 'error',
            code => 408,
            raw => undef,
            id => $id,
            data => "Message timed out",
            timeout => 1
        });                

        # Done!
        delete $self->{DATA_ID2REPLY}->{$id};   

    }
}

#######################################
# Shorthand to send send an IQ message
# If "tag" equals to "", then the RAW
# data of "$data" variable will be sent
sub send_iq {
#######################################
    my ($self, $packet, $type, $tag, $xmlns, $data) = @_; 
    my $XMPPCon = $self->{XMPPCon};
    
    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    $iq->SetFrom($packet->GetTo());
    $iq->SetTo($packet->GetFrom());
    $iq->SetType($type);
    $iq->SetID($packet->GetID());
    
    # Prepare XML
    my $xml;
    if ($tag eq "") {
    	
        	# use RAW xml response
        $xml = $iq->GetTree();
        $xml->add_raw_xml($data);
    	
    } else {
    	
    	    # Use structured XML response
        log_debug("Using Structured XML Construction");
	    my $query = new XML::Stream::Node($tag);
	    $query->put_attrib(
	         xmlns => $xmlns
	    );
	    
	    $query->add_raw_xml($data);
	    
	    $xml = $iq->GetTree();
	    $xml->add_child($query);
	    
    }            
            
    # And send
    log_debug("Sending Quick IQ Response XML: ".$xml->GetXML());
    $XMPPCon->Send($xml);
}

#######################################
# Compares permissions array agains
# the permissions hash received from
# the security module (LDAPAuth)
#
# First parameter is an array with
# the permissions you want to check.
# Permissions can be prefixed with:
#
#  ~ : Use OR operator instead of AND
#  ! : Reverse matching permission
#
# Example:
#
# [ 'read', '!admin', '~sysadmin' ]
#
# Translates to:
# 
#  Users with read permissions AND NO admin permissions
#  OR sysadmin permissions.
#
# The second parameter is a hash with
# the permissions in true/false format.
#
# Example:
# {
#    any => 1,
#    read => 1,
#    write => 0
# }
#
#--------------------------------------
sub check_permissions {
#######################################
    my ($rules, $permissions) = @_;
    my $first = 1;
    my $res = 1;
    foreach my $r (@$rules) {
        my $m_mode = '+'; # +: AND, ~: OR
        my $m_not = 0;    # !: NOT
        if ($r =~ m/!?~.*/) { $m_mode = '~'; $r=~ s/~//;  };
        if ($r =~ m/!.*/) { $m_not = 1; $r=~s/!//; };
 
        # Apply the logic
        my $in = $permissions->{$r};
        if ($m_not) { $in =!$in; };
        if ($m_mode eq '+') {
            $res = $res && $in;
        } elsif ($m_mode eq '~') {
            $res = $res || $in;
        }

        # Invalid? Quit
        return 0 if (!$res);
    }

    # Return result
    return $res;
}


#######################################
# A local function to generate UIDs
my $LAST_UID = 0;
sub get_uid {
#######################################
    return "uid" . (++$LAST_UID);
}

#######################################
# Parse a Net::XMPP::IQ object and convert
# it to the abstract hash, used by
# the comm system.
sub get_iq_hash {
#######################################
    my ($packet) = @_;

    # Packet MUST be an IQ message
    return undef unless UNIVERSAL::isa($packet, 'Net::XMPP::IQ');

    # Build initial fields
    my $res = {

        # Standard stuff 
        type => $packet->GetType,
        from => $packet->GetFrom,
        error => $packet->GetErrorCode,
        error_text => $packet->GetError,
        context => $packet->GetQueryXMLNS,

        # Parameters
        parameters => { },
        action => undef,
        data => undef
        
    };

    # Return the hash we got already if we have no body
    return $res if not defined $packet->GetQuery;

    # Populate parameters
    my $tree = $packet->GetQuery()->GetTree();
    my $e_archipel = undef;
    foreach (@{$tree->children()}) {
        if ($_->get_tag() eq 'archipel') {
            $e_archipel=$_;
            last;
        }
    }
    return undef if (!defined $e_archipel); # Could not find an 'archipel' node

    # Process <archipel /> node
    $res->{parameters} = $e_archipel->attrib();
    if (defined $res->{parameters}->{action}) {
        $res->{action} = $res->{parameters};
        delete $res->{parameters}->{action};
    }

    # Process payload
    if ($e_archipel->XPathCheck("opt")) {

        # Revert numeric tags and attributes
        my $xml = $e_archipel->XPath('opt')->GetXML;
        	$xml =~ s/num:d(\d+)/$1/g;

        # Parse data
        $res->{data} = XMLin($xml);
        
    } elsif ($e_archipel->XPathCheck("json")) {

        # Fetch object from json
        $res->{data} = decode_json($e_archipel->XPath('json')->get_cdata);

    } elsif ($e_archipel->get_cdata() ne '') {
        $res->{data} = $e_archipel->get_cdata;
        
    } else {
        $res->{data} = $e_archipel->GetXML;
    }

    # Return the hash
    return $res;

}

#######################################
# Send a presence object
sub send_presence {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    my $pr =new Net::XMPP::Presence();

    $pr->SetTo($packet->{to});
    $pr->SetFrom($packet->{from});

    # Set ID if defined
    my $msgID;
    if (defined $packet->{id}) {
        $msgID=$packet->{id};
    } else {
        $msgID=get_uid();
    }
    $pr->SetID($msgID);
    
    # Create a query object
    my $node = $pr->GetTree();

    # Append data
    if (defined $packet->{data}) {

        if (UNIVERSAL::isa($packet->{data}, 'HASH')) {
            log_debug("Appending Hash-To-XML payload: " . XMLout($packet->{data}));
            $node->add_raw_xml(XMLout($packet->{data}));
            
        } elsif (UNIVERSAL::isa($packet->{data}, 'XML::Stream::Node')) {
            log_debug("Appending RAW XML::Stream::Node payload: " . $packet->{data}->GetXML());
            $node->add_child($packet->{data});
            
        } else {
            log_debug("Appending String payload: " . $packet->{data});
            $node->add_raw_xml($packet->{data});
            
        }
        
    }
    
    # And send
    log_debug("Sending presence node: " . $node->GetXML());
    $XMPPCon->Send($node);

}

#######################################
# Send a packet to the network
# (Used to unify comm_reply and comm_send)
sub send_packet {
#######################################
    my ($self, $packet, $replyTo) = @_;
    my $XMPPCon = $self->{XMPPCon};
        
    # Extract the interesting data from the packet
    if (UNIVERSAL::isa($packet, 'HASH')) {
        
        log_debug("Sending a HASH objet");
        
        # Prepare packet defaults
        my $data = $packet;
        $data->{context} = 'chat:command' unless defined $data->{context};
                
        # Handle the very simple chat:text context
        if ($data->{context} eq 'chat:text') {

            # use Message packet in this case
            log_debug("Sending text chat message");

            # Chat-specific defaults
            $data->{type} = 'chat' unless defined $data->{type};      

            # Build body
            my $body = "";
            if (defined $data->{data}) {
                # If we have defined data, just send the string representation
                if (UNIVERSAL::isa($data->{data}, 'HASH') || UNIVERSAL::isa($data->{data}, 'ARRAY')) {
                    $body = to_json($data->{data}, {utf8 => 1, pretty => 1}); # Pretty representation => Human readable
                } else {
                    $body = $data->{data}
                }
            }
            
            # Send the packet
            $XMPPCon->MessageSend(
                to => $data->{to},
                body => $body,
                type => $data->{type}
            );

            # Chat messages do not have reply. If we have a replyTo, send a successful reply now
            POE::Kernel->call($iAgent::Kernel::LAST_SOURCE, $replyTo, {
                from => $data->{to},
                type => 'success',
                raw => undef,
                id => 0,
                timeout => 0
            });

        # Handle shouts
        } elsif ($data->{context} eq 'chat:shout') {

            # use Message packet in this case
            log_debug("Sending shout text message");

            # Chat-specific defaults
            $data->{type} = 'headline' unless defined $data->{type};      

            # Build body
            my $body = "";
            if (defined $data->{data}) {
                # If we have defined data, just send the data as-is             
                $body = $data->{data}
            }
            
            # Send the packet
            $XMPPCon->MessageSend(
                to => $data->{to},
                body => $body,
                type => $data->{type}
            );

            # Chat messages do not have reply. If we have a replyTo, send a successful reply now
            POE::Kernel->call($iAgent::Kernel::LAST_SOURCE, $replyTo, {
                from => $data->{to},
                type => 'success',
                raw => undef,
                id => 0,
                timeout => 0
            });

        # Handle the more elaborate chat:json context
        } elsif ($data->{context} eq 'chat:json') {

            # use Message packet in this case
            log_debug("Sending text chat message");

            # Chat-specific defaults
            $data->{type} = 'chat' unless defined $data->{type};      

            # Build response object
            my $response = {};
            $response->{parameters} = $data->{parameters}   unless not defined($data->{parameters});
            $response->{data} = $data->{data}               unless not defined($data->{data});
            $response->{action} = $data->{action}           unless not defined($data->{action});
            

            # Send the packet
            $XMPPCon->MessageSend(
                to => $data->{to},
                body => encode_json($response),
                type => $data->{type}
            );

            # Chat messages do not have reply. If we have a replyTo, send a successful reply now
            POE::Kernel->call($iAgent::Kernel::LAST_SOURCE, $replyTo, {
                from => $data->{to},
                type => 'success',
                raw => undef,
                id => 0,
                timeout => 0
            });
        
        # Handle the advanced chat:command context
        } elsif ($data->{context} eq 'chat:command') {
            
            # use Message packet in this case
            log_debug("Sending generic chat message");

            # Chat-specific defaults
            $data->{type} = 'chat' unless defined $data->{type};      
            
            # Try to build content
            my $body = '';
            
            if (defined $data->{data}) {
                
                # If we have defined data, just send the data as-is             
                $body = $data->{data}
                
            } else {
                
                $body = $data->{action};
                
                # Otherways, build a command-line syntax
                if (UNIVERSAL::isa($data->{parameters}, 'ARRAY')) {
                    foreach my $cmd (@{$data->{parameters}}) {
                        if($cmd =~ m/"/) {
                            $body .= " \"$cmd\"";
                        } else {    
                            $body .= " $cmd";
                        }
                    }
                } elsif (UNIVERSAL::isa($data->{parameters}, 'HASH')) {
                    foreach my $parm (keys %{$data->{parameters}}) {
                        my $cmd = $data->{parameters}->{$parm};
                        $body .= " -$parm";
                        if($cmd =~ m/"/) {
                            $body .= " \"$cmd\"";
                        } else {    
                            $body .= " $cmd";
                        }
                    }
                };
                
            }
            
            # Send the packet
            $XMPPCon->MessageSend(
                to => $data->{to},
                body => $body,
                type => $data->{type}
            );          

            # Chat messages do not have reply. If we have a replyTo, send a successful reply now
            POE::Kernel->call($iAgent::Kernel::LAST_SOURCE, $replyTo, {
                from => $data->{to},
                type => 'success',
                raw => undef,
                id => 0,
                timeout => 0
            });
            
            
        } else {
            # Otherwise use IQ messages
            
            log_debug("Sending IQ message");
            
            # IQ-Specific Defaults
            $data->{type} = 'set' unless defined $data->{type};
            $data->{parameters} = { } unless defined $data->{parameters};
            
            # Prepare the proper XML contents for the packet
            log_debug("Preparing IQ to ".$data->{to}." type: ".$data->{type});
            my $iq = new Net::XMPP::IQ();
            $iq->SetTo($data->{to});
            $iq->SetType($data->{type});

            # Set ID if defined
            if (defined $data->{id}) {
                $LAST_IQ_ID=$data->{id};
            } else {
                $LAST_IQ_ID=get_uid();
            }
            $iq->SetID($LAST_IQ_ID);
            
            # Create a query object
            my $query;
            if ((defined $data->{noquery}) and ($data->{noquery} == 1)) {
                $query = $iq->GetTree();
            } else {
                my $qName = 'query';
                $qName = $data->{nodeName} if (defined $data->{nodeName});
            
	            log_debug("Preparing <$qName /> node");
	            $query = new XML::Stream::Node($qName);
	            $query->put_attrib(
	                xmlns => $data->{context}
	            );
            }
            
            # Create an action object if we have an action specified
            my $node = $query;
            if (defined $data->{action}) {
	            log_debug("Preparing <archipel /> node");
	            my $action = new XML::Stream::Node('archipel');
	            $action->put_attrib(%{$data->{parameters}});
	            $action->put_attrib(
	                action => $data->{action}
	            );
	            $node = $action;
                $query->add_child($action);
            }
            
            # Append extra payload if we have defined 'data'
            if (defined $data->{data}) {
            	
            	# Automatically detect the input and produce
            	# valid XML no matter what...
            	
                if (UNIVERSAL::isa($data->{data}, 'XML::Stream::Node')) {
                	# Standard XML::Stream::Node
                    log_debug("Appending RAW XML::Stream::Node payload");
                    $node->add_child($data->{data});
                    
                } elsif (UNIVERSAL::isa($data->{data}, 'HASH')) {
                        my $xml='';
                    	
                    	# HASH Reference? Check how to create the XML
                    	if (!defined($data->{encode}) || ($data->{encode} eq 'xml')) {
                    	    # Use XML (Generates <opt> tag)
                        	$xml = XMLout($data->{data}, NoIndent => 1);

                        	# There is a case we might encounter a numeric
                        	# tag, like: <2 ... />. In this case it should
                        	# be converted into the format: <_2 ... />
                        	# wich is valid by the XML standards.
                        	$xml =~ s/<(\d+\s)/<num:d$1/g;
                        	$xml =~ s/\s(\d+)=/num:d$1=/g;
                    	    
                    	} elsif ($data->{encode} eq 'json') {
                    	    
                    	    # Use JSON (Generates <json> tag)
                    	    $xml = '<json>'.to_json($data->{data}, {utf8 => 1, pretty => 0}).'</json>';
                    	    
                    	}
                	
                    log_debug("Appending Structured XML payload: ".$xml);
                    $node->add_raw_xml($xml);
                    
                } else {
                    	# Scalar? Check for XML Formatting
                    	if ($data->{data} =~ m!^<.*>$!s) {
                    		
                    		# Looks like XML (Starts with < and ends with >)
                    		# Assume that's a valid XML and send it!
                    		# TODO: Use validator
                            log_debug("Appending RAW XML payload: ".$data->{data});
                            $node->add_raw_xml($data->{data});
                    		
                    	} else {
                    		
                    		# Looks like CDATA Payload
                            log_debug("Appending CDATA payload: ".$data->{data});
                            $node->add_cdata($data->{data});
                            
                    	}
                }
            }
            
            # Nest
            log_debug("Nesting objects to create IQ message");
            my $xml = $iq->GetTree();
            if ((defined $data->{noquery}) and ($data->{noquery} == 1)) {
               	$xml = $query; 
            } else {
                $xml->add_child($query);
            }
            
            log_debug("Sending IQ XML: ".$xml->GetXML(). " (ID=".$iq->GetID().")");

            # If we have requested a reply handler, set it up now
            $self->bind_id_reply($LAST_IQ_ID, $replyTo) if (defined $replyTo);
            
            # And send
            $XMPPCon->Send($xml);
            
        }
        
    } else {
        
        # Send the raw packet as-is
        $XMPPCon->Send($packet->{raw});
        
    }
}

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                       CORE EVENT HANDLERS & CONNECTION MAINTENANCE                                          | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

###########################################
#+---------------------------------------+#
#|            EVENT HANDLERS             |#
#|                                       |#
#| All the functions prefixed with '__'  |#
#| are handling the respective event     |#
#+---------------------------------------+#
###########################################

############################################
# A delegate function that is forced into
# every plugin's POE session that handles
# the comm_action message and dispatches it
# to the module handlers accordingly.
#
# (This is used in order to preserve the
#  iAgents module's priority stack)
#
# AKA: We are using this function, in order
# to allow other modules with higher priority
# to trap the event and modify or abort it.
#
sub XMPP_DELEGATE {
###########################################
    my ($kernel, $session, $heap, $packet, $replyTo) = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    # If we have no permissions, something's wrong
    if (!defined $packet->{permissions}) {
        log_warn("A comm_action packet does not contain permissions! Please make sure an authentication module is loaded!");
        iAgent::Kernel::Reply('comm_reply_error', { type => 'forbidden', code => 401, message => 'You do not have permission to perform '.$packet->{context}."::".$packet->{action}."/".$packet->{type} });    	
        return RET_ABORT;
    }

    # Check if the action will be handled
    my $handled=0;
    my $ans=undef;

    # (Now, LAST_MESSAGE is properly adjusted by the plugin stack)
    	# Post the customized messages
    	my $CACHE = $heap->{XMPP}->{CACHE};
    	if (defined $CACHE->{$packet->{context}} &&
    	    defined $CACHE->{$packet->{context}}->{$packet->{type}} &&
    	    defined $CACHE->{$packet->{context}}->{$packet->{type}}->{$packet->{action}}) {
        my $failed=0;

        # Direct broadcast to all modules
    	    foreach my $h (@{$CACHE->{$packet->{context}}->{$packet->{type}}->{$packet->{action}}}) {
            $handled=1;

            # Check permissions
            if (!check_permissions($h->{permissions}, $packet->{permissions})) {
                $failed=1;
            } else {

                # Check if we have parameter requirements
                my $valid=1; my $missing_parm='';
                if (defined $h->{parameters}) {
                    foreach my $p (@{$h->{parameters}}) {
                        if (UNIVERSAL::isa($p, 'HASH')) { # HASH is used for re-mapped values: {key => new_key}
                            my ($k) = keys %$p;
                            my $km = $p->{$k};
                            if (!defined $packet->{parameters}->{$k}) {
                                $valid=0;
                                $missing_parm=$k;
                                last;
                            } else {
                                # Map to another key
                                $packet->{parameters}->{$km} = $packet->{parameters}->{$k};
                                delete $packet->{parameters}->{$k};
                            }
                        } else {
                            if (!defined $packet->{parameters}->{$p}) {
                                $valid=0;
                                $missing_parm=$p;
                                last;
                            }
                        }
                    }
                }

                # Check if the parameter validation was successful
                if (!$valid) {
                    log_warn("Missing parameter \"$missing_parm\" for command ".$packet->{context}."::".$packet->{action}."/".$packet->{type});
                    iAgent::Kernel::Reply('comm_reply_error', { type => 'bad-request', code => 400, message => "Missing parameter \"$missing_parm\" for command ".$packet->{context}."::".$packet->{action}."/".$packet->{type} });    	
                } else {
                    # Yield message to my session
                    $ans=$kernel->call($session, $h->{message}, $packet, $replyTo);
        	        return RET_ABORT if ((defined $ans) && ($ans == 0));
        	    }
            }

	    }

	    # If filed, reply falure message
	    if ($failed) {
            log_warn("Remote user does not have permissions to perform action ".$packet->{context}."::".$packet->{action}."/".$packet->{type});
            iAgent::Kernel::Reply('comm_reply_error', { type => 'forbidden', code => 401, message => 'You do not have permission to perform '.$packet->{context}."::".$packet->{action}."/".$packet->{type} });    	
	    }

    }
        
    # If not handled, call the default handler(s)
    if (!$handled) {
        if (defined $CACHE->{$packet->{context}} && defined $CACHE->{$packet->{context}}->{$packet->{type}} && defined $CACHE->{$packet->{context}}->{$packet->{type}}->{default}) {
            log_info("Forwarding default message to " . $CACHE->{$packet->{context}}->{$packet->{type}}->{default});
	        $handled=1;
	        $kernel->yield($CACHE->{$packet->{context}}->{$packet->{type}}->{default}, $packet, $replyTo);
        }
        if (defined $CACHE->{$packet->{context}} && defined $CACHE->{$packet->{context}}->{default}) {
            log_info("Forwarding default message to " . $CACHE->{$packet->{context}}->{default});
	        $handled=1;
	        $kernel->yield($CACHE->{$packet->{context}}->{default}, $packet, $replyTo);
        }
        if (defined $CACHE->{default}) {
            log_info("Forwarding default message to " . $CACHE->{default});
	        $handled=1;
	        $kernel->yield($CACHE->{default}, $packet, $replyTo);
        }
    }

    # Return appropriate value on the message bus
    if ($handled) {
        # If handled, return what the handler returned
        return $ans;
    } else {
        # If we were not handled, make kernel think we were never called!
        # (This is used in order to generate a '501:feature-not-implemented' error if noone else responds)
        return RET_PASSTHRU;
    }
            	    
}

###########################################
# All modules loaded
#
# This function process the mnifests of all modules
# and builds the manifest cache that is used 
# to trigger the appropriate messages on
# every module, with the appropriate ACLs
#
# Parameters processed:
#
# MANIFEST => {
#   ...
#
#   # GLOBAL Module minimum permissions
#   permissions => [ 'perm', ... ],
#
#   # Jabber messages routing
#   XMPP => {
#      permissions => [ 'perm', ... ],
#      <context> => {
#           permissions => [ 'perm', ... ],
#           <type> => {
#               permissions => [ 'perm', ... ],
#               <action> => "message"
#               .. or ..
#               <action> => {
#                   permissions => [ 'perm', ... ],
#                   message => "message"

#                   parameters => [ 'parm', 'parm' ... ],
#                   .. or ..
#                   parameters => [ {parm => 'mapped_name'}, .. ]
#               }
#           }
#      }
#   }
#
#   ...
# }
#
#
sub __ready {
###########################################
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    my (@P_SESSION, @P_GLOBAL, @P_CONTEXT, @P_TYPE, @P_ACTION);
    my ($D_GLOBAL, $D_CONTEXT, $D_TYPE);

    # Build the manifest cache
    for my $inf (@iAgent::Kernel::SESSIONS) {
        my $heap = $inf->{session}->get_heap();
        my $manifest = $heap->{MANIFEST};
        my $cache = { };
        
        # Fetch the session permissions if exists
        if (defined $manifest->{permissions}) {
            @P_SESSION = @{$manifest->{permissions}};
        }
        
        # Fetch XMPP messages        	
        if (defined $manifest->{XMPP}) {

            log_debug("Registering XMPP message relays for ".$heap->{CLASS});

            # Reset global variables
            $D_GLOBAL = undef;
            @P_GLOBAL = ( );

            $D_GLOBAL = $manifest->{XMPP}->{default};
            if (defined $manifest->{XMPP}->{permissions}) {
                @P_GLOBAL = @{$manifest->{XMPP}->{permissions}};
            } else {
                @P_GLOBAL = ( );
            }
                    
            foreach my $CTX (keys %{$manifest->{XMPP}}) {  ### CONTEXT 
                
                if (($CTX ne 'permissions') && ($CTX ne 'default')) {
                
                    foreach my $TYP (keys %{$manifest->{XMPP}->{$CTX}}) { ### TYPE

                        # Get context default and permissions
                        $D_CONTEXT = $manifest->{XMPP}->{$CTX}->{default};
                        if (defined $manifest->{XMPP}->{$CTX}->{permissions}) {
                            @P_CONTEXT = @{$manifest->{XMPP}->{$CTX}->{permissions}};
                        } else {
                            @P_CONTEXT=( );
                        }

                        if ( ($TYP ne 'permissions') && ($TYP ne 'permissions') ) {

                            # Process actions
                            foreach my $A (keys %{$manifest->{XMPP}->{$CTX}->{$TYP}}) { ### ACTION 

                                $D_TYPE = $manifest->{XMPP}->{$CTX}->{$TYP}->{default};
                                if (defined $manifest->{XMPP}->{$CTX}->{$TYP}->{permissions}) {
                                    @P_TYPE = @{$manifest->{XMPP}->{$CTX}->{$TYP}->{permissions}};
                                } else {
                                    @P_TYPE=( );
                                }

                                if ( ($A ne 'permissions') && ($A ne 'default') ) {
                                
                                    my $V = $manifest->{XMPP}->{$CTX}->{$TYP}->{$A};
                                    my $msg = '';

                                    # Check hash or string mode
                                    if (UNIVERSAL::isa($V, 'HASH')) {
                                        $msg = $V->{message} unless not defined $V->{message};
                                        @P_ACTION = @{$V->{permissions}} unless not defined $V->{permissions};                                    
                                    } else {
                                        @P_ACTION = ( );
                                        $msg = $V;
                                        $V = {};
                                    }

                                    # Get only unique entries
                                    my @LIST = (@P_GLOBAL, @P_SESSION, @P_CONTEXT, @P_TYPE, @P_ACTION);
                                    my %hash   = map { $_ => 1 } @LIST;
                                    my @permissions = keys %hash;

                                    # Update cache
                                    $cache->{$CTX} = { } unless defined $cache->{$CTX};
                                    $cache->{$CTX}->{$TYP} = { } unless defined $cache->{$CTX}->{$TYP};
                                    $cache->{$CTX}->{$TYP}->{$A} = [ ] unless defined $cache->{$CTX}->{$TYP}->{$A};

                                    # Push cached action entry
                                    $V->{message} = $msg;
                                    $V->{permissions} = \@permissions;
                                    push @{$cache->{$CTX}->{$TYP}->{$A}}, $V;

                                    log_debug( "Proxying action ${CTX}::${A}/$TYP with permissions [@permissions] to " . $heap->{CLASS} . "->$msg" );
                                        
                                } # Else
                                
                            } # Foreach

                        } # Else
                        
                        # Update default type action
                        $cache->{$CTX}->{$TYP}->{default} = $D_TYPE;
                        
                    } # Foreach

                } # Else
                
                # Update default context action
                $cache->{$CTX}->{default} = $D_CONTEXT;

            } # Foreach

            # Update default action
            $cache->{default} = $D_GLOBAL;

            # Store cache to heap
            $heap->{XMPP}->{CACHE} = $cache;

            # Register delegate function on comm_action event
            $inf->{session}->_register_state('comm_action', \&XMPP_DELEGATE );
			iAgent::Kernel::RegisterHandler($inf->{session}, 'comm_action');
        	
        } #If defined XMPP
    }

    # Everything is ready to start. Connect now...    
	$kernel->yield( 'connect' );
    
}

###########################################
# Connect to XMPP
sub __main { # Handle 'main'
###########################################
    my ($self, $kernel) = @_[ OBJECT, KERNEL ];
    my $XMPPCon = $self->{XMPPCon};

    # If we are killed, exit
    return if ($self->{killed});

    # Process incoming message
	my $res = $XMPPCon->Process(0);
	
	# Detect for recoverable errors
	if (!defined($res)) {
		
		# Get failure info
		my $err = $XMPPCon->GetErrorCode();
		
		# Connection failed?
		log_warn("XMPP Connection lost! Error: ".$self->real_error());
		
		# Broadcast disconnect
        Broadcast('comm_disconnect');
		
		# Broadcast recoverable error
        Broadcast('comm_error', { message=> 'Connection lost', recoverable => 1 });
        
        # Disconnect and inform the XMPP module that we handled the error
        $XMPPCon->Disconnect();
	    $XMPPCon->{PROCESSERROR} = 0;
		
	    # Put module in standby 
	    $kernel->delay( _standby => 1 );
		
	} else {
		
		# Everything OK? Loop...
        # This tiny delay is needed to avoid pointless CPU load
		$_[KERNEL]->delay('main' => 0.1);
	}

}

###########################################
# Connect to XMPP Server
sub __connect {	# Handle 'connect'
###########################################
    my ($self, $kernel) = @_[ OBJECT, KERNEL ];
    my $XMPPCon = $self->{XMPPCon};
    my $config = $self->{config};
    
    # Try to connect to the defined XMPP Server
    log_debug("Connecting to XMPP: ".$config->{XMPPServer});
    my $ans = $XMPPCon->Connect(hostname=>$config->{XMPPServer},
                      timeout=>10,
                      tls=>1);
    
    # Check for unrecoverable errors
	if (not defined $ans) {
		log_warn("Unable to connect to XMPP server! ");
		Broadcast('comm_error', { message=> 'Unable to connect to XMPP Server', recoverable => 1 });

		# Put module in standby
		$kernel->delay( _standby => 1 );

		# Exit event
		return RET_ABORT;
	}

    # Build my resource name
    my $host = hostname;
    $host=$config->{XMPPResource};

	# Authenticate on the XMPP server using my host name as resource
    log_debug("Setting XMPP user to: ".$config->{XMPPUser}.'@'.$config->{XMPPServer}.'/'.$host);
    my @res;
    eval {
	   @res = $XMPPCon->AuthSend(username=>$config->{XMPPUser},
                                    password=>$config->{XMPPPassword},
                                    resource=>$host);
    };
    if ($@) {
    	# If something goes really wrong, Net::XMPP Module just raises an exception
        log_warn("Something when wrong while trying to send auth: @_");
    	
        # Unrecoverable error. Crash module...
        Broadcast('comm_error', { message => 'Authentication error: '.$@, recoverable => 0 });

		# Put module in standby
		$kernel->delay( _standby => 1 );
		
        # Exit event
        #iAgent::Kernel::Crash('Authentication error: '.$@);
        return RET_ABORT;
    	
    };
    
	# Check for other errors
	my $result = \@res;
	if (!$result) {
		
        # Unrecoverable error. Crash module...
        Broadcast('comm_error', { message=> 'Connection lost', recoverable => 0 });

		# Put module in standby
		$kernel->delay( _standby => 1 );

        return RET_ABORT;
        
    } elsif ($result->[0] eq 'ok') {
		
		log_debug('XMPP Authenticated');
		Broadcast('comm_connected', {
			me => $config->{XMPPUser}.'@'.$config->{XMPPServer}.'/'.$host
		});
		$self->{me} = $config->{XMPPUser}.'@'.$config->{XMPPServer}.'/'.$host;

        # Send comm_ready only when we also have the user's list
        # Otherwise, send it 1 second after we authenticated
        $self->{ready}=0;
    		POE::Kernel->delay('_notify_ready' => 0.5);
		
	} elsif ($result->[0] eq 'error') {
		log_warn("Got connection error: ".$result->[1]);
		
		# If we are not authorized, *NOW* try to register
		if ($result->[1] eq 'not-authorized') {
		    
            # If told so, try to register
            if ($config->{XMPPRegister} == 1) {
                log_msg("User is not authorized, trying to register");
                
                # (1) Ask if we can register (And fetch registration-required fields)
                # -----
                my %info;
            	eval {
                	%info = $XMPPCon->RegisterRequest(
                	   to => $config->{XMPPServer}
                	);
            	};
                if ($@) {
                    # If something goes really wrong, Net::XMPP Module just raises an exception

                    # Unrecoverable error. Crash module...
                    Broadcast('comm_error', { message=> 'Registration error: '.$@, recoverable => 0 });
                    log_warn("Unable to perform registration request: $@");

            	    # Put module in standby
            	    $kernel->delay( _standby => 1 );

                    # Exit event
                    #iAgent::Kernel::Crash('Registration error: '.$@);
                    return RET_ABORT;

                }
                
                # (2) Populate registration fields
                # -----
                log_debug("Trying to register to the XMPP server");
            	my $fields = $info{fields};
            	delete $fields->{instructions} if defined($fields->{instructions});
            	my $vars = {};
            	for my $var (keys %{$fields}) {
            		$vars->{$var} = "";
            		$vars->{$var} = $config->{XMPPUser} if ($var eq "username");
            		$vars->{$var} = $config->{XMPPPassword} if ($var eq "password");
            	}

                # (3) Perform registration
                # -----
            	log_debug("Registering user");
                $vars->{to} = $config->{XMPPServer};
            	my @ans = $XMPPCon->RegisterSend(%{$vars});

            	# Check response
            	if ($ans[0] eq "409") {

                    log_debug("Username collision while trying to register the user. Considering this as a successful registration");

            	} elsif ($ans[0] ne "ok") {

                    log_warn("Unable to register to the XMPP Server! Error: ".$self->real_error());
                    Broadcast('comm_error', { message=> 'Unable to register to the XMPP Server', recoverable => 0 });

            	    # Put module in standby
            	    $kernel->delay( _standby => 1 );

            	    # And abort
                    return RET_ABORT;

            	} else{
                    log_msg("Registration to XMPP server was successful");
            		log_debug("Registration successful");
            	}

                # (4) Disconnect and restart connection
                # -----
        		log_debug("Restarting connection to complete registration");
        		$kernel->delay( _standby => 1 );
        		
        		# Do not send connected signal. Wait for restart...
        		return RET_ABORT;

            }
		    
		}
		
        # Unrecoverable error. Crash module...
        Broadcast('comm_error', { message=> 'Authentication error: '.$result->[1], recoverable => 0 });

		# Put module in standby
		$kernel->delay( _standby => 1 );
        return RET_ABORT;
		
	} else {
		
        # Unrecoverable error. Crash module...
        Broadcast('comm_error', { message=> 'Unknown response code:'.$result->[0], recoverable => 0 });

		# Put module in standby
		$kernel->delay( _standby => 1 );

        #iAgent::Kernel::Crash('Authentication error: '.$result->[1]);
        return RET_ABORT;
        
	}

    # Connect/Initialize sub-modules
    iAgent::Module::XMPP::Roster::connected($self, $XMPPCon);
    iAgent::Module::XMPP::VCard::connected($self, $XMPPCon);

	# Send presence with capabilities
	my $caps_iq =new Net::XMPP::Presence();
	my $caps_xml = new XML::Stream::Node('c');
	$caps_xml->put_attrib(
		xmlns => 'http://jabber.org/protocol/caps',
        hash => 'sha-1',
        node => 'http://cernvm.cern.ch/iagent',
        ver => 'FlSbCphM5VnDqER82NNChWn8ooY='
	);
	$caps_iq->AddChild($caps_xml);
	log_debug("Sending extended presence with capabilities: ".$caps_iq->GetXML());
	$XMPPCon->Send($caps_iq);
	
	# Start the event processing loop
    log_msg("XMPP Connected and ready");
	$_[KERNEL]->yield('main');
}

############################################
# Session stopped
sub ___stop { # Handle '_stop'
############################################
    my ($self) = @_;
    my $XMPPCon = $self->{XMPPCon};
    
    log_debug('Disconnecting XMPP');
    
    # Trigger the disconnect event
    log_msg("XMPP Disconnected");
    Broadcast('comm_disconnect');
    
    # Shut down XMPP
    $self->leave_all_groups();
    $XMPPCon->PresenceSend(type=>"unavailable");
    $XMPPCon->Disconnect();
    
    log_msg('XMPP Module stopped');
}

############################################
# Standby waiting for reconnect
sub ___standby { # Handle '_standby'
############################################
    my ($self, $kernel) = @_[ OBJECT, KERNEL ];
    my $XMPPCon = $self->{XMPPCon};

    # TODO: Cleanup scripts
    $XMPPCon->Disconnect();    
    $XMPPCon->{PROCESSERROR} = 0;

    # Try to connect again
    $kernel->yield('connect');
    
}


############################################
# Internal function that notifies that 
# everything is ready (Also the users list
# is updated)
sub ___notify_ready {
############################################
    my ($self, $kernel) = @_[ OBJECT, KERNEL ];
    return if ($self->{ready});

    # We are ready
    Broadcast("comm_ready", $self->{me});
    $self->{ready}=1;
}

## =========================================================================================================================== ##
##                                              INCOMING MESSAGE HANDLERS                                                      ##
## =========================================================================================================================== ##

############################################
# Reply to the last sent message
sub __comm_reply { # Handle comm_reply
############################################
    my ($self, $packet, $replyTo) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};
    if ($LAST_MESSAGE_TYPE == 0) {
    	log_debug("comm_reply was requested, but no message was arrived!");
        	return RET_ABORT;
    }

    # Replied :)
    $PENDING_REPLY = 0;    

    # Reply to specific
    $_[ KERNEL ]->yield('comm_reply_to', $LAST_MESSAGE, $packet, $replyTo);
        
    return RET_OK; # Ok, continue if needed
}


############################################
# Reply to specified sent message
sub __comm_reply_to { # Handle comm_reply_to
############################################
    my ($self, $message, $packet, $replyTo) = @_[ OBJECT, ARG0, ARG1, ARG2 ];
    my $XMPPCon = $self->{XMPPCon};
    
    # Normal chat message?
    if (substr($message->{context},0,5) eq 'chat:') {
    	
    	    # Just replace 'to'
        my $data = $packet;
        	$data->{to} = $message->{from};
    	 
        # Send the packet
        $self->send_packet($data, $replyTo);
    	 
    # IQ Message?
    } else {
    	
        	# Create a proper IQ reply
        log_debug("Sending IQ reply");

        # Replace all the required parameters from the previous message        
        my $data = $packet;
        $data->{context} = $message->{context};
        $data->{type} = 'result';
        $data->{type} = 'error' if defined $data->{type} and $data->{type} eq 'error';
        $data->{to} = $message->{from};
        $data->{from} = $message->{to};
        $data->{id} = $message->{id};
        $data->{noquery} = 1;
        
        # Send the packet
        $self->send_packet($data, $replyTo);    	
    }
    
    return RET_OK; # Ok, continue if needed
}

############################################
# Reply to the last sent message with an error
sub __comm_reply_error { # Handle comm_reply_error
############################################
    my ($self, $data, $replyTo) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};
    if ($LAST_MESSAGE_TYPE == 0) {
        log_debug("comm_reply_error was requested, but no message was arrived!");
        return RET_ABORT;
    }
    
    # Replied :)
    $PENDING_REPLY = 0;    
    
    # Prepare error defaults
    $data->{action} = "cancel" unless defined $data->{action};
    $data->{type} = "internal-server-error" unless defined $data->{type};
    $data->{xmlns} = "urn:ietf:params:xml:ns:xmpp-stanzas" unless defined $data->{xmlns};
    
    # Normal chat message?
    if ($LAST_MESSAGE_TYPE == 1) {
        
        # Prepare message
        my $msg = $data->{type}."!";
        $msg.=" (Code ".$data->{code}.")" if defined $data->{code};
        $msg.=" ".$data->{message} if defined $data->{message};
        
        # Just replace 'to'
        my $data = {
        	context => $LAST_MESSAGE->{context},
        	data => $msg
        };
        $data->{to} = $LAST_MESSAGE->{from};
         
        # Send the packet
        $self->send_packet($data, $replyTo);
         
    # IQ Message?
    } elsif ($LAST_MESSAGE_TYPE == 2) {
        
        # Create a proper IQ reply
        log_debug("Sending IQ error reply");
        
        # Prepare XML
        my $xml = "<error type='".encode_entities($data->{action})."'";
        $xml.=" code='".$data->{code}."'" if defined $data->{code};
        $xml.="><".$data->{type}." xmlns='".encode_entities($data->{xmlns})."' />";
        if (defined $data->{message}) {
        	$xml.="<text xmlns='url:ietf:params:xml:ns:xmpp-stanzas' xml:lang='en'>".encode_entities($data->{message})."</text>";
        }
        $xml.="</error>";

        # Append error to the request data end send back
        $self->send_iq($LAST_MESSAGE->{raw}, 'error', '', '', 
                       $LAST_MESSAGE->{raw_query}->GetXML().$xml);
        
    }
    
    return RET_OK; # Ok, continue if needed
}

############################################
# Send a packet
sub __comm_send { # Handle 'comm_send'
############################################
    my ($self, $packet, $replyTo) = @_[ OBJECT, ARG0, ARG1 ];

    # Send the packet
    $self->send_packet($packet, $replyTo);
    
    return RET_OK; # Ok, continue if needed
}


###

############################################
# Send a synchronous action
#
# ------------------------------------------------
#  A small delegate to perform asynchronous call
#  to 'comm_action'
sub ___async_send_action { iAgent::Kernel::Dispatch('comm_action', $_[ ARG0 ]); }
# ------------------------------------------------
#
sub __comm_send_action { # Handle 'comm_send_action'
############################################
    my ($self, $packet, $replyTo) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate
    exit RET_ABORT unless defined ($packet->{to});
    exit RET_ABORT unless defined ($packet->{action});
    $packet->{type}='get' unless defined($packet->{type});
    $packet->{context}='archipel:dummy' unless defined($packet->{context});
    $packet->{async}=0 unless defined($packet->{async});

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    $iq->SetFrom($self->{me});
    $iq->SetTo($packet->{to});
    $iq->SetType($packet->{type});
    #$iq->SetID(get_uid());
    if ($packet->{type} eq 'error') {
        $iq->SetErrorCode($packet->{error}) if defined($packet->{error});
        $iq->SetError($packet->{error_text}) if defined($packet->{error_text});
    }

    # Build query and archipel node
    my $e_query = $iq->NewChild(XMLARCHIPEL_QUERY);
    my $e_archipel = new XML::Stream::Node('archipel');

    # Populate fields
    if (defined $packet->{parameters}) {
        foreach (keys %{$packet->{parameters}}) {
            $e_archipel->put_attrib($_ => $packet->{parameters}->{$_});
        }
    }
    $e_archipel->put_attrib("action", $packet->{action});

    # Append extra payload if we have defined 'data'
    if (defined $packet->{data}) {

        # Automatically detect the input and produce
        # valid XML no matter what...

        if (UNIVERSAL::isa($packet->{data}, 'XML::Stream::Node')) {
	        # Standard XML::Stream::Node
            log_debug("Appending RAW XML::Stream::Node payload");
            $e_archipel->add_child($packet->{data});
            
        } elsif (UNIVERSAL::isa($packet->{data}, 'HASH')) {
                my $xml='';
        	
            	# HASH Reference? Check how to create the XML
            	if (!defined($packet->{encode}) || ($packet->{encode} eq 'xml')) {
            	    # Use XML (Generates <opt> tag)
                	$xml = XMLout($packet->{data}, NoIndent => 1);

                	# There is a case we might encounter a numeric
                	# tag, like: <2 ... />. In this case it should
                	# be converted into the format: <_2 ... />
                	# wich is valid by the XML standards.
                	$xml =~ s/<(\d+\s)/<num:d$1/g;
                	$xml =~ s/\s(\d+)=/num:d$1=/g;
        	    
            	} elsif ($packet->{encode} eq 'json') {
        	    
            	    # Use JSON (Generates <json> tag)
            	    $xml = '<json>'.to_json($packet->{data}, {utf8 => 1, pretty => 0}).'</json>';
        	    
            	}
	
            log_debug("Appending structured hash data: $xml");
            $e_archipel->add_raw_xml($xml);
            
        } else {
            	# Scalar? Check for XML Formatting
            	if ($packet->{data} =~ m!^<.*>$!s) {
            		
            		# Looks like XML (Starts with < and ends with >)
            		# Assume that's a valid XML and send it!
            		# TODO: Use validator
                    log_debug("Appending RAW XML payload: ".$packet->{data});
                    $e_archipel->add_raw_xml($packet->{data});
            		
            	} else {
            		
            		# Looks like CDATA Payload
                    log_debug("Appending CDATA payload: ".$packet->{data});
                    $e_archipel->add_cdata($packet->{data});
            	}
        }
    }

    # Update query
    $e_query->SetRaw($e_archipel->GetXML);
    $e_query->SetXMLNS($packet->{context});

    # Send and wait for anwer
	my $ans = $XMPPCon->SendAndReceiveWithID($iq, 10);

    # Could not receive something? Asume it never sent
    return RET_ABORT unless defined $ans;

    # Check statis
    if ($ans->GetType eq 'result') {

        # Create response hash in the request 
        $packet->{response} = get_iq_hash($ans);
        
        # And also dispatch a send_action asynchronously
        $_[KERNEL]->yield( '_async_send_action', $packet->{response});
        return RET_OK;

    } elsif ($ans->GetType eq 'error') {
    
        $packet->{error} = $ans->GetErrorCode;
        $packet->{error_text} = $ans->GetError;        
        return RET_ERROR;
        
    } else {

        # Something went really wrong
        log_warn("Something went readlly wrong while sending IQ packet. Expecting result or error, but got '".$ans->GetType."'!");
        return RET_ABORT;

    }
    
}

############################################
# Send a text message somewhere
sub __comm_send_message { # Handle 'comm_send_message'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0, ARG1 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate
    return RET_ABORT unless defined ($packet->{to});
    return RET_ABORT unless defined ($packet->{message});

    # Build the send message
    my $msg = new Net::XMPP::Message();
    $msg->SetFrom($self->{me});
    $msg->SetTo($packet->{to});
    $msg->SetBody(encode_entities($packet->{message}));
    $msg->SetThread($packet->{thread}) if defined($packet->{thread});
    $msg->SetSubject($packet->{subject}) if defined($packet->{subject});
    $msg->SetType('normal');

    log_debug("Sending message: ".$msg->GetXML);

    # Send
    $XMPPCon->Send($msg);
    
    return RET_OK; # Ok, continue if needed
}


## =========================================================================================================================== ##
##                                                 BINDINGS TO THE CLI                                                         ##
## =========================================================================================================================== ##

############################################
# Get my jid
sub __cli_me { # Handle 'xmpp/me' command
############################################
    my ($self, $command, $kernel) = @_[ OBJECT, ARG0, KERNEL ];
    iAgent::Kernel::Dispatch("cli_write", "My JID is $self->{me}");
    return RET_COMPLETED;
}

############################################
# Send a message
sub __cli_send { # Handle 'xmpp/send' command
############################################
    my ($self, $command, $kernel) = @_[ OBJECT, ARG0, KERNEL ];

    # Send message
    iAgent::Kernel::Dispatch('comm_send', {
        to => $command->{options}->{to},
        context => $command->{options}->{context},
        action => $command->{options}->{action},
        data => $command->{options}->{payload}
    }, '_cli_send_status');

}

############################################
# Send an action
sub __cli_action { # Handle 'xmpp/action' command
############################################
    my ($self, $command, $kernel) = @_[ OBJECT, ARG0, KERNEL ];

    # Parse cmdline
    my ($cmd, $params) = parse_cmdline($command->{cmdline});

    # Split first part of cmd and use it as context
    my ($context, $action) = split("::", $cmd);

    # Fetch 'to', 'type'
    my $to = $params->{to};
    my $type = $params->{type};
    delete $params->{to};
    delete $params->{type};

    # Defaults
    $type='get' unless defined($type);

    # Check validity
    if (!defined($to)) {
        iAgent::Kernel::Dispatch("cli_error", "Please specify a target jid with the --to= parameter");
        return RET_ERROR;
    };
    if (!defined($context) || !defined($action)) {
        iAgent::Kernel::Dispatch("cli_error", "Please specify an action in context::action format");
        return RET_ERROR;
    };

    # Send action
    iAgent::Kernel::Dispatch('comm_send', {
        to => $to,
        context => $context,
        action => $action,
        parameters => $params,
        type => $type
    }, '_cli_send_status');

    # return OK
    return RET_OK;
    
}

############################################
# Internal callback to get the response of
# a sent message
sub ___cli_send_status {
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    
    if ($packet->{type} eq 'error') {
        iAgent::Kernel::Dispatch("cli_error", "Got error!");
        iAgent::Kernel::Dispatch("cli_write", "Got response: ".$packet->{raw}->GetXML) if (defined $packet->{raw});
        iAgent::Kernel::Dispatch("cli_completed", 1);
    } else {
        iAgent::Kernel::Dispatch("cli_write", "Got response: ".$packet->{raw}->GetXML);
        iAgent::Kernel::Dispatch("cli_completed", 0);
    }

}


#########################################
#########################################
# Module initialization manifest
#########################################
#########################################


=head1 CONFIGURATION

This module is looking for the configuration file 'xmpp.conf' that should contain
the following entries:

  # Connection information
  XMPPServer       "myejabberd.company.com"
  XMPPUser         "user"
  XMPPPassword     "s3cr3t"
  
  # If not specified, the current hostname will be used
  XMPPResource     "random"
  
  # If '1' the server will try to register
  XMPPRegister     0


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
