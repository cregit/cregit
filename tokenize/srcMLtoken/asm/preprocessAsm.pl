#!/usr/bin/perl

use strict;
use warnings;

use File::Basename;


my $filename = shift;
my $output = shift;

die "$0 <filename> <outputfile*>" if $filename eq "";

print STDERR "Tokenizing $filename\n";
if (defined($output)) {
    open(OUT, ">$output") or die "Unable to create output file\n";
    select OUT;
}


open(IN, $filename) or die "Unable to open input file [$filename]";

my @all = <IN>;
close IN;
my $lines = join ('',@all);

#print strip_comments($lines);

my @linesNC = split(/\n/, strip_comments($lines));

print "being_unit\n";

foreach my $l (@linesNC) {
    if ($l =~ /^comment/) {
        print $l, "\n";
        next;
    }
            
    my ($l, $c) =split_comment($l);

    $l =~ s/^\s+//;
    $l =~ s/\s+$//;
    $l =~ s/\s+/ /g;
    print "comment|$c\n" if ($c);
   next if $l eq "";
    print "$l\n";
}

print "end_unit\n";

sub strip_comments {
    my $string=shift;
    my $t;
  $string =~ 

  s{
   /\*         ##  Start of /* ... */ comment
   [^*]*\*+    ##  Non-* followed by 1-or-more *'s
   (
     [^/*][^*]*\*+
   )*          ##  0-or-more things which don't start with /
               ##    but do end with '*'
   /           ##  End of /* ... */ comment

 |         ##     OR  various things which aren't comments:

   (
     "           ##  Start of " ... " string
     (
       \\.           ##  Escaped char
     |               ##    OR
       [^"\\]        ##  Non "\
     )*
     "           ##  End of " ... " string

   |         ##     OR

     '           ##  Start of ' ... ' string
     (
       \\.           ##  Escaped char
     |               ##    OR
       [^'\\]        ##  Non '\
     )*
     '           ##  End of ' ... ' string

   |         ##     OR

     .           ##  Anything other char
     [^/"'\\]*   ##  Chars which doesn't start a comment, string or escape
   )
 }{defined $2 ? $2 : ($t = $&, $t=~s/\n/ /g, "\ncomment|".$t."\n")}gxse;


  return $string;
}


sub split_comment {
    my $line = shift;
    my $com = "#;@!\|";

    if ($line =~ m@(.*?)//\s+(.*)$@) {
        return ($1, $2);
    }

    if ($line =~ /^[$com]+\s(.*)$/) {
        return ("", $1)
    }

    $line =~ /(.*?)\s[$com]+\s+(.*)$/;
    if (defined($2)) {
        return ($1, $2);
    }
    return ($line, "")
}


