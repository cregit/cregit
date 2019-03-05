#!/usr/bin/perl
use strict;
use Date::Format;
use Date::Parse;
use File::Path;
use File::Basename;
use Getopt::Long;
use HTML::Template;
use Pod::Usage;
use Storable qw(dclone);
use lib dirname(__FILE__);
use prettyPrint;

# reserved global variables
my $cregitVersion = "2.0-RC1";
my $man = 0;
my $help = 0;
my $verbose = 0;
my $templateFile = undef;
my $webRoot = "";
my $webRootRelative = 0;
my $outputFile = undef;
my $gitURL = "";
my $dryrun = 0;
my $filter = "";
my $filter_lang = 0;
my $overwrite = 0;
my @userVars;
my %userVars;
my $tokenExtension = ".token.line";

my $repoDir;
my $blameDir;
my $lineDir;
my $sourceDB;
my $authorsDB;
my $outputDir;

my $defaultTemplate = dirname(__FILE__) . "/templates/directory.tmpl";
my $templateParams = {
	loop_context_vars => 1,
	die_on_bad_params => 0,
};

sub print_dir_info {
    $repoDir = shift @ARGV; # original.repo/
    $blameDir = shift @ARGV; # blame/
    $lineDir = shift @ARGV; # token.line/
    $sourceDB = shift @ARGV; # cregitRepoDB: token.db
    $authorsDB = shift @ARGV; # authorsDB: persons.db
    $outputDir = shift @ARGV; # output directory

    # filter for c and c++ programming language
    if ($filter_lang eq "c") {
	    $filter = "\\.(h|c)\$";
    } elsif ($filter_lang eq "cpp") {
	    $filter = "\\.(h(pp)?|cpp)\$";
    }

    # Usage($message, $verbose)
    Usage("Source directory does not exist [$repoDir]", 0) unless -d $repoDir;
    Usage("Tokenized blame file directory does not exist [$blameDir]", 0) unless -d $blameDir;
    Usage("Tokenized line file directory does not exist [$lineDir]", 0) unless -d $lineDir;
    Usage("Database of tokenized repository does not exist [$sourceDB]", 0) unless -f $sourceDB;
    Usage("Database of authors does not exist [$authorsDB]", 0) unless -f $authorsDB;

    # end program if directory cannot be created
    exit PrettyPrint::Error("Unable to create output directory: $outputDir\n") unless (-e $outputDir or mkdir $outputDir);

    # prepare metaQuery
    PrettyPrint::setup_dbi($sourceDB, $authorsDB);
	
    my $index = 0;
    my $processCount = 0;
    my $errorCount = 0;
    my $rootDirectoryContent = file_system_object("root", "d", "");
    get_directory_content($rootDirectoryContent);

    my @parentPath = ();
    process_directory_content($rootDirectoryContent, \@parentPath);

    return 0;
}

