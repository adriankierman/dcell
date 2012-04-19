class Quorum < Chorus

  def initialize(actors_array,minimum_for_quorum=nil,timeout=2)
    minimum_for_quorum=actors_array.count if minimum_for_quorum.nil?
    super(actors_array,minimum_for_quorum,timeout)


  end

  def action(meth, *args, &block)
    msgs=super(meth, *args, &block)
    deconflict(msgs)
  end

  def deconflict(msgs)
    QuorumVersionSet.new(msgs)
  end



end

class QuorumVersionSet
  attr_reader :sources, :counts, :value
  def initialize(msgs)
    @sources={}
    msgs.each{|msg|
      if (@sources.has_key?(msg.value))
        @sources[msg.value].push(msg.from_mailbox)
      else
        @sources[msg.value]=[msg.from_mailbox]
      end
    }
    majority=nil
    majority_count=-1
    @counts=sources.map {|k,v|
      majority=k if (v.count>majority_count)
      [k,v.count]
    }
    @value=majority
  end
end

