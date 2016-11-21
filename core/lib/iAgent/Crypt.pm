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

iAgent::Crypt - Cryptographic module for iAgent

=head1 DESCRIPTION

This module provides shorthands for accessing system-wide signing and encrypting fucntions.

=head1 REQUIRE CONFIGURATION

The following parameters are required in you iAgent configuration

 <Crypto>
    
    MasterKey           "AnyRandomString"   # The master key to encrypt the keystore entries
    AllowUntrusted      0|1                 # Set to 1 to allow decryption using the DefaultKey from untrusted sources
    DefaultCipher       "AES"               # The default cipher to use for the cryptographic operations
    DefaultKey          "EverythingKey"     # Default key of encrypting/decrypting any traffic
                                            # If missing, per-user configuration is required
    DefaultPermissions  "read"              # The default permissions any user will have if the user is not found in the database
    KeystoreTable       "crypto_keystore"   # THe table where to lookup the dynamic part of the keystore
    
    <User "jid">                            # Per-user configuration
        key                                 # The secret to use for communication with the specified user
        permissions     "read,write"        # A comma-separated list of permissions (roles) to add to the user
    </User>
    ...
 
 </Crypto>

=cut

package iAgent::Crypt;
use strict;
use warnings;
use iAgent::Log;
use iAgent::Kernel;
use iAgent::DB;
use Data::Dumper;
use MIME::Base64;
use Crypt::CBC;
use JSON;

require Exporter;
our @ISA        = qw(Exporter);
our @EXPORT     = qw(Encrypt Decrypt EncryptFor DecryptFrom ImportKey DeleteKey CanEncryptFor IsTrusted IsKeystoreChanged PermissionsOf ReloadKeystore);
our $DRIVER     = undef;

# Some constants
sub SYSTEM_DEFAULT_CIPHER   { "AES" };

# Dynamic and predefined keystore
my  $KEYSTORE = { };
my  @KEYSTORE_JIDS;

# User permissions
my $PERMISSIONS = { };

# Some keys required by the system
my  $DEFAULT_CIPHER = undef;
my  $DEFAULT_PERMISSIONS = [ ];
my  $MASTER_CIPHER = undef;
my  $ALLOW_UNTRUSTED = 0;
my  $KEYSTORE_TABLE = "crypto_keystore";
my  $LAST_KEYSTORE_ID = 0;

