require 'spec_helper'
require 'pp'
describe Quorum do
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

  it "creates a Quorum" do
    secondary_actor = @node[:secondary_test_actor]
    actor = @node[:test_actor]
    c=Quorum.new([actor,secondary_actor])
    c.should_not be_nil
  end

  it "replies once for each value in the Quorum" do
      secondary_actor = @node[:secondary_test_actor]
      secondary_actor.value=43

      actor = @node[:test_actor]
      q=Quorum.new([actor,secondary_actor])

      response=q.value
      [42,43].should include(response.value)
      response.counts.values.should eql([1,1])
    end
end
