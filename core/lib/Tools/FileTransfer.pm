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

package Tools::FileTransfer;

=head1 NAME

Tools::FileTransfer - File transfer utilities

=head1 DESCRIPTION

This module provides some file transfering utilities widely used by many agents.

=head1 FUNCTIONS

The following functions are provided. Also check the L</"SUPPORTED URIs"> for a list
of the supported URIs for file transfers:

=cut

use strict;
use warnings;
use Data::UUID;
use MIME::Base64;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(get_file put_file);
 
#######################################
# Fetch a remote file

=head1 get_file URI, FILENAME, TARGET, [ Parameters => ... ]

Download a file using the specified protocol definition in URI and save it to TARGET.

=cut

sub get_file {
#######################################
    my $uri = shift;
    my $filename = shift;
    my $target = shift;
    my %args = @_;
	my $uuid = Data::UUID->new()->create_str;

    # Process connection uri
    my ($proto, $url) = split(":",$uri,2);
	
	# Handle SCP/SFTP
    if (($proto eq 'scp') || ($proto eq 'sftp')) {

    	# Prepare identity file
    	my $identity = "/tmp/$uuid.id";
    	open(IDF,">$identity"); print IDF $args{key}; close(IDF);
        chmod 0400, $identity;
        
        # SCP Get the file
    	my $ret = system("scp", 
    	    "-i", $identity, 
    	    $url.'/'.$filename, 
    	    $target);

    	# Remove identity file
    	unlink($identity);

        # Return result
    	return $ret unless ($ret == 0);

 	# Handle CHIRP
    } elsif ($proto eq 'chirp') {

        # Split more details from the URI
        my ($server, $F) = split('/',$url,2);
        my ($folder, $key) = split(/\?/,$F,2);
        
    	# Prepare identity file
    	my $identity = "/tmp/$uuid.id";
    	open(IDF,">$identity"); print IDF decode_base64($key); close(IDF);
        chmod 0400, $identity;

        # CHIRP Get the file
    	my $ret = system("chirp", 
	        "-a", "ticket",
    	    "-i", $identity, 
    	    $server,
    	    "get",
    	    "/$folder/$filename",
    	    $target);

    	# Remove identity file
    	unlink($identity);

    	# Return result
    	return $ret unless ($ret == 0);
    	
	} elsif ($proto eq 'nfs') {

	} elsif ($proto eq 'smb') {

	} elsif ($proto eq 'ftp') {

	} elsif (($proto eq 'http') || ($proto eq 'https')) {
    
    } else {
        print("Unknown transfer protocol: $proto");
        return 1;
        
    }
    
    return 0;
}


#######################################
# Fetch a remote file

=head1 put_file URI, SOURCE, FILENAME, [ Parameters => ... ]

Upload the SOURCE file using the specified protocol definition in URI and save it to FILENAME on the remote server.

=cut

sub put_file {
#######################################
    my $uri = shift;
    my $target = shift;
    my $filename = shift;
    my %args = @_;
	my $uuid = Data::UUID->new()->create_str;

    # Process connection uri
    my ($proto, $url) = split(":",$uri,2);
	
	# Handle different URI types
    if (($proto eq 'scp') || ($proto eq 'sftp')) {

    	# Prepare identity file
    	my $identity = "/tmp/$uuid.id";
    	open(IDF,">$identity"); print IDF $args{key}; close(IDF);
        chmod 0400, $identity;
        
        # SCP Get the file
    	my $ret = system("scp", 
    	    "-i", $identity, 
    	    $target,
    	    $url.'/'.$filename
    	    );
    	
    	# Remove identity file
    	unlink($identity);

        # Return failure
    	return $ret unless ($ret == 0);

 	# Handle CHIRP
    } elsif ($proto eq 'chirp') {

        # Split more details from the URI
        my ($server, $F) = split('/',$url,2);
        my ($folder, $key) = split(/\?/,$F,2);

    	# Prepare identity file
    	my $identity = "/tmp/$uuid.id";
    	open(IDF,">$identity"); print IDF decode_base64($key); close(IDF);
        chmod 0400, $identity;

        # CHIRP Get the file
    	my $ret = system("chirp", 
    	    "-a", "ticket",
    	    "-i", $identity, 
    	    $server,
    	    "put",
    	    $target,
    	    "/$folder/$filename");

    	# Remove identity file
    	unlink($identity);

    	# Return failure
    	return $ret unless ($ret == 0);

	} elsif ($proto eq 'nfs') {
        
	} elsif ($proto eq 'smb') {

	} elsif ($proto eq 'ftp') {

	} elsif (($proto eq 'http') || ($proto eq 'https')) {
        
    } else {
        print("Unknown transfer protocol: $proto");
        return 1;
        
    }
    
    return 0;
}


=head1 SUPPORTED URIs

=head2 SCP/SFTP

You can exchange files through SCP/SFTP using the following uri:

C<scp:username@hostname:base_directory>

=over

=item username

The username to use as log-in.

=item hostname

The hostname where the SSH server runs.

=item base_directory

The name the directory where the file operations are relative to.

=back

=head2 CHIRP

You can exchange files through CHIRP protocol using the following uri:

C<chirp:hostname/base_directory?token>

=over

=item hostname

The hostname where the CHIRP server runs.

=item base_directory

The name the directory where the file operations are relative to.

=item token

The authentication token to use in BASE64-encoded format.

=back


=head1 AUTHOR

Developed by Ioannis Charalampidis <ioannis.charalampidis@cern.ch> 2011-2012 at PH/SFT, CERN

=cut

1;