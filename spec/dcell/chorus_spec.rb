require 'spec_helper'
require 'pp'
describe Chorus do
  before do
    @node = DCell::Node['test_node']
    @node.id.should == 'test_node'
  end

  it "finds all available nodes" do
    nodes = DCell::Node.all
    nodes.should include(DCell.me)
  end

  it "finds remote actors" do
    secondary_actor = @node[:secondary_test_actor]
    actor = @node[:test_actor]
    secondary_actor.value.should == 42
    actor.value.should == 42
  end

  it "lists remote actors" do
    @node.actors.should include :test_actor
    @node.actors.should include :secondary_test_actor
    @node.all.should include :test_actor
    @node.all.should include :secondary_test_actor
  end

  it "creates a chorus" do
    secondary_actor = @node[:secondary_test_actor]
    actor = @node[:test_actor]
    c=Chorus.new([actor,secondary_actor])
    c.should_not be_nil
  end

  it "replies once for each actor in the chorus" do
      secondary_actor = @node[:secondary_test_actor]
      secondary_actor.value=43
      actor = @node[:test_actor]
      c=Chorus.new([actor,secondary_actor])

      replies=c.value
      replies[0].should_not ==replies[1]
      pp replies
      replies.count.should == 2
      #replies[0].from_mailbox.should_not ==replies[1].from_mailbox
    end
end
