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

iAgent::Module::XMPP::PubSub - Publish/Subscribe extensions on the XMPP object

=head1 DESCRIPTION

That's a partial implementation of XEP-0060 (Publish-Subscribe) XMPP Standard. It exposes
it's functionality through the C<comm_pubsub_*> messages.

=head1 PROVIDED EVENTS

TODO

=cut

# Basic definitions
package iAgent::Module::XMPP::PubSub;
use strict;
use warnings;

# Include namespaces
use iAgent::Module::XMPP::Namespaces;

# For connection with iAgent
use iAgent;
use iAgent::Kernel;
use iAgent::Log;

# The actually usable stuff
use POE;
use Data::Dumper;
use Net::XMPP;
use Sys::Hostname;
use XML::Simple;
use Data::UUID;

my $IQ_TIMEOUT = 60;

# Extend XMPP Cache
our $MANIFEST = {

    CLI => {
        "xmpp/pubsub/subscriptions" => {
            description => "List Publish-Subscribe subscriptions",
            message => "cli_pubsub_list",
        },
        "xmpp/pubsub/subscribe" => {
            description => "Subscribe to a node",
            message => "cli_pubsub_subscribe",
        },
        "xmpp/pubsub/unsubscribe" => {
            description => "Unsubscribe from a node",
            message => "cli_pubsub_unsubscribe",
        },
        "xmpp/pubsub/create" => {
            description => "Create to a pub/sub node",
            options => [ 'node=s', 'title=s' ],
            message => "cli_pubsub_create"
        },
        "xmpp/pubsub/delete" => {
            description => "Delete a pub/sub node",
            options => [ 'node=s' ],
            message => "cli_pubsub_delete"
        },
        "xmpp/pubsub/publish" => {
            description => "Publish a message on a node",
            message => "cli_pubsub_publish",
            options => [ 'node=s', 'message=-' ]
        }
    }

};

##===========================================================================================================================##
##                                              INITIALIZE SUBMODULE                                                         ##
##===========================================================================================================================##

sub init {
    my ($self, $XMPPCon) = @_;

    # Register VCard response callback
    $XMPPCon->SetXPathCallBacks(
    
        # Publish/Subscribe event
        "/message/event[\@xmlns='http://jabber.org/protocol/pubsub#event']" => sub { shift; return $self->CALLBACK_PUBSUB_EVENT(@_) },
        
    );

}

##===========================================================================================================================##
##                                       ENDPOINTS THAT CONNECTS WITH XMPP MODULE                                            ##
##===========================================================================================================================##

############################################
# Headnline arrived
sub CALLBACK_PUBSUB_EVENT {
############################################
    my $self = shift;
    my ($event) = @_;

    # Extract child
    my $ev = $event->GetChild(XMLPUBSUB_EVENT);

    # Get <items node='' />
    my @items = $ev->GetItems();
    for my $g_items (@items) {

        # Get <entry /> inside <item />
        for my $g_item ($g_items->GetEntries()) {
            #log_error($g_item->GetXML);

            # Make sure I am not the one sent this message
            if ($g_item->GetFrom() ne $self->{me}) {

                # Process data
                my $data = undef;
                if ($g_item->DefinedData) {
                    my $data_node = $g_item->GetData();
                    if ($data_node->GetType eq 'iagent:hash') {
                        $data = XMLin($data_node->GetRaw());
                    } elsif ($data_node->GetType eq 'iagent:text') {
                        $data = $data_node->GetText();
                    }
                }
                
                # Dispatch arrived event(s)
                my @notify_targets = $g_item->GetNotify();
                iAgent::Kernel::Dispatch("comm_pubsub_event", {
                    node => $g_items->GetNode(),
                    from => $g_item->GetFrom(),
                    id => $g_item->GetID(),
                    action => $g_item->GetAction(),
                    title => $g_item->GetTitle(),
                    message => $g_item->GetMessage(),
                    summary => $g_item->GetSummary(),
                    notify => \@notify_targets,
                    context => $g_item->GetContext(),
                    data => $data
                });


            }
            
        }
    }
}

##===========================================================================================================================##
##                                                  CLI HANDLERS                                                             ##
##===========================================================================================================================##

