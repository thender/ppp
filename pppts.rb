require "fileutils"
require "thread"

@server_mode=true
@threads=8

def pppts_fail(msg=nil,cmd=nil)
  s="\nFAIL"
  s+=": #{cmd}\n" if cmd
  msg.split("\n").each { |e| s+="      #{e}\n" } if msg
  puts s
  if @server_mode and @srvr.alive?
    @srvr.raise(Interrupt)
  else
    exit(1)
  end
end

def pppts_docmd(cmd)
  out=IO.popen(cmd+" 2>&1") { |e| e.readlines.reduce("") { |s,e| s+=e } }
  [($?.exitstatus==0)?(true):(false),out]
end

def pppts_exe(bin)
  cmd=bin
  stat,out=pppts_docmd(cmd)
  pppts_fail(out,cmd) unless stat
  out
end

def pppts_run(q,socket)
  pppts_test(q.deq,socket) until q.empty?
end

def pppts_start_server
  socket=File.expand_path("./socket.#{$$}")
  clear_socket(socket)
  s=Thread.new { server(socket,true) }
  sleep 1 until File.exist?(socket)
  [s,socket]
end

def pppts_test(t,socket)
  print "."
  pppts_exe("make -C #{t} clean")
  x=(socket)?(" SOCKET=#{socket} "):(" ")
  pppts_exe("make -C #{t}#{x}exe")
  e="./a.out"
  stdout=((File.exist?(File.join(t,e)))?(pppts_exe("cd #{t} && #{e}")):(""))
  f=File.join(t,"control")
  if File.exist?(f)
    control=File.open(f,"rb").read
    unless stdout==control
      msg="#{t} output expected:\n--begin--\n"
      msg+=control
      msg+="-- end --\n#{t} output actual:\n--begin--\n"
      msg+=stdout
      msg+="-- end --"
      pppts_fail(msg)
    end
  end
  pppts_exe("make -C #{t} clean")
end

pppts_fail("Need at least one thread to run tests") unless @threads>0
pppts_exe("make")
load File.join(File.dirname($0),"common.rb")
@srvr,socket=(@server_mode)?(pppts_start_server):(nil)
tdir="tests"
tests=(ARGV[0])?(["#{tdir}/#{ARGV[0]}"]):(Dir.glob("#{tdir}/t*").sort)
q=Queue.new
tests.each { |e| q.enq(e) }
(1..@threads).reduce([]) { |m,e| m << Thread.new { pppts_run(q,socket) } }.each { |e| e.join }
puts "\nOK (#{tests.size} tests)"
@srvr.raise(Interrupt) if @server_mode

# paul.a.madden@noaa.gov