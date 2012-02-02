
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

require 'set'

#Abstract model representing files actually registered to the system.
#
#<b>Userfile should not be instantiated directly.</b> Instead, all files
#should be registered through one of the subclasses (SingleFile, FileCollection
#or CivetOutput as of this writing).
#
#=Attributes:
#[*name*] The name of the file.
#[*size*] The size of the file.
#= Associations:
#*Belongs* *to*:
#* User
#* DataProvider
#* Group
#*Has* *and* *belongs* *to* *many*:
#* Tag
#
class Userfile < ActiveRecord::Base

  Revision_info=CbrainFileRevision[__FILE__]

  after_save              :update_format_group
  before_destroy          :erase_or_unregister, :format_tree_update, :nullify_children
  
  validates_uniqueness_of :name, :scope => [ :user_id, :data_provider_id ]
  validates_presence_of   :name
  validates_presence_of   :user_id
  validates_presence_of   :data_provider_id
  validates_presence_of   :group_id
  validate                :validate_associations
  validate                :validate_filename
  validate                :validate_group_update

  belongs_to              :user
  belongs_to              :data_provider
  belongs_to              :group
  belongs_to              :format_source,
                          :class_name   => "Userfile",
                          :foreign_key  => "format_source_id"
  belongs_to              :parent,
                          :class_name   => "Userfile",
                          :foreign_key  => "parent_id"
                          
  has_and_belongs_to_many :tags
  has_many                :sync_status
  has_many                :formats,
                          :class_name   => "Userfile",
                          :foreign_key  => "format_source_id"
  has_many                :children,
                          :class_name   => "Userfile",
                          :foreign_key  => "parent_id"
                                                    
  # For tree sorting algorithm
  attr_accessor           :level
  attr_accessor           :tree_children
  attr_accessor           :rank_order
  
  scope                   :name_like, lambda { |n| {:conditions => ["userfiles.name LIKE ?", "%#{n}%"]} }
  scope                   :file_format, lambda { |f|
                                          format_filter = Userfile.descendants.map(&:to_s).find{ |c| c == f }
                                          format_ids = Userfile.connection.select_values("select format_source_id from userfiles where format_source_id IS NOT NULL AND type='#{format_filter}'").join(",")
                                          format_ids = " OR userfiles.id IN (#{format_ids})" unless format_ids.blank?
                                          {:conditions  => "userfiles.type='#{format_filter}'#{format_ids}"}
                                        }
  scope                   :has_no_parent, :conditions => {:parent_id => nil}
  scope                   :has_no_child,  lambda { |ignored|
                                            all_parents = Userfile.connection.select_values("SELECT DISTINCT parent_id FROM userfiles WHERE parent_id IS NOT NULL").join(",")
                                            { :conditions => "userfiles.id NOT IN (#{all_parents})" }
                                          }

  class Viewer
    attr_reader :name, :partial
    
    def initialize(viewer)
      atts = viewer
      unless atts.is_a? Hash
        atts = { :name  => viewer.to_s.classify.gsub(/(.+)([A-Z])/, '\1 \2'), :partial => viewer.to_s.underscore }
      end
      initialize_from_hash(atts)
    end
    
    def initialize_from_hash(atts = {})
      unless atts.has_key?(:name) || atts.has_key?(:partial)
        cb_error("Viewer must have either name or partial defined.")
      end
      
      name       = atts.delete(:name)
      partial    = atts.delete(:partial)
      att_if     = atts.delete(:if)      || []
      cb_error "Unknown viewer option: '#{atts.keys.first}'." unless atts.empty?

      @conditions = []
      @name       = name      || partial.to_s.classify.gsub(/(.+)([A-Z])/, '\1 \2')
      @partial    = partial   || name.to_s.gsub(/\s+/, "").underscore 
      att_if = [ att_if ] unless att_if.is_a?(Array)
      att_if.each do |method|
        cb_error "Invalid :if condition '#{method}' in model." unless method.respond_to?(:to_proc)
        @conditions << method.to_proc
      end
    end
    
    def valid_for?(userfile)
      return true if @conditions.empty?
      @conditions.all? { |condition| condition.call(userfile) }
    end
    
    def ==(other)
      return false unless other.is_a? Viewer
      self.name == other.name
    end
  end

  # Class representing the way in which the content
  # of a userfile can be transferred to a client. 
  # Created by using the #has_content directive 
  # in a Userfile subclass.
  # ContentLoaders are defined by two parameters:
  # [method] an instance method defined for the
  #          class that will prepare the data for
  #          transfer.
  # [type]   the type of data being transfered.
  #          Generally, this is the the key to be
  #          used in the hash given to a render
  #          call in the controller. One special
  #          is :send_file, which the controller
  #          will take as indicating that the
  #          ContentLoader method will return 
  #          the path of a file to be sent directly.
  # For example, if one wished to send the content
  # as xml, one would first define the content loader
  # method:
  #  def generate_xml
  #     ... # make the xml
  #  end
  # And then register the loader using #has_content:
  #  has_content :method => generate_xml, :type => :xml
  # The #has_content directive can also take a single 
  # symbol or string, which it will assume is the
  # name of the content loader method, and setting
  # the type to :send_file.
  class ContentLoader
    attr_reader :method, :type
    
    def initialize(content_loader)
      atts = content_loader
      unless atts.is_a? Hash
        atts = {:method => atts}
      end
      initialize_from_hash(atts)
    end
    
    def initialize_from_hash(options = {})
      cb_error "Content loader must have method defined." if options[:method].blank?
      @method = options[:method].to_sym
      @type   = (options[:type]  || :send_file).to_sym
    end
    
    def ==(other)
      return false unless other.is_a? ContentLoader
      self.method == other.method
    end
  end

  #List of viewers for this model
  def viewers
    class_viewers = self.class.class_viewers
    
    @viewers = class_viewers.select { |v| v.valid_for?(self) }
  end
  
  #Find a viewer for this model
  def find_viewer(name)
    self.viewers.find{ |v| v.name == name}
  end
  
  #List of content loaders for this model
  def content_loaders
    self.class.content_loaders
  end
  
  #Find a content loader for this model. Priority is given
  #to finding a matching method name. If none is found, then
  #an attempt is made to match on the type. There may be several
  #type matches so the first is returned.
  def find_content_loader(meth)
    self.class.find_content_loader(meth)
  end
  
  #The site with which this userfile is associated.
  def site
    @site ||= self.user.site
  end
  
  # Define sort orders that don't refer to actual columns in the table.
  def self.pseudo_sort_columns
    ["tree_sort"]
  end
  
  #File extension for this file (helps sometimes in building urls).
  def file_extension
    self.class.file_extension(self.name)
  end

  # Return the file extension (the last '.' in the name and
  # the characters following it).
  def self.file_extension(name)
    name.scan(/\.[^\.]+$/).last
  end

  # Classes this type of file can be converted to.
  # Essentially distinguishes between SingleFile subtypes and FileCollection subtypes.
  def self.valid_file_classes
    return @valid_file_classes if @valid_file_classes

    base_class = self
    base_class = SingleFile     if self <= SingleFile
    base_class = FileCollection if self <= FileCollection
    
    @valid_file_classes = base_class.descendants.unshift(base_class)
  end

  # Instance version of the class method.
  def valid_file_classes
    self.class.valid_file_classes
  end
  
  #Names of classes this type of file can be converted to.
  #Essentially distinguishes between SingleFile subtypes and FileCollection subtypes.
  def self.valid_file_types
    return @valid_file_types if @valid_file_types
    
    @valid_file_types = self.valid_file_classes.map(&:name)
  end
  
  #Instance version of the class method.
  def valid_file_types
    self.class.valid_file_types
  end
  
  #Checks validity according to valid_file_types.
  def is_valid_file_type?(type)
    self.valid_file_types.include? type
  end
  
  def suggested_file_type
    @suggested_file_type ||= self.valid_file_classes.find{|ft| self.name =~ ft.file_name_pattern}
  end
  
  #Updates the class (type attribute) of this file if +type+ is 
  #valid according to valid_file_types.
  def update_file_type(type)
    if self.is_valid_file_type?(type)
      self.type = type
      self.save
    else
      false
    end
  end
  
  # Add a format to this userfile.
  def add_format(userfile)
    source_file = self.format_source || self
    source_file.formats << userfile
  end
  
  # The format name (for display) of this userfile.
  def format_name
    nil
  end
  
  # List of the names of the formats available for the userfile.
  def format_names
    source_file = self.format_source || self
    @format_names ||= source_file.formats.map(&:format_name).push(self.format_name).compact 
  end
  
  # Return true if the given format exists for the calling userfile
  def has_format?(f)
    if self.get_format(f)
      true
    else
      false
    end
  end
  
  # Find the userfile representing the given format for the calling 
  # userfile, if it exists.
  def get_format(f)
    return self if self.format_name.to_s.downcase == f.to_s.downcase || self.class.name == f
    
    self.formats.all.find { |fmt| fmt.format_name.to_s.downcase == f.to_s.downcase || fmt.class.name == f }
  end

  #Return an array of the tags associated with this file
  #by +user+.
  def get_tags_for_user(user)
    user = User.find(user) unless user.is_a?(User)
    self.tags.all(:conditions => ["tags.user_id=? OR tags.group_id IN (?)", user.id, user.cached_group_ids])
  end

  #Set the tags associated with this file to those
  #in the +tags+ array (represented by Tag objects
  #or ids).
  def set_tags_for_user(user, tags)
    user = User.find(user) unless user.is_a?(User)

    tags ||= []
    tags = [tags] unless tags.is_a? Array
     
    non_user_tags = self.tags.all(:conditions  => ["tags.user_id<>? AND tags.group_id NOT IN (?)", user.id, user.group_ids]).map(&:id)
    new_tag_set = tags + non_user_tags

    self.tag_ids = new_tag_set
  end


  # Sort a list of files in "tree order" where
  # parents are listed just before their children.
  # It also keeps the original list's ordering
  # at each level. The method will set the :level
  # pseudo attribute too, with 0 for the top level.
  def self.tree_sort(userfiles = [])
    top         = Userfile.new( :name => "DUMMY_TOP", :parent_id => -999_999_999 ) # Dummy, to collect top level; ID is NIL!
    userfiles   = userfiles.to_a + [ top ] # Note: so that by_id[nil] returns 'top'

    by_id       = {}        # id => userfile
    userfiles.each_with_index do |u,idx|
      u.tree_children = nil
      by_id[u.id]     = u   # WE NEED TO USE THIS INSTEAD OF .parent !!!
      u.rank_order    = idx # original order in array
    end

    # Construct tree
    seen      = {}
    userfiles.each do |file|
      current  = file # probably not necessary
      track_id = file.id # to detect loops
      while ! seen[current]
        break if current == top
        seen[current] = track_id
        parent_id     = current.parent_id # Can be nil! by_id[nil] will return 'top' 
        parent        = by_id[parent_id] # Cannot use current.parent, as this would destroy its :tree_children
        parent      ||= top
        break if seen[parent] && seen[parent] == track_id # loop
        parent.tree_children ||= []
        parent.tree_children << current
        current = parent
      end
    end

    # Flatten tree
    top.all_tree_children(0) # sets top children's levels to '0'
  end

  # Returns an array will all children or subchildren
  # of the userfile, as contructed by tree_sort.
  # Optionally, sets the :level pseudo attribute
  # to all current children, increasing it down
  # the tree.
  def all_tree_children(level = nil) #:nodoc:
    return [] if self.tree_children.blank?
    result = []
    self.tree_children.sort { |a,b| a.rank_order <=> b.rank_order }.each do |child|
      child.level = level if level
      result << child
      if child.tree_children # the 'if' optimizes one recursion out
        child.all_tree_children(level ? level+1 : nil).each { |c| result << c } # amazing! faster than += for arrays!
      end
    end
    result
  end

  # Return the level of the calling userfile in 
  # the parentage tree.
  def level
    @level ||= 0
  end

  #Returns whether or not +user+ has access to this
  #userfile.
  def can_be_accessed_by?(user, requested_access = :write)
    if user.has_role? :admin
      return true
    end
    if user.has_role?(:site_manager) && self.user.site_id == user.site_id && self.group.site_id == user.site_id
      return true
    end
    if user.id == self.user_id
      return true
    end
    if user.is_member_of_group(self.group_id) && (self.group_writable || requested_access == :read)
      return true
    end

    false
  end

  #Returns whether or not +user+ has owner access to this
  #userfile.
  def has_owner_access?(user)
    if user.has_role? :admin
      return true
    end
    if user.has_role?(:site_manager) && self.user.site_id == user.site_id && self.group.site_id == user.site_id
      return true
    end
    if user.id == self.user_id
      return true
    end

    false
  end

  #Returns a scope representing the set of files accessible to the
  #given user.
  def self.accessible_for_user(user, options)
    access_options = {}
    access_options[:access_requested] = options.delete :access_requested
    
    scope = self.scoped(options)
    scope = Userfile.restrict_access_on_query(user, scope, access_options)      
    
    scope
  end

  #Find userfile identified by +id+ accessible by +user+.
  #
  #*Accessible* files are:
  #[For *admin* users:] any file on the system.
  #[For <b>site managers </b>] any file that belongs to a user of their site,
  #                            or assigned to a group to which the user belongs.
  #[For regular users:] all files that belong to the user all
  #                     files assigned to a group to which the user belongs.
  def self.find_accessible_by_user(id, user, options = {})
    self.accessible_for_user(user, options).find(id)
  end

  #Find all userfiles accessible by +user+.
  #
  #*Accessible* files are:
  #[For *admin* users:] any file on the system.
  #[For <b>site managers </b>] any file that belongs to a user of their site,
  #                            or assigned to a group to which the user belongs.
  #[For regular users:] all files that belong to the user all
  #                     files assigned to a group to which the user belongs.
  def self.find_all_accessible_by_user(user, options = {})
    self.accessible_for_user(user, options)
  end

  #This method takes in an array to be used as the :+conditions+
  #parameter for Userfile.where and modifies it to restrict based
  #on file ownership or group access.
  def self.restrict_access_on_query(user, scope, options = {})
    return scope if user.has_role? :admin
    
    access_requested = options[:access_requested] || :write
    
    data_provider_ids = DataProvider.find_all_accessible_by_user(user).all.map(&:id)
    
    query_user_string = "userfiles.user_id = ?"
    query_group_string = "userfiles.group_id IN (?) AND userfiles.data_provider_id IN (?)"
    if access_requested.to_sym != :read
      query_group_string += " AND userfiles.group_writable = true"
    end
    query_string = "(#{query_user_string}) OR (#{query_group_string})"
    query_array  = [user.id, user.group_ids, data_provider_ids]
    if user.has_role? :site_manager
      scope = scope.joins(:user).readonly(false)
      query_string += "OR (users.site_id = ?)"
      query_array  << user.site_id
    end
    
    scope = scope.where( [query_string] + query_array)
    
    scope
  end

  # This method returns true if the string +basename+ is an
  # acceptable name for a userfile. We restrict the filenames
  # to contain printable characters only, with no slashes
  # or ASCII nulls, and they must start with a letter or digit.
  def self.is_legal_filename?(basename)
    return true if basename && basename.match(/^[a-zA-Z0-9][\w\~\!\@\#\%\^\&\*\(\)\-\+\=\:\[\]\{\}\|\<\>\,\.\?]*$/)
    false
  end

  #Returns the name of the Userfile in an array (only here to
  #maintain compatibility with the overridden method in
  #FileCollection).
  def list_files(*args)
    @file_list ||= {}
   
    @file_list[args.dup] ||= if self.is_locally_cached?
                               self.cache_collection_index(*args)
                             else
                               self.provider_collection_index(*args)
                             end
  end
  
  # Calculates and sets the size attribute unless
  # it's already set.
  def set_size
    self.set_size! if self.size.blank?
  end 

  # Calculates and sets.
  # (Abstract: should be redefined in subclass).
  def set_size!
    raise "set_size! called on Userfile. Should only be called in a subclass."
  end

  #Should return a regex pattern to identify filenames that match a given
  #userfile subclass
  def self.file_name_pattern
    nil
  end

  #Human-readable version of a userfile class name. Can be overridden
  #if necessary in subclasses.
  def self.pretty_type
    @pretty_type_name ||= self.name.gsub(/(.+)([A-Z])/, '\1 \2')
  end

  # Convenience instance method that calls the class method.
  def pretty_type
    self.class.pretty_type
  end

  ##############################################
  # Tree Traversal Methods
  ##############################################

  # Make the calling userfile a child of the argument.
  def move_to_child_of(userfile)
    if self.id == userfile.id || self.descendants.include?(userfile)
      raise ActiveRecord::ActiveRecordError, "A userfile cannot become the child of one of its own descendants." 
    end
    
    self.parent_id = userfile.id
    self.save!
        
    true
  end

  # List all descendants of the calling userfile.
  def descendants(seen = {})
    result     = []
    seen[self] = true
    self.children.each do |child|
      next if seen[child] # defensive, against loops
      seen[child] = true
      result << child
      result += child.descendants(seen)
    end
    result
  end



  ##############################################
  # Sequential traversal methods.
  ##############################################
  
  # Find the next file (by id) available to the given user.
  def next_available_file(user, options = {})
    Userfile.accessible_for_user(user, options).order('userfiles.id').where( ["userfiles.id > ?", self.id] ).first
  end

  # Find the previous file (by id) available to the given user.
  def previous_available_file(user, options = {})
    Userfile.accessible_for_user(user, options).order('userfiles.id').where( ["userfiles.id < ?", self.id] ).last
  end
  
  ##############################################
  # Synchronization Status Access Methods
  ##############################################

  # Forces the userfile to be marked
  # as 'newer' on the provider side compared
  # to whatever is in the local cache for the
  # current Rails application. Not often used.
  # Results in the destruction of the local
  # sync status object.
  def provider_is_newer
    SyncStatus.ready_to_modify_dp(self) do
      true
    end
  end

  # Forces the userfile to be marked
  # as 'newer' on the cache side of the current
  # Rails application compared to whatever is in
  # the official data provider.
  # Results in the the local sync status object
  # to be marked as 'CacheNewer'.
  def cache_is_newer
    SyncStatus.ready_to_modify_cache(self) do
      true
    end
  end

  # This method returns, if it exists, the SyncStatus
  # object that represents the syncronization state of
  # the content of this userfile on the local RAILS
  # application's DataProvider cache. Returns nil if
  # no SyncStatus object currently exists for the file.
  def local_sync_status(refresh = false)
    @syncstat = nil if refresh
    @syncstat ||= SyncStatus.where(
      :userfile_id        => self.id,
      :remote_resource_id => CBRAIN::SelfRemoteResourceId
    ).first
  end

  # Returns whether this userfile's contents has been
  # synced to the local cache.
  def is_locally_synced?
    syncstat = self.local_sync_status
    return true if syncstat && syncstat.status == 'InSync'
    return false unless self.data_provider.is_fast_syncing?
    self.sync_to_cache
    syncstat = self.local_sync_status(:refresh)
    return true if syncstat && syncstat.status == 'InSync'
    false
  end
  
  # Returns whether this userfile's contents
  # is present in the local cache and valid.
  #
  # The difference between this method and is_locally_synced?
  # is that this method will also return true if the contents
  # are more up to date on the cache than on the provider
  # (and thus are not officially "In Sync").
  def is_locally_cached?
    return true if is_locally_synced?
    
    syncstat = self.local_sync_status
    syncstat && syncstat.status == 'CacheNewer'
  end

  ##############################################
  # Data Provider easy access methods
  ##############################################

  # Cam this file have its owner changed
  def allow_file_owner_change?
    self.data_provider.allow_file_owner_change?
  end 

  # See the description in class DataProvider
  def sync_to_cache
    self.data_provider.sync_to_cache(self)
  end

  # See the description in class DataProvider
  def sync_to_provider
    self.data_provider.sync_to_provider(self)
    self.set_size!
  end

  # See the description in class DataProvider
  def cache_erase
    self.data_provider.cache_erase(self)
  end

  # See the description in class DataProvider
  def cache_prepare
    self.save! if self.id.blank? # we need an ID to prepare the cache
    self.data_provider.cache_prepare(self)
  end

  # See the description in class DataProvider
  def cache_full_path
    self.data_provider.cache_full_path(self)
  end

  # See the description in class DataProvider
  def provider_erase
    self.data_provider.provider_erase(self)
  end

  # See the description in class DataProvider
  def provider_rename(newname)
    self.data_provider.provider_rename(self, newname)
  end

  # See the description in class DataProvider
  def provider_move_to_otherprovider(otherprovider, options = {})
    self.data_provider.provider_move_to_otherprovider(self, otherprovider, options)
  end
  
  # See the description in class DataProvider
  def provider_copy_to_otherprovider(otherprovider, options = {})
    self.data_provider.provider_copy_to_otherprovider(self, otherprovider, options)
  end

  # See the description in class DataProvider
  def provider_collection_index(directory = :all, allowed_types = :regular)
    self.data_provider.provider_collection_index(self, directory, allowed_types)
  end

  # See the description in class DataProvider
  def provider_readhandle(*args, &block)
    self.data_provider.provider_readhandle(self, *args,  &block)
  end

  # See the description in class DataProvider
  def cache_readhandle(*args, &block)
    self.data_provider.cache_readhandle(self, *args,  &block)
  end

  # See the description in class DataProvider
  def cache_writehandle(*args, &block)
    self.save!
    self.data_provider.cache_writehandle(self, *args, &block)
    self.set_size!
  end

  # See the description in class DataProvider
  def cache_copy_from_local_file(filename)
    self.save!
    self.data_provider.cache_copy_from_local_file(self, filename)
    self.set_size!
  end

  # See the description in class DataProvider
  def cache_copy_to_local_file(filename)
    self.save!
    self.data_provider.cache_copy_to_local_file(self, filename)
  end
  
  # Returns an Array of FileInfo objects containing
  # information about the files associated with this Userfile
  # entry.
  #
  # Information is requested from the cache (not the actual data provider).
  def cache_collection_index(directory = :all, allowed_types = :regular)
    self.data_provider.cache_collection_index(self, directory, allowed_types)
  end
  
  # Returns true if the data provider for the content of
  # this file is online.
  def available?
    self.data_provider.online?
  end

  private
  
  # Add a viewer to the calling class.
  # Arguments can be one or several hashes,
  # strings or symbols used as arguments to
  # create Viewer objects.
  def self.has_viewer(*new_viewers)
    new_viewers.map!{ |v| Viewer.new(v) }
    new_viewers.each{ |v| add_viewer(v) }
  end
  
  # Synonym for #has_viewers.
  def self.has_viewers(*new_viewers)
    self.has_viewer(*new_viewers)
  end
  
  # Remove all previously defined viewers
  # for the calling class.
  def self.reset_viewers
    @ancestor_viewers = []
    @class_viewers    = []
  end
  
  # Add a viewer to the calling class. Unlike #has_viewer
  # the argument is a single Viewer object.
  def self.add_viewer(viewer)
    if self.class_viewers.include?(viewer)
      cb_error "Redefinition of viewer in class #{self.name}."
    end
    
    @class_viewers << viewer
  end
  
  # List viewers for the calling class.
  def self.class_viewers
    unless @ancestor_viewers
      if self.superclass.respond_to? :class_viewers
        @ancestor_viewers = self.superclass.class_viewers
      end
    end
    @ancestor_viewers ||= []
    @class_viewers    ||= []
    class_v    = (@class_viewers).clone
    ancestor_v = (@ancestor_viewers).clone
    
    class_v + ancestor_v
  end
  
  # Add a content loader to the calling class.
  def self.has_content(options = {})
    new_content = ContentLoader.new(options)
    @@content_loaders ||= []
    if @@content_loaders.include?(new_content) 
      cb_error "Redefinition of content loader in class #{self.name}."
    end 
    @@content_loaders << new_content
  end
  # List content loaders for the calling class.
  def self.content_loaders
    @@content_loaders ||= []
  end
  
  #Find a content loader for this model. Priority is given
  #to finding a matching method name. If none is found, then
  #an attempt is made to match on the type. There may be several
  #type matches so the first is returned.
  def self.find_content_loader(meth)
    return nil if meth.blank?
    method = meth.to_sym
    self.content_loaders.find { |cl| cl.method == method } || 
    self.content_loaders.find { |cl| cl.type == method }
  end
  
  def validate_associations
    unless DataProvider.where( :id => self.data_provider_id ).first
      errors.add(:data_provider, "does not exist.")
    end
    unless User.where( :id => self.user_id ).first
      errors.add(:user, "does not exist.")
    end
    unless Group.where( :id => self.group_id ).first
      errors.add(:group, "does not exist.")
    end
  end

  # Active Record validation.
  def validate_filename #:nodoc:
    unless Userfile.is_legal_filename?(self.name)
      errors.add(:name, "contains invalid characters.")
    end
  end
  
  def erase_or_unregister
    unless self.data_provider.is_browsable? && self.data_provider.meta[:must_erase].blank?
      self.provider_erase
    end
    self.cache_erase
    true
  end
  
  def format_tree_update
    return true if self.format_source
    
    format_children = self.formats
    return true if format_children.empty?
    
    new_source = format_children.shift
    new_source.update_attributes!(:format_source_id  => nil)
    format_children.each do |fmt|
      fmt.update_attributes!(:format_source_id  => new_source.id)
    end
  end
  
  def nullify_children
    self.children.each do |c|
      c.parent_id = nil
      c.save!
    end    
  end
  
  def validate_group_update
    if self.format_source_id && self.changed.include?("group_id") && self.format_source 
      unless self.group_id == self.format_source.group_id
        errors.add(:group_id, "cannot be modified for a format file.")
      end
    end
  end
  
  def update_format_group
    unless self.format_source_id
      self.formats.each do |f|
        f.update_attributes!(:group_id => self.group_id)
      end
    end
    true
  end
  
end

