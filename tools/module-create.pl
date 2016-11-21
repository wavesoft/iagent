#!/usr/bin/perl
use strict;
use warnings;

my $name = shift(@ARGV) or die("Please specify the class name for your new module (ex. $0 CernVM::Agent) ");
my ($inf_author, $inf_desc, $tpl_detail, $tpl_config, $ans);
eval {
    local $| = 1;
    print "Author: ";
    chomp($inf_author = <STDIN>);
    print "A short description: ";
    chomp($inf_desc = <STDIN>);
    print "Do you want an Explained or Simple template? ([e]/s): ";
    chomp($ans = <STDIN>);
    $tpl_detail = !(($ans eq 's') || ($ans eq 'S'));
    print "Do you want a configuration file? ([y]/n): ";
    chomp($ans = <STDIN>);
    $tpl_config = !(($ans eq 'n') || ($ans eq 'N'));
};

# Generate timestamp
my $time = scalar localtime time();

# Convert to folder name
my $fname = lc($name);
$fname =~ s/::/-/g;
my $dir = $fname;

# Create the class name
my $cname = 'Module::'.$name;

# Get the last part of the path name for short naming
my @sname = split("-",$fname);
my $sname = pop(@sname);

# Make folder
mkdir($dir);

# Make perl-lib
$dir .= '/perl-lib';
mkdir($dir);

# Make bin/etc/lib
mkdir("$dir/bin");
mkdir("$dir/lib");

# Make lib subdirectories
my @parts = split("::",$cname);
my $pmname = pop(@parts);
my $reldir = 'lib';
foreach (@parts) {
    $reldir.='/'.$_;
    mkdir($dir.'/'.$reldir);
}
my $pmdir = $dir.'/'.$reldir;

# Prepare manifest lines
my @MANIFEST = (
        'MANIFEST',
        'Makefile.PL',
        "bin/agent-$sname",
        "$reldir/$pmname.pm"
    );

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                                      CONFIG FILE                                                            | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

# Prepare the ETC line for the makefile
my $ETCline = "#'etc/cernvm-agent/config.d/$sname.conf' => '\$(INST_AGENTCONFIG)/config.d/$sname.conf'";

# Prepare the etc file 
if ($tpl_config) {

# Make dirs
mkdir("$dir/etc");
mkdir("$dir/etc/cernvm-agent");
mkdir("$dir/etc/cernvm-agent/config.d");

my $lname = ucfirst($sname);
print "Creating $dir/etc/cernvm-agent/config.d/$sname.conf...";
open F, ">$dir/etc/cernvm-agent/config.d/$sname.conf";
print F <<EOF
#
# Configuration file for $cname
# Created by $inf_author at $time
#

# TODO: Put your configuration values here:
${lname}Var\t"Value"

EOF
;close F;
print "ok\n";

# Update ETC line for makefile
my $ETCline = "'etc/cernvm-agent/config.d/$sname.conf' => '\$(INST_AGENTCONFIG)/config.d/$sname.conf'";
push @MANIFEST, "etc/cernvm-agent/config.d/$sname.conf";

}

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                                      MAKEFILE.PL                                                            | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

# Make Makefile.PL
print "Creating $dir/Makefile.PL...";
open F, ">$dir/Makefile.PL";
print F <<EOF
#
# Makefile script for $cname
#
# Developed by $inf_author
# Created at $time
#
use 5.008006;
use ExtUtils::MakeMaker;
use File::Basename;
use strict;
use warnings;

# My ETC files to install
my \$ETC = {

    # Default configuration file
    $ETCline
    
    # ===============================
    # Specify your ETC files here
    # ===============================

};

# Return a string that ensures the existence
# of the specified directory
sub validate_dir {
    my (\$name, \$track_hash) = \@_;
    my \@parts = split('/', \$name);
    my \$path=''; my \$ans="";
    foreach (\@parts) {
        \$path.='/' if (\$path ne '');
        \$path.=\$_;
        if (!defined(\$track_hash->{\$path})) {
            \$track_hash->{\$path}=1;
            \$ans.="\t[ ! -d \${path} ] && mkdir \${path} || true\\n";
        }
    }
    return \$ans;
}

