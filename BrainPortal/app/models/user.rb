
#
# CBRAIN Project
#
# User model
#
# Original author: restful authentication plugin
# Modified by: Tarek Sherif
#
# $Id$
#

require 'digest/sha1'

#Model representing CBrain users. 
#All authentication of user access to the system is handle by the User model.
#User level access to pages are handled through a given user's +role+ (either *admin* or *user*).
#
#=Attributes:
#[*full_name*] The full name of the user.
#[*login*] The user's login ID.
#[*email*] The user's e-mail address.
#[*role*]  The user's role.
#= Associations:
#*Has* *many*:
#* Userfile
#* CustomFilter
#* Tag
#* Feedback
#*Has* *and* *belongs* *to* *many*:
#* Group
#
#=Dependencies
#[<b>On Destroy</b>] A user cannot be destroyed if it is still associated with any
#                    Userfile, RemoteResource or DataProvider resources.
#                    Destroying a user will destroy the associated 
#                    Tag, Feedback and CustomFilter resources.
class User < ActiveRecord::Base

  Revision_info=CbrainFileRevision[__FILE__]

  # Virtual attribute for the unencrypted password
  attr_accessor :password #:nodoc:

  validates_presence_of     :full_name, :login, :email, :role
  validates_presence_of     :password,                   :if => :password_required?
  validates_presence_of     :password_confirmation,      :if => :password_required?
  validates_length_of       :password, :within => 4..40, :if => :password_required?
  validates_confirmation_of :password,                   :if => :password_required?
  validates_length_of       :login,    :within => 3..40
  validates_length_of       :email,    :within => 3..100
  validates_uniqueness_of   :login, :case_sensitive => false
  validate                  :prevent_group_collision,    :on => :create
  validate                  :immutable_login,            :on => :update
  validate                  :site_manager_check
  
  before_create              :add_system_groups
  before_save               :encrypt_password
  after_update              :system_group_site_update
  before_destroy            :validate_destroy
  after_destroy             :destroy_user_sessions
    
  # prevents a user from submitting a crafted form that bypasses activation
  # anything else you want your user to change should be added here.
  attr_accessible :full_name, :email, :password, :password_confirmation, :time_zone, :city, :country

  # The following resources PREVENT the user from being destroyed if some of them exist.
  has_many                :userfiles
  has_many                :data_providers
  has_many                :remote_resources
  has_many                :cbrain_tasks
  has_and_belongs_to_many :groups   
  belongs_to              :site

  # The following resources are destroyed automatically when the user is destroyed.
  has_many                :messages,        :dependent => :destroy
  has_many                :tools,           :dependent => :destroy
  has_many                :tags,            :dependent => :destroy
  has_many                :feedbacks,       :dependent => :destroy
  has_many                :custom_filters,  :dependent => :destroy

  force_text_attribute_encoding 'UTF-8', :full_name, :city, :country
  
  #Return the admin user
  def self.admin
    @admin ||= self.find_by_login("admin")
  end
  
  #Return all users with role 'admin'
  def self.all_admins
    @all_admins ||= self.find_all_by_role("admin")
  end
  
  # Authenticates a user by their login name and unencrypted password.  Returns the user or nil.
  def self.authenticate(login, password)
    u = find_by_login(login) # need to get the salt
    return nil unless u && u.authenticated?(password)
    u.last_connected_at = Time.now
    u.save
    u
  end
  
  #Create a random password (to be sent for resets).
  def set_random_password
    s = random_string
    self.password = s
    self.password_confirmation = s
  end

  # Encrypts some data with the salt.
  def self.encrypt(password, salt) #:nodoc:
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end

  # Encrypts the password with the user salt
  def encrypt(password) #:nodoc:
    self.class.encrypt(password, salt)
  end

  def authenticated?(password) #:nodoc:
    crypted_password == encrypt(password)
  end

  def remember_token? #:nodoc:
    remember_token_expires_at && Time.now.utc < remember_token_expires_at 
  end

  # These create and unset the fields required for remembering users between browser closes.
  def remember_me #:nodoc:
    remember_me_for 2.weeks
  end

  def remember_me_for(time) #:nodoc:
    remember_me_until time.from_now.utc
  end

  def remember_me_until(time) #:nodoc:
    self.remember_token_expires_at = time
    self.remember_token            = encrypt("#{email}--#{remember_token_expires_at}")
    save(:validate => false)
  end

  def forget_me #:nodoc:
    self.remember_token_expires_at = nil
    self.remember_token            = nil
    save(:validate => false)
  end

  # Returns true if the user has just been activated.
  def recently_activated? #:nodoc:
    @activated
  end
  
  #Does this user's role match +role+?
  def has_role?(role)
    return self.role == role.to_s
  end
  
  #Find the tools that this user has access to.
  def available_tools(options = {})
    if self.has_role? :admin
      Tool.scoped(options)
    elsif self.has_role? :site_manager
      Tool.scoped(options).where( ["tools.user_id = ? OR tools.group_id IN (?) OR tools.user_id IN (?)", self.id, self.group_ids, self.site.user_ids])
    else
      Tool.scoped(options).where( ["tools.user_id = ? OR tools.group_id IN (?)", self.id, self.group_ids])
    end
  end
  
  #Find the scientific tools that this user has access to.
  def available_scientific_tools(options = {})
    self.available_tools(options).where( :category  => "scientific tool" ).order( "tools.select_menu_text" )
  end
  
  #Find the conversion tools that this user has access to.
  def available_conversion_tools(options = {})
    self.available_tools(options).where( :category  => "conversion tool" ).order( "tools.select_menu_text" )
  end
  
  #Return the list of groups available to this user based on role.
  def available_groups(options = {})
    if self.has_role? :admin
      group_scope = Group.where(options)
    elsif self.has_role? :site_manager
      group_scope = Group.where(options)
      group_scope = group_scope.where(["groups.id IN (select groups_users.group_id from groups_users where groups_users.user_id=?) OR groups.site_id=?", self.id, self.site_id])
      group_scope = group_scope.where("groups.name <> 'everyone'")
      group_scope = group_scope.where(["groups.type NOT IN (?)", InvisibleGroup.descendants.map(&:to_s).push("InvisibleGroup") ])      
    else                  
      group_scope = self.groups.where(options)
      group_scope = group_scope.where("groups.name <> 'everyone'")
      group_scope = group_scope.where(["groups.type NOT IN (?)", InvisibleGroup.descendants.map(&:to_s).push("InvisibleGroup") ])
    end
    
    group_scope
  end
  
  def available_tags(options = {})
    Tag.where(options).where( ["tags.user_id=? OR tags.group_id IN (?)", self.id, self.group_ids] )
  end
  
  def available_tasks(options = {})
    if self.has_role? :admin
      CbrainTask.where(options)
    elsif self.has_role? :site_manager
      CbrainTask.where(options).where( ["cbrain_tasks.user_id = ? OR cbrain_tasks.group_id IN (?) OR cbrain_tasks.user_id IN (?)", self.id, self.group_ids, self.site.user_ids] )
    else
      CbrainTask.where(options).where( ["cbrain_tasks.user_id = ? OR cbrain_tasks.group_id IN (?)", self.id, self.group_ids] )
    end
  end
  
  #Return the list of users under this user's control based on role.
  def available_users(options = {})
    if self.has_role? :admin
      user_scope = User.where(options)
    elsif self.has_role? :site_manager
      user_scope = self.site.users.where(options)
    else
      user_scope = User.where( :id => self.id ).where(options)
    end
    
    user_scope
  end

  def can_be_accessed_by?(user, access_requested = :read) #:nodoc:
    return true if user.has_role? :admin
    return true if user.has_role?(:site_manager) && self.site_id == user.site_id
    self.id == user.id
  end
  
  # Returns the SystemGroup associated with the user; this is a
  # group with the same name as the user.
  def system_group
    @own_group ||= UserGroup.where( :name => self.login ).first
  end

  # An alias for system_group()
  alias own_group system_group

  # Returns true if the user belongs to the +group_id+ (or a Group)
  def is_member_of_group(group_id)
     group_id = group_id.id if group_id.is_a?(Group)
     @group_ids_hash ||= self.group_ids.index_by { |gid| gid }
     @group_ids_hash[group_id] ? true : false
  end

  # Destroy all sessions for user 
  def destroy_user_sessions
    myid = self.id
    return true unless myid # defensive
    sessions = CbrainSession.all.select do |s|
      data = s.data rescue {} # old sessions can have problems being reconstructed
      (s.user_id && s.user_id == myid) ||
      (data && data[:user_id] && data[:user_id] == myid)
    end
    sessions.each do |s|
      s.destroy rescue true
    end
    true
  end

  protected

  # before filter 
  def encrypt_password #:nodoc:
    return if password.blank?
    self.salt = Digest::SHA1.hexdigest("--#{Time.now.to_s}--#{login}--") if new_record?
    self.crypted_password = encrypt(password)
  end
    
  def password_required? #:nodoc:
    crypted_password.blank? || !password.blank?
  end

  private
  
  #Create a random string (currently for passwords).
  def random_string
    length = rand(5) + 6
    s = ""
    length.times do
      c = rand(75) + 48
      c += 1 if c == 96
      s << c
    end
    s
  end
   
  def prevent_group_collision #:nodoc:
    if self.login && SystemGroup.find_by_name(self.login)
      errors.add(:login, "already in use by an existing project.")
    end
  end
  
  def immutable_login #:nodoc:
    if self.changed.include? "login"
      errors.add(:login, "is immutable.")
    end
  end
  
  #Ensure that the system will be in a valid state if this user is destroyed.
  def validate_destroy
    if self.login == 'admin'
      cb_error "Default admin user cannot be destroyed.", :redirect  => {:action  => :index}
    end
    unless self.userfiles.empty?
      cb_error "User #{self.login} cannot be destroyed while there are still files on the account.", :redirect  => {:action  => :index}
    end
    unless self.data_providers.empty?
      cb_error "User #{self.login} cannot be destroyed while there are still data providers on the account.", :redirect  => {:action  => :index}
    end
    unless self.remote_resources.empty?
      cb_error "User #{self.login} cannot be destroyed while there are still remote resources on the account.", :redirect  => {:action  => :index}
    end
    unless self.cbrain_tasks.empty?
      cb_error "User #{self.login} cannot be destroyed while there are still tasks on the account.", :redirect  => {:action  => :index}
    end
    destroy_system_group
  end
  
  def system_group_site_update  #:nodoc:
    self.own_group.update_attributes(:site_id => self.site_id)
    
    if self.changed.include?("site_id")
      unless self.changes["site_id"].first.blank?
        old_site = Site.find(self.changes["site_id"].first)
        old_site.own_group.users.delete(self)
      end
      unless self.changes["site_id"].last.blank?
        new_site = Site.find(self.changes["site_id"].last)
        new_site.own_group.users << self
      end
    end
  end
  
  def site_manager_check  #:nodoc:
    if self.role == "site_manager" && self.site_id.blank?
      errors.add(:site_id, "manager role must be associated with a site.")
    end
  end
  
  def destroy_system_group #:nodoc:
    system_group = SystemGroup.where( :name => self.login ).first
    system_group.destroy if system_group
  end
  
  def add_system_groups #:nodoc:
    userGroup = UserGroup.new(:name => self.login, :site  => self.site)
    userGroup.save!
    
    everyoneGroup = Group.everyone
    group_ids = self.group_ids
    group_ids << userGroup.id
    group_ids << everyoneGroup.id
    if self.site
      site_group = SiteGroup.find_by_name(self.site.name)
      group_ids << site_group.id
    end
    self.group_ids = group_ids
  end

end