sub process_directory_content {
    my $directory = shift @_;
    my @parentPath = @{shift @_}; # breadcrumbs navigation
    my @dirList = ();
    my @fileList = ();

    my $currPath = File::Spec->catfile($repoDir, $directory->{path});
    return PrettyPrint::Error("unable to open [$currPath] directory") unless opendir(my $dh, $currPath);
    # readdir DIRHANDLE
    my @contentList = grep {$_ ne '.' and $_ ne '..'} readdir $dh;
    my @sortedContentList = sort_directory_content(\@contentList, $currPath); # sorted list : [dir...dir][file...file]
    
    foreach (@sortedContentList) {
        my $currContents = $_;
        # skip hidden file or directory
        next if substr($currContents, 0, 1) eq ".";

        my $contentPath = File::Spec->catfile($currPath, $currContents);
        my $path = $directory->{path} ? File::Spec->catfile($directory->{path}, $currContents) : $currContents; # special case for root path
        my $currObject = undef;

        # print "Directory : $contentpath\n" if -d $contentPath;

        if (-d $contentPath) {
            $currObject = file_system_object($currContents, "d", $path);
            get_directory_content($currObject);
            # skip empty directory or directory that has unrelated files
            next if !defined $currObject->{content};

            print "\nDirectory : $path\n";
            print "===== \n" if $verbose;

            # create new navigation list for next directory
            my @newParentPath = ();
            foreach (@parentPath) {
                push (@newParentPath, {name => $_->{name}, path => $_->{path} . "../"});
            }
            push (@newParentPath, {name => $directory->{name}, path => "../"});

            my @params = process_directory_content($currObject, \@newParentPath);

            push (@dirList, $currObject);

        } elsif (-f $contentPath) {
            # filter
            next if ($filter ne "" and $currContents !~ /$filter/); # in Java : if ($filter!="" and !$filePath.contains($filter)) continue; 
            
            print "$path\n" if $verbose;

            $currObject = file_system_object($currContents, "f", $path);

            my $sourceFile = File::Spec->catfile($repoDir, $path);
            my $blameFile = File::Spec->catfile($blameDir, $path . ".blame");
            my $lineFile = File::Spec->catfile($lineDir, $path . $tokenExtension);
            my @params = PrettyPrint::get_template_parameters($sourceFile, $lineFile, $blameFile);
            return 1 unless $params[0] != 1;

            my ($fileStats, $authors, $spans, $commits, $contentGroups, $repos) = @params;

            $currObject->{contentStats}->{commits} = $fileStats->{commits};
            $currObject->{contentStats}->{tokens} = $fileStats->{tokens};
            $currObject->{contentStats}->{line_counts} = $fileStats->{line_count};
            $currObject->{contentStats}->{file_counts}++;
            $currObject->{authors} = $authors;
            $currObject->{commits} = $commits;

            push (@fileList, $currObject);
        } else {
            next;
        }

        # update current directory
        $directory->{contentStats}->{commits} += $currObject->{contentStats}->{commits};
        $directory->{contentStats}->{tokens} += $currObject->{contentStats}->{tokens};
        $directory->{contentStats}->{line_counts} += $currObject->{contentStats}->{line_counts};
        $directory->{contentStats}->{file_counts} += $currObject->{contentStats}->{file_counts};

        # update directory authors list
        foreach (@{$currObject->{authors}}) {
            my $author = $_;
            my $authorName = $author->{name};

            # look for a matched author
            my ($matchedAuthor) = grep {$_->{name} eq $authorName} @{$directory->{authors}};
            if ($matchedAuthor) {
                # if match found, update the existing author
                $matchedAuthor->{commits} += $author->{commits};
                $matchedAuthor->{tokens} += $author->{tokens};
            } else {
                # not found, add it
                $directory->{authors}[scalar @{$directory->{authors}}] = dclone $author;
            }
        }

        # update directory commits list
        foreach (@{$currObject->{commits}}) {
            my $commit = $_;
            my $commitId = $commit->{cid};

            # look for a matched commit
            my ($matchedCommit) = grep {$_->{cid} eq $commitId} @{$directory->{commits}};
            
            $matchedCommit->{token_count} += $commit->{token_count} if $matchedCommit;
            next if $matchedCommit;
            # else add it to the diretory
            $directory->{commits}[scalar @{$directory->{commits}}] = dclone $commit;
        }
        
    }

    update_directory_stats($directory);

    print_directory($directory, \@parentPath, \@dirList, \@fileList);
    closedir $dh;

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
            return {};
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

    return \@dateGroups;
}