sub __cli_pubsub_list {
    my ($self, $kernel) = @_[ OBJECT, KERNEL ];

    my $p = { };
    my $ans = iAgent::Kernel::Dispatch('comm_pubsub_subscriptions', $p);
    return RET_ERROR if (!$ans);

    foreach (values %{$p->{subscriptions}}) {
        iAgent::Kernel::Dispatch("cli_write", " * ".$_->{node}." (Subscription ID= ".$_->{subid}.")")
    }

    return RET_COMPLETED;
    
}

sub __cli_pubsub_configure {
    my ($self, $kernel, $cmd) = @_[ OBJECT, KERNEL, ARG0 ];
    my @parameters = split(' ',$cmd->{cmdline});

    my $p = { node => $cmd->{cmdline} };
    my $ans = iAgent::Kernel::Dispatch('comm_pubsub_subscribe', $p);
    return RET_ERROR if (!$ans);

    iAgent::Kernel::Dispatch("cli_write", "Successfully subscribed to node ".$p->{node});
    return RET_COMPLETED;
    
}

sub __cli_pubsub_subscribe {
    my ($self, $kernel, $cmd) = @_[ OBJECT, KERNEL, ARG0 ];

    my $p = { node => $cmd->{cmdline} };
    my $ans = iAgent::Kernel::Dispatch('comm_pubsub_subscribe', $p);
    return RET_ERROR if (!$ans);

    iAgent::Kernel::Dispatch("cli_write", "Successfully subscribed to node ".$p->{node});
    return RET_COMPLETED;
    
}

sub __cli_pubsub_unsubscribe {
    my ($self, $kernel, $cmd) = @_[ OBJECT, KERNEL, ARG0 ];

    # Check if we should unsubscribe everything or just the specified JID
    my ($node, $subid) = split(' ',$cmd->{cmdline});

    # Remove all subscriptions if subID is not specified
    if (!defined $subid) {
        my $p = { };
        my $ans = iAgent::Kernel::Dispatch('comm_pubsub_subscriptions', $p);
        return RET_ERROR if (!$ans);

        foreach (values %{$p->{subscriptions}}) {
            if ($_->{node} eq $node) {

                my $p = { node => $_->{node}, subid => $_->{subid} };
                iAgent::Kernel::Dispatch("cli_write", "Unsubscribing from $_->{node} ($_->{subid})");
                my $ans = iAgent::Kernel::Dispatch('comm_pubsub_unsubscribe', $p);
                return RET_ERROR if (!$ans);

            }
        }

    } else {

        # Remove specified subscription ID
        my $p = { node => $node, subid => $subid };
        iAgent::Kernel::Dispatch("cli_write", "Unsubscribing from $node ($subid)");
        my $ans = iAgent::Kernel::Dispatch('comm_pubsub_unsubscribe', $p);
        return RET_ERROR if (!$ans);

    }

    iAgent::Kernel::Dispatch("cli_write", "Successfully unsubscribe from node ".$node);
    return RET_COMPLETED;
    
}

sub __cli_pubsub_publish {
    my ($self, $kernel, $cmd) = @_[ OBJECT, KERNEL, ARG0 ];

    my $p = { node => $cmd->{options}->{node}, message => $cmd->{options}->{message} };
    my $ans = iAgent::Kernel::Dispatch('comm_pubsub_publish', $p);
    return RET_ERROR if (!$ans);

    iAgent::Kernel::Dispatch("cli_write", "Successfully published. Entry ID = ".$p->{entry_id});
    return RET_COMPLETED;
    
}

sub __cli_pubsub_delete {
    my ($self, $kernel, $cmd) = @_[ OBJECT, KERNEL, ARG0 ];
    my $p = {  node => $cmd->{cmdline} };

    my $ans = iAgent::Kernel::Dispatch('comm_pubsub_delete', $p);
    return RET_ERROR if (!$ans);

    iAgent::Kernel::Dispatch("cli_write", "Successfully deleted");
    return RET_COMPLETED;
}