# Postamble to install configuration
sub MY::postamble {
    my \$frag = "install ::\\n";
    my \$checked_dirs = { };
    \$frag .= "\t[ ! -d \\\$(INST_SYSCONFIG) ] && mkdir -p \\\$(INST_SYSCONFIG) || true\\n";
    foreach my \$from (keys %\$ETC) {
        my \$to = \$ETC->{\$from};
        \$frag .= validate_dir(dirname(\$to), \$checked_dirs);
        \$frag .= "\tcp \$from \$to\\n";
    }
    return \$frag;
}

# Write makefile
WriteMakefile(
    NAME              => '$cname',
    AUTHOR            => '$inf_author',
    VERSION           => '0.0.1',
    ABSTRACT          => '$inf_desc',
    LICENSE           => 'gpl',
    
    EXE_FILES         => [ qw(bin/iagent-$sname) ],
    
    PREREQ_PM         => {        

        # Require iAgent bindings
        'iAgent' => 0,
        'iAgent::Kernel' => 0,
        'iAgent::Log' => 0,
        'POE' => 0
                
        # ===============================
        # Put your own dependencies here
        # ===============================
        
    },
    
    # Custom macros for ETC
    macro               => {
        
        'INST_SYSCONFIG' => '\$(PREFIX)/etc',
        'INST_AGENTCONFIG' => '\$(INST_SYSCONFIG)/cernvm-agent'
        
    }
        
);
EOF
;close F;
print "ok\n";

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                                      BOOTSTRAP                                                              | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

# Make bootstrap script
push @MANIFEST, "bin/agent-$sname";
print "Creating $dir/bin/agent-$sname...";
open F, ">$dir/bin/agent-$sname";
print F <<EOF
#!/usr/bin/perl -w -I../lib
#
# iAgent Bootstrap
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
# Developed by $inf_author
# Created at $time
#

use strict;
use warnings;
use iAgent;
use iAgent::Log;

# Select an ETC folder
my \$etc = '';
if (-d '/etc/cernvm-agent') { # Check global ETC
    \$etc='/etc/cernvm-agent';
    
} elsif (-d '/usr/local/etc/cernvm-agent') { # Check local ETC
    \$etc='/usr/local/etc/cernvm-agent';

} elsif (-d '/usr/etc/cernvm-agent') { # Check for user ETC
    \$etc='/usr/etc/cernvm-agent';

} elsif (-d "\$ENV{HOME}/.iagent/etc") { # Check for user's iagent & etc
    \$etc = "\$ENV{HOME}/.iagent/etc";
    push \@INC, "\$ENV{HOME}/.iagent/lib" if (-d "\$ENV{HOME}/.iagent/lib");
    
} else {
    if (scalar \@ARGV == 0) {
        log_die("Unable to locate the configuration folder! Please specify it as the first command-line parameter");
    } else {
        \$etc = \$ARGV[0];
    }
}

# Ensure we have at least iagent.conf there
log_die("Unable to find iagent.conf in '\$etc'!") unless (-f "\$etc/iagent.conf");

# Start iAgent
exit(iAgent::start( 
    
    # Default ETC folder
    etc => \$etc,
    
    # Override the LoadModule parameter to load the agent module
    LoadModule => [
        '$cname'
    ]
    
));

EOF
;close F;
print "ok\n";
chmod 0755, "$dir/bin/agent-$sname";

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                                      SIMPLE PM                                                              | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

# Create a dummy module file
if (!$tpl_detail) {
print "Creating $pmdir/$pmname.pm...";
open F, ">$pmdir/$pmname.pm";
print F <<EOF
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
# Developed by $inf_author 
# Created at $time
#

=head1 NAME

$cname - $inf_desc

=head1 DESCRIPTION

Automatically generated module

TODO: Write description of this module

=head1 AUTHOR

$inf_author

=cut

# Core definitions
package $cname;
use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use POE;

# Manifest definition
our \$MANIFEST = {
	
};

############################################
# Create new instance
sub new {
############################################
    my \$class = shift;
    my \$config = shift;

    # Initialize instance
    my \$self = { 
            Config => \$config
        };
    
    # Create instance
    return bless \$self, \$class;

}

EOF
;close F;
print "ok\n";
}

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                                    EXPLAINED PM                                                             | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##


