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

package PrettyPrint;
use strict;
use Date::Parse;
use Date::Format;
use DBI;
use File::Basename;
use Getopt::Long;
use HTML::Template;
use Pod::Usage;

my $dbh;
my $metaQuery;
my $metaCache = { };
my $metaCacheEnabled = 1;
my $defaultTemplate = dirname(__FILE__) . "/templates/page.tmpl";
my $warningCount = 0;
my $templateParams = {
	loop_context_vars => 1,
	die_on_bad_params => 0,
};

sub print_file {
	my $sourceFile = shift @_;
	my $blameFile = shift @_;
	my $lineFile =  shift @_;
	my $options = shift @_		// { };
	$options->{cregitVersion}	//= "0.0";
	$options->{templateFile}	//= $defaultTemplate;
	$options->{outputFile}		//= "";
	$options->{webRoot}			//= "";
	$options->{gitURL}			//= "";
	$warningCount = 0;

	return Error("Source file does not exist [$sourceFile]") unless -f $sourceFile;
	return Error("Tokenized line file does not exist [$lineFile]") unless -f $lineFile;
	return Error("Tokenized blame file does not exist [$blameFile]") unless -f $blameFile;

	my @params = get_template_parameters($sourceFile, $lineFile, $blameFile);
	return 1 unless $params[0] != 1;
	
	my ($fileStats, $authorStats, $spans, $commits, $contentGroups) = @params;
	my $firstCommit = @$commits[0];
	my $creationDate = time2str("%Y-%m-%d", $firstCommit->{epoch});
	my @sortedAuthors = sort { $a->{name} cmp $b->{name} } @$authorStats;

	my $template = HTML::Template->new(filename => $options->{templateFile}, %$templateParams);
	$template->param(file_name => $fileStats->{name});
	$template->param(total_commits => $fileStats->{commits});
	$template->param(total_tokens => $fileStats->{tokens});
	$template->param(line_count => $fileStats->{line_count});
	$template->param(creation_date => $creationDate);
	$template->param(creation_author => $firstCommit->{author});
	$template->param(content_groups => $contentGroups);
	$template->param(commit_spans => $spans);
	$template->param(commits => $commits);
	$template->param(contributors => $authorStats);
	$template->param(contributors_sorted => [@sortedAuthors]);
	$template->param(cregit_version => $options->{cregitVersion});
	$template->param(web_root => $options->{webRoot});
	$template->param(git_url => $options->{gitURL});

	my $file = undef;
	my $outputPath = $options->{outputFile};
	if ($outputPath ne "") {
		open($file, ">", $outputPath) or return Error("cannot write to [$outputPath]");
	} else {
		$file = *STDOUT
	}
	
	print $file $template->output();
	
	return 0;
}

