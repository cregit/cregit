#!/usr/bin/perl
use strict;
use Data::Dumper; # print stringified data
use Date::Parse;
use DBI;
use File::Path;
use File::Basename;
use Getopt::Long;
use HTML::Template;
use Pod::Usage;
use Storable qw(dclone); # for deep clone reference object
# potentially could reuse some of the functions in previous prettyPrint
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
my @userVars; # array
my %userVars; # hashref
my $tokenExtension = ".token.line";

sub print_dir_info {
    my $repoDir = shift @ARGV; # original.repo/
    my $blameDir = shift @ARGV; # blame/
    my $lineDir = shift @ARGV; # token.line/
    my $sourceDB = shift @ARGV; # cregitRepoDB: token.db
    my $authorsDB = shift @ARGV; # authorsDB: persons.db
    my $outputDir = shift @ARGV; # output directory
    my $filter = $filter; # filter key

    # filter for c and cpp programming language
    # TODO: compatible for other languages
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
    die "Unable to create output directory: $outputDir\n" unless (-e $outputDir or mkdir $outputDir);

    # prepare metaQuery
    PrettyPrint::setup_dbi($sourceDB, $authorsDB);
	
    my $index = 0;
    my $processCount = 0;
    my $errorCount = 0;
    my $rootDirectoryContent = file_system_object("root", "d", "");

    # update directory contents
    get_directory_content($rootDirectoryContent, $repoDir, $filter);
    # update directory statistics
    print "collecting stats...\n";
    get_directory_stats($rootDirectoryContent, $repoDir, $blameDir, $lineDir);
    print "updating directory stats...\n";
    update_directory_stats($rootDirectoryContent);

    # my @printDir = grep {$_->{type} eq "d"} @{$rootDirectoryContent->{content}}; 
    # foreach (@printDir) {
    #     print "====================\n";
    #     print "directory : $_->{name}\n contentStats : \n";
    #     print Dumper($_->{contentStats});
    #     print "authors : \n";

    #     my $authors = $_->{authors};
    #     foreach (@$authors) {
    #         my $author = $_;
    #         print "$author->{id} $author->{name} : $author->{token_percent} $author->{tokens}\n";
    #     }
    # }
    print Dumper(\$rootDirectoryContent);
}

sub update_directory_stats {
    my $directory = shift @_;

    print "====================================================\n";
    print "$directory->{path} : \n";
    print "Total token : $directory->{contentStats}->{tokens}\n";
    print "Total commit : $directory->{contentStats}->{commits}\n";

    my $totalToken = $directory->{contentStats}->{tokens};
    my $totalCommit = $directory->{contentStats}->{commits};

    # sort authors by their tokens
    my @sortedAuthors = sort {$b->{tokens} <=> $a->{tokens}} @{$directory->{authors}};
    # update stats for each author
    my $index = 0;
    foreach (@sortedAuthors) {
        my $author = $_;
        print "AUTHOR : $author->{name} \n";

        $author->{id} = $index++;
        $author->{commit_proportion} = $author->{commits} / $totalCommit;
        $author->{token_proportion} = $author->{tokens} / $totalToken;
        $author->{commit_percent} = sprintf("%.2f\%", 100.0 * $author->{commit_proportion});
        $author->{token_percent} = sprintf("%.2f\%", 100.0 * $author->{token_proportion});
    }
    $directory->{authors} = [@sortedAuthors];

    foreach (@{$directory->{content}}) {
        my $content = $_;

        # update sub-directory if there is any
        update_directory_stats($content) if $content->{type} eq "d";
    }
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
    my $repoDir = shift @_; # repoDir : /home/zkchen/cregit-data/git/original.repo-v2.17/git
    my $filter = shift @_;
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
            get_directory_content($currObject, $repoDir, $filter);
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
        contentStats => {commits => 0, tokens => 0},
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