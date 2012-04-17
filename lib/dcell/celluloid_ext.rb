# Celluloid mailboxes are the universal message exchange points. You won't
# be able to marshal them though, unfortunately, because they contain
# mutexes.
#
# DCell provides a message routing layer between nodes that can direct
# messages back to local mailboxes. To accomplish this, DCell adds custom
# marshalling to mailboxes so that if they're unserialized on a remote
# node you instead get a proxy object that routes messages through the
# DCell overlay network back to the node where the actor actually exists
#
# Multi-call functionality from jhosteny gist on the subject https://gist.github.com/2354274


module Celluloid
  class << self
    def multicall(actors, responses, timeout, &block)
      r=[]
      uuid = Celluloid.uuid
      actors.each do |actor|
        class << actor
          alias_method :old_method_missing, :method_missing
        end
        actor.instance_eval %Q{
          def method_missing(meth, *args, &block)
            meth = meth.to_s
            raise RuntimeError, "can't call async method with multicall" if meth.to_s.match(/!$/)
            Actor.multicall @mailbox, \"#{uuid}\", meth, *args, &block
          end
        }
      end
      begin
        response = yield actors
      ensure
        actors.each do |actor|
          class << actor
            alias_method :method_missing, :old_method_missing
          end
        end
      end
      response = nil unless response.is_a? Proc
      if actor? and not timeout
        responses.times do
          value = Task.suspend(:callwait).value
          response.call(value) if response
        end
      else
        receive(timeout) do |msg|
          if msg.respond_to?(:uuid) and msg.uuid == uuid
            if response
              response.call(msg.value)
              r.push(msg)
            end
            responses -= 1
            responses > 0 ? false : true
          else
            false
          end
        end
      end
      r
    end
  end

  class ActorProxy
    # Marshal uses respond_to? to determine if this object supports _dump so
    # unfortunately we have to monkeypatch in _dump support as the proxy
    # itself normally jacks respond_to? and proxies to the actor
    alias_method :__respond_to?, :respond_to?
    def respond_to?(meth)
      return false if meth == :marshal_dump
      return true  if meth == :_dump
      __respond_to? meth
    end

    # Dump an actor proxy via its mailbox
    def _dump(level)
      @mailbox._dump(level)
    end

    # Create an actor proxy object which routes messages over DCell's overlay
    # network and back to the original mailbox
    def self._load(string)
      mailbox = Celluloid::Mailbox._load(string)

      case mailbox
      when DCell::MailboxProxy
        DCell::ActorProxy.new mailbox
      when Celluloid::Mailbox
        Celluloid::ActorProxy.new(mailbox)
      else raise "funny, I did not expect to see a #{mailbox.class} here"
      end
    end
  end

  class Actor
    class << self
      # Invoke a method on the given actor via its mailbox
      def multicall(mailbox, uuid, meth, *args, &block)
        call = MultiCall.new(Thread.mailbox, uuid, meth, args, block)
        begin
          mailbox << call
        rescue MailboxError
          raise DeadActorError, "attempted to call a dead actor"
        end
      end
    end
  end

  # Don't derive from Response, since that gets handled
  # automatically by the reactor.
  class MultiResponse
    attr_reader :uuid, :value

    def initialize(uuid, value)
      @uuid, @value = uuid, value
    end
  end

  # Multi calls wait for N responses with an optional timeout
  class MultiCall < Call
    attr_reader :task
    attr_reader :uuid

    def initialize(caller, uuid, method, arguments = [], block = nil, task = Fiber.current.task)
      super(caller, method, arguments, block)
      @uuid = uuid
      @task = task
    end

    def dispatch(obj)
      begin
        check_signature(obj)
      rescue => ex
        Logger.crash("#{obj.class}: multi call failed!", ex)
        return
      end

      begin
        result = obj.send @method, *@arguments, &@block
      rescue AbortError => ex
        # Swallow aborted async calls, as they indicate the caller made a mistake
        Logger.crash("#{obj.class}: async call aborted!", ex)
      end
      begin
        @caller << MultiResponse.new(@uuid, result)
      rescue MailboxError
        # It's possible the caller exited or crashed before we could send a
        # response to them.
      end
    end
  end

  class Mailbox
    # This custom dumper registers actors with the DCell registry so they can
    # be reached remotely.
    def _dump(level)
      mailbox_id = DCell::Router.register self
      "#{mailbox_id}@#{DCell.id}@#{DCell.addr}"
    end

    # Create a mailbox proxy object which routes messages over DCell's overlay
    # network and back to the original mailbox
    def self._load(string)
      DCell::MailboxProxy._load(string)
    end
  end

  class SyncCall
    def _dump(level)
      uuid = DCell::RPC::Manager.register self
      payload = Marshal.dump([@caller,@method,@arguments,@block])
      "#{uuid}@#{DCell.id}:#{payload}"
    end

    def self._load(string)
      DCell::RPC._load(string)
    end
  end
end


