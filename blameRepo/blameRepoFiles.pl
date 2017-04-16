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
use File::Copy;
use Pod::Usage;
use Getopt::Long;

my $blameCommand = 'formatBlame.pl';
my $help = 0;
my $man = 0;
my $blameExtension = ".blame";
my $overwrite = 0;
my $verbose = 0;

GetOptions ("formatblame=s" => \$blameCommand,
            "help"     => \$help,      # string
            "blameExtension=s" => \$blameExtension,
            "overwrite"         => \$overwrite,
            "verbose"           => \$verbose,
            "blameCommand=s"   => \$blameCommand,
            "man"      => \$man)   # flag
        or die("Error in command line arguments\n");

if ($man) {
    pod2usage(-verbose=>2);
    exit(1);
}

if (scalar(@ARGV) != 3) {
    pod2usage(-verbose=>1);
    exit(1);
}

my $repoDir = shift;
my $outputDir = shift;
my $fileRegExpr = shift;



open(FILES, "git -C '$repoDir' ls-files|") or die "unable to traverse git repo [$repoDir] $!";

my $count = 0;
my $alreadyDone = 0;
my $errorCount = 0;


while (<FILES>) {
#    next unless /^kernel/;
    chomp;

    if ($fileRegExpr ne "") {
        next unless /$fileRegExpr/;
    }

            
    
    my $name = $_;
    
    if ($verbose) {
        print("matched file: [$name]\n");
    }

    my $originalFile = $repoDir . "/" . $name;
    my $outputFile = $outputDir . "/" . $name . $blameExtension;

    next unless -f $originalFile;

    next unless (-f $originalFile > 0);

    if (!$overwrite && -f $outputFile) {
        $alreadyDone ++;
        next;
    }
    $count++;
    print("$count: $name\n");


    my $errorCode = execute_command($blameCommand, "--blameExtension=$blameExtension", $repoDir, $name, $outputDir);
    if ($errorCode != 0) {
        print "Error code [$errorCode][$name]\n";
        $errorCount ++;
    } else {
        # command already moves file
    }
}

print "Newly processed [$count] Already done [$alreadyDone] files Error [$errorCount]\n";

sub Usage {
    my ($m) = @_;
    print STDERR "$m\n";
    pod2usage(-verbose=>1);
    exit(1);
}


sub execute_command {
    my (@command) = @_;
    # make sure we have more than one element in the array
    #    otherwise system will use the shell to do the execution
    die "command (@command) seems to be missing parameters" unless (scalar(@command) > 1);

    my $status = system(@command);

    return $status;
}

__END__

=head1 NAME

blameRepoFiles.pl: create the "blame" of files in a git repository

=head1 SYNOPSIS

  blameRepoFiles.pl [options] <repository> <outputDirectory> <fileNameRegexp>

     Options:
       --override         overwrite existing files
       --help             brief help message
       --man              full documentation
       --blameExtension=s extension to use in blame
       --formatblame=s    full path formatBlame (command to create them blame).
                          By default it looks in the same directory as this script,
                          otherwise it will try to execute the one in the PATH

=head1 OPTIONS

=over 8

=item B<--help>

    Print a brief help message and exits.

=item B<--man>

    Prints the manual page and exits.

=item B<--override>

    By default, if an output file exists it is skipped. This changes that behaviour.

=back

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something
useful with the contents thereof.

=cut
