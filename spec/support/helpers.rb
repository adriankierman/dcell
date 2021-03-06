# For Gem.ruby, and almost certainly already loaded
require 'rubygems'

module TestNode
  PORT = 21264

  def self.start
    @pid = Process.spawn Gem.ruby, File.expand_path("../../test_node.rb", __FILE__)
  end

  def self.wait_until_ready
    STDERR.print "Waiting for test node to start up..."

    socket = nil
    60.times do
      begin
        socket = TCPSocket.open("127.0.0.1", PORT)
        break if socket
      rescue Errno::ECONNREFUSED
        STDERR.print "."
        sleep 2
      end
    end
    sleep 5



    if socket
      STDERR.puts " done!"
      socket.close
    else
      STDERR.puts " FAILED!"
      raise "couldn't connect to test node!"
    end
  end

  def self.stop
    Process.kill 9, @pid
  rescue Errno::ESRCH
  ensure
    Process.wait @pid rescue nil
  end
end