sub __cli_pubsub_create {
    my ($self, $kernel, $cmd) = @_[ OBJECT, KERNEL, ARG0 ];

    my $p = { 
        node => $cmd->{options}->{node},
        options => {
            'pubsub#persist_items' => 0,
            'pubsub#type' => IAGENT_PUBSUB_ENTRY,
            'pubsub#notification_type' => 'headline',
            'pubsub#deliver_notifications' => 1,
            'pubsub#access_model' => 'open',
            'pubsub#publish_model' => 'open',
            'pubsub#deliver_payloads' => 1,
            'pubsub#presence_based_delivery' => 1,
            'pubsub#purge_offline' => 1,
            'pubsub#tempsub' => 1,
            'pubsub#send_last_published_item' => 'never',
            'pubsub#max_items' => 0,
            'pubsub#title' => $cmd->{options}->{title}
        }
    };

    my $ans = iAgent::Kernel::Dispatch('comm_pubsub_create', $p);
    return RET_ERROR if (!$ans);

    iAgent::Kernel::Dispatch("cli_write", "Successfully created");
    return RET_COMPLETED;
    
}

##===========================================================================================================================##
##                                              PUBSUB IMPLEMENTATION                                                        ##
##===========================================================================================================================##

############################################
# List all of my new pub/sub subscriptions
sub __comm_pubsub_subscriptions { # Handle 'comm_pubsub_subscriptions'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB);

    # Create <subscriptions /> node
    $pubsub->SetSubscriptionsFlag();

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("get");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        # Failed
        $packet->{error}=$ans->GetErrorCode;        
        log_warning("Unable to list subscriptions! (".$ans->GetErrorCode. ')');
        return RET_ABORT;
    } else {
    
        log_debug($ans->GetXML);

        # Fetch subscriptions
        my @e_subscriptions = $ans->GetQuery()->GetSubscriptions();
        my %sub_details;

        foreach (@e_subscriptions) {
            $sub_details{ $_->GetNode() } = {
                jid => $_->GetJID(),
                node => $_->GetNode(),
                subid => $_->GetSubID(),
                subscription => $_->GetSubscription()
            }
        }
        $packet->{subscriptions} = \%sub_details;

        # Success
        log_debug("Subscriptions obtained successfullly");
        return RET_OK;
    }

}

############################################
# Create a new pub/sub node
sub __comm_pubsub_create { # Handle 'comm_pubsub_create'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate source
    return RET_ABORT unless defined $packet->{node};

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB);

    # Create <create /> node
    log_debug("Creating pubsub node ".$packet->{node});
    my $e_create = $pubsub->NewChild(XMLPUBSUB_CREATE);
    $e_create->SetNode($packet->{node});

    # If we have options, create <configure /> node
    if (defined $packet->{options}) {
        log_debug("Configuring pubsub node ".$packet->{node}." with options: ".Dumper($packet->{options}));
        my $e_options = $pubsub->NewChild(XMLPUBSUB_CONFIGURE);
        my $e_data = $e_options->NewChild(JABBER_XDATA);
        $e_data->SetType('submit');
        foreach (keys %{$packet->{options}}) {
            $e_data->NewChild(JABBER_XDATA_FIELD)->SetItem(
                var => $_,
                value => scalar $packet->{options}->{$_}
            );
        }
    }

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("set");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        
        if ($ans->GetErrorCode != 409) {
            # Already exists -> OK
            log_debug("Node ".$packet->{node}.' already exists ('.$ans->GetErrorCode. ')');
            return RET_OK;
            
        } else {
            # Failed
            $packet->{error}=$ans->GetErrorCode;        
            log_warning("Unable to create pubsub node ".$packet->{node}.' ('.$ans->GetErrorCode. ')');
            return RET_ABORT;
        }
        
    } else {
        # Node created
        log_debug("Pubsub node ".$packet->{node}.' created');
        return RET_OK;
    }

}


############################################
# Delete a new pub/sub node
sub __comm_pubsub_delete { # Handle 'comm_pubsub_delete'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate source
    return RET_ABORT unless defined $packet->{node};

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB_OWNER);

    # Create <delete /> node
    log_debug("Delete pubsub node ".$packet->{node});
    my $e_create = $pubsub->NewChild(XMLPUBSUB_DELETE);
    $e_create->SetNode($packet->{node});

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("set");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);
    log_debug("Got XML ".$ans->GetXML());

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        # Failed
        $packet->{error}=$ans->GetErrorCode;        
        log_warning("Unable to delete pubsub node ".$packet->{node}.' ('.$ans->GetErrorCode. ')');
        return RET_ABORT;
        
    } else {
        # Node created
        log_debug("Pubsub node ".$packet->{node}.' deleted');
        return RET_OK;
    }

}