# Create a dummy module file
if ($tpl_detail) {
print "Creating $pmdir/$pmname.pm...";
open F, ">$pmdir/$pmname.pm";
print F <<EOF
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
# Developed by $inf_author 
# Created at $time
#

=head1 NAME

$cname - $inf_desc

=head1 DESCRIPTION

Automatically generated module

TODO: Write description of this module

=head1 AUTHOR

$inf_author

=cut

# Core definitions
package $cname;
use strict;
use warnings;
use iAgent::Kernel;
use iAgent::Log;
use POE;

# Useful for debug, remove for production
use Data::Dumper;

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #
#                                           #
#   The automatic agent generator has       #
#   created many stuff that you might not   #
#    need. They are presented mainly for    #
#   educational purposes but they can be    #
#             used as-is.                   #
#                                           #
#     Please spend some time to cleanup     #
#                                           #
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #

# Manifest definition
our \$MANIFEST = {

    # Automatically detect POE message handlers
    # by hooking the functions prefixed with '__'
    # to the messages with the same name
  	hooks => 'AUTO',
  	hooks_prefix => '__',

    # Workflow entry points
	WORKFLOW => {

		"$sname:action" => {
		    
 			ActionHandler => "myaction_handle",     # The POE message that will be sent to handle this action
 			ValidateHandler => "myaction_validate", # The POE message that will be sent to verify the integrity of the context [Optional]
 			CleanupHandler => "myaction_cleanup",   # The POE message that will be sent to clean-up the action
			Description => "A short description",   # A short description that describes what this function does [Optional]
 			Threaded => 1,                          # Set to 1 (Default) to run the handler in a separate thread [Optional]
			MaxInstances => 5,                      # Set the number of maximum concurrent instances to allow or undef for unlimited [Optional]
 			Permissions => [ 'read', 'write' ],     # Optionally you can specify the permissions required in order to invoke this action [Optional]
 			RequiredParameters => [ 'name' ],       # Which parameters are mandatory to be present [Optional]
 			Provider => 1                           # The action is a provider
 			
		}
	},
	
	# XMPP command entry points
	XMPP => {
        permissions => [ 'read' ],                  # Global permissions
	    'iagent:$sname' => {                        # Context = 'iagent:$sname'
            permissions => [ 'read' ],              # Context-wide permissions
	        'set' => {                              # iq/set messages
	            'set_something' => {
	                message => "xmpp_do_sth",       # The POE message to send
	                permissions => [ 'write' ]
	            }
	        },
	        'get' => {                              # iq/get messages
	            'get_something' => {
	                message => "xmpp_do_sth"
	            }
	        },
	        'chat' => {                             # iq/chat messages
	            'chat_something' => {
	                message => "xmpp_do_sth"
	            }
	        }
  	    }
	},
	
	# CLI Endpoints
	CLI => {
		
		"$sname/hello" => {                         # Command 'hello' on group $sname
			description => "A demo CLI function",   # A description message visible by 'help' command
			message => "cli_hello",                 # The POE message to send
            options => [ 'name=s' ]                 # (Optional) Required parameters in GetOpt::Long format
		}
		
	}
	
};

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## |                                                    INITIALIZATION                                                           | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

############################################
# Create new instance
sub new {
############################################
    my \$class = shift;
    my \$config = shift;

    # Initialize instance
    my \$self = { 
            Config => \$config
        };
    
    # Create instance
    return bless \$self, \$class;

}

############################################
# Setup session
sub ___setup {
############################################
    my (\$self, \$heap, \$kernel) = \@_[OBJECT,HEAP,KERNEL];
    # This code is executed when the session is up and running

    return RET_OK;
}

############################################
# Cleanup session
sub ___stop {
############################################
    my (\$self, \$heap, \$kernel) = \@_[OBJECT,HEAP,KERNEL];
    # This code is executed when the session is being destroied
    
    return RET_OK;
}

############################################
# iAgent kernel is ready
sub __ready {
############################################
    my (\$self, \$heap, \$kernel) = \@_[OBJECT,HEAP,KERNEL];

    return RET_OK;
}

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## |                                                     ENTRY POINTS                                                            | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

#====== WORKFLOW ======#

############################################
# Workflow action handler
sub __myaction_handle {
############################################
    my (\$self, \$context, \$logdir, \$guid) = \@_[ OBJECT, ARG0, ARG1, ARG2 ];
    
    # Do some work (Thread safe)
    
    # Return your error code
    return RET_OK;
}

############################################
# Workflow action validator
sub __myaction_validate {
############################################
    my (\$self, \$context) = \@_[ OBJECT, ARG0 ];
    my \$valid=1;
    
    # Return validation status. Anything that
    # is not RET_OK will be considered invalid.
    if (\$valid) {
        return RET_OK;
    } else {
        return RET_INVALID;
    }
}

############################################
# Workflow action cleanup
sub __myaction_cleanup {
############################################
    my (\$self, \$context, \$logdir, \$guid) = \@_[ OBJECT, ARG0, ARG1, ARG2 ];
    
    # Cleanup your work
    
    # Good practice...
    return RET_OK;
}

#====== XMPP ======#

############################################
# XMPP IQ Command arrived
sub __xmpp_do_sth {
############################################
    my (\$self, \$packet) = \@_[ OBJECT, ARG0 ];

    # A message arrived
    log_info("Message arrived from ".\$packet->{from}." with parameters ".Dumper(\$packet->{parameters}));
    log_info("Message payload: ".Dumper(\$packet->{data}));
    
    # Successfully handled the message
    return RET_OK;
}


#====== CLI ======#

############################################
# CLI Command arrived
sub __cli_hello {
############################################
    my (\$self, \$cmd) = \@_[ OBJECT, ARG0 ];
    
    # Get a command-line parameter
    my \$name = \$cmd->{options}->{name};
    
    # Display something
    Dispatch('cli_write', "Hello \$name! I am the agent");
    Dispatch('cli_error', "(Do not listen to this guy)");
    
    # Depending on what just happened you should return
    # one of the following values:
    #
    # RET_COMPLETED - If the command was completed in this single call
    # RET_OK        - If the command was successful but still pending (This will block CLI until you send 'cli_completed' or 'cli_error')
    # RET_ERROR     - If something went wrong
    
    # I want to do something more, so wait...
    POE::Kernel->delay( complete_hello => 1 );
    
    # Do not complete the CLI call
    return RET_OK;
}

# This function completes __cli_hello
sub __complete_hello {
    
    Dispatch('cli_write', "I am joking, he's cool...");
    
    # Complete the currently active CLI command
    # 'cli_completed' accepts an optional return value
    Dispatch('cli_completed', 0);
    
    # Goot practice..
    return RET_OK;
}

EOF
;close F;
print "ok\n";
}

## +-----------------------------------------------------------------------------------------------------------------------------+ ##
## | =========================================================================================================================== | ##
## |                                                    MANIFEST FILE                                                            | ##
## | =========================================================================================================================== | ##
## +-----------------------------------------------------------------------------------------------------------------------------+ ##

print "Creating $dir/MANIFEST...";
open F, ">$dir/MANIFEST";
foreach (@MANIFEST) {
    print F "$_\n";
}
close F;
print "ok\n";

## ------------------------------------------------------------------------------------------------------------------------------- ##
## ------------------------------------------------------------------------------------------------------------------------------- ##

print "Completed!\n\n";
print "Start by editing the agent module file : $reldir/$pmname.pm\n";
print "And then your configuration file       : etc/cernvm-agent/config.d/$sname.conf\n" if ($tpl_config);
print "\nDon't forget to add on MANIFEST the files you are adding and to put \n";
print "on Makefile.PL the perl modules you are using.\n";
print "Good luck!\n";
