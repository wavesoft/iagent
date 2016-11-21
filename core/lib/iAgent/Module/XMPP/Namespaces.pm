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

iAgent::Module::XMPP::Namespaces - Additional namespaces for Net::XMPP, used by other modules

=head1 DESCRIPTION

This module provides many missing namespace stanzas for the Net::XMPP module. It enables simple interfacing through
the standard Net::XMPP::Stanza Get/Set/Add/Defined/Remove interface.

More precisely it implements the following official XMPP namespaces:

 jabber:x:data
 jabber:iq:version
 url:xmpp:time
 http://jabber.org/protocol/pubsub
 http://jabber.org/protocol/pubsub#owner
 http://jabber.org/protocol/pubsub#event
 http://jabber.org/protocol/disco#info

Plus some dummy namespaces, used by iAgent and archipel:

 iagent:pubsub:entry
 archipel:*

=head2 SHORTHANDS

In order to simplify the reference of long, dummy namespaces, the following aliases are exported:

=begin html

<table>
<tr><td colspan="2" align="left"><h3>Public namespaces</h3></td></tr>
<tr><td>XMLPUBSUB</td><td>http://jabber.org/protocol/pubsub</td></tr>
<tr><td>XMLPUBSUB_OWNER</td><td>http://jabber.org/protocol/pubsub#owner</td></tr>
<tr><td>XMLPUBSUB_EVENT</td><td>http://jabber.org/protocol/pubsub#event</td></tr>
<tr><td>JABBER_XDATA</td><td>jabber:x:data</td></tr>
<tr><td>JABBER_VERSION</td><td>jabber:iq:version</td></tr>
<tr><td>JABBER_TIME</td><td>url:xmpp:time</td></tr>
<tr><td>JABBER_DISCOVERY</td><td>http://jabber.org/protocol/disco#info</td></tr>
<tr><td>IAGENT_PUBSUB_ENTRY</td><td>iagent:pubsub:entry</td></tr>
</table>

<table>
<tr><td colspan="2" align="left"><h3>Private namespaces</h3></td></tr>
<tr><td>XMLPUBSUB_CREATE</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:create</td></tr>
<tr><td>XMLPUBSUB_SUBSCRIBE</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:subscribe</td></tr>
<tr><td>XMLPUBSUB_OPTIONS</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:options</td></tr>
<tr><td>XMLPUBSUB_CONFIGURE</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:configure</td></tr>
<tr><td>XMLPUBSUB_ITEMS</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:items</td></tr>
<tr><td>XMLPUBSUB_ITEM</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:item</td></tr>
<tr><td>XMLPUBSUB_PUBLISH</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:publish</td></tr>
<tr><td>XMLPUBSUB_PUBLISH_ENTRY</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:publish:entry</td></tr>
<tr><td>XMLPUBSUB_RETRACT</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:retract</td></tr>
<tr><td>XMLPUBSUB_UNSUBSCRIBE</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:unsubscribe</td></tr>
<tr><td>XMLPUBSUB_SUBSCRIPTION</td><td>__netxmpp__:http://jabber.org/protocol/pubsub:subscription</td></tr>
<tr><td>XMLPUBSUB_DELETE</td><td>__netxmpp__:http://jabber.org/protocol/pubsub#owner:delete</td></tr>
<tr><td>XMLPUBSUB_EVENT_COLLECTION</td><td>__netxmpp__:http://jabber.org/protocol/pubsub#event:collection</td></tr>
<tr><td>XMLPUBSUB_EVENT_CONFIGURATION</td><td>__netxmpp__:http://jabber.org/protocol/pubsub#event:configuration</td></tr>
<tr><td>XMLPUBSUB_EVENT_DELETE</td><td>__netxmpp__:http://jabber.org/protocol/pubsub#event:delete</td></tr>
<tr><td>XMLPUBSUB_EVENT_ITEMS</td><td>__netxmpp__:http://jabber.org/protocol/pubsub#event:items</td></tr>
<tr><td>XMLPUBSUB_EVENT_PURGE</td><td>__netxmpp__:http://jabber.org/protocol/pubsub#event:purge</td></tr>
<tr><td>XMLPUBSUB_EVENT_SUBSCRIPTION</td><td>__netxmpp__:http://jabber.org/protocol/pubsub#event:subscription</td></tr>
<tr><td>JABBER_XDATA_FIELD</td><td>__netxmpp__:jabber:x:data:field</td></tr>
<tr><td>JABBER_DISCOVERY_IDENTITY</td><td>__netxmpp__:http://jabber.org/protocol/disco#info:identity</td></tr>
<tr><td>JABBER_DISCOVERY_FEATURE</td><td>__netxmpp__:http://jabber.org/protocol/disco#info:feature</td></tr>
<tr><td>IAGENT_PUBSUB_ENTRY_DATA</td><td>__netxmpp__:iagent:pubsub:entry:data</td></tr>
<tr><td>XMLARCHIPEL</td><td>__netxmpp__:acrchipel</td></tr>
<tr><td>XMLARCHIPEL_QUERY</td><td>__netxmpp__:acrchipel:query</td></tr>
</table>


