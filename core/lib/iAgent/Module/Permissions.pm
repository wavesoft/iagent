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

iAgent::Module::Permissions - Permissions provider based on local database

=head1 DESCRIPTION

This module provides local permissions management.

=head1 INTERCEPTED EVENTS

This module intrecepts the following messages

=head2 comm_action  

=cut

package iAgent::Module::Permissions;
use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;
use File::Basename;
use POE;
use Data::Dumper;
use HTML::Entities; 
use DBI;

# Define the module's manifest
our $MANIFEST = {
    
    # Use 'ldap.conf' as our config file
    config => 'iagent.conf',
    
    # Use autodetection for the events, 
    # using the '__' for event prefix
    hooks => 'AUTO',
    
    # Go right after XMPP
    priority => 1
    
};

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    
    # Detect database
    my $DB = config->{PermissionsDB};
    
    # Make subdir(s) if needed
    [ ! -d dirname($DB) ] && mkdir dirname($DB);
    
    # Prepare self
    my $self = {
        	DefaultPerm => { },
        	Permissions => { },
        	PermissionsDBNS => 'dbi:SQLite:'.$DB
        	me => ''
    };
    $self = bless $self, $class;
    
    # Connect DB
    $self->db_connect();

    # Everything was ok
    return bless $self, $class;
}


############################################
# Connect to the database
sub db_connect {
############################################
    my ($self) = @_;
    my $dbh = 0;
    
    eval {
    
        # Connect to the DB
        $dbh = DBI->connect($self->{config}->{WorkflowDBDSN},{
                             AutoCommit => 1,
                             RaiseError => 1
                           });
    
        # Check for failure
        if (!$dbh) {
            log_warn("Error while trying to connecto to DSN ".$self->{config}->{WorkflowDBDSN}."! $DBI::errstr");
            return 0;
        }
       
   };
   if ($@) {
       	iAgent::Kernel::Crash("Error trying to connect to DSN".$self->{config}->{WorkflowDBDSN}."!: ".$@);
        return 0;
   }
   return $dbh;
}

############################################
# Initialize database
sub db_init {
############################################
    my ($self) = @_;
    my $dbh = $self->db_connect();
    if (!$dbh) {
       	iAgent::Kernel::Crash("Unable to initialize database!");
       	return;
    }
    
    # Store DBH instance
    $self->{dbh} = $dbh;
    
    # Create missing tables
    $dbh->do("CREATE TABLE IF NOT EXISTS workflow_definitions (
	     wid            INTEGER PRIMARY KEY,
	     name           VARCHAR(120),
	     maxdepth       INTEGER,
	     description    TEXT,
	     script         TEXT
    )");

    $dbh->do("CREATE TABLE IF NOT EXISTS workflow_instances (
	     did            VARCHAR(64) PRIMARY KEY,
	     rootiid        VARCHAR(64),
	     wid            INTEGER,
	     status         VARCHAR(60) DEFAULT 'pending',
	     started        DATE,
	     updated        DATE,
	     curraction     INTEGER,
	     message        TEXT,
	     result         INTEGER
    )");

    $dbh->do("CREATE TABLE IF NOT EXISTS workflow_actions (
	     iid            VARCHAR(64) PRIMARY KEY,
	     did            VARCHAR(64),
	     wid            INTEGER,
	     aid            INTEGER,
	     target         VARCHAR(120),
	     status         VARCHAR(60) DEFAULT 'running',
	     result         INTEGER,
	     started        DATE,
	     message        TEXT,
	     updated        DATE
    )");

}

