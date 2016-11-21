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

iAgent::Module::iBuilder - iBuilder Plugin for iAgent

=head1 DESCRIPTION

This module provides ability to manage iBuilder Projects and monitor the building process.

=head1 HANDLED ACTIONS

=cut

# Core definitions
package iAgent::Module::iBuilder;
use strict;
use warnings;

# Basic inclusions
use iAgent::Log;
use POE;

# Functional inclusions
use File::Basename;
use Data::Dumper;
use Config::General;
use HTML::Entities;

# The iBuilder Manifest
our $MANIFEST = {
    config => 'ibuilder.conf'    
};

# Some constants
my $XMLNS_IBUILDER_PROJECT = "archipel:ibuilder:projects";
my $XMLNS_IBUILDER_CONFIG  = "archipel:ibuilder:config";

############################################
# New instance
sub new {
############################################

	my ($class, $config) = @_; 
	my $self = {
		dir_projects => $config->{IBuildProjects},
		conf_global  => $config->{IBuildGlobalConfig},
		conf_local   => $config->{IBuildPrivateConfig}
	};
	return bless $self, $class;
}

=head2 archipel:ibuilder:projects/list

This action is a request to list the currently registered iBuilder proejcts.

Request:

    <query xmlns="archipel:ibuilder:projects">
        <archipel action="list">
    </query>

Reply:

    <project dir="dirname" name="projectname">
        <version ver="1" title="title" description="short description of the project" />
        ...
    </project>
    ...
    <model name=".." group=".." description=".." />
    ..
    <stage name=".." stage="..">
        <target project=".." model=".." imagetype=".." arch=".." uid="..">
    </stage>
    ..

=cut

############################################
# Handle the 'list_projects' action
sub iq_list_projects {
############################################
    my ($self) = @_;
    my $ans = "";
    
    opendir my($dh), $self->{dir_projects} or log_warn("Unable to open directory ".$self->{dir_projects}." for listing!") and return 0;
    my @files = readdir $dh;
    closedir $dh;
    
    for my $ENTRY (@files) {
        my $DIR = $self->{dir_projects}."/$ENTRY";
        
        # Do we have a directory entry? It's a project...
        if (-d $DIR and (substr($ENTRY,0,1) ne ".")) {
            
            # Extract project config file
            if (-f $DIR.'/project.conf') {
                            
                my $_conf = new Config::General($DIR.'/project.conf');
                my %config = $_conf->getall;
                
                $ans .= '<directory name="'.$ENTRY.'">';
                
                # Scan all the stages in this folder
                my $STAGES = {};
			    opendir my($dh), $DIR or log_warn("Unable to open directory ".$DIR." for listing!") and return 0;
			    my @stage_dirs = readdir $dh;
			    closedir $dh;
			    for my $STAGE_ENTRY (@stage_dirs) {
			        my $STAGE_DIR = $DIR."/$STAGE_ENTRY";

			        # Do we have a directory and a stage file?
			        if (-d $STAGE_DIR and (substr($STAGE_ENTRY,0,1) ne ".") and (-f "$STAGE_DIR/stage.conf")) {

                        log_debug("Folder validated and $STAGE_DIR/stage.conf exists");

                        # Load the config file
		                my $stage = new Config::General("$STAGE_DIR/stage.conf")->{DefaultConfig};
			        	
			        	# Extract the stage info
                        no strict qw(refs);
			        	for my $S_PROJECT (keys %{$stage->{projects}}) {
			        		for my $S_VER (keys %{$stage->{projects}->{$S_PROJECT}->{version}}) {			        			  
                                  my $S_DATA = $stage->{projects}->{$S_PROJECT}->{version}->{$S_VER};
                                  print Dumper($S_DATA);
                                  $ans .= '<stage name="'.encode_entities($STAGE_ENTRY).'" stage="'.encode_entities($S_DATA->{stage}).'" description="'.encode_entities($S_DATA->{description}).'" />';
			                }
			        	}
			            use strict qw(refs);
			        	
			        }
			        
			    }
                
                # Scan all the existing projects in file
                for my $PROJECT (keys %{$config{projects}}) {
                    
                    # Scan project versions in file
                    my %_project = %{$config{projects}{$PROJECT}};
                    for my $VER (keys %{$_project{version}}) {
                        
                        # Scan project configuration
                        my %_info = %{$_project{version}{$VER}};

                        # Build a response entry
                        $ans .= '<project name="'.$PROJECT.'" ver="'.$VER.'" title="'.encode_entities($_info{title}).'" desc="'.encode_entities($_info{description}).'" platform="'.encode_entities($_info{platform}).'" repos="'.encode_entities($_info{repository}).'" />';
                        
                    }
                    
                }

                # Scan all the defined models from the file
                for my $MODEL (keys %{$config{models}}) {
                	
                    my %_details = %{$config{models}{$MODEL}};
                    
                    $ans .= '<model name="'.$MODEL.'" group="'.encode_entities($_details{group}).'" description="'.encode_entities($_details{description}).'" />';                	
                }

                $ans .= '</directory>';
                
            }
                        
        }
    }
    
    # Reply data
    iAgent::Kernel::Reply('comm_reply', { data => $ans });
}

