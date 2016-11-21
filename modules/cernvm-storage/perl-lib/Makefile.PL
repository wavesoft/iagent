use 5.008006;
use ExtUtils::MakeMaker;
use File::Basename;
use strict;
use warnings;

# My ETC files to install
my $ETC = {

    # Config files
    'etc/cernvm-agent/config.d/storage.conf' => '$(INST_AGENTCONFIG)/config.d/storage.conf'

};

# Return a string that ensures the existence
# of the specified directory
sub validate_dir {
    my ($name, $track_hash) = @_;
    my @parts = split('/', $name);
    my $path=''; my $ans="";
    foreach (@parts) {
        $path.='/' if ($path ne '');
        $path.=$_;
        if (!defined($track_hash->{$path})) {
            $track_hash->{$path}=1;
            $ans.="\t[ ! -d ${path} ] && mkdir ${path} || true\n";
        }
    }
    return $ans;
}

# Postamble to install configuration
sub MY::postamble {
    my $frag = "install ::\n";
    my $checked_dirs = { };
    $frag .= "\t[ ! -d \$(INST_SYSCONFIG) ] && mkdir -p \$(INST_SYSCONFIG) || true\n";
    foreach my $from (keys %$ETC) {
        my $to = $ETC->{$from};
        $frag .= validate_dir(dirname($to), $checked_dirs);
        $frag .= "\tcp $from $to\n";
    }
    return $frag;
}

# Write makefile
WriteMakefile(
    NAME              => 'CernVM::Storage',
    AUTHOR            => 'Ioannis Charalampidis <ioannis.charalampidis@cern.ch>',
    VERSION           => '0.0.1',
    ABSTRACT          => 'CernVM storage agent',
    LICENSE           => 'gpl',
    
    EXE_FILES         => [ qw(bin/iagent-storage) ],
    
    PREREQ_PM         => {        

        # Require iAgent bindings
        'iAgent' => 0,
        'iAgent::Kernel' => 0,
        'iAgent::Log' => 0,
        
        # And some other core components
        'Sys::Hostname' => 0,
        'Data::UUID' => 0,
        'POE' => 0
                
    },
    
    # Custom macros for ETC
    macro               => {
        
        'INST_SYSCONFIG' => '$(PREFIX)/etc',
        'INST_AGENTCONFIG' => '$(INST_SYSCONFIG)/cernvm-agent'
        
    }
        
);
