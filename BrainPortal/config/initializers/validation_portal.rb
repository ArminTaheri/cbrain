
#
# CBRAIN Project
#
# Validation code for brainportal
#
# Original author: Pierre Rioux
#
# $Id$
#

#-----------------------------------------------------------------------------
puts "C> CBRAIN BrainPortal validation starting, " + Time.now.to_s
#-----------------------------------------------------------------------------
require 'socket'



#-----------------------------------------------------------------------------
puts "C> Verifying configuration variables..."
#-----------------------------------------------------------------------------

Needed_Constants = %w( DataProviderCache_dir )

# Constants
Needed_Constants.each do |c|
  unless CBRAIN.const_defined?(c)
    raise "Configuration error: the CBRAIN constant '#{c}' is not defined!\n" +
          "Check 'config_portal.rb' (and compare it to 'config_portal.rb.TEMPLATE')."
  end
end
  
# Run-time checks
unless File.directory?(CBRAIN::DataProviderCache_dir)
  raise "CBRAIN configuration error: Data Provider cache dir '#{CBRAIN::DataProviderCache_dir}' does not exist!"
end


begin



#-----------------------------------------------------------------------------
puts "C> Ensuring that required groups and users have been created..."
#-----------------------------------------------------------------------------

everyone_group = Group.find_by_name("everyone")
if ! everyone_group
  puts "C> \t- 'everyone' system group does not exist. Creating it."
  everyone_group = SystemGroup.create!(:name  => "everyone")
elsif ! everyone_group.is_a?(SystemGroup)
  puts "C> \t- 'everyone' group migrated to SystemGroup."
  everyone_group.type = 'SystemGroup'
  everyone_group.save!
end

unless User.find(:first, :conditions => {:login  => 'admin'})
  puts "C> \t- Admin user does not exist yet. Creating one."
  admin_group = SystemGroup.create!(:name  => "admin")
  
  pwdduh = 'cbrainDuh' # use 9 chars for pretty warning message below.
  User.create!(
    :full_name             => "Admin",
    :login                 => "admin",
    :password              => pwdduh,
    :password_confirmation => pwdduh,
    :email                 => 'admin@here',
    :group_ids             => [everyone_group.id, admin_group.id],
    :role                  => 'admin'
  )
  puts("******************************************************")
  puts("*  USER 'admin' CREATED WITH PASSWORD '#{pwdduh}'    *")
  puts("* CHANGE THIS PASSWORD IMMEDIATELY AFTER FIRST LOGIN *")
  puts("******************************************************")
end



#-----------------------------------------------------------------------------
puts "C> Ensuring that all users have their own group and belong to 'everyone'..."
#-----------------------------------------------------------------------------

User.find(:all, :include => [:groups, :user_preference]).each do |u|
  unless u.group_ids.include? everyone_group.id
    puts "C> \t- User #{u.login} doesn't belong to group 'everyone'. Adding them."
    groups = u.group_ids
    groups << everyone_group.id
    u.group_ids = groups
    u.save!
  end
  
  user_group = Group.find_by_name(u.login)
  if ! user_group
    puts "C> \t- User #{u.login} doesn't have their own system group. Creating one."
    user_group = SystemGroup.create!(:name  => u.login)
    u.groups  << user_group
    u.save!
  elsif ! user_group.is_a?(SystemGroup)
    puts "C> \t- '#{user_group.name}' group migrated to SystemGroup."
    user_group.type = 'SystemGroup'
    user_group.save!
  end
  
  unless u.user_preference
    puts "C> \t- User #{u.login} doesn't have a user preference resource. Creating one."
    UserPreference.create!(:user_id => u.id)
  end
end



#-----------------------------------------------------------------------------
puts "C> Ensuring that all sites have a group and that all their users belong to it."
#-----------------------------------------------------------------------------

Site.all.each do |s|
  site_group = Group.find_by_name(s.name)
  if ! site_group
     puts "C> \t- Site #{s.name} doesn't have their own system group. Creating one."
     site_group = SystemGroup.create!(:name  => s.name, :site_id => s.id)
   elsif ! site_group.is_a?(SystemGroup)
     puts "C> \t- '#{site_group.name}' group migrated to SystemGroup."
     site_group.type = 'SystemGroup'
     site_group.save!
   end
  
   unless s.user_ids.sort == site_group.user_ids.sort
     puts "C> \t- '#{site_group.name}' group user list does not match site user list. Resetting users."
     site_group.user_ids = s.user_ids
   end
end



#-----------------------------------------------------------------------------
puts "C> Ensuring that all groups have a type..."
#-----------------------------------------------------------------------------

Group.all.each do |g|
  next if g.type
  puts "C> \t- '#{g.name}' group migrated to WorkGroup."
  g.type = 'WorkGroup'
  g.save!
end



#-----------------------------------------------------------------------------
puts "C> Ensuring that userfiles all have a group..."
#-----------------------------------------------------------------------------

