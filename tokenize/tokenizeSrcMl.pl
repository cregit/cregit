#!/usr/bin/perl

use strict;
use File::Basename;


my %declarations;
my %listDeclarations;

use Getopt::Long;
  my $srcml   = "srcml";
  my $srcml2token = "srcml2token";
  my $verbose;
  GetOptions ("srcml=s" => \$srcml, 
              "srcml2token=s"   => \$srcml2token,
              "verbose"  => \$verbose)   # flag
  or die("Usage $0 [options] <sourcefilename> <outputfile>*

Options:
   --srcml2token=<path to srcml2token>
   --srcml=<path to srcml>
\n");


my $basedir = dirname($0);
$basedir = "." if ($basedir eq "");

my $filename = shift;
my $output = shift;

die "$0 <filename> <outputfile*>" if $filename eq "";

print STDERR "Tokenizing $filename\n";
if ($output ne "") {
    open(OUT, ">$output") or die "Unable to create output file\n";
    select OUT;
}

Read_Declarations($filename);

#Declarations_Test();

Tokenize($filename);

if ($output ne "") {
    close(OUT);
}

exit;


sub Tokenize
{
    my $saveDir = `pwd`;
    chomp $saveDir;
    #    my $PARSER = "srcml --src-encoding utf8 --position '$filename' | tokenizeSrcML adf | ";
    my $PARSER = "tokenizeSrcML";
    my ($filename) = @_;
    #    open(parser, "srcml --src-encoding utf8 -l C --position '$filename' | srcml2token |") or die "Unable to execute ctags on file [$filename]";
    open(parser, "$srcml -l C --position '$filename' | $srcml2token |") or die "Unable to execute ctags on file [$filename]";

    my $lastLine = -1;
    while (<parser>) {
#        print STDERR;
        chomp;
        my $line =$_;
        die "unable to parse srcml line [$line]" unless $line =~ /^([0-9]+|-):([0-9]+|-)\s+(.+)$/;
        my ($line, $col, $token) = ($1, $2, $3);
#        print STDERR "$line:$col:[$token]\n";
        die "ilegall line [$line] with [$line][$col]" if $line eq '' ;
        if ($line != $lastLine) {
            my @d = Declarations_In_Line($line);
            foreach my $dec (@d) {
                my %thisDec = Get_Declaration($line, $dec);
                print "DECL|";
                print "$thisDec{type}|$thisDec{name}\n";
            }
        } 
        $lastLine = $line;

        print "$token\n";
        if ($token =~ /^end_/) {
            printf "\n";
        }

    }
    close parser;
    chdir($saveDir);
}



sub Declarations_Test
{
    foreach my $line (sort {$a <=> $b} keys %declarations) {
        # each element is an array of hashes
        print "Line: $line\n";
        #    my $t = $decls{$line}{name};
        #    my %h = @$t;
        #    foreach my $k2 (sort keys %h) {
        #        print "  $k2 => $h{$k2}\n";
        #    }
        print "\n";
        print "Test decl in line [$line]\n";
        print join(':', Declarations_In_Line($line));
        print "\n";
        next;
        print "Test Get_Declarations [$line]\n";
        my @d = Declarations_In_Line($line);
        foreach my $dec (@d) {
            print "Declarations for [$line][$dec]\n";
            
            my %thisDec = Get_Declaration($line, $dec);
            foreach my $k (sort keys %thisDec) {
                print "   $k => $thisDec{$k}\n";
            }
            print "\n";
        }
        print "End Test Get_Declarations [$line]\n";
        print "\n";
    }
}

sub Declarations_In_Line
{
    my ($line) = @_;;
    my $a = $listDeclarations{$line};
    return () if not defined($a);
    return (@$a);
}

sub Get_Declaration
{
    my ($line, $name) = @_;
    my $d = $declarations{$line}{$name};
    die "Illegal value in get declaration [$line][$name]" unless defined $d;
    my %h = @$d;
    return %h;
}


sub Read_Declarations
{
    my ($filename) = @_;
    my $CTAGS = "ctags-exuberant --language-force=c -x -u";

    open(ctags, "$CTAGS '$filename'|") or die "Unable to execute ctags on file [$filename]";

    while (<ctags>) {
        my %decl;
        my $rest;
        my $line;
        chomp;
        $decl{original} = $_;
        die "unable to parse output" unless /^([^ ]+)\s+([^ ]+)\s+([0-9]+)\s+(.+)$/;
        ($decl{name}, $decl{type}, $decl{line}, $rest) = ($1, $2, $3, $4);
        $line = $decl{line};
        # skip the filename
        $decl{decl} = substr($rest, length($filename)+1);
        $decl{decl} =~ s/^\s+//;
        # we might have more than one declaration per line
        $declarations{$line}{$decl{name}} = [%decl];
        if (not defined $listDeclarations{$line}) {
            $listDeclarations{$line} = [];
        }
        my $v = $listDeclarations{$line};
        push (@$v, $decl{name});
        # build the return data structure
        # a hash of the four values
    }
    close ctags;
}

