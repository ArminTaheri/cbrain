
#
# CBRAIN Project
#
# Validation code for brainportal
#
# Original author: Pierre Rioux
#
# $Id$
#

#=================================================================
# IMPORTANT NOTE : When adding new validation code in this file,
# remember that in deployment there can be several instances of
# the Rails application all executing this code at the same time.
#=================================================================

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


# Traps exceptions likely to happen for system in need of migrations
begin # See the two matching keywords :RESCUE:



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
  
  pwdduh = 'cbrainDuh' # use 9 chars for pretty warning message below.
  User.create!(
    :full_name             => "Admin",
    :login                 => "admin",
    :password              => pwdduh,
    :password_confirmation => pwdduh,
    :email                 => 'admin@here',
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
    user_group = UserGroup.create!(:name  => u.login)
    u.groups  << user_group
    u.save!
  elsif ! user_group.is_a?(UserGroup)
    puts "C> \t- '#{user_group.name}' group migrated to class UserGroup."
    user_group.type = 'UserGroup'
    user_group.save!
  end
  if user_group.users != [u]
    puts "C> \t- '#{user_group.name}' group not used for user '#{u.login}'. Resetting user list."
    user_group.users = [u]
    user_group.save!
  end
  
  unless u.user_preference
    puts "C> \t- User #{u.login} doesn't have a user preference resource. Creating one."
    UserPreference.create!(:user_id => u.id)
  end
end



#-----------------------------------------------------------------------------
puts "C> Ensuring that all sites have a group and that all their users belong to it..."
#-----------------------------------------------------------------------------

Site.all.each do |s|
  site_group = Group.find_by_name(s.name)
  if ! site_group
     puts "C> \t- Site #{s.name} doesn't have their own site group. Creating one."
     site_group = SiteGroup.create!(:name  => s.name, :site_id => s.id)
   elsif ! site_group.is_a?(SiteGroup)
     puts "C> \t- '#{site_group.name}' group migrated to class SiteGroup."
     site_group.type = 'SiteGroup'
     site_group.save!
   end
   if site_group.site != s
     puts "C> \t- '#{site_group.name}' group doesn't have site set to #{s.name}. Resetting it."
     site_group.site = s
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

# This constant is very helpful whenever we want to
# access the info about this very RAILS app.
# Note that SelfRemoteResourceId is used by SyncStatus methods.
CBRAIN::SelfRemoteResourceId = brainportal.id



#-----------------------------------------------------------------------------
puts "C> Checking to see if Data Provider caches need wiping..."
#-----------------------------------------------------------------------------
dp_init_rev    = DataProvider.cache_revision_of_last_init  # will be "0" if unknown
dp_current_rev = DataProvider.revision_info.svn_id_rev
raise "Serious Internal Error: I cannot get a numeric SVN revision number for DataProvider?!?" unless
   dp_current_rev && dp_current_rev =~ /^\d+/
if dp_init_rev.to_i <= 659 # Before Pierre's upgrade
  puts "C> \t- Data Provider Caches are being wiped (Rev: #{dp_init_rev} vs #{dp_current_rev})..."
  puts "C> \t- WARNING: This could take a long time so you should not"
  puts "C> \t  start another instance of this Rails application."
  Dir.chdir(DataProvider.cache_rootdir) do
    Dir.foreach(".") do |entry|
      next unless File.directory?(entry) && entry !~ /^\./
      puts "C> \t\t- Removing old cache subdirectory '#{entry}' ..."
      FileUtils.remove_entry(entry, true) rescue true
    end
  end
  puts "C> \t- Synchronization objects are being wiped..."
  synclist = SyncStatus.find(:all, :conditions => { :remote_resource_id => CBRAIN::SelfRemoteResourceId })
  synclist.each do |ss|
    ss.destroy rescue true
  end
  puts "C> \t- Re-recording DataProvider revision number in cache."
  DataProvider.cache_revision_of_last_init(:force)
  puts "C> \t- Done."
end



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
    if (ss.destroy rescue false)
      ss_deleted += 1
    end
  end
end
if ss_deleted > 0
  puts "C> \t- Removed #{ss_deleted} old SyncStatus objects."
else
  puts "C> \t- No old SyncStatus objects to delete."
end

#-----------------------------------------------------------------------------
puts "C> Ensuring custom filters have a type..."
#-----------------------------------------------------------------------------

if CustomFilter.column_names.include?("type")
  CustomFilter.all.each do |cf|
    if cf.class == CustomFilter
      puts "C> \t- Giving filter #{cf.name} the type 'UserfileCustomFilter'."
      cf.type = 'UserfileCustomFilter'
      cf.save!
    end
  end
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
# :RESCUE: For the cases when the Rails application is started as part of
# a DB migration.
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

end # :RESCUE:
