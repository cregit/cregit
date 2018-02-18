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
# This program is not very good, but it gets the job done
#
# its objective is to generate an HTML version of the source code
# where each token is colorized according to who is the author of the
# commit that last inserted the token
#
# it takes many different parameters (see Usage for how to use)
#
#   database of authors: information about unified authors so people with
#                        different emails have the same identifier
#
#   commitsDB          : database of metadata of the tokenized repo
#   source             : path to the file of the original source code
#   token-blame file   : path to the tokenized blamed file
#   title              : title of the HTML file
#   footer             : filename to insert as footer to the HTML output
#   header             : filename to insert as header to the HTML output
#
# bugs:
#     some files have multibyte characters that get messed up in the
#     tokenization. Those files might not be properly converted
#
#     I would say that this file has "organically" morphed into its
#     current version. I would rewrite it

use strict;

use HTML::FromText;
use DBI;
use File::Basename;
use Set::Scalar;
use Getopt::Long;
use Pod::Usage;
use IO::Handle;
use File::Basename;
use File::Temp qw/ tempfile tempdir mkstemp/;
use File::Path qw(make_path remove_tree);
use File::Copy;

my $commandPath = dirname(__FILE__);

my %memoCidMeta;

my $cregitVersion = "1.0-RC2";

#my $dbName = shift @ARGV;
#my $authorsDB = shift @ARGV;


#my $source = shift @ARGV;;
#my $token = shift @ARGV;;
#my $title = shift @ARGV;
#my $headerFileName = shift @ARGV;
#my $footerFileName = shift @ARGV;
#my $dbName = '/home/linux/linux-token-bfg-4_10.db';
#my $authorsDB = '/home/dmg/git.projects/l.analysis/new-authors/unified-authors.db';

my $headerFileName = $commandPath . "/header.html";
my $footerFileName = $commandPath . "/footer.html";
my $help = 0;
my $man = 0;
my $verbose = 0;
my $cregitRepoURL = "https://github.com/REPO_URL/commit/";

GetOptions ("header=s" => \$headerFileName,
            "footer=s" => \$footerFileName,
            "help"     => \$help,      # string
            "verbose"  => \$verbose,
            "man"      => \$man)   # flag
        or die("Error in command line arguments\n");

if (scalar(@ARGV) != 7) {
    Usage();
}

my $dbName =  shift @ARGV;
my $authorsDB = shift @ARGV;
my $source = shift @ARGV;;
my $token = shift @ARGV;;
my $outputFile = shift @ARGV;
my $title = shift @ARGV;
$cregitRepoURL = shift @ARGV;

my ($fh, $temp) = mkstemp( "tmpfile-XXXXX" );

select($fh);

# file has been created, we can handle interrupts now
$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;



#my $fileBlameURL= 'https://github.com/torvalds/linux/blame/master/';
#my $commitURL = 'https://github.com/torvalds/linux/commit/';

Usage( "Source file does not exist [$source]") unless -f $source;
Usage( "Tokenized blame file does not exist [$token]") unless -f $token;
Usage( "Database of tokenized repository does not exists [$dbName]") unless -f $dbName;
Usage( "Database of authors does not exists [$authorsDB]") unless -f $authorsDB;

my $dbh = DBI->connect("dbi:SQLite:dbname=$dbName", "", "", { RaiseError => 1, AutoCommit => 1 }) or die $DBI::errstr;

my $at = $dbh->prepare("attach database '$authorsDB' as a;");
$at->execute();

my $header = "";
my $footer = "";

$header = Read_Inc_File($headerFileName) if $headerFileName;

$footer = Read_Inc_File($footerFileName) if $footerFileName;

my $lastChar;

open(SRC, $source) or "unable to open [$source] file";
open(TOKEN, $token) or "unable to open [$token] file";

my %counts;
my %colors;
my %bgcolors;
my $currentColor =1;

my @palette = (
               "hsl(017, 097%, 044%)",
               "hsl(169, 049%, 031%)",
               "hsl(208, 068%, 052%)",
               "hsl(316, 056%, 025%)",
               "hsl(104, 044%, 045%)",
               "hsl(329, 089%, 037%)",
               "hsl(247, 087%, 031%)",
               "hsl(182, 082%, 033%)",
               "hsl(000, 000%, 000%)",
               "hsl(312, 092%, 028%)",
               "hsl(034, 094%, 053%)",
               "hsl(156, 096%, 032%)",
               "hsl(351, 031%, 051%)",
               "hsl(338, 078%, 051%)",
               "hsl(273, 073%, 050%)",
               "hsl(021, 061%, 036%)",
               "hsl(173, 093%, 047%)",
               "hsl(091, 091%, 047%)",
               "hsl(073, 033%, 025%)",
               "hsl(342, 042%, 041%)",
               "hsl(238, 098%, 052%)",
               "hsl(190, 090%, 026%)",
               "hsl(099, 099%, 027%)",
               "hsl(277, 037%, 029%)",
               "hsl(117, 077%, 029%)",
               "hsl(234, 054%, 025%)",
               "hsl(143, 063%, 046%)",
               "hsl(108, 088%, 037%)",
               "hsl(177, 057%, 035%)",
               "hsl(095, 055%, 033%)",
               "hsl(286, 026%, 028%)",
               "hsl(086, 066%, 037%)",
               "hsl(039, 039%, 026%)",
               "hsl(325, 045%, 032%)",
               "hsl(260, 040%, 025%)",
               "hsl(047, 047%, 051%)",
               "hsl(290, 070%, 040%)",
               "hsl(121, 041%, 035%)",
               "hsl(043, 083%, 040%)",
               "hsl(008, 028%, 041%)",
               "hsl(164, 024%, 031%)",
               "hsl(147, 027%, 047%)",
               "hsl(199, 079%, 038%)",
               "hsl(355, 075%, 025%)",
               "hsl(303, 023%, 047%)",
               "hsl(186, 046%, 047%)",
               "hsl(004, 064%, 041%)",
               "hsl(056, 036%, 050%)",
               "hsl(026, 086%, 039%)",
               "hsl(212, 032%, 044%)",
               "hsl(065, 025%, 045%)",
               "hsl(134, 074%, 042%)",
               "hsl(299, 059%, 039%)",
               "hsl(160, 060%, 026%)",
               "hsl(125, 085%, 025%)",
               "hsl(013, 053%, 050%)",
               "hsl(030, 050%, 040%)",
               "hsl(195, 035%, 030%)",
               "hsl(112, 052%, 031%)",
               "hsl(151, 071%, 039%)",
               "hsl(078, 058%, 049%)",
               "hsl(225, 065%, 028%)",
               "hsl(264, 084%, 044%)",
               "hsl(221, 021%, 041%)",
               "hsl(138, 038%, 052%)",
               "hsl(251, 051%, 036%)",
               "hsl(082, 022%, 032%)",
#               "rgb(0, 0, 0)",
#               "rgb(14, 76, 161)",
#                  "rgb(155, 229, 2)",
#                  "rgb(0, 95, 57)",
#                  "rgb(0, 255, 0)",
#                  "rgb(149, 0, 58)",
#                  "rgb(255, 147, 126)",
#                  "rgb(164, 36, 0)",
#                  "rgb(0, 21, 68)",
#                  "rgb(145, 208, 203)",
#                  "rgb(0, 174, 126)",
#                  "rgb(194, 140, 159)",
#                  "rgb(190, 153, 112)",
#                  "rgb(0, 143, 156)",
#                  "rgb(95, 173, 78)",
#                  "rgb(255, 0, 0)",
#                  "rgb(255, 0, 246)",
#                  "rgb(255, 2, 157)",
#                  "rgb(104, 61, 59)",
#                  "rgb(213, 255, 0)",
#                  "rgb(1, 0, 103)",
#                  "rgb(255, 0, 86)",
#                  "rgb(158, 0, 142)",
#                  "rgb(98, 14, 0)",
#                  "rgb(255, 116, 163)",
#                  "rgb(150, 138, 232)",
#                  "rgb(152, 255, 82)",
#                  "rgb(167, 87, 64)",
#                  "rgb(1, 255, 254)",
#                  "rgb(155, 138, 232)",
#                  "rgb(107, 104, 130)",
#                  "rgb(0, 0, 255)",
#                  "rgb(0, 125, 181)",
#                  "rgb(106, 130, 108)",
#                  "rgb(254, 137, 0)",
#                  "rgb(189, 198, 255)",
#                  "rgb(1, 208, 255)",
#                  "rgb(187, 136, 0)",
#                  "rgb(117, 68, 177)",
#                  "rgb(165, 255, 210)",
#                  "rgb(255, 166, 254)",
#                  "rgb(119, 77, 0)",
#                  "rgb(122, 71, 130)",
#                  "rgb(38, 52, 0)",
#                  "rgb(0, 71, 84)",
#                  "rgb(67, 0, 44)",
#                  "rgb(181, 0, 255)",
#                  "rgb(255, 177, 103)",
#                  "rgb(255, 219, 102)",
#                  "rgb(144, 251, 146)",
#                  "rgb(126, 45, 210)",
#                  "rgb(189, 211, 147)",
#                  "rgb(229, 111, 254)",
#                  "rgb(222, 255, 116)",
#                  "rgb(0, 255, 120)",
#                  "rgb(0, 155, 255)",
#                  "rgb(0, 100, 1)",
#                  "rgb(0, 118, 255)",
#                  "rgb(133, 169, 0)",
#                  "rgb(0, 185, 23)",
#                  "rgb(120, 130, 49)",
#                  "rgb(0, 255, 198)",
#                  "rgb(255, 110, 65)",
#                  "rgb(232, 94, 190)"
                 );


my $c;

Skip_Whitespace();

my $first = 1;
my $isBlame = 1;

my $prevCommit;

Print_Header($title);

my %totalPerFunc;
my %total;
my %totalCommitsPerFunc;
my %totalCommits;
my $funNameBy;

my $row = 0;
my $col = 0;
my $prevRow = 0;
Init_Location();

my $line = 0;
while (<TOKEN>) {
    my $token;
    my $file;
    my $cid;
    chomp;

    $token = $_;

    if ($first and /^begin_unit/) {
        # we process the blame file

        $isBlame = 0;
        $first = 0;
    }

    if ($first and /begin_unit/) {
        $token = s/\|.*$//;
        $first = 0;
    }

    if ($isBlame) {

        my @f = split(/;/, $_);

        $cid = shift @f;
        $file = shift @f;

        my $temp = join(';', $cid, $file);

        $token = substr($_, length($temp)+1);
        $token =~ s/^\s*//;

        if ($token !~ /^DECL/) {
            $line++;
            print "<a name=\"L${line}\"></a>";
            ($row, $col) = Location();
            if ($row != $prevRow) {
                print "<a name=\"R${row}\"></a>";
                $prevRow = $row;
            }
        }

    } else {
        die "This is not a blame file";
    }


#    print STDERR "aaaaaa[$token]\n";
#    my $token = $_;

    if (not $token =~ /^(.+?)\|(.+)$/) {
        if ($token eq "begin_function") {
            $funNameBy = "";
            Func_Count_Reset();
            print "<hr class=\"beginFunc\">\n";
        } elsif ($token eq "end_function") {

            Print_Func_Stats();

            print "<hr class=\"endFunc\">\n";
        }
        next;
    }
#    print STDERR "Cid :$cid\n";

    my ($person,$autdate,$sum, $originalcid, $repo) = Get_Cid_Meta($cid);
    print Get_Author_Color_From_Cid($dbh,$cid);
    
    my ($type, $value) = ($1,$2);

    if ($type eq "comment") {
        my $text = Skip_Comment($value);
        #        print "<t>$text</t>";

        Add_Contribution($person, $cid);
        Output_Token("$text", $originalcid, $repo);
        
    } elsif (($type eq "literal")) {
        my $text = Skip_Literal($value);
        Output_Token($text, $originalcid, $repo);

        Add_Contribution($person, $cid);


    } elsif ($type eq "DECL") {
        my $anchor = Extract_Name_From_DECL($value);
        
        print "<a name=\"$anchor\"></a>\n";
    } elsif ($value eq "") {
        ; # do nothing

#        $funNameBy ="Function declaration last changed by by $person [$autdate] $sum";
        
    } elsif (($type eq "begin_function") or ($type eq "end_function") ) {
        print "<hr>";
        next;
    } else {
#        print "Token [$token]\n";
        my $text = Skip_Token($value);
        #        print "<t>$text</t>";
        Output_Token($text, $originalcid, $repo);

        Add_Contribution($person, $cid);


    }
    #    print "[TOKEN][$token]\n";
    print "</span>";
    Skip_Whitespace();
}

Print_File_Stats();
Print_Footer();

select(STDOUT);
close $fh;


copy_file($temp, $outputFile);
if ($verbose) {
    print STDERR "...completed\n";
}

exit 0;

sub Usage {
    my ($m) = @_;
    print STDERR "$m\n";
    pod2usage(-verbose=>1);
    exit(1);
}

sub Print_Footer{
    print $footer;
}

sub Output_Token {
    my ($text, $originalcid, $repo) = @_;
    my $fun;
    # these are hardcoded for linux :)
    if ($repo eq "p") {
        $fun = 'windowpopPreHist';
    } elsif ($repo eq "b") {
        $fun = 'windowpopBitkeeper';
    } elsif ($repo eq "l") {
        $fun = 'windowpopLinux';
    } else {
        $fun = 'windowpop';
    }

    print("<a class=\"cregit\" target='_blank' onclick=\"return $fun('$originalcid')\">");
    Print($text);
    print("</a>");
}


sub Print_Func_Stats {

    my $tot = 0;
    my $totCommits = Function_Total_Commits();
    foreach my $k (keys %totalPerFunc) {
        $tot += $totalPerFunc{$k};
    }

    Print_Stats_Header("Contributors");
    foreach my $k (sort { $totalPerFunc{$b} <=> $totalPerFunc{$a} }  (keys %totalPerFunc)) {
        my $toks = $totalPerFunc{$k};

        my $ccount = Function_Count_Commits($k);
        my $prop = sprintf("%.2f\%", 100.0 * $toks/$tot );
        my $cprop = sprintf("%.2f\%", 100.0 * $ccount/$totCommits);
        print "<tr><td>" , Span_Color_Tag(Get_Author_Color($k), $k), $k,"</span>", "</td><td align=\"right\">$toks</td><td align=\"right\">$prop</td><td align=\"right\">$ccount</td><td align=\"right\">$cprop</td>";
#        print "<tr><td>$k</td>";
        print "</tr>\n";

    }
    print "<tr><td>Total</td><td  align=\"right\">$tot</td><td align=\"right\">100.00%</td><td align=\"right\">$totCommits</td><td align=\"right\">100.00%</td></tr>";

    print "</table>\n";
}

sub  Print_File_Stats {

    print "<hr class=\"endFile\">";

    my $tot = 0;
    foreach my $k (keys %colors) {
        $tot += $total{$k};
    }

    my $totCommits = Total_Commits();

    Print_Stats_Header("Overall Contributors");


    foreach my $k (sort { $total{$b} <=> $total{$a} } (keys %colors)) {
        my $toks = $total{$k};
        my $prop = sprintf("%.2f\%", 100.0 * $toks/$tot );
        my $ccount = Count_Commits($k);
        my $cprop = sprintf("%.2f\%", 100.0 * $ccount/$totCommits);

        print "<tr><td><!--file stats-->" , Span_Color_Tag(Get_Author_Color($k), $k), $k,"</span>", "</td><td align=\"right\">$toks</td><td align=\"right\">$prop</td><td align=\"right\">$ccount</td><td align=\"right\">$cprop</td>";
#        print "<tr><td>$k</td>";
        print "</tr>\n";
    }
    print "<tr><td>Total</td><td align=\"right\">$tot</td><td align=\"right\">100.00%</td><td align=\"right\">$totCommits</td><td align=\"right\">100.00%</td></tr>";
    print "</table>\n";
}


sub Print {
    my ($text) = @_;
    print text2html($text);

#    print $conv->process_chuck($text);
}

