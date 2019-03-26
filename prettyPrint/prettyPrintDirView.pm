package PrettyPrintDirView;
use strict;

use Data::Dumper::Names;
use Date::Format;
use Date::Parse;
use File::Path;
use File::Basename;
use Storable qw(dclone);

sub update_directory_stats {
    my $cacheDirData = shift @_;
    my @cachedDirList = @{shift @_};
    my @cachedFileList = @{shift @_};

    my $totalToken = $cacheDirData->{contentStats}->{tokens};
    my $totalCommit = $cacheDirData->{contentStats}->{commits};

    # sort authors by their tokens
    my @sortedAuthors = sort {$b->{tokens} <=> $a->{tokens}} @{$cacheDirData->{authors}};
    # update stats for each author, assign id
    my $index = 0;
    foreach (@sortedAuthors) {
        my $author = $_;

        $author->{id} = $index++;
        $author->{color_id} = $author->{id} > 60 ? "Black" : $author->{id};
        $author->{hidden} = $author->{id} > 20; # hide authors ranked below 20
        $author->{commit_proportion} = ($totalCommit == 0) ? 0 : ($author->{commits} / $totalCommit);
        $author->{token_proportion} = ($totalToken == 0) ? 0 : ($author->{tokens} / $totalToken);
        $author->{commit_percent} = sprintf("%.2f\%", 100.0 * $author->{commit_proportion});
        $author->{token_percent} = sprintf("%.2f\%", 100.0 * $author->{token_proportion});

        # update commits list author_id
        my @matchedCommits = map {$_->{author_id} = $author->{id}} grep {$_->{author} eq $author->{name}} @{$cacheDirData->{commits}};
        return PrettyPrint::Error("No matched commits found on author : $author->{name}\n") unless @matchedCommits;
    }

    $cacheDirData->{authors} = dclone [@sortedAuthors];

    # sort commits by timestamp
    my @sortedCommits = sort { $a->{epoch} <=> $b->{epoch} } @{$cacheDirData->{commits}};
    $cacheDirData->{commits} = dclone [@sortedCommits];

    # update token percent for content stats graph
    my $tokenLen = 0;
    my $fileTokenLen = 0; # scale between files within the directory
    my $lengthPercentage = 0;
    foreach (@cachedDirList) {
        my $dir = $_;
        $tokenLen = $dir->{contentStats}->{tokens} if $dir->{contentStats}->{tokens} > $tokenLen;
        my $dirAuthors = $dir->{authors};
        foreach (@{$dirAuthors}) {
            my $dirAuthor = $_;
            my ($matchedAuthor) = grep {$dirAuthor->{name} eq $_->{name}} @{$cacheDirData->{authors}};

            if (! defined $matchedAuthor) {
                return PrettyPrint::Error("author $dirAuthor->{name} in directory [$dir->{name}] not found \n");
            }

            $dirAuthor->{id} = $matchedAuthor->{id};
            $dirAuthor->{color_id} = $matchedAuthor->{color_id};
        }
        $dir->{contentStats}->{authors} = scalar @{$dirAuthors};
        my $dateGroups = commits_to_dategroup(\@{$dir->{commits}}, \@{$dirAuthors});
        my @sortedDateGroup = (defined $dateGroups) ? sort { $a->{timestamp} <=> $b->{timestamp} } @{$dateGroups} : ();
        $dir->{dateGroups} = [@sortedDateGroup];
    }

    foreach (@cachedFileList) {
        my $file = $_;
        $tokenLen = $file->{contentStats}->{tokens} if $file->{contentStats}->{tokens} > $tokenLen;
        $fileTokenLen = $file->{contentStats}->{tokens} if $file->{contentStats}->{tokens} > $fileTokenLen;
        my $fileAuthors = $file->{authors};
        foreach (@{$fileAuthors}) {
            my $fileAuthor = $_;
            my ($matchedAuthor) = grep {$fileAuthor->{name} eq $_->{name}} @{$cacheDirData->{authors}};

            if (! defined $matchedAuthor) {
                PrettyPrint::Error("author $fileAuthor->{name} in file $file->{name} not found \n");
                return 1;
            }

            $fileAuthor->{id} = $matchedAuthor->{id};
            $fileAuthor->{color_id} = $matchedAuthor->{color_id};
        }
        $file->{contentStats}->{authors} = scalar @{$fileAuthors};
        my $dateGroups = commits_to_dategroup(\@{$file->{commits}}, \@{$fileAuthors});
        my @sortedDateGroup = (defined $dateGroups) ? sort { $a->{timestamp} <=> $b->{timestamp} } @{$dateGroups} : ();
        $file->{dateGroups} = [@sortedDateGroup];
    }

    foreach (@cachedDirList) {
        my $dir = $_;
        $dir->{line_counts} = $dir->{contentStats}->{line_counts};
        $dir->{file_counts} = $dir->{contentStats}->{file_counts};
        $dir->{author_counts} = $dir->{contentStats}->{authors};
        $dir->{total_tokens} = $dir->{contentStats}->{tokens};
        $lengthPercentage = ($tokenLen == 0) ? 0 : 100.0 * $dir->{contentStats}->{tokens} / $tokenLen;
        $dir->{width} = sprintf("%.2f\%", $lengthPercentage);
        foreach (@{$_->{dateGroups}}) {
            $lengthPercentage = ($dir->{total_tokens} == 0) ? 0 : 100.0 * $_->{total_tokens} / $dir->{total_tokens};
            $_->{width} = sprintf("%.2f\%", $lengthPercentage);
        }
    }
    foreach (@cachedFileList) {
        my $file = $_;
        $file->{line_counts} = $file->{contentStats}->{line_counts};
        $file->{file_counts} = "-";
        $file->{author_counts} = $file->{contentStats}->{authors};
        $file->{total_tokens} = $file->{contentStats}->{tokens};
        $lengthPercentage = ($tokenLen == 0) ? 0 : 100.0 * $file->{contentStats}->{tokens} / $tokenLen;
        $file->{width} = sprintf("%.2f\%", $lengthPercentage);
        $lengthPercentage = ($fileTokenLen == 0) ? 0 : 100.0 * $file->{contentStats}->{tokens} / $fileTokenLen;
        $file->{width_in_files} = sprintf("%.2f\%", $lengthPercentage);
        foreach (@{$_->{dateGroups}}) {
            $lengthPercentage = ($file->{total_tokens} == 0) ? 0 : 100.0 * $_->{total_tokens} / $file->{total_tokens};
            $_->{width} = sprintf("%.2f\%", $lengthPercentage);
        }
    }

    return 0;
}