sub update_dir_and_file_stats {
    my $directory = shift @_;
    my @dirList = @{shift @_};
    my @fileList = @{shift @_};
    my $authors = $directory->{authors};

    my $tokenLen = 0;
    my $fileTokenLen = 0; # scale between files within the directory
    foreach (@dirList) {
        my $dir = $_;
        $tokenLen = $dir->{contentStats}->{tokens} if $dir->{contentStats}->{tokens} > $tokenLen;
        my $dirAuthors = $dir->{authors};
        foreach (@{$dirAuthors}) {
            my $dirAuthor = $_;
            my ($matchedAuthor) = grep {$dirAuthor->{name} eq $_->{name}} @{$authors};
            
            if (! defined $matchedAuthor) {
                PrettyPrint::Error("author $dirAuthor->{name} in directory $dir->{name} not found \n");
                return 1;
            }
            
            $dirAuthor->{id} = $matchedAuthor->{id};
            # $dirAuthor->{color_id} = ($dirAuthor->{id} > 60 ? "Black" : $dirAuthor->{id});
            $dirAuthor->{color_id} = $matchedAuthor->{color_id};
        }
        $dir->{contentStats}->{authors} = scalar @{$dirAuthors};
        my @dateGroups = commits_to_dategroup(\@{$dir->{commits}}, \@{$dirAuthors});
        my @sortedDateGroup = sort { $a->{timestamp} <=> $b->{timestamp} } @dateGroups[0];
        $dir->{dateGroups} = @{dclone(\@sortedDateGroup)}[0];
    }

    foreach (@fileList) {
        my $file = $_;
        $tokenLen = $file->{contentStats}->{tokens} if $file->{contentStats}->{tokens} > $tokenLen;
        $fileTokenLen = $file->{contentStats}->{tokens} if $file->{contentStats}->{tokens} > $fileTokenLen;
        my $fileAuthors = $file->{authors};
        foreach (@{$fileAuthors}) {
            my $fileAuthor = $_;
            my ($matchedAuthor) = grep {$fileAuthor->{name} eq $_->{name}} @{$authors};
            
            if (! defined $matchedAuthor) {
                PrettyPrint::Error("author $fileAuthor->{name} in file $file->{name} not found \n");
                return 1;
            }
            
            $fileAuthor->{id} = $matchedAuthor->{id};
            $fileAuthor->{color_id} = $matchedAuthor->{color_id};
        }
        $file->{contentStats}->{authors} = scalar @{$fileAuthors};
        my @dateGroups = commits_to_dategroup(\@{$file->{commits}}, \@{$fileAuthors});
        my @sortedDateGroup = sort { $a->{timestamp} <=> $b->{timestamp} } @dateGroups[0];
        $file->{dateGroups} = @{dclone(\@sortedDateGroup)}[0];
    }

    foreach (@dirList) {
        my $dir = $_;
        $dir->{line_counts} = $dir->{contentStats}->{line_counts};
        $dir->{file_counts} = $dir->{contentStats}->{file_counts};
        $dir->{author_counts} = $dir->{contentStats}->{authors};
        $dir->{total_tokens} = $dir->{contentStats}->{tokens};
        $dir->{url} = File::Spec->catfile($webRoot, $dir->{path});
        $dir->{width} = sprintf("%.2f\%", 100.0 * $dir->{contentStats}->{tokens} / $tokenLen);
        foreach (@{$_->{dateGroups}}) {
            $_->{width} = sprintf("%.2f\%", 100.0 * $_->{total_tokens} / $dir->{total_tokens});
        }
    }
    foreach (@fileList) {
        my $file = $_;
        $file->{line_counts} = $file->{contentStats}->{line_counts};
        $file->{file_counts} = "-";
        $file->{author_counts} = $file->{contentStats}->{authors};
        $file->{total_tokens} = $file->{contentStats}->{tokens};
        $file->{url} = File::Spec->catfile($webRoot, $file->{path}.".html");
        $file->{width} = sprintf("%.2f\%", 100.0 * $file->{contentStats}->{tokens} / $tokenLen);
        $file->{width_in_files} = sprintf("%.2f\%", 100.0 * $file->{contentStats}->{tokens} / $fileTokenLen);
        foreach (@{$_->{dateGroups}}) {
            $_->{width} = sprintf("%.2f\%", 100.0 * $_->{total_tokens} / $file->{total_tokens});
        }
    }
}


sub print_directory {
    my $directory = shift @_;
    my @breadcrumbs_nav = @{shift @_};
    my @dirList = @{shift @_};
    my @fileList = @{shift @_};

    my $outputPath = File::Spec->catfile($outputDir, $directory->{path});
    my $outputFile = File::Spec->catfile($outputPath, "index.html");
    my ($fileName, $fileDir) = fileparse($outputFile);
    my $relativePath = File::Spec->abs2rel($outputDir, $fileDir);
    $webRoot = $relativePath if $webRootRelative;
    $templateFile = $templateFile ? $templateFile : $defaultTemplate;
    my @contributorsByName = sort {$a->{name} cmp $b->{name}} @{$directory->{authors}};

    update_dir_and_file_stats($directory, \@dirList, \@fileList);
	my $template = HTML::Template->new(filename => $templateFile, %$templateParams);

    $template->param(directory_name => $directory->{name});
    $template->param(web_root => $webRoot);
    $template->param(breadcrumb_nav => \@breadcrumbs_nav);
    $template->param(contributors_by_name => \@contributorsByName);
    $template->param(contributors_count => scalar @contributorsByName);
    $template->param(contributors => $directory->{authors});
    $template->param(total_tokens => $directory->{contentStats}->{tokens});
    $template->param(total_commits => $directory->{contentStats}->{commits});
    $template->param(has_subdir => scalar @dirList);
    $template->param(has_file => scalar @fileList);
    $template->param(directory_list => \@dirList);
    $template->param(file_list => \@fileList);
    $template->param(cregit_version => $cregitVersion);
    $template->param(has_hidden => (scalar @contributorsByName)>20);
    $template->param(time_min => $directory->{commits}[0]->{epoch});
    $template->param(time_max => $directory->{commits}[(scalar @{$directory->{commits}})-1]->{epoch});

    my $file = undef;

    if (-f $outputFile and !$overwrite) {
        print("output file already exists. Skipping.\n") if $verbose; 
        return;
    }

    if ($outputFile ne "") {
        open($file, ">", $outputFile) or return PrettyPrint::Error("cannot write to [$outputFile]");
    } else {
        $file = *STDOUT;
    }
    
    print $file $template->output();
}

