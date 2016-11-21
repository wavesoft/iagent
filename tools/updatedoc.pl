#!/usr/bin/env perl

# Document the iAgent System
use strict;
use warnings;
use Pod::Html;
use File::Basename;
use Data::Dumper;

# Defaults
my $d_scan = "../core/lib";
my $d_out  = "../doc";
my $d_src = "./doc.src";

# Load extras
my $t_head = "";
my $t_toc_head = "";
my $t_toc_footer = "";

# Clear doc dir
system("ls \"$d_out/*\"");

##########################################################

sub load_buffers {
	if (-f "$d_src/append-head.html") {
		open(DAT, "$d_src/append-head.html") || die("Could not open $d_src/append-head.html!");
        my @lines=<DAT>;
		close DAT;
		$t_head = join "\n",@lines;
	}
    if (-f "$d_src/toc-head.html") {
        open(DAT, "$d_src/toc-head.html") || die("Could not open $d_src/toc-head.html!");
        my @lines=<DAT>;
        close DAT;
        $t_toc_head = join "\n",@lines;
    }
    if (-f "$d_src/toc-footer.html") {
        open(DAT, "$d_src/toc-footer.html") || die("Could not open $d_src/toc-footer.html!");
        my @lines=<DAT>;
        close DAT;
        $t_toc_footer = join "\n",@lines;
    }
}

sub post_process {
	my $file = shift;	
	my $root = shift;
	
    open(DAT, $file) || die("Could not open $file for post-processing!");
    my @lines=<DAT>;
    close DAT;
    my $buffer = join "\n", @lines;
    
    # Append extra stuff to <head>
    my $tpl = $t_head;
    $tpl =~ s!##ROOT##!$root!mg;
    
    # Append the extra tags to the head
    $buffer =~ s!</head>!$tpl</head>!img;
    
    # Append perl brush to the <pre> for the auto Highlighter
    $buffer =~ s/<pre>/<pre class="brush: perl">/img;
    
    # Make absolute URLs relative
    $buffer =~ s!href="/!href="$root!img;
    
    # Fix a bug that creates multiple lines
    $buffer =~ s/\n\n/\n/mg;
    
    # Remove all HR's
    $buffer =~ s/<hr \/>//img;
    
    # Add 'doc' class to body
    $buffer =~ s/<body /<body class="doc" /img;
	
	# Write back the file
	open(DAT, ">$file");
	print DAT $buffer;
	close DAT;
}

##########################################################

# Allow some changes to the dirs from command-line
$d_scan = $ARGV[0] if ($#ARGV > -1);

# Load buffers
load_buffers;

# Scan all the files
our $DOC_TREE = {}; 

sub build_dir_tree {
	my $bdir = shift;
	my $BRANCH = shift;
	 
	my @FILES;
	my @DIRS;
	
	opendir my $dh, $bdir or die "Cannot open folder $bdir";
	print "Scanning $bdir...\n";
	while (my $entry = readdir $dh) {
		my $fname = $bdir.'/'.$entry;
		if (not substr($entry,0,1) eq ".") {
			if (-f $fname and (substr($entry, -3) eq ".pm")) {
                push @FILES, $fname;
			} elsif (-d $fname) {
				my %SUB;
				build_dir_tree($fname, \%SUB);
				push @DIRS, \%SUB;
			}
		}
	}
	closedir $dh;
	
	$BRANCH->{NAME} = basename($bdir);
	$BRANCH->{PATH} = $bdir;
	$BRANCH->{FILES} = \@FILES;
    $BRANCH->{DIRS} = \@DIRS;
}
build_dir_tree($d_scan, $DOC_TREE);

# Build documentation for each file
my $TOC = {};
sub build_doc {
    my $ENTRY = shift;
	my $TOC_PART = shift;
    my $DIR = $ENTRY->{PATH};
    my $backdir = shift;
	
	print "Building doc for package ".$ENTRY->{NAME}." ($DIR)\n";
	
	# Parse the files in this package
	for my $F (@{$ENTRY->{FILES}}) {
		
		# Detect package name
	    my $package = substr($F, length($d_scan)+1);
	    $package = substr($package,0,-3);
	    $package =~ s!/!::!mg;
	    
	    # Detect relative path
	    my $rel_path = substr($F, length($d_scan)+1);
	    $rel_path = substr($rel_path,0,-3).'.html';
	    
	    # Detect the current name
	    my $name = basename($F);
	    $name = substr($name,0,-3);
	    
	    # Store the ToC Entry
	    $TOC_PART->{$name} = $rel_path;
	    
	    # Detect the physical target path
	    my $target_path = $d_out.'/'.$rel_path;
	    
	    # Create base dir
	    my $dir = dirname($target_path);
	    `mkdir -p $dir` unless (-d $dir);
	    
	    print " - Documenting file $F (Packate $package) to $target_path\n";
	    pod2html(
	       "--infile=$F",
	       "--outfile=$target_path",
	       "--cachedir=/tmp",
	       "--title=Documentation of $package"
	    );
	    
	    # Post-process doc file
	    post_process($target_path, $backdir);
	    
	}
	
	# And continue with the packages
	for my $CDIR (@{$ENTRY->{DIRS}}) {
		$TOC_PART->{"-".$CDIR->{NAME}} = {};
	    build_doc($CDIR, $TOC_PART->{"-".$CDIR->{NAME}}, $backdir."../");
	    delete $TOC_PART->{"-".$CDIR->{NAME}} if (!keys %{$TOC_PART->{"-".$CDIR->{NAME}}});
	}
	
}
build_doc($DOC_TREE, $TOC, "");

sub build_toc {
	my $TOC_PART = shift;
	my $html="";
	for my $PKG (sort (keys %{$TOC_PART})) {
		my $FILE = $TOC_PART->{$PKG};
		
		if (substr($PKG,0,1) eq "-") {
			# Subdir
           if (defined $TOC_PART->{substr($PKG,1)}) {
           	    my $link = $TOC_PART->{substr($PKG,1)};
                $html.="<li class=\"title\"><a target=\"main\" href=\"$link\">".substr($PKG,1)."</a></li>";
           } else {
	            $html.="<li class=\"title\">".substr($PKG,1)."</li>";
           }
           $html.="<li class=\"sub\"><ul>";
           $html.=build_toc($FILE);
           $html.="</ul></li>\n";
			
		} else {
			# Entry
			if (not defined $TOC_PART->{"-".$PKG}) {
                $html.="<li class=\"file\"><a target=\"main\" href=\"$FILE\">$PKG</a></li>\n";
			}
			
		}
		
	}
    return $html;
}
my $HTML_TOC = $t_toc_head.build_toc($TOC).$t_toc_footer;

# Write ToC on file
open (TOC_FILE, ">$d_out/toc.html");
print TOC_FILE $HTML_TOC;
close TOC_FILE;

# Copy resources
print "Copying resources...\n";
system("cp -R \"$d_src/resources\" \"$d_out\"");
system("cp \"$d_src/index.html\" \"$d_out\"");
system("cp \"$d_src/welcome.html\" \"$d_out\"");

#for my $F (@FILES) {
	
#	my $package = substr($F, length($d_scan)+1);
#	$package = substr($package,0,length($package)-3);
#	$package =~ s!/!::!mg;
	
#    my $rel_path = substr($F, length($d_scan)+1);
#    $rel_path = substr($rel_path,0,length($rel_path)-3).'.html';
	
#	print "Documenting $package found at $rel_path\n";
	
#}

#print Dumper($DOC_TREE);
#print Dumper($TOC);