=end html

=cut

# Basic definitions
package iAgent::Module::XMPP::Namespaces;
use strict;
use warnings;
use Exporter;
our @ISA = qw(Exporter);

##===========================================================================================================================##
##                                          EXTENSIONS TO Net::XMPP NAMESPACE                                                ##
##===========================================================================================================================##

# ------------------------------------------------------------------------------------------------------------------------
# Define a shortcuts for the XML namespaces
# ------------------------------------------------------------------------------------------------------------------------
sub XMLPUBSUB                     { 'http://jabber.org/protocol/pubsub' };
sub XMLPUBSUB_CREATE              { '__netxmpp__:http://jabber.org/protocol/pubsub:create' };
sub XMLPUBSUB_SUBSCRIBE           { '__netxmpp__:http://jabber.org/protocol/pubsub:subscribe' };
sub XMLPUBSUB_OPTIONS             { '__netxmpp__:http://jabber.org/protocol/pubsub:options' };
sub XMLPUBSUB_CONFIGURE           { '__netxmpp__:http://jabber.org/protocol/pubsub:configure' };
sub XMLPUBSUB_ITEMS               { '__netxmpp__:http://jabber.org/protocol/pubsub:items' } ;
sub XMLPUBSUB_ITEM                { '__netxmpp__:http://jabber.org/protocol/pubsub:item' } ;
sub XMLPUBSUB_PUBLISH             { '__netxmpp__:http://jabber.org/protocol/pubsub:publish' };
sub XMLPUBSUB_PUBLISH_ENTRY       { '__netxmpp__:http://jabber.org/protocol/pubsub:publish:entry' };
sub XMLPUBSUB_RETRACT             { '__netxmpp__:http://jabber.org/protocol/pubsub:retract' };
sub XMLPUBSUB_UNSUBSCRIBE         { '__netxmpp__:http://jabber.org/protocol/pubsub:unsubscribe' };
sub XMLPUBSUB_SUBSCRIPTION        { '__netxmpp__:http://jabber.org/protocol/pubsub:subscription' };

sub XMLPUBSUB_OWNER               { 'http://jabber.org/protocol/pubsub#owner' };
sub XMLPUBSUB_DELETE              { '__netxmpp__:http://jabber.org/protocol/pubsub#owner:delete' };

sub XMLPUBSUB_EVENT               { 'http://jabber.org/protocol/pubsub#event' };
sub XMLPUBSUB_EVENT_COLLECTION    { '__netxmpp__:http://jabber.org/protocol/pubsub#event:collection' };
sub XMLPUBSUB_EVENT_CONFIGURATION { '__netxmpp__:http://jabber.org/protocol/pubsub#event:configuration' };
sub XMLPUBSUB_EVENT_DELETE        { '__netxmpp__:http://jabber.org/protocol/pubsub#event:delete' };
sub XMLPUBSUB_EVENT_ITEMS         { '__netxmpp__:http://jabber.org/protocol/pubsub#event:items' };
sub XMLPUBSUB_EVENT_PURGE         { '__netxmpp__:http://jabber.org/protocol/pubsub#event:purge' };
sub XMLPUBSUB_EVENT_SUBSCRIPTION  { '__netxmpp__:http://jabber.org/protocol/pubsub#event:subscription' };

sub JABBER_XDATA                  { 'jabber:x:data' };
sub JABBER_XDATA_FIELD            { '__netxmpp__:jabber:x:data:field' };
sub JABBER_VERSION                { 'jabber:iq:version' };
sub JABBER_TIME                   { 'url:xmpp:time' };
sub JABBER_DISCOVERY              { 'http://jabber.org/protocol/disco#info' };
sub JABBER_DISCOVERY_IDENTITY     { '__netxmpp__:http://jabber.org/protocol/disco#info:identity' };
sub JABBER_DISCOVERY_FEATURE      { '__netxmpp__:http://jabber.org/protocol/disco#info:feature' };