=head2 archipel:ibuilder:projects/get

This action is a request to return the configuration data for the specified project directory.

Request:

    <query xmlns="archipel:ibuilder:projects">
        <archipel action="get" dir="dirname">
    </query>

Reply:

    <project dir="dirname" name="projectname">
        <version ver="1" title="title" description="short description of the project" />
        ...
    </project>
    ...

=cut

############################################
# Return the project configuration
sub iq_get_project {
############################################
    my ($self, $project) = @_;    
    my $DIR = $self->{dir_projects}."/$project";
    
    # Validate dir
    if (not -d $DIR) {
    	iAgent::Kernel::Reply("comm_reply_error", { type=>'item-not-found', code=>602, message=>"The projet $project was not found on the server!" });
    	return;
    }

    my $CONF = $DIR.'/project.conf';
    # Validate config file
    if (not -f $CONF) {
        iAgent::Kernel::Reply("comm_reply_error", { type=>'item-not-found', code=>602, message=>"The configuration file for the project $project does not exist!" });
        return;
    }
    
    # Process file and reply data
    my $_conf = new Config::General($CONF);
    my %config = $_conf->getall;
    iAgent::Kernel::Reply('comm_reply', { data => \%config });
    
}


=head2 archipel:ibuilder:config/get

This action is a request to return the configuration data for the specified project directory.

Request:

    <query xmlns="archipel:ibuilder:config">
        <archipel action="get">
    </query>

Reply:

    <manager name=".." handler=".." proxy="..">
    ...
    <platform name=".." label=".." manager=".." />
    ...
    <repository name=".." label=".." manager=".." />
    ...
    <stage name=".." suffix=".." description=".." />
    ...
    <imagetype name=".." hypervisor=".." description=".." seed=".." suffix=".." flavor=".." handler=".." />
    ...
    <architecture name="" flavour="" ec2="" />
    ...
    
=cut

############################################
# Handle the 'get config' action
sub iq_get_config {
############################################
    my ($self, $project) = @_;        
    my @config;

    # Fetch all configs to @config array
    for my $file ($self->{conf_local}, $self->{conf_global}) {
       if ( -f "$file" ) {
           my $cfg = "$file";
           open(CFG, "<$cfg" );
           while(<CFG>) {
              my($line) = $_;
              push @config, $line;
           }
           close(CFG);
       }
    }
    
    # Merge the multiple configs
    my $c = new Config::General(
         -String => \@config,
         -AllowMultiOptions => "no",
         -MergeDuplicateOptions => "yes",
         -MergeDuplicateBlocks => "yes",
         )->{DefaultConfig};
    
    # Build the response
    my $xml = '';
    for my $NAME (keys %{$c->{managers}}) {
    	my $item = $c->{managers}->{$NAME};
    	$xml.='<manager name="'.encode_entities($NAME).
    	           '" handler="'.encode_entities($item->{handler}).
    	           '" proxy="'.encode_entities($item->{conaryProxy}).'" />';
    }
    for my $NAME (keys %{$c->{platforms}}) {
        my $item = $c->{platforms}->{$NAME};
        $xml.='<platform name="'.encode_entities($NAME).
                   '" label="'.encode_entities($item->{label}).
                   '" manager="'.encode_entities($item->{type}).'" />';
    }
    for my $NAME (keys %{$c->{repositories}}) {
        my $item = $c->{repositories}->{$NAME};
        $xml.='<repository name="'.encode_entities($NAME).
                   '" label="'.encode_entities($item->{label}).
                   '" manager="'.encode_entities($item->{type}).'" />';
    }
    for my $NAME (keys %{$c->{stages}}) {
        my $item = $c->{stages}->{$NAME};
        $xml.='<stage name="'.encode_entities($NAME).
                   '" suffix="'.encode_entities($item->{suffix}).
                   '" description="'.encode_entities($item->{description}).'" />';
    }
    for my $NAME (keys %{$c->{types}}) {
        my $item = $c->{types}->{$NAME};
        $xml.='<imagetype name="'.encode_entities($NAME).
                   '" hypervisor="'.encode_entities($item->{hypervisor}).
                   '" description="'.encode_entities($item->{description}).'" />';
    }
    for my $NAME (keys %{$c->{architectures}}) {
        my $item = $c->{architectures}->{$NAME};
        $xml.='<architecture name="'.encode_entities($NAME).
                   '" flavor="'.encode_entities($item->{flavor}).
                   '" ec2="'.encode_entities($item->{ec2}).'" />';
    }

    # Reply the xml buffer
    iAgent::Kernel::Reply('comm_reply', { data => $xml });
    
}

