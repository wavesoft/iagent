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

package Module::CernVM::Builder;
# Brad Fitchpatrickl

our $MANIFEST = {
    
    config => "cernvm.conf",
	
	WORKFLOW => {
		"ibuilder:build" => {
			RunHandler => "ibuilder_build"
			Threaded => 1
		},
		"ibuilder:build" => {
			RunHandler => "build_images"
			Threaded => 1
		}
	}	
	
};

sub __ibuilder_new_build {
	my ($self, $context) = @_;
	
	use iBuild;
	
	chdir $context->{project_dir};
	$ibuild->build("new", "build");
	
	return 0;
	
	return 1;
	
	
}

sub __ibuilder_build_images {
	my ($self, $context) = @_;
	
	use iBuild;
	
	chdir $context->{project_dir};
	my $images =  $ibuild->build_context( "build", "images" );
	return 1 unless defined $context;

	return 0;
	
	
}


sub __ibuilder_create {
	my ($self, $context) = @_;
	
	use iBuild;
	
	chdir $context->{project_dir};
	my $filename = $ibuild->create_image( @{$context->{image}} );
	
	$context->{files} = [ $filename ];
	
	return 1 unless defined $context;
	return 0;
	
	
}