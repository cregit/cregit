#!/usr/bin/env ruby

require 'yaml'
require 'json'
require 'optparse'

VERSION = '1.0.0'


def panic(rcode, msg, e)
  STDERR.puts msg
  STDERR.puts(e) if e
  exit(rcode)
end

def begin_syntax(line)
  idx = line.index(/[^\s-]/)
  (idx && idx > 0) ? line[0..idx-1] : ''
end

def sanitize_comment(comment)
  comment.gsub(/[^a-z\d\w\s_]/i, '').strip
end

def sanitize_line(line)
  # line.gsub(/['"\\\s]/, '').strip
  line.gsub(/['"\\]/, '').strip
end

$is_json = false

def load_with_comments(yf)
  verbose = false
  begin
    y = YAML.load(yf)
  rescue Exception => e
    #puts yf
    #puts e
    #return [y, [yf, e]]
    raise e
  end
  ys = y.to_yaml

  flines = yf.split(/\n/).reject { |l| ['---', '...'].include?(l[0..2]) }
  ylines = ys.split(/\n/).reject { |l| ['---', '...'].include?(l[0..2]) }

  # STDERR.puts "flines:"
  # STDERR.puts flines.join("\n")
  # STDERR.puts "ylines:"
  # STDERR.puts ylines.join("\n")

  fi = 0
  c = 0
  failed = false
  olines = []
  comm = '__comment__'
  last_yline = ''
  msgsi = []
  msgso = []
  maxyidx = ylines.length - 1
  maxfidx = flines.length - 1
  yskip = false
  broken = false
  ylines.each_with_index do |yline, yidx|
    break if broken
    if yskip
      yskip = false
      next
    end
    while true
      last_yline = yline
      fline = flines[fi]
      unless fline
        msgsi << "Panic - out of sync and end of file reached" if verbose
        failed = true
        olines = ylines
        broken = true
        break
      end
      fline2 = sanitize_line(fline)
      yline2 = sanitize_line(yline)
      msgsi << "'#{yline}' <=> '#{fline}' --> #{fline == yline} (#{yline.length}, #{fline.length})" if verbose
      msgso << "'#{yline2}' <=> '#{fline2}' --> #{fline2 == yline2}, #{fline2.index(yline2)}" if verbose
      if !fline.include?('#') && !yline.include?('#') && !fline2.index(yline2) && !yline2.index(fline2)
        fi += 1
        c += 1
	if olines.last
          cmt = sanitize_comment(fline)
          olines << "#{begin_syntax(olines.last)}#{comm}#{c}: #{cmt}"
	end
        msgso << "Deep problems detected" if verbose
        break
      end
      bro = false
      artificial = []
      while fline2 != '' && fline2 != yline2 && sidx = yline2.index(fline2)
        artificial << sanitize_comment(fline) if artificial.length == 0
        fi += 1
        bro = true
        fline = flines[fi]
	if fline
          fline2 = sanitize_line(fline)
          artificial << sanitize_comment(fline)
          msgso << "Artificial case needed" if verbose
	else
          break
	end
      end
      if bro
        c += 1
        cmt = artificial.join(' ')
        olines << "#{begin_syntax(olines.last)}#{comm}#{c}: #{cmt}"
        break
      end
      if fline2 == yline2
        olines << yline
        fi += 1
        break
      elsif sidx = fline2.index(yline2)
        nline2 = yidx < maxyidx ? sanitize_line(ylines[yidx+1]) : ''
        cline = ''
        if yidx < maxyidx && sidx2 = fline2.index(nline2)
          cline = sanitize_comment(fline2[sidx2+nline2.length..-1])
          yskip = true
        elsif sidx == 0
          # cline = sanitize_comment(fline[yline.length..-1])
          cline = sanitize_comment(fline2[yline2.length..-1])
        else
          msgsi << "Panic in partial match" if verbose
          failed = true
          olines = ylines
          broken = true
          break
        end
        olines << yline
        unless cline == ''
          c += 1
          olines << "#{begin_syntax(yline)}#{comm}#{c}: #{cline}"
        end
        fi += 1
        break
      else
        cline = sanitize_comment(fline)
        unless cline == ''
          c += 1
          olines << "#{begin_syntax(yline)}#{comm}#{c}: #{cline}"
        end
        fi += 1
      end
    end
  end
  fline = flines[fi]
  while fline
    cline = sanitize_comment(fline)
    unless cline == ''
      c += 1
      olines << "#{begin_syntax(olines.last || '')}#{comm}#{c}: #{cline}"
    end
    fi += 1
    fline = flines[fi]
  end

  if failed && verbose
    info = "in:\n" + msgsi.join("\n") + "\n\nout:\n" + msgso.join("\n")
    raise info
  end
  return y if failed

  ydef = olines.join("\n")
  begin
    y2 = YAML.load(ydef)
  rescue Exception => e
    if verbose
      puts ydef
      puts e
      raise e
    end
    return y
  end
  # STDERR.puts y2.to_yaml
  STDERR.puts y2.to_yaml if verbose
  y2
end

class YAMLWithComments
  def self.load(contents)
    load_with_comments(contents)
  end
end

$toi = 0
$pi = 0
$opts = nil

def emit_token(tok, lit = nil, location=true)

  if ($opts.key?(:nums)) 
    $pi += 1
    start = location ? "#{$toi}:#{$pi}\t" : "-:-\t"
  else
    start = ''
  end

  if lit
    lit = lit.to_s.gsub(/\n/, ' ')
    "#{start}#{tok}|#{lit}\n"
  else
    "#{start}#{tok}\n"
  end
end

def split_if_needed(str)
  return [str] unless $opts.key?(:split) and $opts.key?(:split_part_size)
  spl = $opts[:split]
  sps = $opts[:split_part_size]
  sl = str.length
  return [str] unless sl > spl
  stra = str.split(' ')
  s = []
  res = []
  ps = spl
  stra.each do |word|
    tmp = s + [word]
    #STDERR.puts "word: #{word} --> tmp: #{tmp.to_s}, join_len: #{tmp.join(' ').length}"
    if tmp.join(' ').length <= ps
      s << word
      #STDERR.puts "added word: #{word}, s: #{s.to_s}"
    else
      res << s.join(' ') if s.length > 0
      s = [word]
      ps = sps
      #STDERR.puts "Added phrase: res: #{res.to_s}, s: #{s.to_s}"
    end
  end
  if s.length > 0
    res << s.join(' ')
    #STDERR.puts "Added final: res: #{res.to_s}, s: #{s.to_s}"
  end
  #STDERR.puts [stra, str, res, s].map(&:to_s)
  #STDERR.puts res.to_s
  res
end

def traverse_object(repr, o, oname = nil)
  $toi += 1
  $pi = 0
  is_comment = oname && oname.to_s[0..10] == '__comment__'
  repr += emit_token('TYPE', o.class) unless is_comment
  case o
  when Hash
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token('SYNTAX', '{') if $is_json
    l = o.count - 1
    o.keys.each_with_index do |k, i|
      kis_comment = k && k.to_s[0..10] == '__comment__'
      v = o[k]
      repr += emit_token('KEY', k) unless kis_comment
      opi = $pi
      repr = traverse_object(repr, v, k)
      $pi = opi
      repr += emit_token('SYNTAX', ',') if $is_json && i < l
    end
    repr += emit_token('SYNTAX', '}') if $is_json
  when Array
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token('SYNTAX', '[') if $is_json
    l = o.count - 1
    o.each_with_index do |r, i|
      repr += emit_token('INDEX', i)
      opi = $pi
      repr = traverse_object(repr, r)
      $pi = opi
      repr += emit_token('SYNTAX', $is_json ? ',' : '-') if i < l
    end
    repr += emit_token('SYNTAX',']') if $is_json
  when NilClass
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'NULL', 'NULL')
  when TrueClass
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'BOOLEAN', 'TRUE')
  when FalseClass
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'BOOLEAN', 'FALSE')
  when String
    repr += emit_token('IDENT', oname) if oname && !is_comment
    o.split("\n").each do |ol|
      oa = split_if_needed(ol)
      oa.each { |osp| repr += emit_token(is_comment ? 'COMMENT' : 'STRING', osp) }
    end
  when Symbol
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'SYMBOL', o)
  when Fixnum
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'INT', o)
  when Float
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'FLOAT', o)
  when Bignum
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'BIGNUM', o)
  when Time
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'TIME', o)
  when Date
    repr += emit_token('IDENT', oname) if oname && !is_comment
    repr += emit_token(is_comment ? 'COMMENT' : 'DATE', o)
  else
    panic(4, "Unknown class #{o.class}", nil)
  end
  repr
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("-j", "--json", "Input is JSON") do |v|
    options[:json] = true
  end
  opts.on("-y", "--yaml", "Input is YAML") do |v|
    options[:yaml] = true
  end
  opts.on("-n", "--numbers", "Output parsing numbers") do |v|
    options[:nums] = true
  end
  opts.on("-s N", "--split N", Integer, "Split strings longer than N") do |n|
    options[:split] = n
  end
  opts.on("-p N", "--part-size N", Integer, "Split string part size P for strings longer than N") do |p|
    options[:split_part_size] = p
  end