=head2 archipel:ibuilder:config/add

Add a configuration parameter to the global/local configuration files

Request:

    <query xmlns="archipel:ibuilder:config">
    
        <archipel action="add">
        
		    <manager name=".." handler=".." proxy="..">
		    ...
		    <platform name=".." label=".." manager=".." />
		    ...
		    <repository name=".." label=".." manager=".." />
		    ...
		    <stage name=".." suffix=".." description=".." />
		    ...
		    <imagetype name=".." hypervisor=".." description=".." seed=".." suffix=".." flavor=".." handler=".." />
		    ...
		    <architecture name="" flavour="" ec2="" />
		    ...
        
        </archipel>
    </query>

Reply:
    
=cut

############################################
# EXPERIMENTAL: Save global configuration
sub iq_save_config {
    my ($self, $method, $XML) = @_;
    
    # Prepare config depending on save method
    my $_conf = new Config::General($self->{conf_local});
    my %config_local = $_conf->getall;
    $_conf = new Config::General($self->{conf_global});
    my %config_global = $_conf->getall;
    
    for my $NODE (@{$XML->children()}) {
    	
    	
    	
    }

############################################
}

###########################################
#+---------------------------------------+#
#|            EVENT HANDLERS             |#
#|                                       |#
#| All the functions prefixed with '__'  |#
#| are handling the respective event     |#
#+---------------------------------------+#
###########################################

############################################
# Handle the arrived actions
sub __comm_action { # Handle action arrival
############################################
	my ($self, $kernel, $packet) = @_[ OBJECT, KERNEL, ARG0 ];
	if ($packet->{context} eq $XMLNS_IBUILDER_PROJECT) {
		# Filter only archipel:ibuilder namespace
		
		log_debug("Got iBuilder IQ. Asking for: ".$packet->{action});
		
		# Dispatch actions to handlers
		if ($packet->{action} eq 'list') {
			
			# Return a list of the currently defined projects
			$self->iq_list_projects();
			
		} elsif ($packet->{action} eq 'get') {
			
			# Validate request
			if (not defined $packet->{parameters}->{dir}) {
                iAgent::Kernel::Reply('comm_reply_error', {type=> 'bad-request', message=> 'Missing "dir" attribute from "get" action', code=>601 });
                return 0;
			}
			
			# Return the config file of that project
			$self->iq_get_project($packet->{parameters}->{dir});
			
		} else {
			
			# Not a valid action
			iAgent::Kernel::Reply('comm_reply_error', {type=> 'bad-request', message=> 'The action was not understood', code=>600 });
			
		}
		
	} elsif ($packet->{context} eq $XMLNS_IBUILDER_CONFIG) {
		
		# Dispatch actions to handlers
		if ($packet->{action} eq 'get')  {
			
			# Reply config
			$self->iq_get_config();
			
		}
    	
	}
	
	return 1; # Allow further execution
}

1;