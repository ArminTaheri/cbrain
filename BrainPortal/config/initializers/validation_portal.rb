
#
# CBRAIN Project
#
# Validation code for brainportal
#
# Original author: Pierre Rioux
#
# $Id$
#

puts "C> Verifying configuration variables..."

Needed_Constants = %w( DataProviderCache_dir )

# Constants
Needed_Constants.each do |c|
  unless CBRAIN.const_defined?(c)
    raise "Configuration error: the CBRAIN constant '#{c}' is not defined! Check 'config_portal.rb'."
  end
end
  
# Run-time checks
unless File.directory?(CBRAIN::DataProviderCache_dir)
  raise "CBRAIN configuration error: data provider cache dir '#{CBRAIN::DataProviderCache_dir}' does not exist!"
end


begin

puts "C> Ensuring that all providers have proper cache subdirectories..."

# Creating cache dir for Data Providers
DataProvider.all.each do |p|
  puts "\t- " + p.name
  begin
    p.mkdir_cache_providerdir
  rescue => e
    unless e.to_s.match(/No caching in this provider/i)
      raise e
    end
  end
end

puts "C> Ensuring that required groups and users have been created..."

unless SystemGroup.find(:first, :conditions  => {:name  => "everyone"})
  puts "C> \t- 'everyone' system group does not exist. Creating it."
  SystemGroup.create!(:name  => "everyone")
end

everyone_group = SystemGroup.find_by_name("everyone")

unless User.find(:first, :conditions => {:login  => 'admin'})
  puts "C> \t- Admin user does not exist yet. Creating one."
  admin_group = SystemGroup.create!(:name  => "admin")
  
  User.create!(
    :full_name       => "Admin",
    :login           => "admin",
    :password  => 'admin',
    :password_confirmation => 'admin',
    :email => 'admin@here',
    :group_ids  => [everyone_group.id, admin_group.id],
    :role => 'admin'
  )
  puts("****************************************************")
  puts("*    USER 'admin' CREATED WITH PASSWORD 'admin'    *")
  puts("*CHANGE THIS PASSWORD IMMEDIATELY AFTER FIRST LOGIN*")
  puts("****************************************************")
end

system_group_name = SystemGroup.all.collect(&:name)

User.find(:all, :include => [:groups, :user_preference]).each do |u|
  unless u.group_ids.include? everyone_group.id
    puts "C> \t- User #{u.login} doesn't belong to group 'everyone'. Adding them."
    groups = u.group_ids
    groups << everyone_group.id
    u.group_ids = groups
    u.save!
  end
  
  unless system_group_name.include? u.login
    puts "C> \t- User #{u.login} doesn't have their own system group. Creating one."
    user_group = SystemGroup.create!(:name  => u.login)
    u.groups  << user_group
  end
  
  unless u.user_preference
    puts "C> \t- User #{u.login} doesn't have a user preference resource. Creating one."
    UserPreference.create!(:user_id => u.id)
  end
end

rescue => error
  if error.to_s.match(/Mysql::Error.*Table.*doesn't exist/i)
    puts "Skipping validation:\n\t- Database table doesn't exist yet. It's likely this system is new and the migrations have not been run yet."
  elsif error.to_s.match(/Unknown database/i)
    puts "Skipping validation:\n\t- System database doesn't exist yet. It's likely this system is new and the migrations have not been run yet."
  else
    raise
  end
end
