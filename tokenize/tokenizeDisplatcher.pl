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
                 "Java" => 1,
                 "Go" => 1,
                 "Markdown" => 1,
                 "Shell" => 1,
                 "Yaml" => 1,
                 "Json" => 1
);

use Getopt::Long;

my $usage = "
Usage $0 [options] <sourcefilename> <outputfile>*
        
Options:
   --srcml2token=<path to srcml2token>
   --srcml=<path to srcml>
   --go2token=<path to go2token>
   --simpleTokenizer=<path to simpleTokenizer.pl>
   --rtokenizer=<path to ruby tokenizer>
   --language=<C/C++/Java/Go/Markdown/Yaml/Shell/Json>
   --ctags=-<path to ctags-exuberant>
";


my $go2token = "./tokenize/goTokenizer/gotoken";
my $simpleTokenizer = "./tokenize/text/simpleTokenizer.pl";
my $rTokenizer = 'rtokenize.sh';
my $srcml   = "srcml";
my $srcml2token = "srcml2token";
my $ctags = "ctags-exuberant";
my $language = "C";
my $verbose;

GetOptions ("srcml=s" => \$srcml, 
            "srcml2token=s" => \$srcml2token,
            "language=s" => \$language,
            "ctags=s" => \$ctags,
            "go2token=s" => \$go2token,
            "simpleTokenizer=s" => \$simpleTokenizer,
            "rtokenizer=s" => \$rTokenizer,
            "verbose" => \$verbose)   # flag
  or die($usage);

if (not defined($languages{$language})) {
    die($usage);
}


my $basedir = dirname($0);
$basedir = "." if ($basedir eq "");

my $filename = shift;
my $output = shift;

die $usage if $filename eq "";

print STDERR "Tokenizing $filename\n";
if ($output ne "") {
    open(OUT, ">$output") or die "Unable to create output file\n";
    select OUT;
}


# if ($language eq "Markdown" or $language eq "Shell" or $language eq "Yaml" or $language eq "Json") {
if ($language eq "Markdown" or $language eq "Shell") {

    open(parser, "$simpleTokenizer '$filename' |") or die "Unable to execute [$simpleTokenizer] on file [$filename]";
    print "begin_unit\n";
    while(<parser>) {
        print("text|" . $_);
    }
    close(parser);
    print "end_unit\n";

} elsif ($language eq "Yaml" or $language eq "Json") {

    if ($language eq "Yaml") {
        open(parser, "$rTokenizer -y < '$filename' |") or die "Unable to execute [$rTokenizer -y] on file [$filename]";
    } elsif ($language eq "Json") {
        open(parser, "$rTokenizer -j < '$filename' |") or die "Unable to execute [$rTokenizer -j] on file [$filename]";
    } else {
        die "This should not happen";
    }
    while(<parser>) {
        print $_;
    }
    close(parser);

} else {
    if ($language eq 'C' or $language eq 'C++' or $language eq 'Java' or $language eq 'Go') {
        Read_Declarations($filename, $language);
    }

    #Declarations_Test();

    Tokenize($filename);
    if ($output ne "") {
        close(OUT);
    }
}

if ($output ne "") {
    close(OUT);
}

exit;


sub Tokenize
{
    my $saveDir = `pwd`;
    chomp $saveDir;
    my ($filename) = @_;
    if ($language eq "Go") {
        open(parser, "$go2token '$filename' |") or die "Unable to execute [$go2token] on file [$filename]";
    } else {
        open(parser, "$srcml -l $language --position '$filename' | $srcml2token |") or die "Unable to execute srcml on file [$filename]";
    }

    my $lastLine = -1;

    while (<parser>) {
        chomp;
        my $line =$_;
        die "unable to parse srcml line [$line]" unless $line =~ /^([0-9]+|-):([0-9]+|-)\s+(.+)$/;
        my ($line, $col, $token) = ($1, $2, $3);
        $token = Remap_Token($token) if ($language eq "Go");
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
    my ($filename, $language) = @_;
    my $CTAGS = "$ctags --language-force=$language -x -u";

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

sub Remap_Token {
    my ($token) = @_;

    if ($token eq "||") {
        return "barbar|||"
    }

    if ($token =~ /^(.+)\|(.+)$/) {
        #my ($left, $right) = ($1, $2);
        #return $left . "|" . Unquote($right, $left);
        my @ary = split /\|/, $token;
        my $alen = scalar @ary;
        my $ttype = @ary[0];
        my $tvalue = join('|', @ary[1..$alen-1]);
        return $ttype . "|" . Unquote($tvalue, $ttype);
    } elsif ($token eq "begin_unit" or $token eq "end_unit") {
        # these tokens should have no text
        return $token;
    } else {
        return ($token . "|" . $token);
    }

}

sub Unquote {
    my ($token, $type) = @_;

    if ($type eq "STRING") {
        $token =~ s/^"(.+)"$/$1/;
        $token =~ s/\\"/"/g;
        $token =~ s/\\r/ /g;
        $token =~ s/\\t/ /g;
        $token =~ s/\\n/ /g;
        $token =~ s/\\\\u/\\u/g;
        $token =~ s/\\\\x/\\x/g;

        # this must be the very last one
        $token =~ s/\\\\/\\/g;
    } elsif ($type eq "COMMENT") {
        $token =~ s/^"(.+)"$/$1/;
        $token =~ s/\\"/"/g;
        $token =~ s/\\r/ /g;
        $token =~ s/\\t/ /g;
        $token =~ s/\\n/ /g;
        $token =~ s/\\\\u/\\u/g;
        $token =~ s/\\\\x/\\x/g;

        # this must be the very last one
        $token =~ s/\\\\/\\/g;
    } elsif ($type eq "CHAR") {
        $token =~ s/^"(.+)"$/$1/;
        $token =~ s/\\"/"/g;
        $token =~ s/\\\\/\\/g;
    } elsif ($type eq ";") {
        if ($token eq '"\n"') {
            $token= "";
        } else {
            $token =~ s/^"(.+)"$/$1/;
        }
    } elsif ($type eq "IDENT") {
        $token =~ s/^"(.+)"$/$1/;
    } elsif ($type eq "INT") {
        $token =~ s/^"(.+)"$/$1/;
    } elsif ($token ne "") {
        $token =~ s/^"(.+)"$/$1/;
    } else {
    }

    return $token;


}