sub commits_to_dategroup {
    my @commits = @{shift @_};
    my @authors = @{shift @_};

    my @dateGroups = ();
    foreach (@commits) {
        my $commit = $_;
        my $commitAuthor = $commit->{author};
        my $commitTokenCount = $commit->{token_count};
        my ($matchedAuthor) = grep {$commitAuthor eq $_->{name}} @authors;

        if (! defined $matchedAuthor) {
            PrettyPrint::Error("author $commitAuthor not found. \n");
        }

        my $commitAuthorId = $matchedAuthor->{id};
        my $commitDate = time2str("%Y-%m-01 00:00:00", $commit->{epoch});
        my $dateGroupIndex = str2time($commitDate);

        my ($dateGroup) = grep {$dateGroupIndex eq $_->{timestamp}} @dateGroups;

        # create this date group if not defined
        push (@dateGroups, {timestr => time2str("%B %Y", $dateGroupIndex), timestamp => $dateGroupIndex, group => undef, total_tokens => 0}) if ! defined $dateGroup;

        my ($targetDateGroup) = grep {$dateGroupIndex eq $_->{timestamp}} @dateGroups;
        my ($groupWithAuthorId) = grep {$commitAuthorId eq $_->{author_id}} @{$targetDateGroup->{group}};

        if (! defined $groupWithAuthorId) {
            push (@{$targetDateGroup->{group}}, {
                author_id => $commitAuthorId,
                token_count => $commitTokenCount
            });
        } else {
            $groupWithAuthorId->{token_count} += $commitTokenCount;
        }
        $targetDateGroup->{total_tokens} += $commitTokenCount;
    }

    return [@dateGroups];
}

sub trim_directory_data {
    my $trimmedData = shift @_;
    my @trimmedDirList = @{shift @_};
    my @trimmedFileList = @{shift @_};

    my @authorOthersList = ();
    my $directoryAuthors = $trimmedData->{authors};



    return ($trimmedData, [@trimmedDirList], [@trimmedFileList]);
}

sub read_cached_data {
    my $dataFilePath = shift @_;

    my $cacheDirData = undef;
    open (my $in, "<", $dataFilePath) or return PrettyPrint::Error("cannot read data from [$dataFilePath]");

    {
        local $/;
        eval <$in>;
    }

    close $in;

    return ($cacheDirData);
}

# store the raw data for computing directory view graph table and age highlighting
sub write_cached_data {
    my $outputPath = shift @_;
    my $cacheDirData = shift @_;

    my $out;
    if ($outputPath ne "") {
        open($out, ">", $outputPath) or return PrettyPrint::Error("cannot write data to [$outputPath]");
    } else {
        $out = *STDOUT;
    }

    print $out Dumper($cacheDirData);

    return 0;
}

# get breadcrumbs for HTML view
sub get_breadcrumbs {
    my $dirPath = shift @_;

    my @breadcrumbs = ();
    my @dirs = File::Spec->splitdir($dirPath);

    my $pos = scalar(@dirs)-1;
    for (my $i=0; $i<$pos; $i++) {
        my $name = @dirs[$i];
        my $path = "../" x ($pos-$i);

        push (@breadcrumbs, {name => $name, path => $path});
    }

    return \@breadcrumbs;
}

1;