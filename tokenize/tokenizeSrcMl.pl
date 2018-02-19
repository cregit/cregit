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

use strict;
use File::Basename;

my %declarations;
my %listDeclarations;

my %languages = ("C" => 1,
                 "C++" => 1,
                 "Java" => 1);

my %extensions = (
                  ".c" => 'C',
                  ".c++" => 'C++',
                  ".cc" => "C++",
                  ".cp" => 'C++',
                  ".cpp" => "C++",
                  ".cxx" => 'C++',
                  ".h" => "C",
                  ".h++" => 'C++',
                  ".hh" => 'C++',
                  ".hpp" => "C++",
                  ".java" => "Java",
                 );



use Getopt::Long;

my $usage = "
Usage $0 [options] <sourcefilename> <outputfile>*
        
Options:
   --srcml2token=<path to srcml2token>
   --srcml=<path to srcml>
   --language=<C/C++/Java>
   --ctags=-<path to ctags-universal>
   --position
";

my $basedir = dirname($0);
$basedir = "." if ($basedir eq "");

my $srcml   = "srcml";
my $srcml2token = "$basedir/srcMLtoken/srcml2token";
my $ctags = "ctags-universal";
my $language = "";
my $verbose;
my $position = 0;

GetOptions ("srcml=s" => \$srcml, 
            "srcml2token=s"   => \$srcml2token,
            "language=s"      => \$language,
            "ctags=s"         => \$ctags,
            "position"        => \$position,
            "verbose"  => \$verbose)   # flag
  or die($usage);


my $filename = shift;
my $output = shift;


print STDERR "Tokenizing $filename\n" if $verbose;
if ($output ne "") {
    open(OUT, ">$output") or die "Unable to create output file\n";
    select OUT;
}

# find language

if ($language eq "") {
    # autodetect
    Usage("File has no extension. You must provide one [$filename]") unless $filename =~ /(\.[a-z\+]+)$/i;
    my $ext = lc($1);
    $language = $extensions{$ext};
    Usage("Unknown extension [$ext] in file [$filename]. You must provide language using --language option") unless defined $language and $language ne "";
}

Usage("filename not specified") if $filename eq "";

Read_Declarations($filename, $language);

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
    open(parser, "$srcml -l $language --position '$filename' | $srcml2token |") or die "Unable to execute ctags on file [$filename]";

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
                if ($position) {
                    print "$line:-|";
                }
                print "DECL|";
                print "$thisDec{type}|$thisDec{name}\n";
            }
        } 
        $lastLine = $line;
        if ($position) {
            print "$line:$col|"
        }
        print "$token\n";
        if ($token =~ /^end_/) {
            if ($position) {
                print "-:-|"
            }
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
    my ($filename, $language) = @_;

    my $CTAGS = "$ctags --language-force=$language -x --sort=n --_xformat='%n %N @@@ %K @@@ %S'";

    open(ctags, "$CTAGS '$filename'|") or die "Unable to execute ctags on file [$filename]";

    while (<ctags>) {
        my %decl;
        my $rest;
        my $line;
        chomp;
        $decl{original} = $_;
        die "unable to parse output [$_]" unless /^([0-9]+) (.+) @@@ (.*) @@@ (.*)$/;
        #($decl{name}, $decl{type}, $decl{line}, $rest) = ($1, $2, $3, $4);
        ($decl{line}, $decl{name}, $decl{type}, $decl{sig}) = ($1, $2, $3, $4);
        if ($decl{sig} ne "-") {
            $decl{name} .= " " . $decl{sig}
        }
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


sub Usage {

    print STDERR @_;
    die $usage;

}
