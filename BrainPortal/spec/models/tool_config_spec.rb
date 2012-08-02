
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.  
#

require 'spec_helper'

describe ToolConfig do
  let(:tool_config) {Factory.create(:tool_config)}

  describe "#can_be_accessed_by?" do
    let(:user) {Factory.create(:admin_user)}
    let(:group) {Factory.create(:group, :users => [user])}
    let(:group_tool_config) {Factory.create(:tool_config, :group => group)}
    let(:no_b_tool_config) {Factory.create(:tool_config, :bourreau => nil)}
    let(:no_t_tool_config) {Factory.create(:tool_config, :tool => nil)}
    
    
    it "should allow admin user to access a tool config even if they don't belong to its group" do
      tool_config.can_be_accessed_by?(user).should be_true
    end
    
    it "should not allow non-admin user to access a tool config if they don't belong to its group" do
      tool_config.can_be_accessed_by?(Factory.create(:normal_user)).should be_false
    end

    it "should not allow user to access a tool config if the bourreau is not set" do
      no_b_tool_config.can_be_accessed_by?(user).should be_false
    end
    
    it "should not allow user to acces a tool config if the tool is not set" do
      no_t_tool_config.can_be_accessed_by?(user).should be_false
    end

    it "should allow non-admin user to access a tool config to which it is" do
      user.reload
      group_tool_config.can_be_accessed_by?(user).should be_true
    end
  end

  describe "#bourreau_and_tool_can_be_accessed_by?" do

    let(:bourreau) { double("bourreau", :can_be_accessed_by? => true) }
    let(:tool)     { double("tool",     :can_be_accessed_by? => true) }
    let(:user)     { double("user") }

    before(:each) do
      tool_config.stub!(:bourreau).and_return(bourreau)
      tool_config.stub!(:tool).and_return(tool)
    end

    it "should return true if both the bourreau and tool are accessible to the user" do
      tool_config.bourreau_and_tool_can_be_accessed_by?(user).should be_true
    end

    it "should return false if the bourreau is unset" do
      tool_config.stub!(:bourreau).and_return(nil)
      tool_config.bourreau_and_tool_can_be_accessed_by?(user).should be_false
    end

    it "should return false if the tool is unset" do
      tool_config.stub!(:tool).and_return(nil)
      tool_config.bourreau_and_tool_can_be_accessed_by?(user).should be_false
    end

    it "should return false if the bourreau is unaccessible" do
      bourreau.stub!(:can_be_accessed_by?).and_return(false)
      tool_config.bourreau_and_tool_can_be_accessed_by?(user).should be_false
    end

    it "should return false if the tool is unaccessible" do
      tool.stub!(:can_be_accessed_by?).and_return(false)
      tool_config.bourreau_and_tool_can_be_accessed_by?(user).should be_false
    end
    
  end

  describe "#short_description" do
    it "should return first line of description" do
      first_line  = "desc1_part1"
      second_line = "desc1_part2"
      tool_config.description = "#{first_line}\n#{second_line}"
      tool_config.short_description.should be == first_line
    end
  end

  describe "#apply_environment" do
    
    it "should add env_array to ENV if use_extend is false" do
      increase = tool_config.env_array ? tool_config.env_array.size : 0
      lambda do
        tool_config.apply_environment {}
      end.should change{ ENV.size }.by(increase)
    end

    it "should add extended_environment to ENV if use_extend is true" do
      increase = tool_config.extended_environment ? tool_config.extended_environment.size : 0
      tool_config.apply_environment(true) { ENV.keys.should include(tool_config.extended_environment.first.first)}
    end
  end

  describe "#extended_environment" do
    
    it "should add CBRAIN_GLOBAL_TOOL_CONFIG_ID entry to env if only bourreau_id is blank" do
      tool_config.bourreau_id = nil
      tool_config.tool_id     = 1
      env = (tool_config.env_array || []).dup
      env << [ "CBRAIN_GLOBAL_TOOL_CONFIG_ID",     tool_config.id.to_s ]
      tool_config.extended_environment.should be == env
    end
    
    it "should add CBRAIN_GLOBAL_BOURREAU_CONFIG_ID to env if only tool_id is blank" do
      tool_config.bourreau_id = 1
      tool_config.tool_id     = nil
      env = (tool_config.env_array || []).dup
      env << [ "CBRAIN_GLOBAL_BOURREAU_CONFIG_ID", tool_config.id.to_s ]
      tool_config.extended_environment.should be == env
    end

    it "should add CBRAIN_TOOL_CONFIG_ID and CBRAIN_GLOBAL_BOURREAU_CONFIG_ID entry if bourreau_id and tool_id are blank" do
      tool_config.bourreau_id = nil
      tool_config.tool_id     = nil
      env = (tool_config.env_array || []).dup
      env << [ "CBRAIN_GLOBAL_TOOL_CONFIG_ID",     tool_config.id.to_s ]
      env << [ "CBRAIN_GLOBAL_BOURREAU_CONFIG_ID", tool_config.id.to_s ]
      tool_config.extended_environment.should be == env
    end
    
    it "should add CBRAIN_TOOL_CONFIG_ID entry if bourreau_id and tool_id are not blank" do
      tool_config.bourreau_id = 1
      tool_config.tool_id     = 1
      env = (tool_config.env_array || []).dup
      env << [ "CBRAIN_TOOL_CONFIG_ID",            tool_config.id.to_s ]
      tool_config.extended_environment.should be == env
    end
  end

  describe "#to_bash_prologue" do
    
   let(:tool) {Factory.create(:tool, :cbrain_task_class => "CbrainTask::Civet")}

   context "fill HEADER" do
      it "should print 'Configuration: tool_config.id'" do
        tool_config.to_bash_prologue.should =~ /Configuration\s?:\s+#\s+#{tool_config.id}/    
      end

      it "should print 'Tool: ALL' if specific tool is not defined"  do
        tool_config.tool = nil
        tool_config.to_bash_prologue.should =~ /Tool\s?:\s+ALL/    
      end

      it "should print 'Tool: tool_config.tool.name' if specific tool is defined"  do
        tool_config.tool = tool
        tool_config.to_bash_prologue.should =~ /Tool\s?:\s+#{tool_config.tool.name}/    
      end

      it "should print 'Bourreau: ALL' if specific bourreau is not defined"  do
        tool_config.bourreau = nil
        tool_config.to_bash_prologue.should =~ /Bourreau\s?:\s+ALL/    
      end

      it "should print 'Bourreau: tool_config.bourreau.name' if specific bourreau is defined"  do
        tool_config.to_bash_prologue.should =~ /Bourreau\s?:\s+#{tool_config.bourreau.name}/    
      end

      it "should print 'Group: everyone' if specific group is not defined"  do
        tool_config.group = nil
        tool_config.to_bash_prologue.should =~ /Group\s?:\s+everyone/    
      end

      it "should print 'Group: tool_config.group.name' if specific group is defined"  do
        tool_config.to_bash_prologue.should =~ /Group\s?:\s+#{tool_config.group.name}/    
      end
    end

    context "fill DESC" do
      it "should print 'Description: (NONE SUPPLIED)' if description is blank" do
        tool_config.description = nil
        tool_config.tool        = tool
        tool_config.to_bash_prologue.should =~ /Description\s?:\s+\(NONE SUPPLIED\)/   
      end

      it "should print 'Description: tool_config.description' if description is blank" do
        tool_config.tool        = tool
        tool_config.to_bash_prologue.should =~ /Description\s?:\n\#\-+\n\n\#\s+#{tool_config.description}/   
      end
    end

    context "fill ENV" do
      it "should print 'Environment variables: (NONE SUPPLIED)' if env is empty" do
        tool_config.to_bash_prologue.should =~ /Environment variables\s?:\s+\(NONE DEFINED\)/   
      end
      
      it "should print 'Environment variables: export name1=\"value1\".... if env is not empty" do
        tool_config.env_array = [["name1", "value1"],["name2","value2"]]

        script = ""
        tool_config.env_array.each do |name_val|
          name = name_val[0]
          val  = name_val[1]
          name.strip!
          script += "export #{name}=\\\"#{val}\\\"\\n"
        end
        
        tool_config.to_bash_prologue.should =~ /Environment variables\s?:\n\#\-+\n\n#{script}/
      end 
    end

    context "fill SCRIPT" do
      it "should print 'Script Prologue: (NONE SUPPLIED)' if script_prologue is blank" do
        tool_config.to_bash_prologue.should =~ /Script Prologue\s?:\s+\(NONE SUPPLIED\)/ 
      end
    
      it "should print 'Script Prologue: tool_config.script_prologue' if script_prologue is not blank" do
        tool_config.script_prologue = "script_prologue"
        tool_config.to_bash_prologue.should =~ /Script Prologue\s?:\n\#\-+\n\n#{tool_config.script_prologue}/
      end
    end
  end

  describe "#is_trivial?" do
    
    it "should return false if object has environment variables in env_array" do
      tool_config.env_array = ["env1"]
      tool_config.is_trivial?.should be_false
    end
    
    it "should return true if script_prologue is blank" do
      tool_config.script_prologue = nil
      tool_config.is_trivial?.should be_true
    end
    
    it "should return true if script_prologue contain only comments" do
      tool_config.script_prologue = "#prologue11\n#prologue2"
      tool_config.is_trivial?.should be_true
    end

    it "should return false if script_prologue is not blank and don't contain only comments" do 
      tool_config.script_prologue = "prologue1"
      tool_config.is_trivial?.should be_false
    end
  end
  
end