###############################################################
# Query the permissions of the specified user
#
# Usage:
# my $can = permissionsOf("username")
#
# If an attribute is missing, the default option (as specified
# from the configuration file) will be used.
#
# Returns a hash reference like this:
# {
#    write : 1,
#    read  : 0
#    ...    
# }
# 
# Defined by the <Permission> directive of iagent.conf
#
sub permissionsOf {
###############################################################
    my ($self, $username) = @_;
    my $LDAPInfo = $self->{LDAPInfo};
    my $LDAPCon = $self->{LDAPCon};
    my %LDAPDefaultPerm = %{$self->{DefaultPerm}};
    
    # Check for overriden information for the specified user
    if (defined $LDAPInfo->{LDAPOverride}{$username}) {
        my $groups = [];
        my $any = 0;
        my $list = {};

        # Reset defaults, use everything => 0
        foreach my $k (keys %LDAPDefaultPerm) {
            $list->{$k} = 0;
        }
        
        # Extract groups for the user
        if (UNIVERSAL::isa($LDAPInfo->{LDAPOverride}{$username}{LDAPGroup}, 'ARRAY')) {
        	for my $G (@{$LDAPInfo->{LDAPOverride}{$username}{LDAPGroup}}) {
        		push @$groups, $G;
        	}
        } else {
	        $groups = [$LDAPInfo->{LDAPOverride}{$username}{LDAPGroup}];
        }

        # Map LDAP groups to access permissions
        foreach my $k (keys %{$LDAPInfo->{Permissions}}) {
            my $v = $LDAPInfo->{Permissions}->{$k};
            foreach my $grp (@$groups) {
                if ($v eq $grp) {
                    $any = 1;
                    $list->{$k} = 1;
                    last;
                }
            }
        } 
        
        # Append the 'any' permission
        # (We had at least one permission)
        $list->{any} = $any;     	
        
        # Return the user
        return $list;
    }
        
    # Search for the specified user
    my $filter = "(".$LDAPInfo->{LDAPNameAttrib}."=".$username.")";
    log_debug("Searching for $filter within ".$LDAPInfo->{LDAPSearchBase});
    my $mesg = $LDAPCon->search( # perform user search
                            base   => $LDAPInfo->{LDAPSearchBase},
                            filter => $filter
                          );
    $mesg->code && log_die('Unable to connect: '.$mesg->error);
    
    # Search the entries found
    my %defaults = %LDAPDefaultPerm; # Copy permissions hash
    my $list = \%defaults;
    log_debug("Got ".$mesg->count()." entries that match");
    if ($mesg->count() > 0) {
        
        # We have a user 
        # Forget defaults, use everything => 0
        foreach my $k (keys %defaults) {
            $defaults{$k} = 0;
        }
        
        # Search user's groups
        log_debug("Searching user's groups");
        my $entry = $mesg->pop_entry();
        my $groups = $entry->get_value("memberOf", asref => 1);
        my $any = 0;
        
        # Map LDAP groups to access permissions
        foreach my $k (keys %{$LDAPInfo->{Permissions}}) {
            my $v = $LDAPInfo->{Permissions}->{$k};
            foreach my $grp (@$groups) {
                if ($v eq $grp) {
                	$any = 1;
                    $list->{$k} = 1;
                    last;
                }
            }
        } 
        
        # Append the 'any' permission
        # (We had at least one permission)
        $list->{any} = $any; 
                
    } else {
        log_debug("User not found on LDAP");
    }
            
    # Return permissions
    return $list;
} 

###############################################################
# Convert the specified permissions hash to an archipel-
# compatible representation and return it.
sub permissions_xml {
###############################################################
    my ($self, $can) = @_;
    # Build and reply permissions
    my $buf = '';
    for my $perm (keys %{$can}) {
        $buf .= '<permission name="'.encode_entities($perm).'" />'
            if ($can->{$perm});
    }
    return $buf;
}

###############################################################
# Convert the specified permissions description hash to an
# archipel-compatible XML.
sub permissions_desc_xml {
###############################################################
    my ($self, $can) = @_;
    
    # Build and reply permissions
    my $buf = '';
    for my $perm (keys %{$can}) {
        $buf .= '<permission default="0" name="'.encode_entities($perm).'" description="'.encode_entities($can->{$perm}).'" />'
            if ($can->{$perm});
    }
    return $buf;
}

###############################################################
# It works just like permissionsOf, but uses cached
# results. Especially designed for being called often
sub cached_permissionsOf {
###############################################################
    my ($self, $kernel, $session, $SOURCE) = @_;
 
    # Check the source user's permissions
    my $can = $self->{Registry}->{$SOURCE};
    
    # Not found? Something went wrong and we missed
    # the comm_available for that user..
    if (not defined $can) {
        
        # Try again
        $kernel->call($session, 'comm_available', { from => $SOURCE });
        $can = $self->{Registry}->{$SOURCE};
        
        # Still not found?
        if (not defined $can) {
            
            # Then yes, you can't do anything...
            $can = {
                any => 0
            };
            $self->{Registry}->{$SOURCE} = $can;
            
        }
        
    }
    
    # Return the final stuff
    return $can;
}

############################################
sub ___setup { # Initialize module
############################################
    my ( $self, $kernel, $config ) = @_[ OBJECT, KERNEL, ARG0 ];
    
    # Initialize LDAP Connection
    log_debug("Connecting to LDAP: ".$config->{LDAPServer});
    $self->{LDAPCon} = Net::LDAP->new( $config->{LDAPServer} ) or log_die("Unable to instance LDAP: $@");

    # Bind
    log_debug("Binding to LDAP DN: ".$self->{LDAPInfo}->{LDAPBindDN});
    my $mesg = $self->{LDAPCon}->bind($self->{LDAPInfo}->{LDAPBindDN}, password => $self->{LDAPInfo}->{LDAPBindPassword} );
    $mesg->code && log_die('Unable to startup LDAP: '.$mesg->error);

    log_msg('LDAP Authentication module started');
    
    # Start main loop
    $kernel->yield('main');

}

