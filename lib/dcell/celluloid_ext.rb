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
    def multicall(actors, response_count, timeout, meth, *args, &block)
      responses=[]
      uuid = Celluloid.uuid
      actors.each { |actor|
        Actor.multicall actor.mailbox, uuid, meth, *args, &block
      }
      receive_multiple_responses(response_count, responses, timeout, uuid)
      responses
    end

    def receive_multiple_responses(response_count, responses, timeout, uuid)
      while should_wait_for_response(response_count)
        receive(timeout) do |msg|
          if message_is_valid(msg, uuid)
            responses.push(msg)
            response_count -= 1
          end
        end
      end
    end

    def message_is_valid(msg, uuid)
      msg.respond_to?(:uuid) and msg.uuid == uuid
    end

    def should_wait_for_response(response_count)
      (response_count > 0)
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
    attr_reader :uuid, :value, :from_mailbox
    attr_accessor :vector

    def initialize(uuid, value, from_mailbox)
      @uuid, @value, @from_mailbox = uuid, value, from_mailbox
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
        @caller << MultiResponse.new(@uuid, result, _registration_name(obj))
      rescue MailboxError
        # It's possible the caller exited or crashed before we could send a
        # response to them.
      end
    end

    def _registration_name(obj)
          "#{Thread.mailbox.address}@#{DCell.id}@#{DCell.addr}"
    end
  end

  class Mailbox
    attr_reader :dcell_mailbox_id
    # This custom dumper registers actors with the DCell registry so they can
    # be reached remotely.
    def _dump(level)
      @dcell_mailbox_id = DCell::Router.register self
      "#{@dcell_mailbox_id}@#{DCell.id}@#{DCell.addr}"
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


