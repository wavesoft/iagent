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

package iAgent::Module::Tight;

use strict;
use warnings;
use POE;
use iAgent;
use iAgent::Log;
use iAgent::Kernel;
use File::Copy;
use File::Basename;

use Data::Dumper;
use DynaLoader;

our $MANIFEST = {
    
    CLI => {
        "tight/pack" => {
            description => "Pack the current distribution of iAgent in a single file",
			message => "cli_pack"
        }
    }
    
};

############################################
# New instance
sub new { 
############################################
    my ($class, $config) = @_;
    my $self = { };
    return bless $self, $class;
}

############################################
# Pack the currently running iAgent in the 
# given directory
sub __cli_pack {
############################################
    my ($self, $command, $kernel) = @_[ OBJECT, ARG0, KERNEL ];
    my $dir = $command->{cmdline};
    
    # Print the dynaLoaded modules
    log_error(Dumper(@DynaLoader::dl_modules));
        
    # Validate input
    if (!$dir) {
        Dispatch("cli_error", "Please specify a directory where to create the tight package");
        return RET_ERROR;
    }
    
    # Create directory structure
    my $dir_lib = "$dir/lib";
    my $dir_etc = "$dir/etc";
    my $dir_var = "$dir/var";
    `mkdir -p $dir_lib` unless (-d $dir_lib);
    `mkdir -p $dir_etc` unless (-d $dir_etc);
    `mkdir -p $dir_var` unless (-d $dir_var);
    
    # Prepare install packages script
    my @install_files;
    
    # Dump includes
    Dispatch("cli_write", "Copying libraries...");
    foreach my $file (keys %INC) {
        my $src = $INC{$file};
        
        # Find the base
        my $base = substr($src,0,-length($file)-1);
        my $so_file = "$base/auto/$file";
        $so_file =~ s/\.pm$//;
        $so_file .= "/".basename($so_file).'.so';
        
        if (-f $so_file) {
            push @install_files, $file;
            
        } else {
            my $dst = "$dir_lib/$file";
            my $dst_dir = dirname($dst);
            `mkdir -p $dst_dir` if (! -d $dst_dir);
            Dispatch("cli_write", "Copying $src -> $dst");
            copy($src, $dst);
        }
    }
    
    # Copy configuration
    my $etc = $iAgent::ETC;
    Dispatch("cli_write", "Copying configuration...");
    `cp -r $etc/* '$dir_etc/'`;
    
    # Create bootstrap
    Dispatch("cli_write", "Creating bootstrap...");
    open BOOTSTRAP, ">$dir/start.pl";
    print BOOTSTRAP "#!/usr/bin/perl -Ilib\n";
    print BOOTSTRAP "use strict;\n";
    print BOOTSTRAP "use warnings;\n";
    print BOOTSTRAP "use iAgent;\n";
    print BOOTSTRAP "exit(iAgent::start( etc => \"etc\" ));\n";
    close BOOTSTRAP;
    chmod 0755, "$dir/start.pl";
    
    # Create installer
    Dispatch("cli_write", "Creating installer...");
    my $pkgs = join("','", @install_files);
    open INSTALLER, ">$dir/install.pl";
    print INSTALLER "#!/usr/bin/perl\n";
    print INSTALLER "use strict;\n";
    print INSTALLER "use warnings;\n";
    print INSTALLER "print \"Detecting missing modules...\\n\";\n";
    print INSTALLER "my \@files = ('$pkgs');\n";
    print INSTALLER "my \@missing = ( );\n";
    print INSTALLER "for my \$m (\@files) {\n";
    print INSTALLER "   eval { require \"\$m\"; };\n";
    print INSTALLER "   if(\$@) { \$m=~s/\\//::/g; \$m =~ s/\\.pm\$//; push \@missing, \$m; };\n";
    print INSTALLER "}\n";
    print INSTALLER "if (scalar(\@missing)==0){ print \"Ready\\n\"; exit(0); }\n";
    print INSTALLER "my \@app=(\"cpan\");\n";
    print INSTALLER "if (`which apt-get`) { \@missing=map{\$_=~s/::/-/g; 'lib'.lc(\$_).'-perl'; } \@missing; \@app=('apt-get','install'); }\n";
    print INSTALLER "elsif (`which yum`) { \@missing=map{\$_=~s/::/-/g; 'perl-'.\$_; } \@missing; \@app=('yum', 'install'); };\n";
    print INSTALLER "print \"Will install the following missing packages using '\$app[0]': \".join(', ',\@missing).\"\\n\\n\";\n";
    print INSTALLER "exec(\@app, \@missing);\n";
    close INSTALLER;
    chmod 0755, "$dir/install.pl";
    
    # Ok
    return RET_COMPLETED;
    
}

1;
