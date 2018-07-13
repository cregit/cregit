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
#

use strict;
use Date::Parse;
use DBI;
use File::Basename;
use Getopt::Long;
use HTML::Template;
use Pod::Usage;
do "prettyPrint-core.pl"

my $man = 0;
my $help = 0;
my $verbose = 0;
my $templateFile = dirname(__FILE__) . "templates/page.tmpl";
my $outputFile = undef;
my $webRoot = "";

my $cregitVersion = "1.0-RC2";
my $dbh;
my $metaQuery;
my $metaCache = { };

sub main {
	my $sourceFile = shift @ARGV;
	my $blameFile = shift @ARGV;
	my $lineFile =  shift @ARGV;
	my $sourceDB = shift @ARGV;
	my $authorsDB = shift @ARGV;

	Usage("Source file does not exist [$sourceFile]", 0) unless -f $sourceFile;
	Usage("Tokenized line file does not exist [$lineFile]", 0) unless -f $lineFile;
	Usage("Tokenized blame file does not exist [$blameFile]", 0) unless -f $blameFile;
	Usage("Database of tokenized repository does not exists [$sourceDB]", 0) unless -f $sourceDB;
	Usage("Database of authors does not exists [$authorsDB]", 0) unless -f $authorsDB;

	setup_dbi($sourceDB, $authorsDB);

	my @params = get_template_parameters($sourceFile, $lineFile, $blameFile);
	my ($fileStats, $authorStats, $spans, $commits) = @params;

	my $template = HTML::Template->new(filename => "Templates/page.tmpl", die_on_bad_params => 0);
	$template->param(cregit_version => $cregitVersion);
	$template->param(file_name => $fileStats->{name});
	$template->param(web_root => $webRoot);
	$template->param(total_commits => $fileStats->{commits});
	$template->param(total_tokens => $fileStats->{tokens});
	$template->param(commit_spans => $spans);
	$template->param(commits => $commits);
	$template->param(contributors => $authorStats);

	my $file = *STDOUT;
	if (defined($outputFile)) {
		open($file, ">", $outputFile) or die("cannot write to [$outputFile]");
	}
	
	print $file $template->output();
	
	return 0;
}