sub update_directory_stats {
    my $directory = shift @_;
    my $totalToken = $directory->{contentStats}->{tokens};
    my $totalCommit = $directory->{contentStats}->{commits};

    # sort authors by their tokens
    my @sortedAuthors = sort {$b->{tokens} <=> $a->{tokens}} @{$directory->{authors}};
    # update stats for each author, assign id
    my $index = 0;
    foreach (@sortedAuthors) {
        my $author = $_;

        $author->{id} = $index++;
        $author->{color_id} = $author->{id} > 60 ? "Black" : $author->{id};
        $author->{hidden} = $author->{id} > 20; # hide authors ranked below 20
        $author->{commit_proportion} = $author->{commits} / $totalCommit;
        $author->{token_proportion} = $author->{tokens} / $totalToken;
        $author->{commit_percent} = sprintf("%.2f\%", 100.0 * $author->{commit_proportion});
        $author->{token_percent} = sprintf("%.2f\%", 100.0 * $author->{token_proportion});

        # update commits list author_id
        my @matchedCommits = map {$_->{author_id} = $author->{id}} grep {$_->{author} eq $author->{name}} @{$directory->{commits}};
        return PrettyPrint::Error("no matched commits found on author : $author->{name}. \n") unless @matchedCommits;
    }
    $directory->{authors} = [@sortedAuthors];

    # sort commits by timestamp
	my @commits = sort { $a->{epoch} <=> $b->{epoch} } @{$directory->{commits}};
    $directory->{commits} = [@commits];
}

sub get_directory_stats {
    my $directory = shift @_;
    my $repoDir = shift @_;
    my $blameDir = shift @_;
    my $lineDir = shift @_;
    my $currContents = $directory->{content};
    # my $directoryStats = $directory->{contentStats};

    foreach (@$currContents) {
        my $content = $_;

        if ($content->{type} eq "d") {
            get_directory_stats($content, $repoDir, $blameDir, $lineDir);
        } elsif ($content->{type} eq "f") {
            print "$content->{path}\n";
            my $filePath = $content->{path};
            my $sourceFile = File::Spec->catfile($repoDir, $filePath);
            my $blameFile = File::Spec->catfile($blameDir, $filePath . ".blame");
            my $lineFile = File::Spec->catfile($lineDir, $filePath . $tokenExtension);
            
            my @params = PrettyPrint::get_template_parameters($sourceFile, $lineFile, $blameFile);
            return 1 unless $params[0] != 1;
            my ($fileStats, $authors, $spans, $commits, $contentGroups, $repos) = @params;

            $content->{contentStats}->{commits} = $fileStats->{commits};
            $content->{contentStats}->{tokens} = $fileStats->{tokens};
            $content->{authors} = $authors;
            $content->{commits} = $commits;
        }

        # update the current directory stats

        next if !defined $content->{contentStats} or !defined $content->{authors};

        $directory->{contentStats}->{commits} += $content->{contentStats}->{commits};
        $directory->{contentStats}->{tokens} += $content->{contentStats}->{tokens};
    
        foreach (@{$content->{authors}}) {
            my $author = $_;
            my $authorName = $author->{name};

            # look for a matched author
            my ($matchedAuthor) = grep {$_->{name} eq $authorName} @{$directory->{authors}};
            if ($matchedAuthor) {
                # if match found, update the existing author
                $matchedAuthor->{commits} += $author->{commits};
                $matchedAuthor->{tokens} += $author->{tokens};
            } else {
                # not found, add it
                $directory->{authors}[scalar @{$directory->{authors}}] = dclone $author;
            }
        }
    }
}

