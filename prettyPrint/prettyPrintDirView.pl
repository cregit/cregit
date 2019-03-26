#!/usr/bin/perl
use strict;
use File::Path;
use File::Basename;
use Getopt::Long;
use Storable qw(dclone);

use lib dirname(__FILE__);
use prettyPrint;
use prettyPrintDirView;


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
# my $tokenExtension = ".token.line";
my $tokenExtension = ".token";
my $cregitCache = "cregit_cached";
my $count = 0;
my $index = 0;

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

    # Usage($message, $verbose)
    Usage("Source directory does not exist [$repoDir]", 0) unless -d $repoDir;
    Usage("Tokenized blame file directory does not exist [$blameDir]", 0) unless -d $blameDir;
    Usage("Tokenized line file directory does not exist [$lineDir]", 0) unless -d $lineDir;
    Usage("Database of tokenized repository does not exist [$sourceDB]", 0) unless -f $sourceDB;
    Usage("Database of authors does not exist [$authorsDB]", 0) unless -f $authorsDB;

    # end program if directory cannot be created
    exit PrettyPrint::Error("No output directory: $outputDir found, maybe try to run file view first\n") unless (-e $outputDir);

    # prepare metaQuery
    PrettyPrint::setup_dbi($sourceDB, $authorsDB, "");

    # filter for c and c++ programming language
    if ($filter_lang eq "c") {
        $filter = "\\.(h|c).html\$";
    } elsif ($filter_lang eq "cpp") {
        $filter = "\\.(h(pp)?|cpp).html\$";
    }

    my $rootCachedDataFile = File::Spec->catfile($outputDir, $cregitCache);
    my $errorCode = process_content_data($outputDir, $outputDir);
    unlink $rootCachedDataFile if (-e $rootCachedDataFile);
    print "Processed: [$count]\n";

    return PrettyPrint::Error("Unable to process root directory\n") unless $errorCode != 1;

    return 0;
}

