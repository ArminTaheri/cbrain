#
# CBRAIN Project
#
# Model for CBRAIN sites.
#
# Original author: Tarek Sherif
#
# $Id$
#

class Site < ActiveRecord::Base
  
  Revision_info = "$Id$"
                                                               
  validates_presence_of     :name
  validates_uniqueness_of   :name
  validate_on_create        :prevent_group_collision
  
  after_create           :create_system_group
  
  before_save            :save_old_manager_ids,
                         :save_old_user_ids   
  after_save             :set_managers,
                         :set_system_groups
  after_update           :system_group_rename
  before_destroy         :unset_managers,
                         :destroy_system_group
  
  
  has_many        :users,  :dependent => :nullify, :after_remove  => [:user_system_group_remove, :remove_user_from_site_group]
  has_many        :groups, :dependent => :nullify
  
  attr_accessor           :manager_ids
  
  def managers
    self.users.find(:all, :conditions  =>  ["(users.role IN (?))", ["admin", "site_manager"]]) || []
  end
  
  #Find all userfiles that belong to users associated with this site, subject to +options+ (ActiveRecord find options).
  #
  #*NOTE*: the +joins+ and +conditions+ options cannot be used as they are used internally.
  def userfiles_find_all(options = {})
    raise "Options :joins and :conditions cannont be used with this method. They are set internally." if options[:joins] || options[:conditions]
    options.merge!( :joins => :user, :conditions => ["users.site_id = ?", self.id])
    @userfiles ||= Userfile.find(:all, options)
  end
  
  #Find all remote resources that belong to users associated with this site, subject to +options+ (ActiveRecord find options).
  #
  #*NOTE*: the +joins+ and +conditions+ options cannot be used as they are used internally.
  def remote_resources_find_all(options = {})
    raise "Options :joins and :conditions cannont be used with this method. They are set internally." if options[:joins] || options[:conditions]
    options.merge!( :joins => :user, :conditions => ["users.site_id = ?", self.id])
    @remote_resources ||= RemoteResource.find(:all, options)
  end
  
  #Find all data providers that belong to users associated with this site, subject to +options+ (ActiveRecord find options).
  #
  #*NOTE*: the +joins+ and +conditions+ options cannot be used as they are used internally.
  def data_providers_find_all(options = {})
    raise "Options :joins and :conditions cannont be used with this method. They are set internally." if options[:joins] || options[:conditions]
    options.merge!( :joins => :user, :conditions => ["users.site_id = ?", self.id])
    @data_provider ||= DataProvider.find(:all, options)
  end
  
  #Find the userfile with the given +id+ that belong to a user associated with this site, subject to +options+ (ActiveRecord find options).
  #
  #*NOTE*: the +joins+ and +conditions+ options cannot be used as they are used internally.
  def userfiles_find_id(id, options = {})
    raise "Options :joins and :conditions cannont be used with this method. They are set internally." if options[:joins] || options[:conditions]
    options.merge!( :joins => :user, :conditions => ["users.site_id = ?", self.id])
    @userfiles ||= Userfile.find(id, options)
  end
  
  #Find the remote resource with the given +id+ that belong to a user associated with this site, subject to +options+ (ActiveRecord find options).
  #
  #*NOTE*: the +joins+ and +conditions+ options cannot be used as they are used internally.
  def remote_resources_find_id(id, options = {})
    raise "Options :joins and :conditions cannont be used with this method. They are set internally." if options[:joins] || options[:conditions]
    options.merge!( :joins => :user, :conditions => ["users.site_id = ?", self.id])
    @remote_resources ||= RemoteResource.find(id, options)
  end
  
  #Find the data provider with the given +id+ that belong to a user associated with this site, subject to +options+ (ActiveRecord find options).
  #
  #*NOTE*: the +joins+ and +conditions+ options cannot be used as they are used internally.
  def data_providers_find_id(id, options = {})
    raise "Options :joins and :conditions cannont be used with this method. They are set internally." if options[:joins] || options[:conditions]
    options.merge!( :joins => :user, :conditions => ["users.site_id = ?", self.id])
    @data_provider ||= DataProvider.find(id, options)
  end
  
  # Returns the SystemGroup associated with the site; this is a
  # group with the same name as the site.
  def system_group
    SystemGroup.find(:first, :conditions => { :name => self.login } )
  end

  # An alias for system_group()
  alias own_group system_group

  private
  
  def create_system_group
    SystemGroup.create!(:name => self.name, :site_id  => self.id)
  end
  
  def user_system_group_remove(user)
    if user.has_role? :site_manager
      user.update_attributes!(:role  => "user")
    end
    SystemGroup.find_by_name(user.login).update_attributes!(:site => nil)
  end
  
  def remove_user_from_site_group(user)
    site_group = SystemGroup.find_by_name(self.name)
    site_group.users.delete(user)
  end
  
  def save_old_manager_ids
    @old_manager_ids = self.managers.collect{ |m| m.id.to_s }
  end
  
  def save_old_user_ids
    @old_user_ids = self.users.collect{ |m| m.id.to_s }
  end
  
  def set_managers
    self.manager_ids ||= []
    self.user_ids ||= []
    current_manager_ids = self.manager_ids.collect(&:to_s) || []
    current_user_ids = self.user_ids.collect(&:to_s)
    
    User.find(current_user_ids | current_manager_ids).each do |user|
      if current_manager_ids.include? user.id.to_s
        if user.has_role? :user
          user.update_attributes(:site_id  => self.id, :role  => "site_manager")
        else
          user.update_attributes(:site_id  => self.id)
        end
      else
        if user.has_role? :site_manager
          user.update_attributes(:site_id  => self.id, :role  => "user")
        else
          user.update_attributes(:site_id  => self.id)
        end
      end
    end
  end
  
  def set_system_groups
    current_user_ids = self.user_ids || []
    @new_user_ids   = current_user_ids - @old_user_ids
    @unset_user_ids = @old_user_ids - current_user_ids
    site_group = SystemGroup.find_by_name(self.name)
    
    User.find(@new_user_ids).each do |user|
      SystemGroup.find_by_name(user.login).update_attributes!(:site  => self)
      unless user.groups.exists? site_group
        user.groups << site_group
      end
    end
  end
  
  def unset_managers
    self.managers.each do |user|
      if user.has_role? :site_manager
        user.update_attributes!(:role  => "user")
      end
    end
  end
  
  def system_group_rename
    if self.changed.include?("name")
      old_name = self.changes["name"].first
      SystemGroup.find_by_name(old_name).update_attributes!(:name => self.name)
    end
  end
  
  def prevent_group_collision #:nodoc:
    if self.name && (WorkGroup.find_by_name(self.name) || self.name == 'everyone') 
      errors.add(:name, "already in use by a group.")
    end
  end
  
  def destroy_system_group #:nodoc:
    system_group = SystemGroup.find(:first, :conditions => {:name => self.name})
    system_group.destroy if system_group
  end
end
