#!/usr/bin/env ruby

require 'yaml'
require 'json'

def panic(why)
  STDERR.puts why
  exit 1
end

# Debugging output
$verbose = false
# $verbose = true
# $quiet = false
$quiet = true

$multi = false
$prev_ends = 0

def get_max_pos(len)
  $prev_ends.to_f * 1.02 + 2 * len + 10
end

def lookup_token(ft, tp, val, buf, bufdc, pos)
  tp = tp.downcase
  STDERR.puts [tp, val] unless val[0] == '"' || $quiet
  val = val[1..-2]

  skip_types = []
  exact_types = []
  dc_types = []
  case ft
  when 'y'
    skip_types = %w(type index syntax filetype)
    exact_types = %w(comment ident key string symbol int bignum)
    dc_types = %w(float date time)
  when 'j'
    skip_types = %w(type index filetype)
    exact_types = %w(ident syntax key string symbol int bignum)
    dc_types = %w(float date time)
  else
    panic("Unknown token file type: #{ft}")
  end

  case tp
  when *skip_types
  when *exact_types
    npos = buf.index(val, pos)
    if tp == 'int' && !npos
      vals = [
        '0' + val.to_i.to_s(010),
        '0x' + val.to_i.to_s(0x10),
        '0X' + val.to_i.to_s(0X10),
        val.to_i.to_s(10)
      ]
      npos = {}
      vals.each do |v|
        npos[v] = buf.index(v, pos)
      end
      minv = npos.keys.compact.first
      minp = npos.values.compact.first
      npos.each do |iv, pv|
        next unless pv && pv < minp
        minp = pv
        minv = iv
      end
      npos = minp
      if npos
        max_possible = get_max_pos(minv.length)
        if npos > max_possible
          STDERR.puts "set_pos_int: #{npos} tp: #{tp} val: '#{val}' prev_ends: #{$prev_ends}, max_possible: #{max_possible}, err_rate: #{npos.to_f / max_possible}" if $verbose
	else
          pos = npos
          $prev_ends = pos + minv.to_s.length + 1
          STDERR.puts "int: #{tp}: #{val}/#{minv}/equivalent found at #{npos} starting at #{pos}" if $verbose
          STDERR.puts "prev_ends: #{$prev_ends}" if $verbose
	end
      else
        STDERR.puts "int: #{tp}: '#{val}' not found starting at #{pos}" unless npos || $quiet
      end
    end
    if !npos
      val = val.gsub(/'/, "''")
      npos = buf.index(val, pos)
    end
    if !npos
      val = val.gsub(/"/, '\"')
      npos = buf.index(val, pos)
    end
    if npos
      max_possible = get_max_pos(val.length)
      if npos > max_possible
        STDERR.puts "set_pos: #{npos} tp: #{tp} val: '#{val}' prev_ends: #{$prev_ends}, max_possible: #{max_possible}, err_rate: #{npos.to_f / max_possible}" if $verbose
      else
        pos = npos
        STDERR.puts "full: #{tp}: #{val} found at #{npos} starting at #{pos}" if $verbose
        $prev_ends = pos + val.length + 1
        STDERR.puts "prev_ends: #{$prev_ends}" if $verbose
      end
    else
      oldpos = pos
      max_pos = $prev_ends + val.length
      STDERR.puts "#{tp}: '#{val}' not found starting at #{pos}, max_pos=#{max_pos}" if $verbose
      nposs = []
      val.split.each do |word|
        npos = buf.index(word, pos)
        if npos
          STDERR.puts "word: #{tp}: #{word} found at #{npos} starting at #{pos}" if $verbose
          nposs << npos
        else
          nwords = word.split(/[^a-zA-Z0-9_ ]/).reject { |s| s == '' }
          nwords.each do |w|
            STDERR.puts "'#{val}' --> '#{word}' --> '#{w}', pos=#{pos}" if $verbose
            npos = buf.index(w, pos)
            if npos
              STDERR.puts "problematic #{tp}: #{word} found at #{npos} starting at #{pos}" if $verbose
              nposs << npos
            else
              STDERR.puts "splitted word: #{tp}: '#{w}'/'#{word}/'#{val}' not found starting at #{pos}" if $verbose
            end
          end
        end
      end
      STDERR.puts "max_pos: #{max_pos} ary: #{nposs.to_s}" if $verbose
      oks = nposs.select { |p| p >= $prev_ends && p <= max_pos }
      # oks = nposs.select { |p| p <= max_pos }
      minp = oks.min
      STDERR.puts "oks: #{oks.to_s}, min: #{minp}" if $verbose
      if oks.length > 0 && nposs.all?
         pos = minp
         $prev_ends = pos + val.length + 1
         STDERR.puts "prev_ends: #{$prev_ends}" if $verbose
      end
      if pos == oldpos
        STDERR.puts "VERY BAD: #{tp}: '#{val}' not found starting at #{pos}, min_pos: #{$prev_ends}, max_pos: #{max_pos}, min: #{minp}, nposs: #{nposs.to_s}, oks: #{oks.to_s}" unless $quiet
        # panic "bye bye cruel world!"
      end
    end
  when *dc_types
    valdc = val.downcase
    valdc = valdc.split(' ').first if tp == 'time'
    npos = bufdc.index(valdc, pos)
    if npos
      max_possible = get_max_pos(valdc.length)
      if npos > max_possible
        STDERR.puts "set_pos_dc: #{npos} tp: #{tp} val: '#{val}' prev_ends: #{$prev_ends}, max_possible: #{max_possible}, err_rate: #{npos.to_f / max_possible}" if $verbose
      else
        pos = npos
        $prev_ends = pos + valdc.length + 1
        STDERR.puts "dc: #{tp}: #{val}/#{valdc} found at #{npos} starting at #{pos}" if $verbose
        STDERR.puts "prev_ends: #{$prev_ends}" if $verbose
      end
    else
      STDERR.puts "#{tp}: '#{valdc}' not found starting at #{pos}" unless npos || $quiet
    end
  when 'boolean'
    valdc = val.downcase
    vals = %w(off no false disabled) if valdc == 'false'
    vals = %w(on yes true enabled) if valdc == 'true'
    npos = {}
    vals.each do |v|
      npos[v] = bufdc.index(v, pos)
    end
    minv = npos.keys.compact.first
    minp = npos.values.compact.first
    npos.each do |iv, pv|
      next unless pv && pv < minp
      minp = pv
      minv = iv
    end
    npos = minp
    # npos = npos.values.compact.min
    if npos
      max_possible = get_max_pos(minv.length)
      if npos > max_possible
        STDERR.puts "set_pos_bool: #{npos} tp: #{tp} val: '#{val}' prev_ends: #{$prev_ends}, max_possible: #{max_possible}, err_rate: #{npos.to_f / max_possible}" if $verbose
      else
        pos = npos
        $prev_ends = pos + minv.to_s.length + 1
        STDERR.puts "boolean: #{tp}: #{valdc}/#{minv}/equivalent found at #{npos} starting at #{pos}" if $verbose
        STDERR.puts "prev_ends: #{$prev_ends}" if $verbose
      end
    else
      STDERR.puts "boolean: #{tp}: '#{valdc}' not found starting at #{pos}" unless npos || $quiet
    end
  when 'multi'
    $multi = true
  end
  pos
end

def rlocalize(args)
  ftype = args[0][0]
  ftoken = args[1]
  forig = args[2]
  pos = (args[3] || 0).to_i
  buf = File.read(forig)
  if ftype == 'y'
    buf.gsub!('{{', '<<')
    buf.gsub!('}}', '>>')
  end
  bufdc = buf.downcase
  types = %w(BIGNUM BOOLEAN DATE FILETYPE FLOAT IDENT INDEX INT KEY MULTI NULL STRING SYMBOL SYNTAX TIME TYPE)
  types << 'COMMENT' if ftype == 'y'
  converted = false
  localized = false
  lines = []
  File.readlines(ftoken).each do |line|
    ta = line.strip.split('|')
    ttype = ta[0]
    tvalue = ta[1]
    localized = true if ta.length >= 3 && ta.last.to_i.to_s == ta.last
    panic("Unknown token type: #{ttype}") unless types.include?(ttype)
    pos = lookup_token(ftype, ttype, tvalue, buf, bufdc, pos)
    if ftype == 'j' && $multi && !converted
      buf = '[' + buf.gsub("}\n{", "},{") + ']'
      converted = true
    end
    apos = $multi ? pos - 1 : pos
    STDERR.puts "Type: #{ttype}, Value: '#{tvalue}' --> #{pos}" if $verbose
    lines << "#{line.strip}|#{apos}"
  end
  File.write(ftoken, lines.join("\n")+"\n") unless localized
  #puts lines.join("\n")
end

if ARGV.size < 2
  puts "Missing arguments: [yaml|json] file.token file.orig [start_pos]"
  exit(1)
end

rlocalize(ARGV)