sub IAGENT_PUBSUB_ENTRY           { 'iagent:pubsub:entry' };
sub IAGENT_PUBSUB_ENTRY_DATA      { '__netxmpp__:iagent:pubsub:entry:data' };

sub XMLARCHIPEL                   { '__netxmpp__:acrchipel' };
sub XMLARCHIPEL_QUERY             { '__netxmpp__:acrchipel:query' };

our @EXPORT = qw(
    XMLPUBSUB 
    XMLPUBSUB_CREATE
    XMLPUBSUB_SUBSCRIBE
    XMLPUBSUB_OPTIONS
    XMLPUBSUB_CONFIGURE
    XMLPUBSUB_ITEM
    XMLPUBSUB_ITEMS
    XMLPUBSUB_PUBLISH
    XMLPUBSUB_PUBLISH_ENTRY
    XMLPUBSUB_RETRACT
    XMLPUBSUB_UNSUBSCRIBE
    XMLPUBSUB_EVENT
    XMLPUBSUB_OWNER
    XMLPUBSUB_DELETE
    JABBER_XDATA
    JABBER_XDATA_FIELD
    JABBER_DISCOVERY
    JABBER_DISCOVERY_IDENTITY
    JABBER_DISCOVERY_FEATURE
    IAGENT_PUBSUB_ENTRY
    IAGENT_PUBSUB_ENTRY_DATA
    XMLARCHIPEL
    XMLARCHIPEL_QUERY
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
# http://jabber.org/protocol/pubsub#owner
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_OWNER,
    tag   => "pubsub",
    xpath => {
                  Delete  => {
                            type  => 'child',
                            path  => 'delete',
                            child => { ns => XMLPUBSUB_DELETE, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },
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

                  Subscription  => {
                            type  => 'child',
                            path  => 'subscription',
                            child => { ns => XMLPUBSUB_SUBSCRIPTION, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },

                  SubscriptionsFlag => {
                            type  => 'flag',
                            path  => 'subscriptions',
                            calls => [ 'Set' ]
                           },

                  Subscriptions => {
                            type  => 'child',
                            path  => 'subscriptions/subscription',
                            child => { ns => XMLPUBSUB_SUBSCRIPTION }
                           },

                  Unsubscribe  => {
                            type  => 'child',
                            path  => 'unsubscribe',
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

                  PublishID => {
                            path  => 'publish/item/@id'
                           },

                  Retract  => {
                            type  => 'child',
                            path  => 'retract',
                            child => { ns => XMLPUBSUB_RETRACT, },
                            calls => [ 'Get', 'Set', 'Defined' ]
                           },                           
               }
);


#############################################
# http://jabber.org/protocol/pubsub#event
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_EVENT,
    tag => 'event',
    xpath => {
                  Items  => { 
                              path  => 'items', 
                              type => 'child', 
                              child => { ns => XMLPUBSUB_EVENT_ITEMS }, 
                              calls => [ 'Get' ] 
                            }
             }
);

#############################################
# iagent:pubsub:entry
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => IAGENT_PUBSUB_ENTRY,
    tag => 'entry',
    xpath => {
    
                  # Custom payload
                  Data   => { path => 'data', type => 'child', child => { ns => IAGENT_PUBSUB_ENTRY_DATA } },

                  # The action to implement
                  Context   => { path => '@context' },
                  Action    => { path => '@action' },
                  From      => { path => '@from' },
                  Published => { path => '@published', type => 'timestamp' },
                  ID        => { path => '@id' },

                  # Extra structured fields
                  Notify    => { path => 'notify/text()', type => 'array' }, # Targets to be notified
                  Title     => { path => 'title/text()' },    # In case of textual payload, the title
                  Summary   => { path => 'summary/text()' },  # The summary
                  Message   => { path => 'message/text()' }   # And the actual message
                  
             }
);

#############################################
# jabber:iq:version
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => JABBER_VERSION,
    tag => 'query',
    xpath => {
                Name        => { path => 'name/text()' },
                Version     => { path => 'version/text()' },
                OS          => { path => 'os/text()' },
             }
);

#############################################
# url:xmpp:time
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => JABBER_TIME,
    tag => 'time',
    xpath => {
                TZO         => { path => 'tzo/text()' },
                UTC         => { path => 'utc/text()' }
             }
);

