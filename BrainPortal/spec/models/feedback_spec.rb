#
# CBRAIN Project
#
# Feedback spec
#
# Original author: Natacha Beck
#
# $Id$
#


require 'spec/spec_helper'

describe Feedback do
  before(:each) do 
    #objects required in tests below
    @feedback = Factory.build(:feedback)
    @feedback.save
  end

  it "should create a new instance given valid attributes" do
    @feedback.valid?.should be(true)
  end
  
  it { should belong_to(:user) }

  it "should not save without a summary" do
    @feedback.summary = nil
    @feedback.save.should be(false) 
  end
  
  it "should not save without a details" do
    @feedback.details = nil
    @feedback.save.should be(false) 
  end

  it "should not save without a blank summary" do
    @feedback.summary = ""
    @feedback.save.should be(false) 
  end
  
  it "should not save without a blank details" do
    @feedback.details = ""
    @feedback.save.should be(false) 
  end
  
end
