
#
# CBRAIN Project
#
# CBRAIN extensions
#
# Original author: Pierre Rioux
#
# $Id$
#

###################################################################
# CBRAIN ActiveRecord extensions
###################################################################
class ActiveRecord::Base

  ###################################################################
  # ActiveRecord Added Behavior For MetaData
  ###################################################################
  include ActRecMetaData
  after_destroy :destroy_all_meta_data

  # Update meta information to the record based on
  # the content of a hash +myparams+.
  #
  # Example: let's say that when posting to update object @myobj,
  # the form also sent this to the controller:
  #
  #   params = { :meta => { :abc => "2", :def => 'z', :xyz => 'A' } ... }
  #
  # Then calling
  #
  #   @myobj.add_meta_data_from_form(params[:meta], [ :def, :xyz ])
  #
  # will result in two meta data pieces of information added
  # to the object @myobj, like this:
  #
  #   @myobj.meta[:def] = 'z'
  #   @myobj.meta[:xyz] = 'A'
  #
  # +meta_keys+ can be provided to limit the set of keys to
  # be updated; the default is the keyword :all which means all
  # keys in +myparams+ .
  # 
  # See ActRecMetaData for more information.
  def update_meta_data(myparams = {}, meta_keys = :all)
    return true if meta_keys.is_a?(Array) && meta_keys.empty?
    meta_keys = myparams.keys if meta_keys == :all
    meta_keys.each do |key|
      self.meta[key] = myparams[key] # assignment of nil deletes the key
    end
    true
  end

  ###################################################################
  # ActiveRecord Added Behavior For Logging
  ###################################################################
  include ActRecLog
  after_destroy :destroy_log
  after_create  :propagate_tmp_log

  alias original_to_xml to_xml
  
  def to_xml(options = {})
    options[:root] ||= self.class.to_s.gsub("::", "-")
    original_to_xml(options)
  end


  ###################################################################
  # ActiveRecord Added Behavior For Serialization
  ###################################################################

  # This directive is just like ActiveRecord's serialize directive,
  # but it makes sure that the hash will be reconstructed as
  # a HashWithIndifferentAccess ; it is meant to be backwards compatible
  # with old DBs where the records were saved as Hash, so it will
  # update them as they are reloaded using a after_initialize callback.
  def self.serialize_as_indifferent_hash(*attlist)
    attlist.each do |att|
      raise "Attribute '#{att}' not a symbol?!?" unless att.is_a?(Symbol)
      serialize att, BasicObject # we use this to record which attributes are to be indifferent.
      #serialize att
    end
    after_initialize :ensure_serialized_hash_are_indifferent
  end

  # Call this method in a :after_initialize callback, passsing it
  # a list of attributes that are supposed to be serialized hash
  # with indifferent access; if they are, nothing happens. If they
  # happen to be ordinary hashes, they'll be upgraded.
  def ensure_serialized_hash_are_indifferent #:nodoc:
    to_update = {}
    ser_attinfo = self.class.serialized_attributes
    attlist = ser_attinfo.keys.select { |att| ser_attinfo[att] == BasicObject }
    #attlist = ser_attinfo.keys
    attlist.each do |att|
      the_hash = read_attribute(att) # value of serialized attribute, as reconstructed by ActiveRecord
      if the_hash.is_a?(Hash) && ! the_hash.is_a?(HashWithIndifferentAccess)
#puts_blue "Oh oh, must fix #{self.class.name}-#{self.id} -> #{att}"
        #new_hash = HashWithIndifferentAccess.new_from_hash_copying_default(the_hash)
        new_hash = the_hash.with_indifferent_access
        to_update[att] = new_hash
      end
    end

    unless to_update.empty?
      # Proper code that is supposed to update it once and for all in the DB:

      #self.update_attributes(to_update) # reactive once YAML dumping is fixed in Rails

      # Unfortunately, currently a HashWithIndifferentAccess is serialized EXACTLY as a Hash, so
      # it doesn't save any differently in the DB. To prevent unnecessary writes and rewrites of
      # always the same serialized Hash, we'll just update the attribute in memory instead:
      to_update.each do |att,val|
        write_attribute(att,val)
      end
    end

    true
  end

end



###################################################################
# CBRAIN Kernel extensions
###################################################################
module Kernel

  private

  # Raises a CbrainNotice exception, with a default redirect to
  # the current controller's index action.
  def cb_notify(message = "Something may have gone awry.", options = {} )
    options[:status] ||= :ok
    raise CbrainNotice.new(message, options)
  end
  alias cb_notice cb_notify

  # Raises a CbrainError exception, with a default redirect to
  # the current controller's index action.
  def cb_error(message = "Some error occured.",  options = {} )
    options[:status] ||= :bad_request
    raise CbrainError.new(message, options)
  end

  # Debugging tools; this is a 'puts' where the string is colorized.
  def puts_red(message)
    puts "\e[31m#{message}\e[0m"
  end

  # Debugging tools; this is a 'puts' where the string is colorized.
  def puts_green(message)
    puts "\e[32m#{message}\e[0m"
  end

  # Debugging tools; this is a 'puts' where the string is colorized.
  def puts_blue(message)
    puts "\e[34m#{message}\e[0m"
  end

  # Debugging tools; this is a 'puts' where the string is colorized.
  def puts_yellow(message)
    puts "\e[33m#{message}\e[0m"
  end

  # Debugging tools; this is a 'puts' where the string is colorized.
  def puts_magenta(message)
    puts "\e[35m#{message}\e[0m"
  end

  # Debugging tools; this is a 'puts' where the string is colorized.
  def puts_cyan(message)
    puts "\e[36m#{message}\e[0m"
  end
  
  def puts_timer(message, colour = nil, reset = false)
    @@__DEBUG_TIMER__ ||= nil
    if reset
      @@__DEBUG_TIMER__ = nil
    end
    if @@__DEBUG_TIMER__
      @@__DEBUG_TIMER__.timed_puts(message, colour)
    else
      @@__DEBUG_TIMER__ = DebugTimer.new
      method = "puts"
      if colour
        method = "puts_#{colour}"
      end
      send method, message
    end
  end

