# A chorus of actors all execute the same method in the script when action is called
# The supplied block is run with the response from each actor that is in the chorus
class Chorus
  def initialize(actors_array,minimum_for_quorum=2,timeout=2)
    @all=actors_array
    @minimum_for_quorum=minimum_for_quorum
    @timeout=timeout
  end

  def method_missing(meth, *args, &block)
    action(meth, *args, &block)
  end

  def action(meth, *args, &block)
    msgs=Celluloid.multicall(@all, @minimum_for_quorum, @timeout) do |actors|
      actors.each {|actor|
        actor.method_missing(meth.to_s,*args)
      }
      handler_for_each_response(meth,*args, &block)
    end
    msgs
  end

  def handler_for_each_response(meth,*args, &block)
    lambda{|peer_response|
      if block
        block.call(peer_response)
      end
    }
  end
end