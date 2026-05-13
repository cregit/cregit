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


# this program is run by bfg. It does not take any parameters. Instead, it simply reads
# its parameters from the environment

# Env. variables

# BFG_BLOB: the id of the blob (a SHA)
# BFG_FILENAME: basename of the file to process. it has an extension
# BFG_MEMO_DIR: directory of memoized files
# BFG_TOKENIZE_CMD: command to tokenize, might include parameters

# this program must not have any parameters

# it should  get all its parameters from the environment


use Digest::SHA qw(sha1_hex);
use DBI;
use File::Temp qw/ tempfile tempdir mkstemp/;
use strict;
use File::Path qw(make_path);
use File::Copy;



#my $shaDir = '/home/replay/git/token.sha1/';
#my $shaDir = '/home/replay/linux/token.sha/';
#my $shaDir = '/tmp/token.sha/';

# map extension to language

my %mapLang = (
               "c" => 'C',
               "c++" => 'C++',
               "cc" => 'C++',
               "cp" => 'C++',
               "cpp" => 'C++',
               "cxx" => 'C++',
               "go"  => 'go',
               "h" => 'C',
               "h++" => 'C++',
               "hh" => 'C++',
               "hpp" => 'C++',
               "java" => 'Java',
               "md" => "Markdown",
               "yaml" => "Yaml",
    "ac" => "M4",
    "am" => "M4",
    "rs" => "rust",
              );


if (not defined($ENV{BFG_MEMO_DIR}) ||  $ENV{BFG_MEMO_DIR} eq "") {
    die "You must define the environment variable BFG_MEMO_DIR equal to the directory where to memoize"
}

my $shaDir = $ENV{BFG_MEMO_DIR};

if ($shaDir eq "") {
    die "Directory to use to memoize not set. Use BFG_MEMO_DIR environment variable to set"
}

my $tokenizeCmd = $ENV{BFG_TOKENIZE_CMD};

if ($tokenizeCmd eq "") {
    die ("Tokenize command not defined. Use environment variable BFG_TOKENIZE_CMD");
}


die "Sha dir [$shaDir] does not exist" if not -d $shaDir;

my $contents = join( "", <> );

my $sha1 = sha1_hex($contents);


#`printf "--------------\n"`;
#`printf "$sha1\n" >> /speed/tmp/output.txt`;

#`printenv | grep BFG  >> /speed/tmp/output.txt`;

my $dir = $shaDir . '/' . substr($sha1, 0,2) . '/' . substr($sha1, 2,2);
my $filename = $shaDir . '/' . substr($sha1, 0,2) . '/' . substr($sha1, 2,2) . '/' . $sha1;

my $blob = $ENV{BFG_BLOB};
my $blobFN = $ENV{BFG_FILENAME};
my $fileExt;

die "BFG_FILENAME environment variable not set " if $blobFN eq "";

sub my_die {
    my $msg = $_[0]; 

    my $filename = "/tmp/error-tokenizer-${sha1}.err";

    open(my $fh, ">>", $filename) or die "Could not open file '$filename' $!";

    # Append lines to the file
    print $fh "Error processing command [${tokenizeCmd}]\n";
    print $fh "filename [${blobFN}\n";
    print $fh "blob     [${blob}]\n";
    print $fh "fileExt  [${fileExt}]\n";
    print $fh "error    [${msg}]\n";
    print $fh "--------------------\n${contents}";
    close $fh;
    die $msg;
}

if ($blobFN =~ /\.([^.]+)$/) {
    $fileExt = lc($1);
}

if (not defined($mapLang{$fileExt})) {
    my_die("unknown file extension [$fileExt]");
}

if (-f $filename) {
    open(IN, $filename) || my_die ("unable to open memoized file [$filename]");
    my $contents = join( "", <IN> );
    print $contents;
    close(IN);

} else {

  my ($fh, $file) = mkstemp( "tmpfile-in-XXXXX" );
  my ($fout, $outfile) = mkstemp( "tmpfile-out-XXXXX" );

  my $langOp = "--language=" . $mapLang{$fileExt};

  print STDERR "[$tokenizeCmd $langOp $file]\n";

  print $fh $contents or my_die("Unable to write temporary memoized file in tokeyBySha.pl");
  close $fh or my_die("Unable to write temporary memoized file in tokeyBySha.pl");

  open(PROC, "$tokenizeCmd $langOp $file |") or my_die ("unable to execute $tokenizeCmd (verify variable BFG_TOKENIZE_CMD) [$tokenizeCmd]");
  print STDERR "after executing command, before reading it\n";

  while (<PROC>) {
      print $_ ;
      print $fout $_ or my_die ("Unable to write ouput temporary memoized file in tokeyBySha.pl");
  }
  close PROC;
  close $fout;
  if ($? != 0) {
      print STDERR "after executing command, error code [$?]\n";
      my_die ("Failed to execute command error code [$?]");
  }
  if (-s $outfile == 0) {
      print STDERR "output file is empty! $?it\n";
      my_die ("$outfile is empty (zero size)");
  } 
  if (not -d $dir) {
      make_path($dir) or my_die "Unable to create memoized file in tokeyBySha.pl";;
  }

  move( $outfile, $filename) or my_die ("The move operation to memoized directory failed: $!");

  unlink($file) or my_die ("Unable to remove temporary input temporary memoized file in tokeyBySha.pl");

}