sub get_template_parameters {
	my ($sourceFile, $lineFile, $blameFile) = @_;
	my $fileStats = { name => "", tokens => 0, commits => 0 };
	my $authorStats = { };
	my $commits = { };
	my @spans;
	
	open(SRC, $sourceFile) or die("unable to open [$sourceFile] file");
	open(LINE, $lineFile) or die("unable to open [$lineFile] file");
	open(BLAME, $blameFile) or die("unable to open [$blameFile] file");
	die("This is not a line token file") unless <LINE> =~ /begin_unit/;
	die("This is not a blame token file") unless <BLAME> =~ /begin_unit/;

	# Read source text and map line numbers to indices
	my @srcLineIndices = (-1);
	my $srcText = "";
	my $lineIndex = 0;
	while (my $line = <SRC>) {
		push(@srcLineIndices, $lineIndex);
		$srcText .= $line;
		$lineIndex += length($line);
	}
	
	# Parse line and blame token files together
	my $authorStat;
	my $span = { cid => undef };
	while (my $line = <LINE> and my $blame = <BLAME>) {
		chomp $line;
		chomp $blame;
		my @parts = split(/\|/, $line);
		my @parts2 = split(/;/, $blame);
		my @parts3 = split(/\|/, @parts2[2]);
		my ($loc, $type, $token) = @parts;
		my $cid = @parts2[0];
		my ($type2, $token2) = @parts3;
		
		#if ($token != $token2) {
		#	die "blame-token mismatch";
		#}
		
		if ($loc !~ /-/) {	
			if ($cid != %$span{cid}) {		
				# Update commit record
				my $commitStat = $commits->{$cid};
				if ($commitStat == undef) {
					my ($author, $date, $summary) = get_cid_meta($cid);
					$commitStat = {
						cid => $cid,
						author => $author,
						date => $date,
						epoch => str2time($date),
						summary => $summary,
					};
					$commits->{$cid} = $commitStat;
				}
				
				# Update author record
				my $author = $commitStat->{author};
				$authorStat = $authorStats->{$author};
				if ($authorStat == undef) {
					my $authorIdx = scalar (keys %$authorStats);
					$authorStat = {
						name => $author,
						tokens => 0,
						cids => { },
					};
					$authorStats->{$author} = $authorStat;
				}
				$authorStat->{cids}->{$cid} = 1;
				
				# Update span record
				my ($lineNum, $colNum) = split(/:/, $loc);
				my $index = @srcLineIndices[$lineNum] + $colNum - 1;
				$span->{length} = $index - $span->{start};
				$span->{body} = substr($srcText, $span->{start}, $span->{length});
				$span = {
					cid => $cid,
					author => $author,
					date => $commitStat->{date},
					start => $index,
					length => 0,
					body => "",
					author_class => "",
				};
				push(@spans, $span);
			}
			
			$authorStat->{tokens}++;
			$fileStats->{tokens}++;
		}
	}
	$span->{length} = length($srcText) - $span->{start};
	$span->{body} = substr($srcText, $span->{start}, $span->{length});
	
	# Update remaining file data
	$fileStats->{name} = fileparse($sourceFile);
	$fileStats->{commits} = scalar keys %$commits;
	
	# Update remaining author data
	my @authorStatsList;
	for my $key (sort keys %$authorStats) {
		my $stat = $authorStats->{$key};
		$stat->{commits} = scalar keys %{$stat->{cids}};
		$stat->{commit_proportion} = $stat->{commits} / $fileStats->{commits};
		$stat->{token_proportion} = $stat->{tokens} / $fileStats->{tokens};
		$stat->{commit_percent} = sprintf("%.2f\%", 100.0 * $stat->{commit_proportion} );
		$stat->{token_percent} = sprintf("%.2f\%", 100.0 * $stat->{token_proportion} );
		$stat->{class} = "author" . scalar @authorStatsList;
		push(@authorStatsList, $stat);
	}
	
	# Sort commits
	my @unsortedCommits = map { $_ } values %$commits;
	my @commits = sort { $a->{timestamp} cmp $b->{timestamp} } @unsortedCommits;
	
	# Update remaining span data
	my %commitMap = map { @commits[$_]->{cid}, $_ } 0..$#commits;
	my %classMap = map { @authorStatsList[$_]->{name}, "author$_" } 0..$#authorStatsList;
	for my $span (@spans) {
		$span->{cidx} = $commitMap{$span->{cid}};
		$span->{author_class} = $classMap{$span->{author}};
	}
	
	close SRC;
	close LINE;
	close BLAME;
	
	return ($fileStats, [@authorStatsList], [@spans], [@commits])
}

sub setup_dbi {
	my ($sourceDB, $authorsDB) = @_;
	$dbh = DBI->connect("dbi:SQLite:dbname=$sourceDB", "", "", { RaiseError => 1, AutoCommit => 1 }) or die $DBI::errstr;
	$dbh->do("attach database '$authorsDB' as a;");
	
	$metaQuery = $dbh->prepare("
	select coalesce(personname, personid, 'Unknown'), autdate, summary, originalcid, repo  
	from commits  natural left join commitmap 
	   left join emails on (autname = emailname and autemail = emailaddr)
	   natural left join persons
	where cid = ?;"
	);
	
	# Print column names
	my $testQuery = $dbh->prepare("select * from commits limit 1");
	# $testQuery->execute();
	# print STDERR join(" ", @{$testQuery->{NAME}});
}

sub get_cid_meta {
    my ($cid) = @_;
    if (defined($metaCache->{$cid})) {
        return @{$metaCache->{$cid}};
    }
	
	$metaQuery->execute(($cid));
	my @meta = $metaQuery->fetchrow();
	$metaCache->{$cid} = [@meta];
	if (scalar(@meta) != 5 ) {
		die "metadata for commit not found [$cid]";
	}
	
	return @meta;
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
	"template=s" => \$templateFile,
	"output=s"  => \$outputFile,
	"webroot=s" => \$webRoot,
) or die("Error in command line arguments\n");
exit pod2usage(-verbose=>1) if ($help);
exit pod2usage(-verbose=>2) if ($man);
exit pod2usage(-verbose=>1, -exit=>1) if (scalar(@ARGV) != 5);
exit main();

__END__

=head1 NAME

prettyPrint-main.pl: create the "pretty" output of files in a git repository

=head1 SYNOPSIS

  prettyRepoFiles.pl [options] <repoDir> <blameDir> <tokenDir> <cregitRepoDB> <authorsDB> <fileNameRegexp> <outputDir>

     Options:
        --help             Brief help message
        --man              Full documentation
        --template         The template file to use. Defaults to templates/page.tmpl
        --output           The output file. Defaults to STDOUT if none specified
        --webroot          The web_root template parameter value

=cut
