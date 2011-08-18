
#
# CBRAIN Project
#
# Group model
#
# Original author: Tarek Sherif
#
# $Id$
#

#Model representing the Group resource. Groups are meant to represented collective access
#to certain files (analogous to groups of the Unix OS).
#
#=Attributes:
#[*name*] A string representing the name of the group.
#= Associations:
#*Has* *and* *belongs* *to* *many*:
#* User
#*Has* *many*:
#* Userfile
#* DataProvider
#* RemoteResource
#=Dependencies
#[<b>On Destroy</b>] All Userfile, RemoteResource and DataProvider
#                    associated with the group being destroyed will
#                    have their group set to their owner's SystemGroup.
class Group < ActiveRecord::Base

  Revision_info=CbrainFileRevision[__FILE__]

  before_save             :set_default_creator
  after_destroy           :reassign_models_to_owner_group
  
  validates_presence_of   :name
  validates_uniqueness_of :name, :scope => :creator_id
  validate                :validate_groupname
  
  has_many                :tools
  has_and_belongs_to_many :users 
  has_many                :userfiles
  has_many                :data_providers 
  has_many                :remote_resources
  has_many                :cbrain_tasks
  has_many                :tags
  belongs_to              :site

  # Returns the unique and special group 'everyone'
  def self.everyone
    @everyone ||= SystemGroup.find_by_name('everyone')
  end

  # Returns itself; this method is here to make it symetrical
  # with other resource classes such as User and Site, which
  # both have a meaningful own_group() method.
  def own_group
    self
  end

  def can_be_accessed_by?(user, access_requested = :read) #:nodoc:
    @can_be_accessed_cache       ||= {}
    @can_be_accessed_cache[user] ||= (user.has_role?(:admin) || user.is_member_of_group(self))
  end
  
  #Can this group be edited by +user+?
  #
  #Returns false in general. Should be overidden in subclasses
  #in cases where editing is possible.
  def can_be_edited_by?(user)
    false
  end

  # Returns a 'group category name' as seen by +as_user+.
  def pretty_category_name(as_user)
    self.class.to_s.underscore.titleize.sub(/group/i,"Project")
  end

  # Returns true of +name+ is a legal group name. Also called
  # by active record validations.
  def self.is_legal_groupname?(name)
    return true if name && name.match(/^[a-zA-Z0-9][ \w\~\!\@\#\%\^\*\-\+\=\:\;\,\.\?]*$/)
    false
  end

  # ActiveRecord validation.
  def validate_groupname #:nodoc:
    unless Group.is_legal_groupname?(self.name)
      errors.add(:name, "contains invalid characters.")
    end
  end

  private
  
  #Set creator id if it's not set.
  def set_default_creator #:nodoc:
    admin_user = User.find_by_login("admin")
    if self.creator_id.nil? && admin_user #if admin doesn't exist it should mean that it's a new system.
      self.creator_id = admin_user.id
    end
  end
  
  def reassign_models_to_owner_group #:nodoc:
    group_has_many_model_list = Group.reflect_on_all_associations.select { |a| a.macro == :has_many }.map { |a| a.name }
    objlist = group_has_many_model_list.inject([]) { |list,modsym| list += self.send(modsym) }
    user_id_to_own_group_id = {}
    objlist.each do |obj|
      own_group_id = user_id_to_own_group_id[obj.user_id] ||= obj.user.own_group.id
      obj.update_attributes!( :group_id => own_group_id )
    end
  end

end
