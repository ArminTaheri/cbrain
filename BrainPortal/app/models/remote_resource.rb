
#
# CBRAIN Project
#
# Original author: Pierre Rioux
#
# $Id$
#

#Model representing remote services. 
#
#=Attributes:
#[*name*] A string representing a the name of the remote resource.
#[*remote_user*] A string representing a user name to use to access the remote site.
#[*remote_host*] A string representing a the hostname of the remote resource.
#[*remote_port*] An integer representing the port number of the remote resource.
#[*remote_dir*] An string representing the directory of the remote resource.
#[*online*] A boolean value set to whether or not the resource is online.
#[*read_only*] A boolean value set to whether or not the resource is read only.
#[*description*] Text with a description of the remote resource.
#
#= Associations:
#*Belongs* *to*:
#* User
#* Group
class RemoteResource < ActiveRecord::Base

  Revision_info="$Id$"

  validates_uniqueness_of :name
  validates_presence_of   :name, :user_id, :group_id
  validates_format_of     :name, :with  => /^[a-zA-Z0-9][\w\-\=\.\+]*$/,
                                 :message  => 'only the following characters are valid: alphanumeric characters, _, -, =, +, ., ?, !',
                                 :allow_blank => true

  belongs_to  :user
  belongs_to  :group
  has_many    :sync_status

  def site_affiliation
    @site_affiliation ||= self.user.site
  end

  #Returns whether or not this resource can be accessed by +user+.
  def can_be_accessed_by?(user)
      return true if self.user_id == user.id || user.has_role?(:admin)
      return true if user.has_role?(:site_manager) && self.user.site_id == user.site_id
      user.group_ids.include?(group_id)
  end
  
  #Returns whether or not +user+ has owner access to this
  #remote resource.
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
  
  #Find remote resource identified by +id+ accessible by +user+.
  #
  #*Accessible* remote resources  are:
  #[For *admin* users:] any remote resource on the system.
  #[For regular users:] all remote resources that belong to a group to which the user belongs.
  #
  #*Note*: the options hash will accept any of the standard ActiveRecord +find+ parameters
  #except for :conditions which is set internally.
  def self.find_accessible_by_user(id, user, options = {})
    new_options = options.dup
    
    unless user.has_role? :admin
      new_options[:conditions] = ["(remote_resources.group_id IN (?))", user.group_ids]
      
      if user.has_role? :site_manager
        new_options[:joins] = :user
        new_options[:conditions][0] += "OR (users.site_id = ?)"
        new_options[:conditions] << user.site_id
      end
    end
    
    find(id, new_options)
  end
  
  #Find all remote resources accessible by +user+.
  #
  #*Accessible* remote resources  are:
  #[For *admin* users:] any remote resource on the system.
  #[For regular users:] all remote resources that belong to a group to which the user belongs.
  #
  #*Note*: the options hash will accept any of the standard ActiveRecord +find+ parameters
  #except for :conditions which is set internally.
  def self.find_all_accessible_by_user(user, options = {})
    new_options = options.dup
    
    unless user.has_role? :admin
      new_options[:conditions] = ["(remote_resources.group_id IN (?))", user.group_ids]
      
      if user.has_role? :site_manager
        new_options[:joins] = :user
        new_options[:conditions][0] += "OR (users.site_id = ?)"
        new_options[:conditions] << user.site_id
      end
    end
    
    find(:all, new_options)
  end

  #Returns whether or not this resource is active.
  def is_alive?
    false
  end

  # When a remote resource is destroyed, clean up the SyncStatus table
  def after_destroy
    rr_id = self.id
    SyncStatus.find(:all, :conditions => { :remote_resource_id => rr_id }).each do |ss|
      ss.destroy rescue true
    end
    true
  end

end