############################################
# Configure a new pub/sub node
sub __comm_pubsub_configure { # Handle 'comm_pubsub_configure'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate source
    return RET_ABORT unless defined $packet->{node};
    return RET_ABORT unless defined $packet->{options};

    log_debug("Configuring pubsub node ".$packet->{node}." with options: ".Dumper($packet->{options}));

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB);

    # If we have options, create <configure /> node
    my $e_options = $pubsub->NewChild(XMLPUBSUB_CONFIGURE);
    my $e_data = $e_options->NewChild(JABBER_XDATA);
    $e_data->SetType('submit');
    foreach (keys %{$packet->{options}}) {
        $e_data->NewChild(JABBER_XDATA_FIELD)->SetItem(
            var => $_,
            value => scalar $packet->{options}->{$_}
        );
    }

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("set");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        # Failed
        $packet->{error}=$ans->GetErrorCode;        
        log_warning("Unable to configure pubsub node ".$packet->{node}.' ('.$ans->GetErrorCode. ')');
        return RET_ABORT;
    } else {
        # Node configured
        log_debug("Pubsub node ".$packet->{node}.' configured');
        return RET_OK;
    }

}

############################################
# Subscribe to a new pub/sub node
sub __comm_pubsub_subscribe { # Handle 'comm_pubsub_subscribe'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate source
    return RET_ABORT unless defined $packet->{node};
    log_debug("Subscribing to pubsub node ".$packet->{node});

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB);

    # If we have options, create <subsctibe /> node
    my ($basejid) = split('/',$self->{me});
    my $e_subscribe = $pubsub->NewChild(XMLPUBSUB_SUBSCRIBE);
    $e_subscribe->SetNode($packet->{node});
    $e_subscribe->SetJID($basejid);

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("set");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        # Failed
        $packet->{error}=$ans->GetErrorCode;
        log_warning("Unable to subsctibe to pubsub node ".$packet->{node}.' ('.$ans->GetErrorCode. ')');
        return RET_ABORT;
    } else {

        log_debug($ans->GetXML);

        # Get subscription information
        my $e_subscription = $ans->GetQuery()->GetSubscription();

        # Check status
        if ($e_subscription->GetSubscription() eq 'subscribed') {

            # Subscription completed
            log_debug("Subscribed to node ".$packet->{node}.' successfuly');
            return RET_OK;
            
        } elsif ($e_subscription->GetSubscription() eq 'pending') {

            # Subscription needs to be approved
            log_debug("Subscription to node ".$packet->{node}.' requires approval. Approval is pending.');
            return RET_SCHEDULED;

            
        } elsif ($e_subscription->GetSubscription() eq 'unconfigured') {

            # Subscription needs to be approved
            log_debug("Subscription to node ".$packet->{node}.' requires configuration.');
            return RET_INCOMPLETE;
            
        }
    
        # Node created
        return RET_OK;
    }

}

############################################
# Unsubscribe from a new pub/sub node
sub __comm_pubsub_unsubscribe { # Handle 'comm_pubsub_unsubscribe'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate source
    return RET_ABORT unless defined $packet->{node};
    return RET_ABORT unless defined $packet->{subid};
    log_debug("Unsubscribing from pubsub node ".$packet->{node}.'/'.$packet->{subid});

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB);

    # If we have options, create <subsctibe /> node
    my ($basejid) = split('/',$self->{me});
    my $e_unsubscribe = $pubsub->NewChild(XMLPUBSUB_UNSUBSCRIBE);
    $e_unsubscribe->SetNode($packet->{node});
    $e_unsubscribe->SetSubID($packet->{subid});
    $e_unsubscribe->SetJID($basejid);

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("set");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);

    log_debug("Got XML ".$ans->GetXML());

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        # Failed
        $packet->{error}=$ans->GetErrorCode;        
        log_warning("Unable to unsubsctibe from pubsub node ".$packet->{node}.' ('.$ans->GetErrorCode. ')');
        return RET_ABORT;
    } else {
        # Unsubscribed from node
        log_debug("Unsubscribed from pubsub node ".$packet->{node});
        return RET_OK;
    }

}

