module Translator

  require "fileutils"
  require "ostruct"
  require "pathname"
  require "socket"
  require "yaml"

  include Fortran

  @@fp=nil       # fortran parser
  @@np=nil       # normalize parser
  @@server=false # operating in server mode?

  def clear_socket(socket)
    FileUtils.rm_f(socket)
    fail "Socket file #{socket} in use, please free it" if File.exist?(socket)
  end

  def default_props
    {
      :debug=>false,
      :incdirs=>[],
      :nl=>true,
      :normalize=>false,
      :srcfile=>nil,
      :translate=>true
    }
  end
  
  def directive
    unless @directive
      f=File.join(File.dirname(File.expand_path($0)),"sentinels")
      d=File.open(f,"rb").read.gsub(/\$/,'\$').split("\n").join("|")
      @directive=Regexp.new("^\s*!((#{d}).*)",true)
    end
    @directive
  end

  def fail(msg)
    s="#{msg}"
    s+=": #{@@src}" if @@server
    puts s
    exit(1) unless @@server
  end

  def go
    fail usage unless srcfile=ARGV.pop
    srcfile=File.expand_path(srcfile)
    fail "Cannot read file: #{srcfile}" unless File.readable?(srcfile)
    s=File.open(srcfile,"rb").read
    props={:srcfile=>srcfile}
    props=unpack(props,ARGV)
    @@fp.setup(srcfile)
    puts out(s,:program_units,props)
  end

  def normalize(s,newline)
    @@np||=NormfreeParser.new
    s=s.gsub(directive,'@\1')             # hide directives
    s=s.gsub(/^\s+/,"")                   # remove leading whitespace
    s=s.gsub(/[ \t]+$/,"")                # remove trailing whitespace
    s=s.gsub(/^!.*\n/,"")                 # remove full-line comments
    s=@@np.parse(@@np.parse(s).to_s).to_s # two normalize passes
    s=s.sub(/^\n+/,"")                    # remove leading newlines
    s+="\n" if s[-1]!="\n" and newline    # ensure final newline
    s=s.gsub(/^@(.*)/i,'!\1')             # show directives
  end

  def out(s,root=:program_units,override={})
    props=default_props.merge(override)
    translated_source,raw_tree,translated_tree=process(s,root,props)
    translated_source
  end

  def process(s,root=:program_units,override={})

    def assemble(s,seen,incdirs=[])
      current=seen.last
      a=""
      r=Regexp.new("^\s*include\s*(\'[^\']+\'|\"[^\"]+\").*",true)
      s.split("\n").each do |line|
        m=r.match(line)
        if m
          incfile=m[1][1..-2]
          if incfile[0]=="/" or incfile[0]=="."
            incfile=File.expand_path(File.join(File.dirname(current),incfile))
            unless File.exist?(incfile)
              fail "Could not find included file #{incfile}"
            end
          else
            found=false
            incdirs.each do |d|
              maybe=File.expand_path(File.join(d,incfile))
              if File.exist?(maybe)
                found=true
                incfile=maybe
                break
              end
            end
            unless found
              fail "Could not find included file #{incfile} on search path"
            end
          end
          if seen.include?(incfile)
            msg="File #{current} includes #{incfile} recursively:\n"
            msg+=incchain(seen,incfile)
            fail msg
          end
          unless File.readable?(incfile)
            msg="Could not read file #{incfile} "
            msg+=incchain(seen,incfile)
            fail msg
          end
          a+=assemble(File.open(incfile,"rb").read,seen+[incfile],incdirs)
        else
          a+="#{line}\n"
        end
      end
      a
    end

    def cppcheck(s)
      r=Regexp.new("^\s*#")
      i=1
      s.split("\n").each do |line|
        m=r.match(line)
        fail "Detected cpp directive:\n\n#{i}: #{line.strip}" if m
        i+=1
      end
    end

    def incchain(seen,incfile)
      "\n  "+(seen+[incfile]).join(" includes\n  ")
    end

    def wrap(s)

      def directive?(s)
        s=~directive
      end

      max=132
      a=s.split("\n")
      (0..a.length-1).each do |n|
        e=a[n].chomp
        unless directive?(e)
          if e.length>max
            e=~/^( *).*$/
            i=$1.length+2
            t=""
            begin
              r=[max-2,e.length-1].min
              t+=e[0..r]+"&\n"
              e=" "*i+"&"+e[r+1..-1]
            end while e.length>max
            t+=e
            a[n]=t
          end
        end
      end
      a.join("\n")
    end

    props=default_props.merge(override)
    debug=props[:debug]
    @@fp||=FortranParser.new
    s=prepsrc(s) if defined? prepsrc
    s=assemble(s,[props[:srcfile]],props[:incdirs])
    cppcheck(s)
    puts "RAW SOURCE\n\n#{s}\n" if debug
    puts "NORMALIZED SOURCE\n\n" if debug
    s=normalize(s,props[:nl])
    unless props[:normalize]
      puts s if debug
      @@incdirs=props[:incdirs]
      raw_tree=@@fp.parse(s,:root=>root)
      raw_tree=raw_tree.post if raw_tree # post-process raw tree
      if debug
        puts "\nRAW TREE\n\n"
        p raw_tree
      end
      re=Regexp.new("^(.+?):in `([^\']*)'$")
      srcmsg=(re.match(caller[0])[2]=="raw")?(": See #{caller[1]}"):("")
      unless raw_tree
        fail "PARSE FAILED#{srcmsg}"
        return # if in server mode and did not exit in fail()
      end
      translated_tree=(props[:translate])?(raw_tree.translate):(nil)
      if debug
        puts "\nTRANSLATED TREE\n\n"
        p translated_tree
      end
      s=wrap(translated_tree.to_s)
      puts "\nTRANSLATED SOURCE\n\n" if debug
    end
    [s,raw_tree,translated_tree]
  end

  def raw(s,root=:program_units,override={})
    props=default_props.merge(override)
    props[:translate]=false
    translated_source,raw_tree,translated_tree=process(s,root,props)
    raw_tree
  end

  def server(socket,quiet=false)
    @@server=true
    clear_socket(socket)
    trap('INT') { raise Interrupt }
    begin
      UNIXServer.open(socket) do |server|
        while true
          props={}
          client=server.accept
          message=client.read.split("\n")
          @@src=message.shift
          fail "No such file: #{@@src}" unless File.exist?(@@src)
          props[:srcfile]=@@src
          dirlist=message.shift
          srcdir=File.dirname(File.expand_path(@@src))
          props[:incdirs]=[srcdir]
          dirlist.split(":").each do |d|
            d=File.join(srcdir,d) if Pathname.new(d).relative?
            fail "No such directory: #{d}" unless File.directory?(d)
            props[:incdirs].push(d)
          end
          s=message.join("\n")
          @@fp.setup(@@src)
          puts "Translating #{@@src}" unless quiet
          client.puts(out(s,:program_units,props))
          client.close
        end
      end
    rescue Interrupt=>ex
      FileUtils.rm_f(socket)
      exit(0)
    rescue Exception=>ex
      s="#{ex.message}\n"
      s+=ex.backtrace.reduce(s) { |m,x| m+="#{x}\n" }
      fail s
      FileUtils.rm_f(socket)
      exit(1)
    end
  end

  def tree(s,root=:program_units,override={})
    props=default_props.merge(override)
    translated_source,raw_tree,translated_tree=process(s,root,props)
    translated_tree
  end

  def unpack(props,args)
    props[:incdirs]=["."]
    args.reverse!
    while opt=args.pop
      case opt
      when "-I"
        dirlist=args.pop
        fail usage unless dirlist
        dirlist.split(":").each do |d|
          fail "No such directory: #{d}" unless File.directory?(d)
          props[:incdirs].push(d)
        end
      when "normalize"
        props[:normalize]=true
      when "debug"
        props[:debug]=true
      else
        fail usage
      end
    end
    props
  end

  def usage
    f=File.basename(__FILE__)
    "usage: #{f} [-I dir[:dir:...]] source"
  end

end

# paul.a.madden@noaa.gov
