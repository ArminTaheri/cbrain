
#
# CBRAIN Project
#
# Original author: Pierre Rioux
#
# $Id$
#

# This model represents a tool's configuration prefix.
# Unlike other models, the set of ToolConfigs is not
# arbitrary. They fit in three categories:
#
#   * A single tool config represents the the initialization
#     needed by a particular tool on all bourreaux; it
#     has a tool_id and no bourreau_id
#   * A single tool config represents the the initialization
#     needed by a particular bourreau for all tools; it
#     has a bourreau_id and no tool_id
#   * A set of 'versionning' tool configs have both
#     a tool_id and a bourreau_id
#
# 
class ToolConfig < ActiveRecord::Base

  Revision_info="$Id$"
  
  serialize      :env_hash

  belongs_to     :bourreau     # can be nil; it means it applies to all bourreaux
  belongs_to     :tool         # can be nil; it means it applies to all tools
  has_many       :cbrain_tasks

  # Returns the first line of the description. This is used
  # to represent the 'name' of the version.
  def short_description
    description = self.description || ""
    raise "Internal error: can't parse description!?!" unless description =~ /^\s*(\S.*)\n?([\000-\277]*)$/
    header = Regexp.last_match[1].strip
    header
  end

  # Sets in the current Ruby process all the environment variables
  # defined in the object. If +use_extended+ is true, the
  # set of variables provided by +extended_environement+ will be
  # applied instead.
  def apply_environment(use_extended = false)
    env = (use_extended ? self.extended_environment : self.env_hash) || {}
    env.each do |name,val|
      ENV[name.to_s]=val.to_s
    end
    true
  end

  # Returns the set of environment variables as stored in
  # the object, plus a few artificial ones. See the code.
  def extended_environment
    env = (self.env_hash || {}).dup
    env["CBRAIN_GLOBAL_TOOL_CONFIG_ID"]     = self.id.to_s if self.bourreau_id.blank?
    env["CBRAIN_GLOBAL_BOURREAU_CONFIG_ID"] = self.id.to_s if self.tool_id.blank?
    env["CBRAIN_TOOL_CONFIG_ID"]            = self.id.to_s if ! self.tool_id.blank? && ! self.bourreau_id.blank?
    env
  end

  # Generates a partial BASH script that initializes environment
  # variables and is followed a the script prologue stored in the
  # object.
  def to_bash_prologue
    tool     = self.tool
    bourreau = self.bourreau

    script = <<-HEADER

#===================================================
# Configuration: # #{self.id}
# Tool:          #{tool     ? tool.name     : "ALL"}
# Bourreau:      #{bourreau ? bourreau.name : "ALL"}
#===================================================

    HEADER

    if self.tool_id && self.bourreau_id
      desc = self.description || ""
      script += <<-DESC_HEADER
#---------------------------------------------------
# Description:#{desc.blank? ? " (NONE SUPPLIED)" : ""}
#---------------------------------------------------

      DESC_HEADER
      if ! desc.blank?
        desc.gsub!(/\r\n/,"\n")
        desc.gsub!(/\r/,"\n")
        desc_array = desc.split(/\n/).collect { |line| "# #{line}" }
        script += desc_array.join("\n") + "\n\n"
      end
    end

    env = self.env_hash || {}
    script += <<-ENV_HEADER
#---------------------------------------------------
# Environment variables:#{env.size == 0 ? " (NONE DEFINED)" : ""}
#---------------------------------------------------

    ENV_HEADER
    env.each do |name,val|
      name.strip!
      #val.gsub!(/'/,"'\''")
      script += "export #{name}="#{val}"\n"
    end
    script += "\n" if env.size > 0

    prologue = self.script_prologue || ""
    script += <<-SCRIPT_HEADER
#---------------------------------------------------
# Script Prologue:#{prologue.blank? ? " (NONE SUPPLIED)" : ""}
#---------------------------------------------------

    SCRIPT_HEADER
    prologue.gsub!(/\r\n/,"\n")
    prologue.gsub!(/\r/,"\n")
    prologue += "\n" unless prologue =~ /\n$/

    script += prologue

    script
  end

end
