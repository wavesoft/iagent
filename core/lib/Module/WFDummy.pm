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

package Module::WFDummy;

use strict;
use warnings;
use POE;
use iAgent::Log;
use iAgent::Kernel;
use Data::Dumper;

our $MANIFEST = {
	
    WORKFLOW => {
		
		"iagent:prepare" => {
			ActionHandler => "wf_prepare",
			CleanupHandler => "wf_prepare_clean",
			Threaded => 1,
			Description => "Prepare the environment for a project",
			RequiredParameters => [ 'name' ]
		},

		"context:dump" => {
			ActionHandler => "wf_dump"
		},	
			
		"iagent:build" => {
			ActionHandler => "wf_build",
			Threaded => 1,
			MaxInstances => 2,
			Description => "Start building",
			RequiredParameters => [ 'project', 'chdir', 'target' ]
		},
		
		"iagent:convert" => {
		    Description => "A test workflow action that spawns a new target each time nobody is around to handle it",
		    isProvider => 1,
		    AllocateHandler => "",
		    DeallocateHandler => ""
		}
		
    }

};

sub new { 
   return bless { }, $_[0]; 
}

sub __wf_prepare {
	my ($self, $context, $logdir) = @_[ OBJECT, ARG0, ARG1 ];
	
	print `ps`;
	$context->{name} = 'Something';
	$context->{when} = time();
	$context->{project} = 'AProject';
	$context->{chdir} = '/abla';
	$context->{target} = 'ratarget';
	
	print("Sleeping for 5 seconds...\n");
	system('sleep', 5);
	
	return $?;
}

sub __wf_prepare_clean {
	my ($self, $context, $logdir) = @_[ OBJECT, ARG0, ARG1 ];

    print("CLEANING UP NOW! :)\n");
    
    return 0;
}

sub __wf_build {
	my ($self, $context, $logdir) = @_[ OBJECT, ARG0, ARG1 ];
	
	my $ans = system("ls $context->{chdir}");
	sleep(10);
	print "OK!";
	return $ans;
}

sub __wf_dump {
	my ($self, $context, $logdir) = @_[ OBJECT, ARG0, ARG1 ];

    open DUMPFILE, ">/tmp/dump.log";
    print DUMPFILE Dumper($context);
    close DUMPFILE;
    
    return 0;
}

sub __wf_provide {
    my ($self, $context) = @_[OBJECT, ARG0];
    
    system("/Users/icharala/Develop/iAgentSVN/trunk/tools/iagent-dummy.pl /Users/icharala/Develop/iAgentSVN/trunk/core/bin/config-3 &");
    
    return RET_OK;
}

1;