############################################
# Publish something to a new pub/sub node
sub __comm_pubsub_publish { # Handle 'comm_pubsub_publish'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate source
    return RET_ABORT unless defined $packet->{node};
    log_debug("Publishing data to pubsub node ".$packet->{node});

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB);

    # Create a <publish /> node
    my $e_publish = $pubsub->NewChild(XMLPUBSUB_PUBLISH);
    $e_publish->SetNode($packet->{node});
    
    my $e_pubitem = $e_publish->NewChild(XMLPUBSUB_ITEM);
    #$e_pubitem->SetID( Data::UUID->new()->create_b64() );

    # Create an <item xmlns="iagent:pubsub:entry" /> node
    my $e_entry = $e_pubitem->NewChild(IAGENT_PUBSUB_ENTRY);
    $e_entry->SetFrom($self->{me});
    $e_entry->SetPublished(); # Now
    $e_entry->SetContext('generic');

    # Populate fields based on the request packet
    $e_entry->SetID($packet->{id}) if defined ($packet->{id});
    $e_entry->SetAction($packet->{action}) if defined ($packet->{action});
    $e_entry->SetTitle($packet->{title}) if defined ($packet->{title});
    $e_entry->SetMessage($packet->{message}) if defined ($packet->{message});
    $e_entry->SetSubject($packet->{subject}) if defined ($packet->{subject});
    $e_entry->SetNotify($packet->{notify}) if defined ($packet->{notify});
    $e_entry->SetContext($packet->{context}) if defined ($packet->{context});

    # Check how are we going to append the RAW data
    if (defined ($packet->{data})) {
        my $e_data = $e_entry->NewChild(IAGENT_PUBSUB_ENTRY_DATA);
        
        if (UNIVERSAL::isa($packet->{data},'HASH')) {
            $e_data->SetRaw(XMLout($packet->{data}, NoIndent => 1));
            $e_data->SetType('iagent:hash');
        } else {
            $e_data->SetType('iagent:text');
            $e_data->SetText($packet->{data});
        }
    }

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("set");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        # Failed
        $packet->{error}=$ans->GetErrorCode;        
        log_warning("Unable to publish an element to pubsub node ".$packet->{node}.' ('.$ans->GetErrorCode. ')');
        return RET_ABORT;
    } else {

        # Succeeeded! Get item ID    
        log_debug($ans->GetXML);
        my $id = $ans->GetQuery()->GetPublishID();
        $packet->{entry_id} = $id;
        
        # Return OK
        log_debug("Entry published to pubsub node ".$packet->{node}." Entry ID: $id");
        return RET_OK;

    }
        
}

############################################
# Retract something published
sub __comm_pubsub_retract { # Handle 'comm_pubsub_publish'
############################################
    my ($self, $packet) = @_[ OBJECT, ARG0 ];
    my $XMPPCon = $self->{XMPPCon};

    # Validate source
    return RET_ABORT unless defined $packet->{node};
    return RET_ABORT unless defined $packet->{id};
    log_debug("Retracting a pubsub node ".$packet->{node});

    # Prepare IQ
    my $iq = new Net::XMPP::IQ();
    my $pubsub = $iq->NewChild(XMLPUBSUB);

    # Create a <publish /> node
    my $e_retract = $pubsub->NewChild(XMLPUBSUB_RETRACT);
    $e_retract->SetNode($packet->{node});
    $e_retract->SetNode($packet->{id});

    # Prepare IQ Information for transmittion
    $iq->SetID($self->get_uid());
    $iq->SetFrom($self->{me});
    $iq->SetTo("pubsub.".$self->{config}->{XMPPServer});
    $iq->SetType("set");

    # Send IQ
    log_debug("Sending XML ".$iq->GetXML());
    my $ans = $XMPPCon->SendAndReceiveWithID($iq,$IQ_TIMEOUT);

    # Check response
    if (!defined $ans) {
        # Timed-out
        $packet->{error}=1;
        log_warning("Timed out while waiting for response");
        return RET_ABORT;
    
    } elsif ($ans->GetType eq 'error') {
        # Failed
        $packet->{error}=$ans->GetErrorCode;        
        log_warning("Unable to retract pubsub node ".$packet->{node}.' ('.$ans->GetErrorCode. ')');
        return RET_ABORT;
    } else {
        # Node created
        log_debug("Pubsub node ".$packet->{node}.' retracted');
        return RET_OK;
    }
    
}


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