sub process_content_data {
    my $rootPath = shift @_;
    my $dirPath = shift @_;

    my $dirName = basename($dirPath);
    $dirName = ($dirPath eq $rootPath) ? "root" : $dirName;
    my $cacheDirData = content_object($dirName);
    my $breadcrumbsPath = File::Spec->catdir("root/", substr($dirPath, length $rootPath));
    my $breadcrumbs = PrettyPrintDirView::get_breadcrumbs($breadcrumbsPath);
    $cacheDirData->{breadcrumbs} = $breadcrumbs;

    $cacheDirData->{path} = $dirPath;

    my @dirList = ();
    my @fileList = ();
    my $errorCode;
    my $fileCount;

    print "\nCollecting [$breadcrumbsPath] content data ..\n======\n";

    return PrettyPrint::Error("Unable to open [$dirName] directory") unless opendir(my $dh, $dirPath);
    my @contentList = grep {$_ ne '.' and $_ ne '..'} readdir $dh;

    foreach (@contentList) {
        my $currContent = $_;
        # skip hidden file or folder
        next if substr($currContent, 0, 1) eq ".";

        my $content;
        my $contentPath = File::Spec->catfile($dirPath, $currContent);
        if (-d $contentPath) {
            $content = process_content_data($rootPath, $contentPath);
            # return PrettyPrint::Error("Unable to process [$contentPath] content data") unless $errorCode != 1;

            # my $contentCacheFile = File::Spec->catfile($contentPath, $cregitCache);
            # $content = 0;
            # $content = PrettyPrintDirView::read_cached_data($contentCacheFile) if (-e $contentCacheFile);
            # unlink $contentCacheFile if (-e $contentCacheFile); # delete cached data after loaded into the memory
            return PrettyPrint::Warning("No cached data found, skipping ..\n") if $content == 1;
            # return PrettyPrint::Error("Unable to read from [$contentPath] cached data") unless $content != 1;

            $fileCount = $content->{contentStats}->{file_counts};
            # update fileList
            push (@dirList, $content) if $content != 1;
        } elsif (-f $contentPath and $contentPath =~ /$filter/) {
            print(++$index . ": $contentPath\n") if $verbose;

            my $fileName = substr ($contentPath, (length $rootPath)+1, (length $contentPath)-(length $rootPath)-6);

            my $sourceFile = File::Spec->catfile($repoDir, $fileName);
            my $blameFile = File::Spec->catfile($blameDir, $fileName . ".blame");
            my $lineFile = File::Spec->catfile($lineDir, $fileName . $tokenExtension);

            return PrettyPrint::Error("Source file does not exist [$sourceFile]") unless -f $sourceFile;
            return PrettyPrint::Error("Tokenized line file does not exist [$lineFile]") unless -f $lineFile;
            return PrettyPrint::Error("Tokenized blame file does not exist [$blameFile]") unless -f $blameFile;

            my @params = PrettyPrint::get_template_parameters($sourceFile, $lineFile, $blameFile);
            return 1 unless $params[0] != 1;
            my ($fileStats, $authors, $spans, $commits, $contentGroups, $repos) = @params;

            $content = content_object(basename($fileName));
            $content->{authors} = dclone $authors;
            $content->{commits} = dclone $commits;
            $content->{contentStats}->{commits} = $fileStats->{commits};
            $content->{contentStats}->{tokens} = $fileStats->{tokens};
            $content->{contentStats}->{line_counts} = $fileStats->{line_count};
            $content->{contentStats}->{author_counts} = scalar @{$authors};
            $content->{contentStats}->{file_counts} = "-";
            $fileCount = 1;

            # update fileList
            push (@fileList, $content);
            $count++;
        }

        $content->{url} = "./".basename($contentPath);

        # update directory stats
        $cacheDirData->{contentStats}->{tokens} += $content->{contentStats}->{tokens};
        $cacheDirData->{contentStats}->{line_counts} += $content->{contentStats}->{line_counts};
        $cacheDirData->{contentStats}->{file_counts} += $fileCount;

        # update authors and commits in directory stats
        my $authors = $content->{authors};
        my $commits = $content->{commits};
        my $dirAuthors = $cacheDirData->{authors};
        my $dirCommits = $cacheDirData->{commits};

        foreach (@{$authors}) {
            my $currAuthor = $_;
            my $currAuthorName = $currAuthor->{name};
            my @newCommitsByCurrAuthor = grep {$_->{author} eq $currAuthorName} @{$commits};

            if (grep {$_->{name} eq $currAuthorName} @{$dirAuthors}) {
                my @commitsByCurrAuthor = grep {$_->{author} eq $currAuthorName} @{$dirCommits};

                foreach (@newCommitsByCurrAuthor) {
                    my $commit = $_;
                    my $commitId = $commit->{cid};
                    if (my ($existingCommit) = grep {$_->{cid} eq $commitId} @commitsByCurrAuthor) {
                        $existingCommit->{token_count} += $commit->{token_count};
                    } else {
                        push (@{$dirCommits}, $commit);
                    }
                }

                # update commit counts for current author
                my ($currAuthorInDir) = grep {$_->{name} eq $currAuthorName} @{$dirAuthors};
                $currAuthorInDir->{tokens} += $currAuthor->{tokens};
                $currAuthorInDir->{commits} = scalar grep {$_->{author} eq $currAuthorName} @{$dirCommits};
            } else {
                push (@{$dirAuthors}, $currAuthor);
                push (@{$dirCommits}, @newCommitsByCurrAuthor);
            }
        }

        $cacheDirData->{contentStats}->{commits} = (defined $dirCommits) ? scalar @{$dirCommits} : 0;
        $cacheDirData->{contentStats}->{author_counts} = (defined $dirAuthors) ? scalar @{$dirAuthors} : 0;
        $cacheDirData->{authors} = (defined $dirAuthors) ? dclone $dirAuthors : undef;
        $cacheDirData->{commits} = (defined $dirCommits) ? dclone $dirCommits : undef;
    }

    $errorCode = PrettyPrintDirView::update_directory_stats($cacheDirData, \@dirList, \@fileList);
    return PrettyPrint::Error("Unable to update token stats for [$dirPath]") unless $errorCode != 1;

    my @trimmedData = PrettyPrintDirView::trim_directory_data($cacheDirData, \@dirList, \@fileList);
    return PrettyPrint::Error("Unexpected error with PrettyPrintDirView::trim_directory_data()") unless $trimmedData[0] != 1;

    $cacheDirData = shift @trimmedData;
    @dirList = @{shift @trimmedData};
    @fileList = @{shift @trimmedData};

    $errorCode = print_directory($cacheDirData, \@dirList, \@fileList);

    # my $cachedDataFile = File::Spec->catfile($dirPath, $cregitCache);
    # $errorCode = PrettyPrintDirView::write_cached_data($cachedDataFile, $cacheDirData);
    print "\n";
    # return PrettyPrint::Error("Unable to write cached data into [$cachedDataFile]\n") unless $errorCode != 1;

    return $cacheDirData;
}