end.parse!

parser = nil
parser = JSON if options.key?(:json)
parser = YAMLWithComments if options.key?(:yaml)
panic(1, 'No parser defined', nil) unless parser
$is_json = true if options.key?(:json)

in_data = STDIN.read
if options.key?(:yaml)
  in_data.gsub!('{{', '<<')
  in_data.gsub!('}}', '>>')
end
parse_error = 0
multi_json = false

while true
  data = ''
  begin
    # STDERR.puts "PARSE: error=#{parse_error}, len=#{in_data.length}"
    data = parser.load(in_data)
# =begin
  rescue Exception => e
    # STDERR.puts e
    if options.key?(:yaml)
      if parse_error == 0
        in_data.gsub!('{%', '<%')
        in_data.gsub!('%}', '%>')
      elsif parse_error == 1
        in_data.gsub!(/<%.*%>/, '')
      elsif parse_error == 2
        in_data.gsub!(/\${.*}/, '')
      elsif parse_error == 3
        in_data.gsub!(/\$(.*)/, '')
      elsif parse_error == 4
        in_data.gsub!(/<<.*>>/, '')
        #STDERR.puts in_data
      else
        panic(2, "YAML Parse error", e)
      end
    elsif options.key?(:json)
      if parse_error == 0
        in_data = '[' + in_data.gsub("}\n{", "},{") + ']'
        multi_json = true
      else
        panic(2, "JSON Parse error", e)
      end
    else
       panic(3, "Unknown language #{options.to_s}", e)
    end
    parse_error += 1
    next
# =end
  end
  break
end

if multi_json && data.length == 0
  panic(4, "Empty JSON in #{in_data[1..-2]}", nil)
end

$opts = options
repr = emit_token('begin_unit', VERSION, false)

begin
  repr += emit_token('FILETYPE', 'json', false) if options.key?(:json)
  repr += emit_token('FILETYPE', 'yaml', false) if options.key?(:yaml)
  repr += emit_token('MULTI', 'MULTI', false) if multi_json
  repr = traverse_object(repr, data)
#rescue Exception => e
#  panic(3, "Traverse error", e)
end
repr += emit_token('end_unit', nil, false)


puts repr
