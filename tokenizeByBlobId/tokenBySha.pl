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

my %mapLang = (
               "h" => 'C',
               "c" => 'C',
               "hpp" => 'C++',
               "h++" => 'C++',
               "java" => 'Java',
               "cpp" => 'C++',
               "c++" => 'C++',
               "go"  => 'Go',
               "md" => "Markdown",
               "sh" => "Shell",
               "yaml" => "Yaml",
               "yml" => "Yaml",
               "json" => "Json",
              );

my $logfile = "perllog.txt";
my $debugLog = 0;
open(LOG,">>","$logfile") || die ("Error : can't open log file");

if (not defined($ENV{BFG_MEMO_DIR}) ||  $ENV{BFG_MEMO_DIR} eq "") {
    print LOG "BFG_MEMO_DIR\n" if $debugLog;
    die "You must define the environment variable BFG_MEMO_DIR equal to the directory where to memoize"
}

my $shaDir = $ENV{BFG_MEMO_DIR};

if ($shaDir eq "") {
    print LOG "SHA_DIR\n" if $debugLog;
    die "Directory to use to memoize not set. Use BFG_MEMO_DIR environment variable to set"
}

my $tokenizeCmd = $ENV{BFG_TOKENIZE_CMD};

if ($tokenizeCmd eq "") {
    print LOG "TOKENIZE_CMD\n" if $debugLog;
    die ("Tokenize command not defined. Use environment variable BFG_TOKENIZE_CMD");
}

my $contents;

print LOG "SHA_DIR_NE\n" if not -d $shaDir and $debugLog;
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

print LOG "BFG_FILENAME\n" if $blobFN eq "" and $debugLog;
die "BFG_FILENAME environment variable not set " if $blobFN eq "";

my $fileExt;

if ($blobFN =~ /\.([^.]+)$/) {
    $fileExt = $1;
}

if (not defined($mapLang{$fileExt})) {
    print LOG "UNKNOWN_EXT: $fileExt\n" if $debugLog;
    die "unknown file extension [$fileExt]";
}

if (-f $filename) {
    open(IN, $filename) || die "unable to open memoized file [$filename]";
    my $contents = join( "", <IN> );
    print $contents;
    close(IN);
    
} else {

  my ($fh, $file) = mkstemp( "tmpfile-in-XXXXX" );
  my ($fout, $outfile) = mkstemp( "tmpfile-out-XXXXX" );

  print $fh $contents;
  close $fh;

  my $langOp = "--language=" . $mapLang{$fileExt};

  my $env = "BFG_BLOB=$blob BFG_FILENAME='$blobFN' BFG_MEMO_DIR=$shaDir BFG_TOKENIZE_CMD='$tokenizeCmd'";
  if ($debugLog) {
      print LOG "call: $env /home/justa/dev/cregit/tokenizeByBlobId/tokenBySha.pl /home/justa/dev/kubernetes_original/$blobFN\n" if $debugLog;
      print LOG "filenames: file=$file, outfile=$outfile, final=$filename\n" if $debugLog;
      print LOG "start: $tokenizeCmd $langOp $file\n" if $debugLog;
  }
  if (!open(PROC, "$tokenizeCmd $langOp $file |")) {
    print LOG "OPEN_PROC\n" if $debugLog;
    die "unable to execute $tokenizeCmd (verify variable BFG_TOKENIZE_CMD) [$tokenizeCmd]";
  }
  print LOG "end: $tokenizeCmd $langOp $file\n" if $debugLog;

  while (<PROC>) {
      print $_;
      print $fout $_;
  }
  close PROC;
  close $fout;
  if (not -d $dir) {
      make_path($dir);
  }

  move( $outfile, $filename) or die "The move operation to memoized directory failed: $!";

  # print LOG "$tokenizeCmd $langOp $file --> $filename\n" if $debugLog;
  unlink($file)

}
