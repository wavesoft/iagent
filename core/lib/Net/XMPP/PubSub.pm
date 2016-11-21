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

Net::XMPP:PubSub - Publish/Subscribe implementation for the Net::XMPP Module

=head1 DESCRIPTION

This module provides some required nmespaces that are used from PubSub module

More precisely it implements the following XML namespaces:

 jabber:x:data
 http://jabber.org/protocol/pubsub

=cut

# Basic definitions
package Net::XMPP:PubSub;
use strict;
use warnings;
use Exporter;

use Net::XMPP::Stanza;
use base qw( Net::XMPP::Stanza Exporter );

##===========================================================================================================================##
##                                          EXTENSIONS TO Net::XMPP NAMESPACE                                                ##
##===========================================================================================================================##

# ------------------------------------------------------------------------------------------------------------------------
# Define a shortcuts for the XML namespaces
# ------------------------------------------------------------------------------------------------------------------------
sub XMLPUBSUB               { 'http://jabber.org/protocol/pubsub' };
sub XMLPUBSUB_CREATE        { '__netxmpp__:http://jabber.org/protocol/pubsub:create' };
sub XMLPUBSUB_SUBSCRIBE     { '__netxmpp__:http://jabber.org/protocol/pubsub:subscribe' };
sub XMLPUBSUB_OPTIONS       { '__netxmpp__:http://jabber.org/protocol/pubsub:options' };
sub XMLPUBSUB_CONFIGURE     { '__netxmpp__:http://jabber.org/protocol/pubsub:configure' };
sub XMLPUBSUB_ITEMS         { '__netxmpp__:http://jabber.org/protocol/pubsub:items' } ;
sub XMLPUBSUB_PUBLISH       { '__netxmpp__:http://jabber.org/protocol/pubsub:publish' };
sub XMLPUBSUB_RETRACT       { '__netxmpp__:http://jabber.org/protocol/pubsub:retract' };
sub XMLPUBSUB_UNSUBSCRIBE   { '__netxmpp__:http://jabber.org/protocol/pubsub:unsubscribe' };

our @EXPORT = qw(
    XMLPUBSUB 
); 

# ------------------------------------------------------------------------------------------------------------------------
# Official XML Namespace registrations
# ------------------------------------------------------------------------------------------------------------------------

#############################################
# jabber:x:data
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => 'jabber:x:data',
    tag   => "x",
    xpath => {
                  Type  => { path => '@type' },
                  Field => {
                             path => 'field',
                             type => 'child',
                             child => { ns => '__netxmpp__:jabber:x:data:field' },
                             calls => [ 'Add' ]
                           },
                  Fields => {
                             path => 'field',
                             type => 'child',
                             child => { ns => '__netxmpp__:jabber:x:data:field' },
                             calls => [ 'Get' ]
                           }
             }
);

#############################################
# http://jabber.org/protocol/pubsub
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB,
    tag   => "pubsub",
    xpath => {
                  Create  => {
                            type  => 'child',
                            path  => 'create',
                            child => { ns => XMLPUBSUB_CREATE, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },
                           
                  Configure  => {
                            type  => 'child',
                            path  => 'configure/x',
                            child => { ns => 'jabber:x:data', },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },

                  Subscribe  => {
                            type  => 'child',
                            path  => 'subscribe',
                            child => { ns => XMLPUBSUB_SUBSCRIBE, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },

                  Unsubscribe  => {
                            type  => 'child',
                            path  => 'subscribe',
                            child => { ns => XMLPUBSUB_UNSUBSCRIBE, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },
                           
                  Options  => {
                            type  => 'child',
                            path  => 'options',
                            child => { ns => XMLPUBSUB_OPTIONS, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },

                  Items  => {
                            type  => 'child',
                            path  => 'items',
                            child => { ns => XMLPUBSUB_ITEMS, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },
                           
                  Publish  => {
                            type  => 'child',
                            path  => 'publish',
                            child => { ns => XMLPUBSUB_PUBLISH, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },

                  Retract  => {
                            type  => 'child',
                            path  => 'retract',
                            child => { ns => XMLPUBSUB_RETRACT, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },                           
               }
);
# ------------------------------------------------------------------------------------------------------------------------
# Private XML Namespace registrations
# ------------------------------------------------------------------------------------------------------------------------

#############################################
# __netxmpp__:jabber:x:data:field
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => '__netxmpp__:jabber:x:data:field',
    tag   => "field",
    xpath => {
                  Type  =>      { path => '@type' },
                  Label =>      { path => '@label' },
                  Var   =>      { path => '@var' },
                  
                  Desc  =>      { path => 'desc/text()' },
                  Required  =>  { path => 'required', type => 'flag' },
                  Value  =>     { path => 'value/text()' },
                  Option  =>    { path => 'option/text()' },

                  Item =>       { type => 'master' }
             }
);

#############################################
# __netxmpp__:http://jabber.org/protocol/pubsub:create
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_CREATE,
    tag => 'create',
    xpath => {
                  Node  => { path  => '@node' }
             }
);

#############################################
# __netxmpp__:http://jabber.org/protocol/pubsub:configure
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_CONFIGURE,
    tag => 'configure',
    xpath => {
                  Config  => { 
                                path  => 'x',
                                type  => 'child',
                                child => 'jabber:x:data',
                                actions => [ 'Get', 'Set', 'Defined' ]
                             }
             }
);

#############################################
#__netxmpp__:http://jabber.org/protocol/pubsub:subscribe
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_SUBSCRIBE,
    tag => 'subscribe',
    xpath => {
                  Node  => { path  => '@node' },
                  Jid   => { path  => '@jid', type => 'jid' }
             }
);

#############################################
#__netxmpp__:http://jabber.org/protocol/pubsub:unsubscribe
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_UNSUBSCRIBE,
    tag => 'unsubscribe',
    xpath => {
                  Node  => { path  => '@node' },
                  SubID  => { path  => '@subid' },
                  JID   => { path  => '@jid', type => 'jid' }
             }
);

#############################################
#__netxmpp__:http://jabber.org/protocol/pubsub:publish
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_PUBLISH,
    tag => 'publish',
    xpath => {
                  Node  => { path  => '@node' },
                  Item  => {
                             path => 'item',
                             type => 'raw'
                           }
                           
             }
);

