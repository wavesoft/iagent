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

iAgent::Module::REST - REST Web API

=head1 DESCRIPTION

This module exposes specific API messages defined in the iAgent infrastructure via a REST API.

=cut

# Core definitions
package iAgent::Module::REST;

use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;

use URI;
use POE;
use POE::Component::Server::HTTP;
use HTTP::Status;
use Data::Dumper;

our $MANIFEST = {
    # The API module is safe to be reloaded without serious issues
    oncrash => 'reload',
    
    API => {
        "test" => {
            message => "api_test"
        }
    }

};


############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { 
        COMMANDS => {},
        SERVER => undef
    };
    return bless $self, $class;
}

############################################
# Modules loaded, scan all the modules that
# expose API calls.
sub __ready {
############################################
    my ($self, $kernel, $heap, $session) = @_[ OBJECT, KERNEL, HEAP, SESSION ];

    # ------------------------
    # |  LOAD API BINDINGS   |
    # ------------------------
    my $API_COMMANDS = {};
    for my $inf (@iAgent::Kernel::SESSIONS) {
        my $heap = $inf->{session}->get_heap();
    	my $manifest = $heap->{MANIFEST};
    	
        # Fetch API commands
    	if (defined $manifest->{API}) {
    	    foreach my $k (keys %{$manifest->{API}}) {
    	        # Warn overwrites
    	        log_warn("API Command $k is already defined by ".$API_COMMANDS->{$k}->{class}) if (defined($API_COMMANDS->{$k}));
    	        
    	        # Get value
    	        my $v=$manifest->{API}->{$k};
    	        if (!ref($v)) { $v={ message => $v }; };
    	        
    	        # Store entry
    	        $API_COMMANDS->{$k} = {
    	            class => $inf->{class},
    	            session => $inf->{session},
    	            message => $v->{message}
    	        };
    	        
    	    }
	    }
	    
    }
    
    # Store API database
    $self->{COMMANDS} = $API_COMMANDS;
    
    # Start the Web Server
    $self->{SERVER} = POE::Component::Server::HTTP->new(
       Port => 8000,
       ContentHandler => { 
           '/' => sub { return $self->_handler(@_); } 
       },
       Headers => { Server => 'iAgent::REST/1.0' }
    );
    
    # Notify that we are ready
    log_msg("Started REST API server on 0.0.0.0:8000")
    
}

############################################
# Test function for API
sub __api_test {
############################################
    my ($self, $request) = @_[OBJECT, ARG0];
    
    return {
        data => "OK"
    };
}

############################################
# Handler for the REST Requests
sub _handler {
############################################
    my ($self, $request, $response) = @_;
    my $uri = URI->new($request->uri);
    my %args = $uri->query_form;
    
    # Ensure we have an action defined
    if (!defined $args{action}) {
        $response->code(400);
        $response->content("Action is not specified!");
        return RC_OK;
    }
    
    # Prepare request
    my $action = $args{action};
    delete $args{action};
    
    # Lookup action
    my $handler = $self->{COMMANDS}->{$action};
    if (!defined $handler) {
        $response->code(404);
        $response->content("Action was not found!");
        return RC_OK;
    }
    
    # Send the request to the API Handler
    my $ans = POE::Kernel->call($handler->{session}, $handler->{message}, \%args);
    
    # Build response
    $response->code(200);
    $response->content(Dumper($ans));
    return RC_OK;   
}

