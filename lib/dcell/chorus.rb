# A chorus of actors all execute the same method in the script when action is called
# The supplied block is run with the response from each actor that is in the chorus
#
# This means that you can call methods on the chorus of actors in almost the same way
# as you would call methods on a single chorus member.
#
# chorus=Chorus.new([kit1[:librarian],kit2[:librarian]])
# chorus.set_greeting("hello")
# chorus.get_greeting {|greeting| pp greeting}
#
class Chorus
  def initialize(actors_array,minimum_for_quorum=2,timeout=2)
    @actors=actors_array
    @minimum_for_quorum=minimum_for_quorum
    @timeout=timeout
  end

  def method_missing(meth, *args, &block)
    action(meth, *args, &block)
  end

  def action(meth, *args, &block)
    msgs=Celluloid.multicall(@actors, @minimum_for_quorum, @timeout,meth.to_s,*args)

    msgs
  end

end