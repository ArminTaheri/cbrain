
#
# CBRAIN Project
#
# Runtime system checks common to both Portal and Bourreau
#
# $Id$
#

class CbrainSystemChecks < CbrainChecker
  
  Revision_info=CbrainFileRevision[__FILE__]

  # First thing first: identify which RemoteResource object
  # represents the current Rails application.
  def self.a002_ensure_Rails_can_find_itself

    #-----------------------------------------------------------------------------
    puts "C> Ensuring that this CBRAIN app is registered in the DB..."
    #-----------------------------------------------------------------------------

    myname       = ENV["CBRAIN_RAILS_APP_NAME"]
    myname     ||= CBRAIN::CBRAIN_RAILS_APP_NAME if CBRAIN.const_defined?('CBRAIN_RAILS_APP_NAME')
    mytype       = Rails.root.to_s =~ /BrainPortal$/ ? "BrainPortal" : "Bourreau"
    myshorttype  = Rails.root.to_s =~ /BrainPortal$/ ? "portal"      : "bourreau"
    if myname.blank?
      puts "C> \t- No name given to this #{mytype} Rails application."
      puts "C> \t  Please edit 'config/initializers/config_#{myshorttype}.rb' and"
      puts "C> \t  give it a name by setting the value of 'CBRAIN_RAILS_APP_NAME'."
      if mytype == "Bourreau" && CBRAIN.const_defined?('BOURREAU_CLUSTER_NAME')
        puts "C> \t- It seems you already have a value set in the old constant"
        puts "C> \t  'BOURREAU_CLUSTER_NAME' with value '#{CBRAIN::BOURREAU_CLUSTER_NAME}';"
        puts "C> \t  you can start by renaming that variable's name (not value!) to"
        puts "C> \t  'CBRAIN_RAILS_APP_NAME', as it probably has the name we're"
        puts "C> \t  looking for, then restarting this application and following"
        puts "C> \t  the instructions that will appear. This will upgrade your"
        puts "C> \t  configuration."
      end
      show_portals_list(mytype)
      Kernel.exit(1)
    end

    # Find myself.
    rr = Class.const_get(mytype).find_by_name(myname)

    if rr
      # The most important global assignment in the CBRAIN system!
      CBRAIN.const_set("SelfRemoteResourceId",rr.id)
      rr.update_attributes( :online    => true )
      return true # everything OK
    end

    if mytype == "BrainPortal"
      puts "C> \t- BrainPortal named '#{myname} is not registered in database, please run"
      puts "C> \t  this command: 'rake db:sanity:check RAILS_ENV=#{Rails.env}'."
    else
      puts "C> \t- Bourreau named '#{myname} is not registered in database, please add"
      puts "C> \t  it using the interface, or check the value of 'CBRAIN_RAILS_APP_NAME' in"
      puts "C> \t  'config/initializers/config_#{myshorttype}.rb'"
    end
      show_portals_list(mytype)
      Kernel.exit(1)
  end



  # Checks for a proper timezone configuration in Rails' environment.
  def self.a009_check_time_zone_configuration

    #-----------------------------------------------------------------------------
    puts "C> Setting time zone for application..."
    #-----------------------------------------------------------------------------
    
    myself = RemoteResource.current_resource
    my_time_zone = myself.time_zone

    if my_time_zone.blank? || ActiveSupport::TimeZone[my_time_zone].blank?
      puts "C> \t- Warning: time zone not set properly for this Rails app, setting it to UTC."
      my_time_zone = 'UTC'
      myself.time_zone = my_time_zone
      myself.save
    else
      puts "C> \t- Time zone set to '#{my_time_zone}'."
    end

    if myself.is_a? BrainPortal
      CbrainRailsPortal::Application.config.time_zone = my_time_zone
    elsif myself.is_a? Bourreau
      CbrainRailsBourreau::Application.config.time_zone = my_time_zone
    end
    Time.zone = my_time_zone

  end
  


  def self.a050_check_data_provider_cache_wipe

    #-----------------------------------------------------------------------------
    puts "C> Checking to see if Data Provider caches need wiping..."
    #-----------------------------------------------------------------------------

    myself = RemoteResource.current_resource

    cache_root     = DataProvider.cache_rootdir rescue nil
    if cache_root.blank?
      puts "C> \t- SKIPPING! No cache root directory yet configured!"
      return
    end

    DataProvider.revision_info.self_update # just to make sure we have it
    dp_disk_rev = DataProvider.cache_revision_of_last_init rescue nil # will be "Unknown" if unknown, nil if erroneous
    dp_code_rev = DateTime.parse("#{DataProvider.revision_info.date} #{DataProvider.revision_info.time}") rescue nil
    dp_need_rev = DateTime.parse(DataProvider::DataProviderCache_RevNeeded) rescue nil

    raise "Serious Internal Error: I cannot get a 'code' DateTime revision value for DataProvider?!?" unless
      dp_code_rev.is_a?(DateTime)
    raise "Serious Internal Error: I cannot get a 'need' DateTime revision value from DataProvider hardcoded constant?!?" unless
      dp_need_rev.is_a?(DateTime)
    raise "Serious Internal Error: DataProvider 'code' DateTime (#{dp_code_rev.inspect}) is earlier than 'need' DateTime (#{dp_need_rev.inspect}) ?!?" if
      dp_code_rev < dp_need_rev

    if dp_disk_rev.nil? # NIL check important, see method above
      puts "C> \t- SKIPPING! Cache root directory '#{cache_root}' is invalid! Fix with the interface, please."
      return
    end

    cache_dir_mode = File.stat(cache_root).mode
    if (cache_dir_mode & 0777) != 0700
      puts "C> \t- WARNING! Cache root directory '#{cache_root}' has invalid permissions #{sprintf("%4.4o",cache_dir_mode & 0777)}. Fixing to 0700."
      File.chmod(0700,cache_root)
    end

    if ( ! dp_disk_rev.is_a?(DateTime) ) || dp_disk_rev < dp_need_rev # Before Pierre's upgrade
      puts "C> \t- Data Provider Caches need to be wiped..."
      puts "C> \t  Disk Rev: '#{dp_disk_rev.inspect}'"
      puts "C> \t  Need Rev: '#{dp_need_rev.inspect}'"
      puts "C> \t  Code Rev: '#{dp_code_rev.inspect}'"
      puts "C> \t- WARNING: This could take a long time so you should not"
      puts "C> \t  start another instance of this Rails application."
      Dir.chdir(cache_root) do
        Dir.foreach(".") do |entry|
          next unless File.directory?(entry) && entry =~ /^\d\d+$/ # only subdirectories named '00', '123' etc
          newname = ".#{entry}_being_deleted.#{Process.pid}"
          renamed_ok = File.rename(entry,newname) rescue false
          if renamed_ok
            puts "C> \t\t- Removing old cache subdirectory '#{entry}' in background..."
            system("/bin/rm -rf '#{newname}' </dev/null &")
          end
        end
      end
      puts "C> \t- Synchronization objects are being wiped..."
      synclist = SyncStatus.where( :remote_resource_id => myself.id )
      synclist.each do |ss|
        ss.destroy rescue true
      end
      puts "C> \t- Re-recording DataProvider 'code' DateTime in cache."
      DataProvider.cache_revision_of_last_init(:force)
    end

    md5 = DataProvider.cache_md5 rescue nil
    if md5 && myself.cache_md5 != md5
      puts "C> \t- Re-recording DataProvider MD5 ID in database."
      myself.update_attributes( :cache_md5 => md5 )
    end
  end



  def self.a080_ensure_set_starttime_revision

    # Global for the whole Rails process
    $CBRAIN_StartTime_Revision = RemoteResource.current_resource.info.revision

    #-----------------------------------------------------------------------------
    puts "C> Current application tag or revision: #{$CBRAIN_StartTime_Revision}"
    #-----------------------------------------------------------------------------

  end

  private

  # Shows a list of currently configured BrainPortals
  def self.show_portals_list(type) #:nodoc:
    portals = Class.const_get(type).all
    return if portals.size == 0
    puts "C> \t- Note: there are already #{portals.size} #{type} records registered:"
    portals.each do |p|
      puts "C> \t\t- #{type} record named '#{p.name}' was created #{p.created_at}"
    end
    puts "C> \t- It's possible you need to set the value of CBRAIN_RAILS_APP_NAME to"
    puts "C> \t  #{portals.size > 1 ? "one of these names." : "this name."}"
  end

  def self.move_old_config_vars(bourreau_or_portal_keyword,varname_to_method) #:nodoc:

    find_some_old = varname_to_method.keys.select { |c| CBRAIN.const_defined?(c) }
    return unless find_some_old.size > 0

    puts "C> Configuration error: found some old configuration constants in"
    puts "C> 'config/initializers/config_#{bourreau_or_portal_keyword}.rb':"
    find_some_old.each do |c|
      puts "C> \t- No longer needed: '#{c}'"
    end
    puts "C> We will now try to propagate the values of these variables to"
    puts "C> the database."

    myself = RemoteResource.current_resource
    
    conflicts = []

    find_some_old.each do |c|
      method = varname_to_method[c]
      next unless method
      puts "C> \t- Checking value for constant '#{c}'..."
      old = myself.send(method)
      new = CBRAIN.const_get(c)
      if old && old != new
        puts "C> \t\t- Value of '#{c}' already set in DB, not overridding."
        puts "C> \t\t  WARNING: Values differ! DB=#{old.inspect}, FILE=#{new.inspect}"
        conflicts << c
      else
        puts "C> \t\t- Value of '#{c}' recorded for DB."
        myself.attributes = { method => new }
      end
    end

    puts "C> Preparing to save new DB record..."
    myself.save!
    puts "C> Success!"

    puts "C> Please remove the old constants from the config file now."

    if conflicts.size > 0
      puts "C> IMPORTANT NOTE: The values for some variables, as seen in the"
      puts "C> file 'config/initializers/config_#{bourreau_or_portal_keyword}.rb',"
      puts "C> were not transfered to the DB as they conflict with values"
      puts "C> already present there. Here are the variable names:"
      conflicts.each do |c|
        puts "C> \t- #{c}"
      end
      puts "C> Please double check those values with the CBRAIN interface"
      puts "C> before removing the constants from the config file."
    end

    raise "Configuration error: old constants still active. Exiting."
  end

end 