sub get_template_parameters {
	my ($sourceFile, $lineFile, $blameFile) = @_;
	my $fileStats = { name => "", tokens => 0, commits => 0 };
	my $authorStats = { };
	my $commits = { };
	my @contentGroups;
	my @spans;
	
	return Error("unable to open [$sourceFile] file") unless open(my $SRC, $sourceFile);
	return Error("unable to open [$lineFile] file") unless open(my $LINE, $lineFile);
	return Error("unable to open [$blameFile] file") unless open(my $BLAME, $blameFile);
	return Error("[$lineFile] is not a line token file") unless <$LINE> =~ /begin_unit/;
	return Error("[$blameFile] is not a blame token file") unless <$BLAME> =~ /begin_unit/;
	
	# Read source text and map line numbers to indices
	my @srcLineLengths = (-1);
	my @srcLineIndices = (-1);
	my $srcText = "";
	my $lineIndex = 0;
	my $lineCount = 0;
	while (my $line = <$SRC>) {
		push(@srcLineIndices, $lineIndex);
		push(@srcLineLengths, length($line));
		$srcText .= $line;
		$lineIndex += length($line);
		$lineCount++;
	}
	
	# Parse line and blame token files together
	my $tokenLine = 2;
	my $authorStat;
	my $contentGroup = { done => 1, spans => []};
	my $span = { cid => undef, start => 0 };
	my $spanBreak = 0;
	while (my $line = <$LINE> and my $blame = <$BLAME>) {
		chomp $line;
		chomp $blame;
		my ($loc, $type, $token, $decl) = split(/\|/, $line, 4);
		my ($cid, $blank, $blameInfo) = split(/;/, $blame, 3);
		my ($type2, $token2) = split(/\|/, $blameInfo);
		my $isMeta = ($loc =~ /-/);
		my $isText = ($loc !~ /-/);
		
		if ($token ne $token2) {
			return Error("[ln$tokenLine]blame-token mismatch");
		}
		
		if ($isMeta)
		{
			# Start content group
			if ($type =~ /begin_/) {
				if (!$contentGroup->{done} && $contentGroup->{type} ne "unknown") {
					Warning("[ln$tokenLine]Encountered new content group without ending the previous one.");
				}
				
				my $groupType = substr($type, length("begin_"));
				$contentGroup = new_content_group($groupType);
				$spanBreak = 1;
				push (@contentGroups, $contentGroup);
			}
			
			# End content group
			if ($type =~ /end_/ and $type ne "end_unit") {
				if ($contentGroup->{done}) {
					Warning("[ln$tokenLine]Encountered end of content group without starting one.");
				}
				if (substr($type, length("end_")) ne $contentGroup->{type}) {
					Warning("[ln$tokenLine]Content group end type does not match the type of the current one. Continuing.");
				} else {
					$contentGroup->{done} = 1;
				}
			}
			
			# function declaration
			if ($type eq "DECL") {
				my ($lineNum, $colNum) = split(/:/, $loc);
				$contentGroup->{line_start} = $lineNum;
				$contentGroup->{decltype} = $token;
				$contentGroup->{declaration} = $decl;
			}
		}
		
		if ($isText)
		{
			my ($lineNum, $colNum) = split(/:/, $loc);
			my $lineLength = $srcLineLengths[$lineNum];
			
			if ($lineNum - 1 > $lineCount) {
				return Error("[ln$tokenLine] Received position $loc but source file is only $lineCount lines long.");
			} elsif ($colNum - 1 > $lineLength) {
				return Error("[ln$tokenLine] Received position $loc but source line is only $lineLength characters long.");
			}
		
			if ($contentGroup->{done}) {
				Warning("[ln$tokenLine]Encountered text content outside of content group. Adding to new group.");
				$contentGroup = new_content_group("unknown");
				$spanBreak = 1;
				push (@contentGroups, $contentGroup);
			}
		
			if ($cid ne %$span{cid} or $spanBreak) {
				my $commitStat = get_commit_stat($cid, $commits);
				my $authorName = $commitStat->{author};
				my $originalCid = $commitStat->{cid};
				
				# Update author record
				$authorStat = get_author_stat($authorName, $authorStats);
				$authorStat->{cids}->{$originalCid} = 1;
				
				# Update previous span record
				my $index = $srcLineIndices[$lineNum] + $colNum - 1;
				$span->{length} = $index - $span->{start};
				$span->{body} = substr($srcText, $span->{start}, $span->{length});
				
				# Sanity check
				return Error("[ln$tokenLine]Span start is undefined") if !defined($span->{start});
				return Error("[ln$tokenLine]Span length is negative. This is likely due to a mismatch between the blame/token files and the source file.") if $span->{length} < 0;
				
				# Start a new span
				$span = new_span($cid, $authorName, $index);
				push(@spans, $span);
				
				# Update content group
				if (!defined($contentGroup->{line_start})) {
					$contentGroup->{line_start} = $lineNum;
				}
				push(@{$contentGroup->{spans}}, $span);
				$contentGroup->{cids}->{$originalCid} = 1;
				
				$spanBreak = 0;
			}
			
			$contentGroup->{tokens}++;
			$authorStat->{tokens}++;
			$fileStats->{tokens}++;
		}
		
		$tokenLine++;
	}
	$span->{length} = length($srcText) - $span->{start};
	$span->{body} = substr($srcText, $span->{start}, $span->{length});
	
	# Update remaining file data
	$fileStats->{name} = fileparse($sourceFile);
	$fileStats->{commits} = scalar keys %$commits;
	$fileStats->{line_count} = $lineCount;
	
	# Update remaining content group data
	my $groupCount = scalar(@contentGroups);
	for (my $i = 0; $i < $groupCount; $i++) {
		my $group = @contentGroups[$i];
		$group->{line_end} = ($i < $groupCount - 1 ? @contentGroups[$i + 1]->{line_start} : $lineCount);
		$group->{spans_count} = scalar @{$group->{spans}};
		$group->{commits} = scalar %{$group->{cids}};
		$group->{cids} = undef;
	}
	
	# Sort and update remaining author data
	my @unsortedAuthors = values %$authorStats;
	my @authors = sort { $b->{tokens} <=> $a->{tokens} } @unsortedAuthors;
	for (my $i = 0; $i < scalar @authors; $i++) {
		my $author = $authors[$i];
		$author->{id} = $i;
		$author->{commits} = scalar keys %{$author->{cids}};
		$author->{commit_proportion} = $author->{commits} / $fileStats->{commits};
		$author->{token_proportion} = $author->{tokens} / $fileStats->{tokens};
		$author->{commit_percent} = sprintf("%.2f\%", 100.0 * $author->{commit_proportion} );
		$author->{token_percent} = sprintf("%.2f\%", 100.0 * $author->{token_proportion} );
		$author->{cids} = undef;
	}
	
	# Sort and update remaining commit data
	my @unsortedCommits = values %$commits;
	my @commits = sort { $a->{epoch} <=> $b->{epoch} } @unsortedCommits;
	my %authorMap = map { $authors[$_]->{name}, $_ } 0..$#authors;
	for (my $i = 0; $i < scalar @commits; $i++) {
		my $commit = $commits[$i];
		$commit->{author_id} = $authorMap{$commit->{author}};
	}
	
	# Update remaining span data
	my %commitMap = map { $commits[$_]->{cregit_cid}, $_ } 0..$#commits;
	for my $span (@spans) {
		$span->{cidx} = $commitMap{$span->{cid}};
		$span->{author_id} = $authorMap{$span->{author}};
		$span->{cid} = $commits[$span->{cidx}]->{cid};
	}
	
	return ($fileStats, [@authors], [@spans], [@commits], [@contentGroups])
}