end



###################################################################
# CBRAIN Extensions To Core Types
###################################################################

class Symbol

  # Used by views for CbrainTasks to transform a
  # symbol such as :abc into a path to a variable
  # inside the params[] hash, as "cbrain_task[params][abc]".
  #
  # CBRAIN adds a similar method in the String class.
  def to_la
    "cbrain_task[params][#{self}]"
  end

  # Used by views for CbrainTasks to transform a
  # symbol such as :abc (representing a path to a
  # variable inside the params[] hash) into the name
  # of a pseudo accessor method for that variable.
  # This is also the name of the input field's HTML ID
  # attribute, used for error validations.
  #
  # CBRAIN adds a similar method in the String class.
  def to_la_id
    self.to_s.to_la_id
  end

end

class String

  # Used by views for CbrainTasks to transform a
  # string such as "abc" or "abc[def]" into a path to a
  # variable inside the params[] hash, as in
  # "cbrain_task[params][abc]" or "cbrain_task[params][abc][def]"
  #
  # CBRAIN adds a similar method in the Symbol class.
  def to_la
    key = self
    if key =~ /^(\w+)/
      newcomp = "[" + Regexp.last_match[1] + "]"
      key = key.sub(/^(\w+)/,newcomp) # not sub!() !
    end
    "cbrain_task[params]#{key}"
  end

  # Used by views for CbrainTasks to transform a
  # string such as "abc" or "abc[def]" (representing
  # a path to a variable inside the params[] hash, as in
  # "cbrain_task[params][abc]" or "cbrain_task[params][abc][def]")
  # into the name of a pseudo accessor method for that variable.
  # This is also the name of the input field's HTML ID
  # attribute, used for error validations.
  #
  # CBRAIN adds a similar method in the Symbol class.
  def to_la_id
    self.to_la.gsub(/\W+/,"_").sub(/_+$/,"").sub(/^_+/,"")
  end

  # Considers self as a pattern to with substitutions
  # are to be applied; the substitutions are found in
  # self by recognizing keywords surreounded by
  # '{}' (curly braces) and those keywords are looked
  # up in the +keywords+ hash.
  #
  # Example:
  #
  #  mypat  = "abc{def}-{mach-3}{ext}"
  #  mykeys = {  :def => 'XYZ', 'mach-3' => 'fast', :ext => '.zip' }
  #  mypat.pattern_substitute( mykeys ) # return "abcXYZ-fast.zip"
  #
  # Note that keywords are limited to sequences of lowercase
  # characters and digits, like 'def', '3', or 'def23' or the same with
  # a number extension, like '4-34', 'def-23' and 'def23-3'.
  #
  # Options:
  #
  # :allow_unset, if true, allows substitution of an empty
  # string if a keyword is defined in the pattern but not
  # in the +keywords+ hash. Otherwise, an exception is raised.
  def pattern_substitute(keywords, options = {})
    pat_comps = self.split(/(\{(?:[a-z0-9_]+(?:-\d+)?)\})/i)
    final = ""
    pat_comps.each_with_index do |comp,i|
      if i.even?
        final += comp
      else
        comp.gsub!(/[{}]/,"")
        val = keywords[comp.downcase] || keywords[comp.downcase.to_sym]
        cb_error "Cannot find value for keyword '{#{comp.downcase}}'." if val.nil? && ! options[:allow_unset]
        final += val.to_s
      end
    end
    final
  end

end

class Array

  # Converts the array into a complex hash.
  # Runs the given block, passing it each of the
  # elements of the array; the block must return
  # a key that will be given to build a hash table.
  # The values of the hash table will be the list of
  # elements of the original array for which the block
  # returned the same key. The method returns the
  # final hash.
  #
  #   [0,1,2,3,4,5,6].hashed_partition { |n| n % 3 }
  #
  # will return
  #
  #   { 0 => [0,3,6], 1 => [1,4], 2 => [2,5] }
  def hashed_partition
    partitions = {}
    self.each do |elem|
       key = yield(elem)
       partitions[key] ||= []
       partitions[key] << elem
    end
    partitions
  end
  alias hashed_partitions hashed_partition
  
  def to_xml(options = {})
    raise "Not all elements respond to to_xml" unless all? { |e| e.respond_to? :to_xml }
    require 'builder' unless defined?(Builder)
  
    options = options.dup
    options[:root]     ||= "records"
    options[:indent]   ||= 2
    options[:builder]  ||= Builder::XmlMarkup.new(:indent => options[:indent])
  
    root     = options.delete(:root).to_s
    children = options.delete(:children)
  
    if !options.has_key?(:dasherize) || options[:dasherize]
      root = root.dasherize
    end
  
    options[:builder].instruct! unless options.delete(:skip_instruct)
  
    opts = options.clone
  
    xml = options[:builder]
    if empty?
      xml.tag!(root, options[:skip_types] ? {} : {:type => "array"})
    else
      xml.tag!(root, options[:skip_types] ? {} : {:type => "array"}) {
        yield xml if block_given?
        each { |e| e.to_xml(opts.merge({ :skip_instruct => true })) }
      }
    end
  end
  
end