############################################
sub __comm_ready { # Handle comm_ready
############################################
    my ($self, $msg) = @_[ OBJECT, ARG0 ];
    
    # When COMM is ready, it broadcasts
    # our local name. We need this in order
    # to bilndly allow messages sent by me
    $self->{me} = $msg->{me};
}

############################################
sub __comm_available { # Handle comm_available
############################################
	my ($self, $msg) = @_[ OBJECT, ARG0 ];
	my $FROM = $msg->{from};
	
	# Update user registry
    my @name = split "@", $FROM;
	$self->{Registry}->{$FROM} = $self->permissionsOf($name[0]);
	
	# Stringify permissions for debug
	my $s = "";
	foreach (keys %{$self->{Registry}->{$FROM}}) {
		if ($self->{Registry}->{$FROM}->{$_}) {
			$s.=',' unless ($s eq '');
			$s.=$_;
		}
	}
	log_debug("User $FROM is permitted to: $s");
}

############################################
sub __comm_unavailable { # Handle comm_unavailable
############################################
    my ($self, $msg) = @_[ OBJECT, ARG0 ];
    my $FROM = $msg->{from};
    
    # Update user registry
    delete $self->{Registry}->{$FROM};
    
    log_debug("Permissons for user $FROM flushed");
}

############################################
sub __main { # Intercept 'main'
############################################

    # Infinite block
    $_[KERNEL]->delay(main => 0.1);
    
}

############################################
sub __comm_action { # Intercept the actions
############################################
    my ($self, $kernel, $session, $msg) = @_[ OBJECT, KERNEL, SESSION, ARG0 ];    
    my $SOURCE = $msg->{from};
    
    log_debug("Checking validity of source $SOURCE");
    
    # Get my permissions
    my $can = cached_permissionsOf($self, $kernel, $session, $SOURCE);

    # Intercept archipel:permissions messages
    # and reply the permissions of the user
    if ($msg->{context} eq 'archipel:permissions') {
    	
        	# We might need the source's bare JID
        	my @bare_jid_parts = split "/", $SOURCE;
        	my $bare_jid = $bare_jid_parts[0];
        
        # Handle the get/getown
        if (($msg->{action} eq 'getown') and ($msg->{type} eq 'get')) {
            
            # Reply owner's permission
            if ($msg->{parameters}->{permission_target} eq $bare_jid) {
	            # Reply the permissions
	            iAgent::Kernel::Reply('comm_reply', { data => $self->permissions_xml($can) });
            	
            } else {
	            # Reply blank if the target is not me :)
	            # Because it's just forbidden..
	            iAgent::Kernel::Reply('comm_reply', { data => { } });
            	
            }
                            
            # Block message
            return 0;
            
        }
        
        # Handle the get/get
        elsif (($msg->{action} eq 'get') and ($msg->{type} eq 'get')) {
        	
            	# Do we have the permissions to read other people's pemissions?
            	my $perm = {};
            	if ($can->{permissions_get}) {
	                # Get the permissions of that user
	                my $perm = cached_permissionsOf($self, $kernel, $session, $msg->{parameters}->{permission_target});        		
            	}
            	
            	# Reply
                iAgent::Kernel::Reply('comm_reply', { data => $self->permissions_xml($perm) });
            	
            	# Block message
            	return 0;
            	
        }
        	
        # Handle the get/get
        elsif (($msg->{action} eq 'list') and ($msg->{type} eq 'get')) {

            # Return the list of the permissions available
            iAgent::Kernel::Reply('comm_reply', { data=> $self->permissions_desc_xml($self->{Permissions} ) });

            # Block message
            return 0;

        }
    }
    
    # Does the user have at least one
    # permission?
    if (!$can->{any}) {
    	
        	# Reply "unauthorized"
        iAgent::Kernel::Reply('comm_reply_error', { type => 'forbidden', code => 401, message => 'You do not have permission to perform '.$msg->{context}."/".$msg->{type}.":".$msg->{action} });    	
        	
        	return 0; # Block message
    	
    } else {
    	    	
	    # Inject permissions
	    # to the message
	    $msg->{permissions} = $can;
	
	    return undef; # Be invisible on the execution chain
	    
    }
}


=head1 CONFIGURATION

This module is looking for the configuration file 'ldap.conf' that should contain
the following entries:

  # LDAP Authentication
  LDAPServer       "mydc.company.com"
  LDAPBindDN       "cn=user,DC=mycompany,DC=com"
  LDAPBindPassword "v3ry$3cr3t"
  
  # Specify how we should find the user
  LDAPSearchBase   "OU=People,DC=mycompany,DC=com"
  LDAPNameAttrib   "cn"
  
  # LDAP Groups-to-permissions mapping
  <Permission admin>
      LDAPGroup    "CN=admins,OU=Groups,DC=mycompany,DC=com"
      
      # If default=1, and the user was not found on the database,
      # The permission will be granted. If the user was found, but
      # the group was missing, the pemission will be revoked.
      Default      0
  </Permission>


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;