#############################################
#__netxmpp__:http://jabber.org/protocol/pubsub:retract
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_RETRACT,
    tag => 'retract',
    xpath => {
                  Node  => { path  => '@node' },
                  Item  => {
                             path => 'item',
                             type => 'raw',
                             actions => [ 'Add' ]
                           },
                  Items  => {
                             path => 'item',
                             type => 'raw',
                             actions => [ 'Get' ]
                           }
                           
             }
);

##===========================================================================================================================##
##                                          IMPLEMENTATION OF THE PUBSUB NODE                                                ##
##===========================================================================================================================##


sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = { };

    bless($self, $proto);

    $self->{DEBUGHEADER} = "IQ";
    $self->{TAG} = "iq";

    $self->{FUNCS} = \%FUNCTIONS;

    $self->_init(@_);

    return $self;
}

$FUNCTIONS{Error}->{path} = 'error/text()';

$FUNCTIONS{ErrorCode}->{path} = 'error/@code';

$FUNCTIONS{From}->{type} = 'jid';
$FUNCTIONS{From}->{path} = '@from';

$FUNCTIONS{ID}->{path} = '@id';

$FUNCTIONS{To}->{type} = 'jid';
$FUNCTIONS{To}->{path} = '@to';

$FUNCTIONS{Type}->{path} = '@type';

$FUNCTIONS{XMLNS}->{path} = '@xmlns';

$FUNCTIONS{IQ}->{type}  = 'master';

$FUNCTIONS{Child}->{type}  = 'child';
$FUNCTIONS{Child}->{path}  = '*[@xmlns]';
$FUNCTIONS{Child}->{child} = { };

$FUNCTIONS{Query}->{type}  = 'child';
$FUNCTIONS{Query}->{path}  = '*[@xmlns][0]';
$FUNCTIONS{Query}->{child} = { child_index=>0 };

##############################################################################
#
# GetQueryXMLNS - returns the xmlns of the first child
#
##############################################################################
sub GetQueryXMLNS
{
    my $self = shift;
    return $self->{CHILDREN}->[0]->GetXMLNS() if ($#{$self->{CHILDREN}} > -1);
}


##############################################################################
#
# Reply - returns a Net::XMPP::IQ object with the proper fields
#         already populated for you.
#
##############################################################################
sub Reply
{
    my $self = shift;
    my %args;
    while($#_ >= 0) { $args{ lc pop(@_) } = pop(@_); }

    my $reply = $self->_iq();

    $reply->SetID($self->GetID()) if ($self->GetID() ne "");
    $reply->SetType("result");

    $reply->NewChild($self->GetQueryXMLNS());

    $reply->SetIQ((($self->GetFrom() ne "") ?
                   (to=>$self->GetFrom()) :
                   ()
                  ),
                  (($self->GetTo() ne "") ?
                   (from=>$self->GetTo()) :
                   ()
                  ),
                 );
    $reply->SetIQ(%args);

    return $reply;
}

1;
