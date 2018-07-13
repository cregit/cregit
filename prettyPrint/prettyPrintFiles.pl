#!/usr/bin/perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,#!/usr/bin/perl

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

use strict;
use File::Basename;
use File::Path qw(make_path);
use File::Spec::Functions;
use Getopt::Long;
use Pod::Usage;

my $prettyCommand = dirname(__FILE__) . "/prettyPrint-main.pl";
my $man = 0;
my $help = 0;
my $verbose = 0;
my $quiet = 0;
my $dryrun = 0;
my $filter = "";

sub main {
	my $repoDir = shift @ARGV;
	my $blameDir = shift @ARGV;
	my $lineDir = shift @ARGV;
	my $cregitDB = shift @ARGV;
	my $authorsDB = shift @ARGV;
	my $outputDir = shift @ARGV;

	open(FILES, "git -C '$repoDir' ls-files |") or die "unable to traverse git repo [$repoDir] $!";

	my $index = 0;
	my $count = 0;
	my $errorCount = 0;
	while (my $filePath = <FILES>) {
		chomp $filePath;
		next if ($filter != "" and $filePath !~ /$filter/);
		print(++$index . ": $filePath\n") if $verbose;
		
		my $originalFile = File::Spec->catfile($repoDir, $filePath);
		my $blameFile = File::Spec->catfile($blameDir, $filePath . ".blame");
		my $lineFile = File::Spec->catfile($lineDir, $filePath . ".token");
		my $outputFile = File::Spec->catfile($outputDir, $filePath . ".html");
		my ($fileName, $fileDir) = fileparse($outputFile);
		my $relative = File::Spec->abs2rel($outputDir, $fileDir);
		
		goto NOSOURCE if (! -f $originalFile);
		goto NOBLAME if (! -f $blameFile);
		goto NOLINE if (! -f $lineFile);
		
		print("$filePath\n") if !$quiet;
		
		my (@options, @args) = ((), ());
		push(@options, "--output=$outputFile");
		push(@options, "--webroot=$relative");
		push(@args, $originalFile);
		push(@args, $blameFile);
		push(@args, $lineFile);
		push(@args, $cregitDB);
		push(@args, $authorsDB);
		
		my $cmdline = join(' ', $prettyCommand, @options, @args);
		my $errorCode = 0;
		
		print($cmdline, "\n") if $verbose or $dryrun;
		if (!$dryrun) {
			make_path($fileDir);
			$errorCode = system($cmdline);
		}

		if ($errorCode != 0) {
			print "Error code [$errorCode][$filePath]\n";
			$errorCount++;
		}
		$count++;
		
		next;
		NOSOURCE:	print("file does not exist in local repo [$originalFile]. Skipping\n") if $verbose; next;
		NOBLAME:	print("blame file [$blameFile] does not exist. skipping\n") if $verbose; next;
		NOLINE:		print("line file [$lineFile] does not exist. skipping\n") if $verbose; next;
	}
	
	if (!$quiet) {
		print "Processed: [$count]\n";
		print "Errors: [$errorCount]\n";
	}
	return 0;
}

sub Usage {
    my ($message, $verbose) = @_;
    print STDERR $message, "\n";
    pod2usage(-verbose=>$verbose) if $verbose > 0;
    exit(1);
}

GetOptions (
	"help" => \$help,
	"man" => \$man,
	"verbose" => \$verbose,
	"dryrun" => \$dryrun,
	"command=s" => \$prettyCommand,
	"filter=s" => \$filter,
) or die("Error in command line arguments\n");
exit pod2usage(-verbose=>1) if ($help);
exit pod2usage(-verbose=>2) if ($man);
exit pod2usage(-verbose=>1, -exit=>1) if (scalar(@ARGV) != 6);
exit Usage("Unable to find executable at [$prettyCommand].", 0) if (! -X $prettyCommand);
exit main();

__END__

=head1 NAME

prettyPrint-files.pl: create the "pretty" output of files in a git repository

=head1 SYNOPSIS

  prettyRepoFiles.pl [options] <repoDir> <blameDir> <tokenDir> <repoDB> <authorsDB> <outputDir>

     Options:
        --help             Brief help message
        --man              Full documentation
        --verbose          Show verbose output
        --quiet            Suppress informational output
        --dryrun           Prints commands only
        --command          The command to run on each set of input files.
                           By default it looks in the same directory as this script.
        --filter           A regex file filter for processed files.

=cut
