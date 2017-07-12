#!/usr/bin/perl

use Text::ParseWords;


use strict;
use warnings;

undef $/;
my $s = <>;

my @tokens = split(/\s+/, $s);

for my $t (@tokens) {
    if ($t =~ /[(\[\]\)]/) {
#        print "++++$t+++++\n";
        my @subst = split(/([(\[\]\)])/, $t);
        for my $st (@subst) {
            print $st . "\n" if $st ne "";
        }
    } else {
        # we might have to remove trailing spaces
        print $t . "\n";
    } 
}