#############################################
# http://jabber.org/protocol/disco#info
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => JABBER_DISCOVERY,
    tag => 'query',
    xpath => {
    
                Feature    => { 
                                path => 'feature',
                                type => 'child',
                                child => { ns => JABBER_DISCOVERY_FEATURE },
                                calls => [ 'Add', 'Defined' ]
                              },
                              
                Features   => { 
                                path => 'feature/@var',
                                type => 'array',
                                calls => [ 'Get' ]
                              },
                              
                Identity   => { 
                                path => 'identity', 
                                type => 'child', 
                                child => { ns => JABBER_DISCOVERY_IDENTITY },
                                calls => [ 'Add', 'Defined' ]
                              },
                Identities   => { 
                                path => 'identity', 
                                type => 'child', 
                                child => { ns => JABBER_DISCOVERY_IDENTITY },
                                calls => [ 'Get' ]
                              }
             }
);


# ------------------------------------------------------------------------------------------------------------------------
# Private XML Namespace registrations
# ------------------------------------------------------------------------------------------------------------------------

#############################################
# __netxmpp__:http://jabber.org/protocol/disco#info:identity
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => JABBER_DISCOVERY_IDENTITY,
    tag => 'identity',
    xpath => {
                Name        => { path => '@name' },
                Category    => { path => '@category' },
                Type        => { path => '@type' },

                Item        => { type => 'main' }
             }
);

#############################################
# __netxmpp__:http://jabber.org/protocol/disco#info:feature
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => JABBER_DISCOVERY_FEATURE,
    tag => 'feature',
    xpath => {
                Var        => { path => '@var' },
             }
);

#############################################
# __netxmpp__:acrchipel:query
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLARCHIPEL_QUERY,
    tag => 'query',
    xpath => {
                 Node        => { path => 'archipel', type => 'child', child => { ns => XMLARCHIPEL } },
                 Raw         => { path => 'raw', type => 'raw' },
                 XMLNS       => { path => '@xmlns' }
             }
);

#############################################
# __netxmpp__:acrchipel
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLARCHIPEL,
    tag => 'archipel',
    xpath => {
                  # Custom payload
                  Raw       => { path => 'raw', type => 'raw' },
                  Text      => { path => 'text()' },

                  # Archipel action
                  Action    => { path => '@action' }
             }
);


#############################################
# iagent:pubsub:entry
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => IAGENT_PUBSUB_ENTRY_DATA,
    tag => 'data',
    xpath => {
                  # Custom payload
                  Raw       => { path => 'raw', type => 'raw' },
                  Text      => { path => 'text()' },

                  # Payload type
                  Type      => { path => '@type' }                  
             }
);

#############################################
# http://jabber.org/protocol/pubsub#event:items
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_EVENT_ITEMS,
    tag => 'items',
    xpath => {
                  Node   =>     { path  => '@node' },
                  Entries =>    {
                                  path  => 'item/entry',
                                  type  => 'child',
                                  child => { ns => IAGENT_PUBSUB_ENTRY },
                                  calls => [ 'Get' ]
                                },
                  RawEntries => {
                                  path  => 'item/entry',
                                  type  => 'child',
                                  child => { ns => XMLPUBSUB_ITEM },
                                  calls => [ 'Get' ]
                                }
             }
);

#############################################
# __netxmpp__:http://jabber.org/protocol/pubsub:item
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_ITEM,
    tag   => "item",
    xpath => {
                 Raw    =>      { path => 'item', type=>'raw' },
                 ID     =>      { path => '@id' }
             }
);

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
                  Node  => { path  => '@node' },
                  Type  => { path  => '@type' },
             }
);

#############################################
# __netxmpp__:http://jabber.org/protocol/pubsub:delete
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_DELETE,
    tag => 'delete',
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
                  JID   => { path  => '@jid', type => 'jid' }
             }
);

#############################################
#__netxmpp__:http://jabber.org/protocol/pubsub:subscription
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_SUBSCRIPTION,
    tag => 'subscription',
    xpath => {
                  Node         => { path  => '@node' },
                  JID          => { path  => '@jid', type => 'jid' },
                  SubID        => { path  => '@subid' },
                  Subscription => { path  => '@subscription' },
                  Item         => { type  => 'master' }
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
                  Entry => { 
                                path => 'item/entry',
                                type => 'child',
                                child => { ns => XMLPUBSUB_PUBLISH_ENTRY }
                           },
                  ID    => { path => 'item/@id' }
                           
             }
);

#############################################
#__netxmpp__:http://jabber.org/protocol/pubsub:publish:entry
#############################################
&Net::XMPP::Namespaces::add_ns(
    ns    => XMLPUBSUB_PUBLISH_ENTRY,
    tag => 'entry',
    xpath => {
                  Raw   => { path => 'raw', type => 'raw' },
                  XMLNS => { path => '@xmlns' }
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
                  ID    => { path  => 'item/@id' }
             }
);


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
