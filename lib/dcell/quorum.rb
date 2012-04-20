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
    versions=QuorumVersionSet.new(msgs)
    # many people prefer to just get a value back from the distributed method call - make a best effort to do this
    # probably more convention over configuration this way
    value=versions.value
    make_versioned(value, versions)
    value
  end

  def make_versioned(value, versions)
    value.class.instance_eval("attr_accessor :dcell_versions") if !value.respond_to?(:dcell_versions)
    value.dcell_versions=versions
    value
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
    @counts={}
    @sources.each_pair {|k,v|
      majority=k if (v.count>majority_count)
      @counts[k]=v.count
    }
    @value=majority
  end
end