sub Skip_Literal {
    my ($literal)= @_;
    my $original = $literal;
    my $text = "";
    my $len = length($literal);
    my $new = "";
    while ($literal ne "") {
        my $cT;
        ($cT, $literal) = Consume($literal);

        my $c = Read_Src_Char();

        if (length($c) == 0) {
            print STDERR "literal [$original][$c] is empty\n";
            die;
        }

        if (Is_Whitespace($c) and Is_Not_Whitespace($cT)) {
            while (defined($c) and Is_Whitespace($c)) {
                $text .= $c;
                $c = Read_Src_Char();
            }
        }

        if (Is_Not_Whitespace($c) and Is_Whitespace($cT)) {
            die "it should not reacch here" if $literal eq "";
            while ($literal and Is_Whitespace($cT) ) {
                ($cT, $literal) = Consume($literal);
            }
        }
        die unless defined($c);
        die unless defined($cT);
        $text .= $c;
        if (($c eq $cT) or
            ($c eq "\n" and $cT eq " ")) {
            # this is ok
        } else {
            my $oc = ord($c);
            my $ocT = ord($cT);

            if ($ocT> 127 and $oc > 127) {
                # extended characters. srcML changes encoding
                # so we have to assume that these are mismatches in the encoding
                # see if we can synchronize, one of the two might be multitoken
                # if both are upper values
                my $max = 2;
                while ($max-- > 0 and $original ne "" and $ocT> 128) {
                    # read next token
                    # and things should be ok...
                    ($cT, $literal) = Consume($literal);
                    $ocT = ord($cT);
                }
                die "literal does not match exp [$original] found [$text] [$c][$cT][$oc][$ocT]"  unless $c == $cT;

            }


    }
    }

    return $text;
}

sub Consume {
    my ($st) = @_;
    return (substr($st,0,1), substr($st,1));
}

sub Is_Whitespace {
    my ($ch) = @_;

    die "In whitespace [$ch]. it should be one char" unless length($ch) == 1;
    return $ch =~ /^\s+$/;
}

sub Is_Not_Whitespace {
    my ($ch) = @_;
    return not Is_Whitespace($ch);
}


sub Skip_Comment {
    my ($comment) = @_;
    my $text;

    while ($comment ne "") {
        my $ch = Read_Src_Char();

        while (Is_Whitespace($ch)) {
            $text .= $ch;
            $ch = Read_Src_Char();
        }
        my $cT;
        
        ($cT, $comment)= Consume($comment);

        while (Is_Whitespace($cT) and ($comment ne "")) {
            ($cT, $comment)= Consume($comment);
        }

#        print "C> Token [$cT] text [$ch]\n";
        $text .= $ch;
        my $cTo = ord($cT);
        my $cho = ord($ch);
        if ($cTo == 131 and $cho == 165) {
#            $ch = $cT;
        }
#        print STDERR $ch;
        if (($cT eq $ch) or ($cT eq ' ' and $ch eq "\n")) {
            ;
        } else {
            if ($cTo> 127 and $cho > 127) {
                # extended characters. srcML changes encoding
                # so we have to assume that these are mismatches in the encoding
                # see if we can synchronize, one of the two might be multitoken
                # if both are upper values
                my $max = 2;
                while ($max-- > 0 and $comment ne "" and $cTo> 127 ) {
                    # read next token
                    # and things should be ok...
                    ($cT, $comment)= Consume($comment);
                    $cTo = ord($cT);
                }
            }
            if ($cT != $ch) {
                print STDERR "not matching\n";
                die "Token [$cT] Text [$ch]  [$cTo][$cho]";
            }
        }
       
    }
    return $text;
}

sub Skip_Token2 {
    my ($token) = @_;
    my $text;

    while ($token ne "") {
        my $ch = Read_Src_Char();
        while ($ch eq "\t") {
            $ch = Read_Src_Char();
        }
        my $cT;
        ($cT, $token) = Consume($token);

        $text .= $ch;
        die "[$cT][$ch]" unless ($cT eq $ch) or ($cT eq ' ' and $ch eq "\n");
    }
    return $text;
}

sub Skip_Token {
    my ($token) = @_;
    my $text;
    $token =~ s/\s//g;
    my $l = length($token);
    my $match ;
    while ($l > 0) {
        my $ch = Read_Src_Char();
        $text .= $ch;

        if (Is_Not_Whitespace($ch)) {
            $l--;
            $match .= $ch;
        }
    }
    $match =~ s/\n/ /g;
    die "Difference [$text] token [$token] match [$match]" unless $token eq $match;
    return $text;
}