missing_gid = Userfile.find(:all, :conditions => { :group_id => nil })
missing_gid.each do |file|
  user   = file.user
  raise "Error: cannot find a user for file '#{file.id}' ?!?" unless user
  ugroup = SystemGroup.find_by_name(user.login)
  raise "Error: cannot find a SystemGroup for user '#{user.login}' ?!?" unless ugroup
  puts "C> \t- Adjusted file '#{file.name}' to group '#{ugroup.name}'."
  file.group = ugroup
  file.save!
end



#-----------------------------------------------------------------------------
puts "C> Ensuring that this RAILS app is registered as a RemoteResource..."
#-----------------------------------------------------------------------------

dp_cache_md5 = DataProvider.cache_md5
brainportal  = BrainPortal.find(:first,
               :conditions => { :cache_md5 => dp_cache_md5 })
unless brainportal
  puts "C> \t- Creating a new BrainPortal record for this RAILS app."
  admin  = User.find_by_login('admin')
  gadmin = Group.find_by_name('admin')
  brainportal = BrainPortal.create!(
                  :name        => "Portal_" + rand(10000).to_s,
                  :user_id     => admin.id,
                  :group_id    => gadmin.id,
                  :online      => true,
                  :read_only   => false,
                  :description => 'CBRAIN BrainPortal on host ' + Socket.gethostname,
                  :cache_md5   => dp_cache_md5 )
  puts "C> \t- NOTE: You might want to use the console and give it a better name than '#{brainportal.name}'."
end

# These two constants are helpful whenever we want to
# access the info about this very RAILS app.
# Note that SelfRemoteResourceId is used by SyncStatus methods.
CBRAIN::SelfRemoteResource   = brainportal
CBRAIN::SelfRemoteResourceId = brainportal.id



#-----------------------------------------------------------------------------
puts "C> Ensuring that all Data Providers have proper cache subdirectories..."
#-----------------------------------------------------------------------------

# Creating cache dir for Data Providers
DataProvider.all.each do |p|
  begin
    p.mkdir_cache_providerdir
    puts "C> \t- Data Provider '#{p.name}': OK."
  rescue => e
    unless e.to_s.match(/No caching in this provider/i)
      raise e
    end
    puts "C> \t- Data Provider '#{p.name}': no need."
  end
end



#-----------------------------------------------------------------------------
puts "C> Starting SSH control channels and tunnels to each Bourreau, if necessary..."
#-----------------------------------------------------------------------------

Bourreau.all.each do |bourreau|
  name = bourreau.name
  if (bourreau.has_remote_control_info? rescue false)
    if bourreau.online
      tunnels_ok = bourreau.start_tunnels
      puts "C> \t- Bourreau '#{name}' channels " + (tunnels_ok ? 'started.' : 'NOT started.')
    else
      puts "C> \t- Bourreau '#{name}' not marked as 'online'."
    end
  else
    puts "C> \t- Bourreau '#{name}' not configured for remote control."
  end
end



#-----------------------------------------------------------------------------
puts "C> Cleaning up old SyncStatus objects..."
#-----------------------------------------------------------------------------

rr_ids = RemoteResource.all.index_by { |rr| rr.id }
ss_deleted = 0
SyncStatus.all.each do |ss|
  ss_rr_id = ss.remote_resource_id
  if ss_rr_id.blank? || ! rr_ids[ss_rr_id]
    ss.destroy rescue true
    ss_deleted += 1
  end
end
if ss_deleted > 0
  puts "C> \t- Removed #{ss_deleted} old SyncStatus objects."
else
  puts "C> \t- No old SyncStatus objects to delete."
end



##-----------------------------------------------------------------------------
#puts "C> Checking that size variables for userfiles are properly set... "
##-----------------------------------------------------------------------------
## The following line is just to trigger an exception for "Unknown column"
## if we've not yet migrated userfiles to contain 'num_files'
#Userfile.find(:first, :conditions => { :num_files => 123456 })
#Userfile.all.each do |u|
#  unless u.size_set?
#    puts "C> \t- #{u.type} #{u.name} (id: #{u.id}) does not have its size properly set. Updating..."
#    u.set_size
#  end
#end


#-----------------------------------------------------------------------------
rescue => error
  if error.to_s.match(/Mysql::Error.*Table.*doesn't exist/i)
    puts "Skipping validation:\n\t- Database table doesn't exist yet. It's likely this system is new and the migrations have not been run yet."
  elsif error.to_s.match(/Mysql::Error: Unknown column/i)
    puts "Skipping validation:\n\t- Some database table is missing a column. It's likely that migrations aren't up to date yet."
  elsif error.to_s.match(/Unknown database/i)
    puts "Skipping validation:\n\t- System database doesn't exist yet. It's likely this system is new and the migrations have not been run yet."
  else
    raise
  end
end
