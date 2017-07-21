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
use Cwd 'abs_path';
use File::Basename;
use Parallel::ForkManager;

my $commandPath = dirname(__FILE__);

my $prettyCommand = $commandPath . '/prettyPrint-author.pl';
#my $prettyCommand = $commandPath . '/mt_test.sh';
my $help = 0;
my $man = 0;
my $prettyExtension = ".html";
my $overwrite = 0;
my $verbose = 0;
my $blameExtension = ".blame";

my $headerFile = "";
my $footerFile = "";

#my $githubURL = "";

my $ncpus = substr `grep -c ^processor /proc/cpuinfo`, 0, -1;
my $pm = Parallel::ForkManager->new($ncpus);
print "Using ", $pm->max_procs, " threads\n";

GetOptions (
            "prettyExtension=s" => \$prettyExtension,
            "blameExtension=s"  => \$blameExtension,
            "prettyCommand=s"   => \$prettyCommand,
            "header=s"          => \$headerFile,
            "footer=s"          => \$footerFile,
            "help"               => \$help,      # string
            "overwrite"         => \$overwrite,
            "verbose"           => \$verbose,
            "man"      => \$man)   # flag
        or die("Error in command line arguments\n");

if ($man) {
    pod2usage(-verbose=>2);
    exit(1);
}

if (scalar(@ARGV) != 7) {
    pod2usage(-verbose=>1);
    exit(1);
}

my $cregitDB = shift;
my $authorsDB = shift;
my $repoDir = shift;
my $blameDir = shift;
my $outputDir = shift;
my $cregitRepoURL = shift;
my $fileRegExpr = shift;


if (! -X $prettyCommand ) {
    print("Unable to find executable for pretty print [$prettyCommand]. Use --prettyExtension option\n");
    pod2usage(-verbose=>1);
    exit(1);
}

my @options = ();

if ($headerFile ne "") {
    push (@options , "--header=$headerFile");
}
if ($footerFile ne "") {
    push (@options , "--footer=$footerFile");
}

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

    print("matched file: [$name] ...") if $verbose;


    my $originalFile = $repoDir . "/" . $name;
    my $blameFile = $blameDir . "/" . $name . $blameExtension;
    my $outputFile = $outputDir . "/" . $name . $prettyExtension;

    if (not (-f $blameFile)) {
        print("blame file [$blameFile] does not exist. skipping\n") if $verbose;
        next;
    }
    if (not (-f $originalFile)) {
        print("file does not exist in repository [$originalFile]. Skipping\n") if $verbose;
        next;
    }
    if (-s $originalFile == 0) {
        print("file in repository is empty [$originalFile]. Skipping\n") if $verbose;
        next;
    }

    if (!$overwrite && -f $outputFile) {
        print("file already processed [$outputFile]. Skipping\n") if $verbose;
        $alreadyDone ++;
        next;
    }
    $count++;
    print("$count: $name\n");

    my $pid = $pm->start and next;
    my $errorCode = execute_command($prettyCommand, @options, $cregitDB, $authorsDB, $originalFile,
                                    $blameFile, $outputFile, "$name", $cregitRepoURL);

    if ($errorCode != 0) {
        print "Error code [$errorCode][$name]\n";
        $errorCount ++;
    } else {
        # command already moves file
    }
    $pm->finish;
}
$pm->wait_all_children;

print "Newly processed [$count] Already done [$alreadyDone] files Error [$errorCount]\n";
exit(0);



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

    print(join(" ", @command), "\n") if $verbose;

    my $status = system(@command);

    return $status;
}

__END__

=head1 NAME

prettyRepoFiles.pl: create the "pretty" of files in a git repository

=head1 SYNOPSIS

  prettyRepoFiles.pl [options] <cregitRepoDB> <authorsDB> <repository> <blameDir> <outputDirectory> <cregitRepoURL> <fileNameRegexp>

     Options:
       --override         overwrite existing files
       --help             brief help message
       --man              full documentation
       --header=s         file to insert as a header
       --footer=s         file to insert as a footer
       --blameExtension=s extension of blame files (default .blame)
       --prettyExtension=s extension to use in pretty (default .html)
       --formatpretty=s    full path formatPretty (command to create them pretty).
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