sub get_directory_content {
    my $directory = shift @_;
    my $currPath = File::Spec->catfile($repoDir, $directory->{path});
    
    return PrettyPrint::Error("unable to open [$currPath] directory") unless opendir(my $dh, $currPath);
    # readdir DIRHANDLE
    my @contentList = grep {$_ ne '.' and $_ ne '..'} readdir $dh;
    my @sortedContentList = sort_directory_content(\@contentList, $currPath);
    my $index = 0;
    foreach (@sortedContentList) {
        # skip hidden file or directory
        next if substr($_, 0, 1) eq ".";

        my $contentPath = File::Spec->catfile($currPath, $_);
        my $path = $directory->{path} ? File::Spec->catfile($directory->{path}, $_) : $_; # special case for root path
        my $currObject = undef;

        if (-d $contentPath) {
            $currObject = file_system_object($_, "d", $path);
            get_directory_content($currObject);
            # skip empty directory or directory that has unrelated files
            next if !defined $currObject->{content};
        } elsif (-f $contentPath) {
            # filter
            next if ($filter ne "" and $_ !~ /$filter/); # in Java : if ($filter!="" and !$filePath.contains($filter)) continue; 
            $currObject = file_system_object($_, "f", $path);
        } else {
            next;
        }

        # update content in current directory
        $directory->{content}[$index] = $currObject;
        $index++;
    }

    closedir $dh;
}

# sort directory content in a format: [directories][files]
sub sort_directory_content {
    my @list = @{shift @_};
    my $currPath = shift @_;
    my @dir = ();
    my @file = ();

    foreach (@list) {
        my $contentPath = File::Spec->catfile($currPath, $_);
        push (@dir, $_) if -d $contentPath;
        push (@file, $_) if -f $contentPath;
    }

    my @returnList = ();
    push (@returnList, sort @dir);
    push (@returnList, sort @file);

    return @returnList;
}

sub file_system_object {
    my $fsName = shift @_;
    my $fsType = shift @_;
    my $fsPath = shift @_;
    
    my $fsObject = {
        name => $fsName,
        type => $fsType,
        path => $fsPath,
        content => undef,
        contentStats => {
            commits => 0, 
            tokens => 0,
            line_counts => 0,
            file_counts => 0,
            authors => 0
            },
        authors => undef,
        commits => undef
    };

    return $fsObject;
}

GetOptions(
    "help" => \$help,
    "man" => \$man,
    "verbose" => \$verbose,
    "template=s" => \$templateFile,
    "output=s" => \$outputFile,
    "filter=s" => \$filter,
    "filter-lang=s" => \$filter_lang,
    "overwrite" => \$overwrite,
    "template-var=s" => \@userVars,
    "git-url=s" => \$gitURL,
    "webroot=s" => \$webRoot,
    "webroot-relative" => \$webRootRelative,
) or die("Error in command line arguments\n");
%userVars = map { split(/=/, $_, 2) } @userVars; # split user defined variables

exit pod2usage(-verbose=>1) if ($help);
exit pod2usage(-verbose=>2) if ($man);
exit pod2usage(-verbose=>1, -exit=>1) if (!defined(@ARGV[0]));
exit pod2usage(-verbose=>1, -exit=>1) if (not -f @ARGV[0] and not -d @ARGV[0]);
exit pod2usage(-verbose=>1, -exit=>1) if (-f @ARGV[0] and scalar(@ARGV) != 5);
exit pod2usage(-verbose=>1, -exit=>1) if (-d @ARGV[0] and scalar(@ARGV) != 6);
exit print_dir_info;

__END__

# pod
=head1 NAME

  prettyPrintDir.pl: create the "pretty" output of directories detailed blame information in a git repository

=head1 SYNOPSIS

  prettyPrintDir.pl [options] <sourceFile> <blameFile> <tokenFileWithLineNumbers> <cregitRepoDB> <authorsDB>

  prettyPrintDir.pl [options] <repoDir> <blameDir> <tokenDirWithLineNumbers> <cregitRepoDB> <authorsDB> <outputDir>

     Options:
        --help             Brief help message
        --man              Full documentation
        --verbose          Enable verbose output
        --template         The template file used to generate static html pages
                           Defaults to templates/page.tmpl
    
     Options: (single)
        --output           The output file. Defaults to STDOUT.
        --webroot          The web_root template parameter value.
                           Defaults to empty
        --git-url          The git_url template parameter value.
                           Defaults to empty
        --template-var     Defines additional template variables.
                           Usage: --template-var [variable]=[value]
    
     Options: (multi)
        --overwrite        Overwrite existing files that have previously been generated.
        --webroot          The web_root template parameter value.
                           Defaults to empty
        --webroot-relative Specifies that the value of webroot should
                           be set based on the relative path of the file
                           in relation to the output directory.
        --filter           A regex file filter for processed files.
        --filter-lang      Filters input files by language
                               c      *.c|*.h
                               cpp    *.cpp|*.h|*.hpp

# Pod block end
=cut
