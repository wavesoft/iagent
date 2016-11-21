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

iAgent::Module::XMPP::VCard - VCard implementation for the XMPP Module

=head1 DESCRIPTION

TODO

=head1 PROVIDED EVENTS

TODO

=cut

# Basic definitions
package iAgent::Module::XMPP::VCard;
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
use XML::Simple;
use HTML::Entities;
use MIME::Base64;

##===========================================================================================================================##
##                                              INITIALIZE SUBMODULE                                                         ##
##===========================================================================================================================##

#######################################
# Called when XMPP module is initializing
sub init {
#######################################
    my ($self, $XMPPCon) = @_;

    # Buld my vCard as an XML::Stream::Node 
    # and save it back to me
    $self->{vCard} = $self->build_vcard();

    # Register VCard response callback
    $XMPPCon->SetXPathCallBacks(
    
        # VCard Requested
        "/iq/vcard"  => sub { shift; return $self->CALLBACK_IQ_VCARD(@_) },        
        
    );

}

#######################################
# Called when XMPP module is connected
sub connected {
#######################################
    my ($self, $XMPPCon) = @_;
    
	# Update my vCard
	log_debug("Sending vCard Update");
	$self->update_vcard();

}

##===========================================================================================================================##
##                                        CALLBACKS FOR NET::XMPP::CLIENT                                                    ##
##===========================================================================================================================##

#######################################
sub CALLBACK_IQ_VCARD {
#######################################
    my ($self, $packet) = @_;
    my $XMPPCon = $self->{XMPPCon};
    log_debug("IQ VCard callback: ".$packet->GetXML);

    # Prepare reply
    my $iq = $packet->Reply(
        type => 'result'
    );

    # Update tree with the (already built) VCard
    my $tree = $iq->GetTree();
    $tree->add_child($self->{vCard});
    
    log_debug("Sending IQ vCard XML Reply: ".$tree->GetXML());

    # And send
    $XMPPCon->Send($tree);

}

##===========================================================================================================================##
##                                               HELPER FUNCTIONS                                                            ##
##===========================================================================================================================##

#######################################
# Reads an image file and builds the
# appropriate base64 chunk (for vCard)
sub build_photo {
#######################################
    my ($file) = @_; 
    my $ext = substr($file, -4);
    my $mime = "image/unknown";
    
    # Simple detection of content
    if ($ext eq ".png") {
    	$mime = "image/png";
    } elsif ($ext eq ".gif") {
        $mime = "image/gif";        
    } elsif ($ext eq ".jpg") {
        $mime = "image/jpeg";        
    } elsif ($ext eq ".bmp") {
        $mime = "image/bmp";        
    }
    
    # Detect absolute/relative filename
    if (not (substr($file,0,1) eq "/")) {
    	$file = $iAgent::ETC.'/'.$file;
    }
    
    # Read image to buffer
    if (!open IMAGE, $file) {
    	log_warn("Unable to read file $file");
    	return "";
    }
    my $bin_buf = join"",<IMAGE>;
    close IMAGE;

    # Return image    
    return "<TYPE>".$mime."</TYPE><BINVAL>".encode_base64($bin_buf,"")."</BINVAL>";

}

##===========================================================================================================================##
##                                             VCARD IMPLEMENTATION                                                          ##
##===========================================================================================================================##

#######################################
# Build a XML::Stream::Node XML out of my vcard config
sub build_vcard {
#######################################
    my ($self) = @_;
    my $vcard = new XML::Stream::Node('vCard');
    $vcard->put_attrib(
         xmlns => "vcard-temp"
    );
    
    # Import the vcard entries
    for my $VCItem (keys %{$self->{config}->{XMPPVCard}}) {
        my $VCI = uc $VCItem;
        if ($VCI eq "PHOTO") {
            $vcard->add_raw_xml("<PHOTO>".build_photo($self->{config}->{XMPPVCard}->{$VCItem})."</PHOTO>");
        } else {
            $vcard->add_raw_xml("<$VCI>".encode_entities($self->{config}->{XMPPVCard}->{$VCItem})."</$VCI>");
        }
    }
    
    return $vcard;
}

#######################################
# Update the vCard to the server
sub update_vcard {
#######################################
    my ($self) = @_;
    my $XMPPCon = $self->{XMPPCon};

    my $iq = new Net::XMPP::IQ();
    $iq->SetType("set");
    $iq->SetID(iAgent::Module::XMPP::get_uid());
    
    my $xml = $iq->GetTree();
    $xml->add_child($self->{vCard});

    #log_debug("Sending IQ vCard XML Update: ".$xml->GetXML());

    # And send
    $XMPPCon->Send($xml);

}

#######################################
# Fetch the vcard information of the
# specified user.
sub update_user_vcard {
#######################################
    my ($self, $jid) = @_;
    my $XMPPCon = $self->{XMPPCon};

    # Prepare VCard-Temp IQ
    my $iq = new Net::XMPP::IQ();
    my $id = iAgent::Module::XMPP::get_uid();
    $iq->SetType("get");
    $iq->SetFrom($self->{me});
    $iq->SetTo($jid);

    # Add the vcard request node    
    my $xml = $iq->GetTree();
    $xml->add_raw_xml("<vCard xmlns='vcard-temp'/>");
    log_debug("Requesting vCard for $jid: ".$xml->GetXML());

    # Send IQ request and wait for response
    my $ans = $XMPPCon->SendAndReceiveWithID($xml->GetXML(), $id);
    if ($ans) {
        if ($ans->GetType() eq 'error') {
            log_warn("Unable to get vcard of user $jid: " . $ans->GetError());
        } else {
            my $body = $ans->GetTree();
            my @children = $body->children();
            $self->{USERS}->{$jid}->{vcard} = XMLin($children[0]->GetXML());
            log_debug("User vcard updated from $jid");
        }
    } else {
        log_warn("Unable to get vcard of user $jid");
    }
}

=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