############################################
# Initialize the Crypt engine
sub Initialize {
############################################
    my ($keystore) = shift;
    my @lines;
    
    # Fetch keystore table if defined
    if (defined($keystore->{KeystoreTable})) {
        $KEYSTORE_TABLE = $keystore->{KeystoreTable};
    }
    
    # Extract master key from the config
    if (!defined($keystore->{MasterKey})) {
        log_error("Master key is missing, the dynamic keystore will be disabled!");
        
    } else {
        
        # Initialize database
        DB->do(DBQ("CREATE TABLE IF NOT EXISTS $KEYSTORE_TABLE (
        	 id integer PRIMARY KEY [[AUTOINCREMENT]],
        	 jid varchar(128),
        	 keydata TEXT
        )"));
        
        # Setup master AES key
        $MASTER_CIPHER = _cipher_instance($keystore->{MasterKey}, SYSTEM_DEFAULT_CIPHER);
        
    }
    
    # Check if we have default permissions
    if (defined($keystore->{DefaultPermissions})) {
        $DEFAULT_PERMISSIONS=_get_permissions($keystore->{DefaultPermissions});
    }
    
    # Check if we must use a default cipher
    if (defined($keystore->{DefaultKey})) {
        
        # Setup default cipher
        $DEFAULT_CIPHER = _cipher_instance(
            $keystore->{DefaultKey},
            $keystore->{DefaultCipher}
            );
            
        # Check if we should also allow untrusted
        $ALLOW_UNTRUSTED=1 if ($keystore->{AllowUntrusted});
    }
    
    # Reset keystore and permissions
    $KEYSTORE = { };
    $PERMISSIONS = { };
    
    # Import hard-coded entries
    if (defined($keystore->{User})) {
        foreach my $jid (keys %{$keystore->{User}}) {
            my $entry = $keystore->{User}->{$jid};
            my $key = $entry->{key};
            my $perm = $entry->{permissions};
            
            # Process permissions
            if (!$perm) {
                $perm = $DEFAULT_PERMISSIONS;
            } else {
                $perm = _get_permissions($perm);
            }
            
            # Store the cipher for this user
            $KEYSTORE->{$jid} = _cipher_instance(
                $key,
                $keystore->{DefaultCipher}
                );
            
            # Store the permissions for this user
            $PERMISSIONS->{$jid} = $perm;
        }
    }
    
    # Reload keystore
    iAgent::Crypt::LoadKeystore();
}

#===========================================
# Utility function to convert a comma-separated
# permissions list to a hash in permission => 1
# format
sub _get_permissions { 
#===========================================
    my $str = shift;
    my @parts = split(",", $str);
    my $ans = { };
    foreach my $k (@parts) {
        $k =~ s/\s+//g;
        $ans->{$k}=1;
    }
    return $ans;
}

#===========================================
# Utility function to return an instance of
# the algorithm responsible to encrypt/decrypt
# data from the specified key.
sub _cipher_instance {
#===========================================
    my ($key, $algo) = @_;
    $algo=SYSTEM_DEFAULT_CIPHER unless defined($algo);
    
    # AES encryption
    if ($algo eq 'AES') {
        
        # Create an AES/CBC instance
        return Crypt::CBC->new(
                 -key    => $key,
                 -cipher => "Crypt::OpenSSL::AES"
        );
        
    } else {
        log_warn("Unknown algorithm '$algo' specified for private key.");
        return undef;
    }
    
}

#===========================================
# Utility function to check domain and user-
# wide resources.
sub _keystore_id {
#===========================================
    my $jid = shift;
    if (defined $KEYSTORE->{$jid}) {
        # This also checks resource-wide
        return $jid;
        
    } elsif ($jid =~ m/^([^@]+)(@[^\/]+)?(\/.*)?/) {
        
        if (defined($2) && (defined $KEYSTORE->{"$1$2"})) {
            # Check domain-wide
            return "$1$2";
            
        } elsif (defined $KEYSTORE->{$1}) {
            # Check user-wide
            return $1;
            
        } else {
            # Not found
            return undef;
        }
        
    } else {
        return undef;
    }
}

#===========================================
# Get the last record ID in the keystore
sub _last_entry_id {
#===========================================

    # Prepare row
    my $row = DB->selectrow_arrayref(qq{
        SELECT id FROM ${KEYSTORE_TABLE} ORDER BY id DESC LIMIT 0,1
    }) || return 0;
    
    # Return the ID
    return $row->[0];

}

############################################
# Import a key in the database
sub ImportKey {
############################################
    my ($jid, $key, $cipher, $permissions) = @_;
    $cipher=SYSTEM_DEFAULT_CIPHER unless defined($cipher);
    return RET_ERROR if (!$MASTER_CIPHER);
    
    # If we already have this entry, drop the previous
    if (defined($KEYSTORE->{$jid})) {
        delete $KEYSTORE->{$jid};
        DB->do("DELETE FROM $KEYSTORE_TABLE WHERE jid = ?", undef, $jid);
    }
    
    # Process permissions
    $permissions=$DEFAULT_PERMISSIONS unless defined($permissions);
    if (UNIVERSAL::isa($permissions,'ARRAY')) {
        my $perm={ };
        foreach my $k (@$permissions) {
            $perm->{$k}=1;
        }
        $permissions=$perm;
        
    } elsif (!UNIVERSAL::isa($permissions,'HASH')) {
        $permissions=_get_permissions($permissions);
    }
    
    # Prepare key data
    my $data = encode_json({
        Cipher => $cipher,
        Key => $key,
        Permissions => $permissions
    });
    log_msg("Importing key for user $jid");
    
    # Encrypt data using the master key
    $data = encode_base64($MASTER_CIPHER->encrypt($data), '');
    
    # Insert entry
    my $sth = DB->prepare("INSERT INTO $KEYSTORE_TABLE ( jid, keydata ) VALUES ( ?, ? )");
    return RET_ERROR if(!$sth);
    return RET_ERROR if (!$sth->execute(
        $jid,
        $data
    ));

    # Also import key in the cache
    $KEYSTORE->{$jid} = _cipher_instance($key, $cipher);
    $PERMISSIONS->{$jid} = $permissions;

    # Return ok
    return RET_OK;
}

############################################
# Delete a previously defined key
sub DeleteKey {
############################################
    my $jid = shift;
    return RET_ERROR if (!$MASTER_CIPHER);

    # Delete entry
    DB->do("DELETE FROM $KEYSTORE_TABLE WHERE jid = ?", undef, $jid);
    delete $KEYSTORE->{$jid};
    delete $PERMISSIONS->{$jid};
    
    # Return OK
    return RET_OK;
}

############################################
# Load the keys from the database
sub LoadKeystore {
############################################
    
    # Lookup instances in the database and update the resource consumption
    my $sth = DB->prepare("SELECT * FROM $KEYSTORE_TABLE");
    return RET_ERROR if(!$sth);
    $sth->execute();
    
    # Reset the last ID
    $LAST_KEYSTORE_ID = 0;
    
    # Update keystore
    if (defined($MASTER_CIPHER)) {
        while (my $r = $sth->fetchrow_hashref()) {
        
            # Update ID
            $LAST_KEYSTORE_ID = $r->{id} if ($r->{id} > $LAST_KEYSTORE_ID);
        
            # Decrypt the data stored in the DB using the master key
            my $keydata = $MASTER_CIPHER->decrypt(decode_base64($r->{keydata}));
            if (!$keydata) {
                log_warn("Unable to decrypt keystore information for jid ".$r->{jid});
                next;
            }
            my $keyinfo = decode_json($keydata);
            if (!$keyinfo) {
                log_warn("Unable to process keystore information for jid ".$r->{jid});
                next;
            }
        
            # Compatibility with old keys
            $keyinfo->{Permissions} = [] unless defined($keyinfo->{Permissions});
        
            # Register the key and permissions
            $KEYSTORE->{$r->{jid}} = _cipher_instance($keyinfo->{Key}, $keyinfo->{Cipher});
            $PERMISSIONS->{$r->{jid}} = $keyinfo->{Permissions};
            
            # This JID is loaded from keystore
            push @KEYSTORE_JIDS, $r->{jid};
            
        }
    }
    
}

############################################
# Reload the dynamic keystore
sub ReloadKeystore {
############################################
    
    # Remove all the jids that were registered dynamically
    for my $jid (@KEYSTORE_JIDS) {
        delete $KEYSTORE->{$jid};
        delete $PERMISSIONS->{$jid};
    }
    
    # Load keystore again
    @KEYSTORE_JIDS = ( );
    LoadKeystore();
    
}

############################################
# Check if encryption information are provided
# for the specified user.
sub CanEncryptFor {
############################################
    my $jid = shift;
    $jid = _keystore_id($jid) or return 0;
    return 0 if (!defined($KEYSTORE->{$jid}) && (!$ALLOW_UNTRUSTED));
    return 1;
}

############################################
# Return the permissions of the specified JID
sub PermissionsOf {
############################################
    my $jid = shift;
    $jid = _keystore_id($jid) or return undef;
    if (defined($PERMISSIONS->{$jid})) {
        return $PERMISSIONS->{$jid};
    } elsif ($ALLOW_UNTRUSTED) {
        return $DEFAULT_PERMISSIONS;
    } else {
        return undef;
    }
}

############################################
# Encrypt data for a specific JID
sub EncryptFor {
############################################
    my ($ujid, $data) = @_;
    my $cipher;
    
    my $jid = _keystore_id($ujid);
    if (!defined($jid)) {
        return undef if (!defined($DEFAULT_CIPHER)); # << Enable encryption to everybody
        $cipher = $DEFAULT_CIPHER;
    } else {
        $cipher = $KEYSTORE->{$jid};
    }
    
    # Ecnrypt using the appropriate cipher function
    my $ans = undef;
    eval {
        $ans=$cipher->encrypt($data);
    };
    if ($@) {
        log_error("Encryption error for user $ujid: $@");
    };
    
    # Return answer
    return $ans;
}

############################################
# Decrypt data that came from a specified JID
sub DecryptFrom {
############################################
    my ($ujid, $data) = @_;
    my $cipher;
    my $jid = _keystore_id($ujid);
    if (!defined($jid)) {
        return undef if (!$ALLOW_UNTRUSTED); # << Require decryption only from trusted entities
        $cipher = $DEFAULT_CIPHER;
    } else {
        $cipher = $KEYSTORE->{$jid};
    }
    
    # Ecnrypt using the appropriate cipher function
    my $ans = undef;
    eval {
        $ans=$cipher->decrypt($data);
    };
    if ($@) {
        log_error("Decryption error from user $ujid: $@");
    };
    
    # Return answer
    return $ans;
}

############################################
# Encrypt using a predefined cipher
sub Encrypt {
############################################
    my ($data, $key, $algo) = @_;
    
    # Instance cipher
    my $cipher = _cipher_instance($key, $algo);
    return undef if (!defined($cipher));
    
    # Ecnrypt using the appropriate cipher function
    my $ans = undef;
    eval {
        $ans=$cipher->encrypt($data);
    };
    if ($@) {
        log_error("Could not encrypt requested data: $@");
    };
    
    # Return answer
    return $ans;
}

############################################
# Decrypt using a predefined cipher
sub Decrypt {
############################################
    my ($data, $key, $algo) = @_;

    # Instance cipher
    my $cipher = _cipher_instance($key, $algo);
    return undef if (!defined($cipher));

    # Ecnrypt using the appropriate cipher function
    my $ans = undef;
    eval {
        $ans=$cipher->encrypt($data);
    };
    if ($@) {
        log_error("Could not decrypt requested data: $@");
    };

    # Return answer
    return $ans;
}

############################################
# Return TRUE if the specified user is trusted
# A user is 'trusted' if it's username is found
# in the keystore.
sub IsTrusted {
############################################
    return 1 if ($ALLOW_UNTRUSTED);
    my $user = shift;
    return defined(_keystore_id($user));
}

############################################
# Check if the keystore is changed
############################################
sub IsKeystoreChanged {
    my $id = _last_entry_id();
    return 1 if ($id > $LAST_KEYSTORE_ID);
    return 0;
}

1;