{ 
    my $lastchar;
    my $row = 1;
    my $col = 1;
    my $prevCol = 0;

    sub Init_Location {
        $row = 1;
        $col = 1;
        $prevCol = 0;
    }
    
    sub Read_Src_Char {
        my $ch ;


        if (not defined($lastChar)) {
            read(SRC, $ch, 1);
        } else {
            $ch = $lastChar;
            undef $lastChar;
        }
        if ($ch eq "\n") {
            $row ++;
            $prevCol = $col;
            $col = 1;
        } else {
            $col++;
        }

        return $ch;
    }

    sub Un_Read_Char {
        ($lastChar) = @_;

        if ($lastChar eq "\n") {
            $row --;
            $col = $prevCol;
        } else {
            $col--;
        }

        
    }

    sub Skip_Whitespace {
        
        my $ch;

        while (defined($ch = Read_Src_Char)) {
            last if not $ch =~ /^\s$/;
            print "$ch";
        }
        if (defined($ch)) {
            Un_Read_Char($ch);
        }
    }

    sub Location {
        return ($row, $col);
    }

}

sub Get_Cid_Meta {
    my ($cid) = @_;
    my $ret;
    if (defined($memoCidMeta{$cid})) {
        $ret = $memoCidMeta{$cid};
        return @$ret;
    } else {
#        print STDERR "$cid\n";
        my @meta = Simple_Query($dbh, "
select coalesce(personname, personid, 'Unknown'), autdate, summary,originalcid, repo  
from commits  natural left join commitmap 
   left join emails on (autname = emailname and autemail = emailaddr)
   natural left join persons
where cid = ?;", $cid);

        if (scalar(@meta) != 5 ) {
            die "metadata for commit not found [$cid]";
        }

        # we need to clean up the summary because it might have HTML characters
        $meta[2] =~ s/"/&quot;/g;

        $memoCidMeta{$cid} = [@meta];
        return @meta;
    }
}

sub Get_Author {
    my ($aut) = @_;
    $aut =~ s/^<//;
    $aut =~ s/>$//;
    return $aut;
}

sub Simple_Query {
    my ($dbh, $query, @params) = @_;

    my $meta = $dbh->prepare($query);
    
    $meta->execute(@params);

    return $meta->fetchrow();

}


{

    sub Span_Color_Tag {
        my ($color, $bg, $title) = @_;
        return "<span title=\"$title\" style=\"color: $color; background-color: $bg)\">";
    }


    sub Get_Author_Color_From_Cid {

        my ($dbh, $cid) = @_;
        my $title = $cid;
        my $aut = "bob";
        my @meta = Get_Cid_Meta($cid);
        my ($color, $bg) = Get_Author_Color($meta[0]);
        $title = join(';', @meta);
        return Span_Color_Tag($color, $bg, $title);
        
    }

    sub Get_Author_Color {
        my ($aut) = @_;
        my $ori = $aut;

#        print STDERR "=>[$aut]\n";
#        print STDERR "[$currentColor]\n";
        if (not defined ($colors{$aut})) {
            $colors{$aut} = $palette[$currentColor];
            #            $bgcolors{$aut} = $palette[($currentColor + 5) % scalar(@palette)];
            $bgcolors{$aut} = $currentColor *3;
#            print STDERR "[$aut] => [$colors{$aut}] [$currentColor]";
            $currentColor =  ($currentColor + 1) % scalar(@palette);
        }
        
        #        return "<span style=\"color: $colors{$aut}; background-color: $bgcolors{$aut}\">";
        my $bg;
        if ($bgcolors{$aut} % 4 == 0) {
            $bg = 255;
        } else {
            $bg= $bgcolors{$aut} % 64 + 127+64;
        }
        return ($colors{$aut}, "rgb($bg,$bg,$bg)");
    }

 
}

# <html>
# <head>
# <script type="text/javascript" src="http://turingmachine.org/~dmg/cregit/cregit.js" ></script>
# <link rel="stylesheet" type="text/css" href="http://turingmachine.org/~dmg/cregit/cregit-linux.css">
# <title>$title</title>
# </head>
# <body>

# $header



sub Print_Header {
    my ($title)= @_;
    print <<END;
$header
<pre>
END
}     

sub Read_Inc_File {
    my ($file) = @_;
    my $lines = "";
    open(IN, $file) or die "unable to open file $file";
    while (<IN>) {
        $lines .= $_;
    }
    close(IN);

    my $filename = $title;
    my $dir = dirname($filename);

    $lines =~ s/_CREGIT_FILENAME_/$filename/g;
    $lines =~ s/_CREGIT_DIRNAME_/$dir/g;
    $lines =~ s/_CREGIT_VERSION_/$cregitVersion/g;
    $lines =~ s/_CREGIT_REPO_URL_/$cregitRepoURL/g;
    return $lines;
}

sub Func_Count_Reset {
    %totalCommitsPerFunc = ();
    %totalPerFunc = ();

}

sub Add_Contribution {
    my ($person, $cid) = @_;
    Add_Commit($person, $cid);
    $totalPerFunc{$person}++;
    $total{$person}++;

}
        


sub Add_Commit {
    my ($person, $cid) = @_;

    if (defined($totalCommitsPerFunc{$person})) {
        my $s = $totalCommitsPerFunc{$person};
        $s->insert($cid);
    } else {
        $totalCommitsPerFunc{$person} = Set::Scalar->new($cid);
    }

    if (defined($totalCommits{$person})) {
        my $s = $totalCommits{$person};
        $s->insert($cid);
    } else {
        $totalCommits{$person} = Set::Scalar->new($cid);
    }


}



sub Function_Count_Commits {
    my ($person) = @_;

    if (defined($totalCommitsPerFunc{$person})) {
        my $s = $totalCommitsPerFunc{$person};        
        return $s->size();
    } else {
        return 0;
    }
}

sub Count_Commits {
    my ($person) = @_;

    if (defined($totalCommits{$person})) {
        my $s = $totalCommits{$person};        
        return $s->size();
    } else {
        return 0;
    }
}


sub Function_Total_Commits {
    my $count = 0;

    foreach my $k (keys %totalCommitsPerFunc) {
        my $s = $totalCommitsPerFunc{$k};
        $count += $s->size();;
    }
    return $count;
}

sub Total_Commits {
    my $count = 0;

    foreach my $k (keys %totalCommits) {
        my $s = $totalCommits{$k};
        $count += $s->size();;
    }
    return $count;
}

sub Print_Stats_Header {
    my ($title) = @_;
    print "<h4>$title</h4>";
    print '<table>';
    print "<tr><td>Person</td><td>Tokens</td><td>Prop</td><td>Commits</td><td>CommitProp</td>";
}
         

sub Extract_Name_From_DECL {
    my ($value) = @_;
    my @fields = split('\|', $value);
    return pop @fields;
}

sub signal_handler{
    print STDERR "Program interrupted. Deleting [$outputFile]\n";
    close (STDOUT);
    if (-f $outputFile) {
        unlink($outputFile);
    }
}

sub copy_file
{
    my ($from, $toName) = @_;
    
    my $toDir = dirname($toName);

#    printf ("copy [$from] to [$to] [$toDir][$toName]\n");

    die "from file does not exist in copy_file [$from]" if not -f $from;

    if (not -d $toDir) {
        printf("Creating directory [$toDir]\n");
	make_path($toDir) or "die unable to create directory $toDir";
    } 
    move($from, $toName) or
            (unlink($toName),  "unable to move [$from] to [$toName]");
}


__END__

=head1 NAME

prettyPrint-author.pl - generate the pretty-printed files

=head1 SYNOPSIS

prettyPrint-author.pl [options] <cregitDB> <authorsDB>  <originalSourceCode> <tokenizedBlame> <outputFile> <titleOfHTMLfile>  <cregitRepoURL<>

     Options:
       --header=s           File to use as header
       --footer=s           File to use as footer
       --help               brief help message
       --man                full documentation

=head1 OPTIONS

=over 8

=item B<--help>
    Print a brief help message and exits.

=item B<--man>
    Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<This program> will read run blame on a given file in a given git 
repository and create a file in the output directory
with the same full path as the original file, with 
the .blame extension (which can be changed with the --blame option).

=cut
