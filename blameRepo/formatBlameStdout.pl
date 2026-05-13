#!/usr/bin/perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


use File::Basename;
use File::Path qw(make_path remove_tree);
use strict;
use File::Temp qw/ tempfile tempdir mkstemp/;
use File::Copy;
use Getopt::Long;
use Pod::Usage;

my $help = 0;
my $man = 0;
my $verbose = 0;



GetOptions (
            "help"     => \$help,      # string
            "verbose"  => \$verbose,
            "man"      => \$man)   # flag
        or die("Error in command line arguments\n");

if ($man) {
    pod2usage(-verbose=>2);
    exit(1)
}

if (scalar(@ARGV) != 2) {
    print STDERR " Error invalid parameters [@ARGV]";
    pod2usage(-verbose=>1);
    exit(1)
}

my $repo = shift @ARGV;
my $file = shift @ARGV;

if (index($repo, $file) == 0) {
    $file =~ s/^\Q$repo\E//;
}

Usage("Error [$file] should be a file in repository [$repo] [$repo/$file]\n\n usage $0 <repo> <filename> <destinationDir>") unless -f "$repo/$file";
Usage("Error [$repo] should be a git repo\n\nUsage $0 <repo> <filename> <destinationDir>") unless -d "$repo/.git";


if ($verbose) {
    print STDERR "$0 processing repo [$repo] file [$file]\n";
}


#open(IN, "git -C '$repo' blame  -C100 --line-porcelain '$file'|" ) or "unable to execute git ";
open(IN, "git -C '$repo' blame -M50 -C50 --line-porcelain '$file'|" ) or "unable to execute git ";
while (my $l = Read_Record()) {
    print $l;
    print "\n";
}
close IN;

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
		$f .=  $2 . ";";
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


__END__

=head1 NAME

formatBlame.pl - extract the blame information for a file

=head1 SYNOPSIS

formatBlame.pl [options] <repository> <file>

     Options:
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