sub print_directory {
    my $directory = shift @_;
    my @dirList = @{shift @_};
    my @fileList = @{shift @_};

    my $outputFile = File::Spec->catfile($directory->{path}, "index.html");
    my ($fileName, $fileDir) = fileparse($outputFile);
    my $relativePath = File::Spec->abs2rel($outputDir, $fileDir);
    $webRoot = $relativePath if $webRootRelative;
    $templateFile = $templateFile ? $templateFile : $defaultTemplate;
    my @contributorsByName = sort {$a->{name} cmp $b->{name}} @{$directory->{authors}};
    my @sortedDirList = sort {$a->{name} cmp $b->{name}} @dirList;
    my @sortedFileList = sort {$a->{name} cmp $b->{name}} @fileList;

    my $template = HTML::Template->new(filename => $templateFile, %$templateParams);

    $template->param(directory_name => $directory->{name});
    $template->param(web_root => $webRoot);
    $template->param(breadcrumb_nav => $directory->{breadcrumbs});
    $template->param(contributors_by_name => \@contributorsByName);
    $template->param(contributors_count => scalar @contributorsByName);
    $template->param(contributors => $directory->{authors});
    $template->param(total_tokens => $directory->{contentStats}->{tokens});
    $template->param(total_commits => $directory->{contentStats}->{commits});
    $template->param(has_subdir => scalar @dirList);
    $template->param(has_file => scalar @fileList);
    $template->param(directory_list => \@sortedDirList);
    $template->param(file_list => \@sortedFileList);
    $template->param(cregit_version => $cregitVersion);
    $template->param(has_hidden => (scalar @contributorsByName)>20);
    $template->param(time_min => $directory->{commits}[0]->{epoch});
    $template->param(time_max => $directory->{commits}[(scalar @{$directory->{commits}})-1]->{epoch});

    my $file = undef;

    if (-f $outputFile and !$overwrite) {
        print("Output file already exists. Skipping.\n") if $verbose;
        return;
    }

    if ($outputFile ne "") {
        open($file, ">", $outputFile) or return PrettyPrint::Error("cannot write to [$outputFile]");
    } else {
        $file = *STDOUT;
    }

    print "\nGenerating directory view of [$directory->{path}] ...";
    print $file $template->output();
    print " Done! \n";

    return 0;
}

sub content_object {
    my $name = shift @_;

    my $contentObject = {
        name => $name,
        contentStats => {
            tokens => 0,
            commits => 0,
            line_counts => 0,
            file_counts => 0,
            author_counts => 0
        },
        authors => undef,
        commits => undef
    };

    return $contentObject;
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

  prettyPrintDirView.pl: create the "pretty" output of directories detailed blame information in a git repository

=head1 SYNOPSIS

  prettyPrintDirView.pl [options] <sourceFile> <blameFile> <tokenFileWithLineNumbers> <cregitRepoDB> <authorsDB>

  prettyPrintDirView.pl [options] <repoDir> <blameDir> <tokenDirWithLineNumbers> <cregitRepoDB> <authorsDB> <outputDir>

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