sub new_content_group {
	my $type = shift @_;
	my $group = {
		done => 0,
		type => $type,
		spans => [],
		spans_count => 0,
		tokens => 0,
		cids => { },
		commits => 0,
		line_start => undef,
		line_end => undef,
		decltype => "",
		declaration => "",
	};
	
	return $group;
}

sub new_span {
	my $cid = shift @_;
	my $authorName = shift @_;
	my $start = shift @_;
	my $span = {
		cid => $cid,
		author => $authorName,
		author_id => -1,
		start => $start,
		length => 0,
		body => "",
	};
	
	return $span;
}

sub get_author_stat {
	my $name = shift @_;
	my $authorStats = shift @_;
	if ($authorStats->{$name} == undef) {
		$authorStats->{$name} = {
			id => -1,
			name => $name,
			tokens => 0,
			cids => { },
			tokens => 0,
			commits => 0,
			commit_proportion => 0,
			token_proportion => 0,
			commit_percent => "0%",
			token_percent => "0%",
		};
	}
	
	return $authorStats->{$name};
}

sub get_commit_stat {
	my $cid = shift @_;
	my $commitStats = shift @_;
	
	if ($commitStats->{$cid} == undef) {
		my ($author, $date, $summary, $originalCid) = get_cid_meta($cid);
		$commitStats->{$cid} = {
			cid => $originalCid,
			cregit_cid => $cid,
			author => $author,
			author_id => -1,
			date => $date,
			epoch => str2time($date),
			summary => $summary,
		};
	}

	return $commitStats->{$cid};
}

sub get_cid_meta {
    my $cid = shift @_;
	
	if ($metaCache->{$cid} != undef) {
        return @{$metaCache->{$cid}};
    }
	
	my $result = $metaQuery->execute($cid);
	my @meta = $metaQuery->fetchrow();
	if (!defined($result) or scalar(@meta) != 5 ) {
		Warning("Unable to retrieve metadata for commit [$cid]");
		@meta = ("unknown", "", "");
	}
	
	if ($metaCacheEnabled) {
		$metaCache->{$cid} = [@meta];
	}
	
	return @meta;
}

sub setup_dbi {
	my ($sourceDB, $authorsDB) = @_;
	my $dsn = "dbi:SQLite:dbname=$sourceDB";
	my $user = "";
	my $password = "";
	my $options = { RaiseError => 1, AutoCommit => 1 };
	$dbh = DBI->connect($dsn, $user, $password, $options) or die $DBI::errstr;
	$dbh->do("attach database '$authorsDB' as a;");
	
	$metaQuery = $dbh->prepare("
		select coalesce(personname, personid, 'Unknown'), autdate, summary, originalcid, repo  
		from commits  natural left join commitmap 
		   left join emails on (autname = emailname and autemail = emailaddr)
		   natural left join persons
		where cid = ?;"
	);
}

sub test_print_db_info {
	my $testQuery = $dbh->prepare("SELECT name FROM sqlite_master WHERE type='table';");
	$testQuery->execute();
	while (my $row = $testQuery->fetchrow()) {
		print STDERR $row, "\n";
	}

	my $testQuery2 = $dbh->prepare("select * from commits limit 1");
	$testQuery2->execute();
	print STDERR join(" ", @{$testQuery2->{NAME}});
}

sub Error {
    my $message = shift @_;
    print STDERR "Error: ", $message, "\n";
	return 1;
}

sub Warning {
	my $message = shift @_;
	print STDERR "Warning: ", $message, "\n";
	$warningCount++;
	return 1;
}

1;