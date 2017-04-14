#!/usr/bin/perl

use File::Basename;
use File::Path qw(make_path remove_tree);
use strict;
use File::Temp qw/ tempfile tempdir mkstemp/;
use File::Copy;
use Getopt::Long;
use Pod::Usage;

my $blameExtension = ".blame";
my $help = 0;
my $man = 0;
my $verbose = 0;

GetOptions ("blameExtension=s" => \$blameExtension, 
            "help"     => \$help,      # string
            "verbose"  => \$verbose,
            "man"      => \$man)   # flag
        or die("Error in command line arguments\n");

if ($man) {
    pod2usage(-verbose=>2);
    exit(1)
}

if (scalar(@ARGV) != 3) {
    pod2usage(-verbose=>1);
    exit(1)
}

my $repo = shift @ARGV;
my $file = shift @ARGV;
my $dest = shift @ARGV;

my ($fh, $temp) = mkstemp( "tmpfile-XXXXX" );

Usage("Error [$file] should be a file in repository [$repo] [$repo/$file]\n\n usage $0 <repo> <filename> <destinationDir>") unless -f "$repo/$file";
Usage( "Error [$repo] should be a git repo\n\nUsage $0 <repo> <filename> <destinationDir>") unless -d "$repo/.git";
Usage( "Error [$dest] should be a directory\n\nUsage $0 <repo> <filename> <destinationDir>") unless -d $dest and $dest ne "";

if ($verbose) {
    print STDERR "$0 processing repo [$repo] file [$file] [$dest]\n";
}

open(IN, "git -C '$repo' blame  --line-porcelain '$file'|" ) or "unable to execute git ";

while (my $l = Read_Record()) {
    print $fh $l;
    print $fh "\n";
}
close IN;
close $fh;
copy_file($temp, $dest, $file . $blameExtension);
if ($verbose) {
    print STDERR "...completed\n";
}


sub Read_Record {
    my $f ;
    my $cid;
    while (<IN>) {
	chomp;
        if ($_ =~ /^([0-9a-f]{40}) [0-9]/ ) {
            $cid = $1;
            $f = "$1;";
        } elsif ($_ =~ /^(filename) (.+)$/) {
	    if ($2 ne $file) {
		$f .=  $2 . "[$2][$file];";
	    } else {
		$f .= ";";
	    }
	} elsif (/^	(.*)/) { #actual line
	    $f = $f . $_;
	    return $f;
	} else {
	    ; # simply ignore
	}
    }
    return $f;
}

sub Usage {
    my ($m) = @_;
    print STDERR "$m\n";
    pod2usage(-verbose=>1);
    exit(1);
}

sub copy_file
{
    my ($from, $toDir, $toName) = @_;
    
    my $to = "${toDir}/$toName";
    $toDir = dirname($to);

#    printf ("copy [$from] to [$to] [$toDir][$toName]\n");

    die "from file does not exist in copy_file [$from]" if not -f $from;

    if (not -d $toDir) {
        printf("Creating directory [$toDir]\n");
	make_path($toDir) or "die unable to create directory $to";
    } 
    move($from, $to) or
            (unlink($to),  "unable to move [$from] to [$to]");
}

__END__

=head1 NAME

formatBlame.pl - extract the blame information for a file

=head1 SYNOPSIS

formatBlame.pl [options] <repository> <file> <outputDirectory>

     Options:
       --blame-extension=s  extension to append to output files. 
                            Default is .blame
       --help               brief help message
       --man                full documentation

=head1 OPTIONS

=over 8

=item B<--help>
    Print a brief help message and exits.

=item B<--man>
    Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<This program> will read run blame on a given file in a given git 
repository and create a file in the output directory
with the same full path as the original file, with 
the .blame extension (which can be changed with the --blame option).

=cut
