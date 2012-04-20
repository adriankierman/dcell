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
    versions.value
  end
end

class QuorumVersionSet
  attr_reader :sources, :counts, :value
  def initialize(msgs)
    @sources=values_by_source(msgs)
    @value=majority()
    apply_version_stamp(@value)
  end

  def majority
    majority=nil
    majority_count=-1
    @counts={}
    @sources.each_pair { |k, v|
      majority=k if (v.count>majority_count)
      @counts[k]=v.count
    }
    majority
  end

  def values_by_source(msgs)
    sources={}
    msgs.each { |msg|
      if (sources.has_key?(msg.value))
        sources[msg.value].push(msg.from_mailbox)
      else
        sources[msg.value]=[msg.from_mailbox]
      end
    }
    sources
  end

  def apply_version_stamp(obj)
      obj.class.instance_eval("attr_accessor :dcell_versions") if !obj.respond_to?(:dcell_versions)
      obj.dcell_versions=self
      obj
  end
end

