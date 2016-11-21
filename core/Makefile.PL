use 5.008006;
use ExtUtils::MakeMaker;
use File::Basename;
use strict;
use warnings;

# My ETC files to install
my $ETC = {

    # Config files
    'etc/cernvm-agent/iagent.conf' => '$(INST_AGENTCONFIG)/iagent.conf',
    'etc/cernvm-agent/config.d/xmpp.conf' => '$(INST_AGENTCONFIG)/config.d/xmpp.conf',
    'etc/cernvm-agent/config.d/cryptousers.conf' => '$(INST_AGENTCONFIG)/config.d/cryptousers.conf',
    
    # Avatars
    'etc/cernvm-agent/avatars/iBuilder.png' => '$(INST_AGENTCONFIG)/avatars/iBuilder.png'

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
    NAME              => 'iAgent',
    AUTHOR            => 'Ioannis Charalampidis <ioannis.charalampidis@cern.ch>',
    VERSION           => '0.4.0',
    ABSTRACT          => 'iAgent library for the CernVM Virtual Machine Lifecycle Management infrastructure',
    LICENSE           => 'gpl',

    EXE_FILES         => [ qw(bin/iagent-config) ],
        
    PREREQ_PM         => {
        
        # General utilities
        'Data::Dumper' => 0,
        'Data::UUID' => 0,
        'Config::General' => 0,
        'Hash::Merge' => 0,
        'POSIX' => 0,
        'MIME::Base64' => 0,
        'Digest::MD5' => 0,
        'File::Basename' => 0,
        
        # POE
        'POE' => 0,
        'POE::Wheel::ReadLine' => 0,
        
        # CLI-Bindings
        'Term::ReadKey' => 0,
        'Term::ANSIColor' => 0,
        'Getopt::Long' => 0,
        
        # Encryption routines
        'Crypt::OpenSSL::AES' => 0,
        'Crypt::CBC' => 0,
        
        # XMPP & LDAP Core modules
        'Net::LDAP' => 0,
        'Net::XMPP' => 0,
        'HTML::Entities' => 0,
        'XML::Simple' => 0,
        'Sys::Hostname' => 0,
        'JSON' => 0,
        
        # Workflow
        'Date::Format' => 0,
        
        # Database with SQLite
        'DBI' => 0,
        'DBD::SQLite' => 0
                
    },

    
    PM => {

        # Don't add everything, only the specified files from iAgent Library
        'lib/iAgent.pm' => '$(INST_LIBDIR)/iAgent.pm',
        'lib/iAgent/Kernel.pm' => '$(INST_LIBDIR)/iAgent/Kernel.pm',
        'lib/iAgent/Log.pm' => '$(INST_LIBDIR)/iAgent/Log.pm',
        'lib/iAgent/DB.pm' => '$(INST_LIBDIR)/iAgent/DB.pm',
        'lib/iAgent/Crypt.pm' => '$(INST_LIBDIR)/iAgent/Crypt.pm',
        'lib/iAgent/SchemaValidator.pm' => '$(INST_LIBDIR)/iAgent/SchemaValidator.pm',
        'lib/iAgent/Utilities.pm' => '$(INST_LIBDIR)/iAgent/Utilities.pm',
        'lib/iAgent/Module/CLI.pm' => '$(INST_LIBDIR)/iAgent/Module/CLI.pm',
        'lib/iAgent/Module/Dummy.pm' => '$(INST_LIBDIR)/iAgent/Module/Dummy.pm',
        'lib/iAgent/Module/Reporter.pm' => '$(INST_LIBDIR)/iAgent/Module/Reporter.pm',
        'lib/iAgent/Module/EncryptionIn.pm' => '$(INST_LIBDIR)/iAgent/Module/EncryptionIn.pm',
        'lib/iAgent/Module/EncryptionOut.pm' => '$(INST_LIBDIR)/iAgent/Module/EncryptionOut.pm',
        'lib/iAgent/Module/XMPP/MUC.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPP/MUC.pm',
        'lib/iAgent/Module/XMPP/Namespaces.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPP/Namespaces.pm',
        'lib/iAgent/Module/XMPP/PubSub.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPP/PubSub.pm',
        'lib/iAgent/Module/XMPP/Roster.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPP/Roster.pm',
        'lib/iAgent/Module/XMPP/VCard.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPP/VCard.pm',
        'lib/iAgent/Module/XMPPMonitor.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPPMonitor.pm',
        'lib/iAgent/Module/XMPP.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPP.pm',
        'lib/iAgent/Module/Discovery/Invoker.pm' => '$(INST_LIBDIR)/iAgent/Module/Discovery/Invoker.pm',
        'lib/iAgent/Module/Discovery/Listener.pm' => '$(INST_LIBDIR)/iAgent/Module/Discovery/Listener.pm',
        'lib/iAgent/Module/Testing/TestBlock.pm' => '$(INST_LIBDIR)/iAgent/Module/Testing/TestBlock.pm',
        'lib/iAgent/Module/Testing/TestController.pm' => '$(INST_LIBDIR)/iAgent/Module/Testing/TestController.pm',
        'lib/iAgent/Module/Testing.pm' => '$(INST_LIBDIR)/iAgent/Module/Testing.pm',
        'lib/iAgent/Wheel/FSM.pm' => '$(INST_LIBDIR)/iAgent/Wheel/FSM.pm',
        'lib/iAgent/Wheel/Queue.pm' => '$(INST_LIBDIR)/iAgent/Wheel/Queue.pm',
        'lib/iAgent/Wheel/PriorityQueue.pm' => '$(INST_LIBDIR)/iAgent/Wheel/PriorityQueue.pm',
        
        # Include system modules
        'lib/Module/Workflow/Definition.pm' => '$(INST_LIBDIR)/Module/Workflow/Definition.pm',
        'lib/Module/WorkflowActions.pm' => '$(INST_LIBDIR)/Module/WorkflowActions.pm',
        'lib/Module/WorkflowAgent.pm' => '$(INST_LIBDIR)/Module/WorkflowAgent.pm',
        'lib/Module/WorkflowServer.pm' => '$(INST_LIBDIR)/Module/WorkflowServer.pm',
        'lib/Module/WorkflowCLI.pm' => '$(INST_LIBDIR)/Module/WorkflowCLI.pm',
        'lib/Module/XMPPCLI.pm' => '$(INST_LIBDIR)/iAgent/Module/XMPPCLI.pm',
        
        # Include also some tools
        'lib/Tools/FileTransfer.pm' => '$(INST_LIBDIR)/Tools/FileTransfer.pm'
    
    },
    
    # Custom macros for ETC
    macro               => {
        
        'INST_SYSCONFIG' => '/etc',
        'INST_AGENTCONFIG' => '$(INST_SYSCONFIG)/cernvm-agent'
        
    }
    
);
