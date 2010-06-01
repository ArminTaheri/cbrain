
#
# CBRAIN Project
#
# $Id$
#

require 'fileutils'
require 'pathname'
require 'socket'
require 'digest/md5'

#
# = Data Provider interface
#
# This abstract class describe an external 'data provider'
# for CBRAIN files.
#
# A data provider models a pair of endpoints: the *provider* side
# is where files are stored permanently, while the *cache* side
# is where files are stored in transit to being created and accessed.
# Typically, the *provider* side is a remote host or service, while
# the *cache* side is a filesystem local to the Rails application.
# Most programming tasks requires calling the methods on the *cache* side.
#
# Most API methods work on a Userfile object, which provides a
# name and a user ID for the object that are used to represent
# its content as a file. Since Userfiles have a data provider
# associated with them, this means that renaming a userfile +u+ would
# involve these steps:
#
#    data_provider_id = u.data_provider_id
#    data_provider    = DataProvider.find(data_provider_id)
#    data_provider.provider_rename(u,"newname")
#
# However, two shorthands can be used:
#
# * Use Rails's ability to link models directly:
#
#    u.data_provider.provider_rename(u,"newname")
#
# * Use the fact that the Userfile model has already been extended to provide access to the DataProvider methods directly:
#
#    u.provider_rename("newname")   # note that u is no longer supplied in argument
#
# == The API to write new files
#
# A typical scenario to *create* a new userfile and store its
# content (the string "ABC") on the provider looks like this:
#
#    u = SingleFile.new( :user_id => 2, :data_provider_id => 3, :name => "filename" )
#    u.cache_writehandle do |fh|
#      fh.write("ABC")   
#    done
#    u.save
#
# Note that when the block provided to cache_writehandle() ends, a
# sync to the provider is automatically performed.
#
# Alternatively, if the content "ABC" of the file comes from another local
# file +localfile+, then the code can be rewritten as:
#
#    u = SingleFile.new( :user_id => 2, :data_provider_id => 3, :name => "filename" )
#    u.cache_copy_from_local_file(localfile)
#    u.save
#
# == The API to read files
#
# A typical scenario to *read* data from a userfile +u+ looks like this:
#
#    u.cache_readhandle do |fh|
#      data = fh.read
#    done
#
# Alternatively, if the data is to be sent to a local file +localfile+, then
# the code can be rewritten simply as:
#
#    u.cache_copy_to_local_file(localfile)
#
# == Handling FileCollections content
#
# The cache_readhandle() and cache_writehandle() methods *cannot* be used
# to access FileCollections, as these are modeled on the filesystem by
# subdirectories. However, the methods cache_copy_to_local_file() and
# cache_copy_from_local_file() will work perfectly well, assuming that
# the +localfile+ they are given in argument is itself a local subdirectory.
#
# When creating new FileCollections, the cache_prepare() method should be
# called once first, then the cache_full_path() can be used to obtain
# a full path to the subdirectory where the collection will be created
# (note that the subdirectory itself will not be created for you).
#
# = Here is the complete list of API methods:
#
# == Status methods:
#
# * is_alive?
# * is_alive!
# * is_browsable?
# * is_fast_syncing?
#
# == Access restriction methods:
#
# * can_be_accessed_by?(user)  # user is a User object
# * has_owner_access?(user)    # user is a User object
#
# == Synchronization methods:
#
# * sync_to_cache(userfile)
# * sync_to_provider(userfile)
#
# Note that both of these are also present in the Userfile model.
#
# == Cache-side methods:
#
# * cache_prepare(userfile)
# * cache_full_path(userfile)
# * cache_readhandle(userfile)
# * cache_writehandle(userfile)
# * cache_copy_from_local_file(userfile,localfilename)
# * cache_copy_to_local_file(userfile,localfilename)
# * cache_erase(userfile)
#
# Note that all of these are also present in the Userfile model.
#
# == Provider-side methods:
#
# * provider_erase(userfile)
# * provider_rename(userfile,newname)
# * provider_move_to_otherprovider(userfile,otherprovider)
# * provider_copy_to_otherprovider(userfile,otherprovider)
# * provider_list_all(user=nil)
#
# Note that all of these except for provider_list_all() are
# also present in the Userfile model.
#
# = Aditional notes
#
# Most methods raise an exception if the provider's +online+ attribute is
# false, or if trying to perform some write operation and the provider's
# +read_only+ attribute is true.
#
# None of the methods issue a save() operation on the +userfile+
# they are given in argument; this means that after a successful
# provider_rename(), provider_move_to_otherprovider() or
# provider_copy_to_otherprovider(), the caller must call
# the save() method explicitely.
#
# = Implementations In Subclasses
#
# A proper implementation in a subclass must have the following
# methods defined:
#
# * impl_is_alive?
# * impl_sync_to_cache(userfile)
# * impl_sync_to_provider(userfile)
# * impl_provider_erase(userfile)
# * impl_provider_rename(userfile,newname)
# * impl_provider_list_all(user=nil)
#
# =Attributes:
# [*name*] A string representing a the name of the data provider.
# [*remote_user*] A string representing a user name to use to access the remote site of the provider.
# [*remote_host*] A string representing a the hostname of the data provider.
# [*remote_port*] An integer representing the port number of the data provider.
# [*remote_dir*] An string representing the directory of the data provider.
# [*online*] A boolean value set to whether or not the provider is online.
# [*read_only*] A boolean value set to whether or not the provider is read only.
# [*description*] Text with a description of the data provider.
# 
# = Associations:
# *Belongs* *to*:
# * User
# * Group
# *Has* *many*:
# * UserPreference
class DataProvider < ActiveRecord::Base

  Revision_info="$Id$"
  
  include ResourceAccess

  belongs_to  :user
  belongs_to  :group
  has_many    :user_preferences,  :dependent => :nullify
  has_many    :userfiles

  validates_uniqueness_of :name
  validates_presence_of   :name, :user_id, :group_id
  validates_inclusion_of :read_only, :in => [true, false]

  validates_format_of     :name, :with  => /^[a-zA-Z0-9][\w\-\=\.\+]*$/,
    :message  => 'only the following characters are valid: alphanumeric characters, _, -, =, +, ., ?, and !',
    :allow_blank => true
                                 
  validates_format_of     :remote_user, :with => /^\w[\w\-\.]*$/,
    :message  => 'only the following characters are valid: alphanumeric characters, _, -, and .',
    :allow_blank => true

  validates_format_of     :remote_host, :with => /^\w[\w\-\.]*$/,
    :message  => 'only the following characters are valid: alphanumeric characters, _, -, and .',
    :allow_blank => true

  validates_format_of     :remote_dir, :with => /^[\w\-\.\=\+\/]*$/,
    :message  => 'only paths with simple characters are valid: a-z, A-Z, 0-9, _, +, =, . and of course /',
    :allow_blank => true

  before_destroy          :validate_destroy
  
  # These DataProvider subclasses don't use the owner's login in their organizational structures, so 
  # changing the owner of a Userfile stored on them won't cause any problems.
  ALLOW_FILE_OWNER_CHANGE = ["SshDataProvider", "EnCbrainSmartDataProvider", "EnCbrainLocalDataProvider", "EnCbrainSshDataProvider"]

  # A class to represent a file accessible through SFTP or available locally.
  # Most of the attributes here are compatible with
  #   Net::SFTP::Protocol::V01::Attributes
  class FileInfo
    attr_accessor :name, :symbolic_type, :size, :permissions,
                  :uid, :gid, :owner, :group,
                  :atime, :mtime, :ctime
    
    def depth
      return @depth if @depth
      cb_error "File doesn't have a name." if self.name.blank?
      count = -1
      Pathname.new(self.name).cleanpath.descend{ count += 1}
      @depth = count
      @depth
    end
  end



  #################################################################
  # Official Data API methods (work on userfiles)
  #      - Provider query/access methods -
  #################################################################
  
  # This method must not block, and must respond quickly.
  # Returns +true+ or +false+.
  def is_alive?
    return false if self.online == false
    
    #set time of death or set to offline is past 1 hour
    alive_flag = impl_is_alive?

    unless alive_flag
      self.time_of_death ||= Time.now
      if self.time_of_death < 2.minutes.ago
        self.time_of_death = Time.now
      elsif self.time_of_death < Time.now
        self.online = false
      end
      self.save
      return false
    end

    #reset time of death 
    if alive_flag
      self.time_of_death = nil 
      self.save
      return true
    end

    cb_error "Error: is_alive? is returning a non truth that is true" 
  end

  # Raises an exception if is_alive? is +false+, otherwise
  # it returns +true+.
  def is_alive!
    cb_error "Error: data provider is not accessible right now." unless self.is_alive?
    true
  end

  # This method returns true if the provider is 'browsable', that is
  # you can call provider_list_all() without fear of an exception.
  # Most data providers are not browsable.
  def is_browsable?
    false
  end
  
  # This predicate returns whether syncing from the current provider
  # is considered a negligeable operation. e.g. if the provider is local to the portal.
  #
  # For the base DataProvider class this returns false. For subclasses, this method
  # should be redefined to return +true+ if the given DataProvider is fast-syncing.
  def is_fast_syncing?
    false
  end
  
  def allow_file_owner_change? #:nodoc:
    ALLOW_FILE_OWNER_CHANGE.include? self.class.name
  end



  #################################################################
  # Official Data API methods (work on userfiles)
  #            - Synchronization -
  #################################################################
  
  # Synchronizes the content of +userfile+ as stored
  # on the provider into the local cache.
  def sync_to_cache(userfile)
    cb_error "Error: provider is offline." unless self.online
    SyncStatus.ready_to_copy_to_cache(userfile) do
      impl_sync_to_cache(userfile)
    end
  end

  # Synchronizes the content of +userfile+ from the
  # local cache back to the provider.
  def sync_to_provider(userfile)
    cb_error "Error: provider is offline."   unless self.online
    cb_error "Error: provider is read_only." if     self.read_only
    SyncStatus.ready_to_copy_to_dp(userfile) do
      impl_sync_to_provider(userfile)
    end
  end



  #################################################################
  # Official Data API methods (work on userfiles)
  #            - Cache Side Methods -
  #################################################################
  
  # Makes sure the local cache is properly configured
  # to receive the content for +userfile+; usually
  # this method is called before writing the content
  # for +userfile+ into the cached file or subdirectory.
  # Note that this method is already called for you
  # when invoking cache_writehandle(userfile).
  def cache_prepare(userfile)
    cb_error "Error: provider is offline."   unless self.online
    cb_error "Error: provider is read_only." if     self.read_only
    SyncStatus.ready_to_modify_cache(userfile) do
      mkdir_cache_subdirs(userfile)
    end
    true
  end

  # Returns the full path to the file or subdirectory
  # where the cached content of +userfile+ is located.
  # The value returned is a Pathname object, so be careful
  # to call to_s() on it, when necessary.
  def cache_full_path(userfile)
    cb_error "Error: provider is offline."   unless self.online
    cache_full_pathname(userfile)
  end
  
  # Executes a block on a filehandle open in +read+ mode for the
  # cached copy of the content of +userfile+; note
  # that this method automatically calls the synchronization
  # method sync_to_cache(userfile) before creating
  # and returning the filehandle.
  #
  #   content = nil
  #   provider.cache_readhandle(u) do |fh|
  #     content = fh.read
  #   end
  def cache_readhandle(userfile, rel_path = ".")
    cb_error "Error: provider is offline."   unless self.online
    sync_to_cache(userfile)
    full_path = cache_full_path(userfile) + rel_path
    cb_error "Error: read handle cannot be provided for non-file." unless File.file? full_path
    File.open(full_path,"r") do |fh|
      yield(fh)
    end
  end

  # Executes a *block* on a filehandle open in +write+ mode for the
  # cached copy of the content of +userfile+; note
  # that this method automatically calls the method
  # cache_prepare(userfile) before the block is executed,
  # and automatically calls the synchronization
  # method sync_to_provider(userfile) after the block is
  # executed.
  #
  #   content = "Hello"
  #   provider.cache_writehandle(u) do |fh|
  #     fh.write(content)
  #   end
  #
  # In the case where +userfile+ is not a simple file
  # but is instead a directory (e.g. it's a FileCollection),
  # no filehandle is provided to the block, but the rest
  # of the behavior is identical. Note that brand new
  # FileCollections will NOT have a directory yet created
  # for them, only the path leading TO the FileCollection will
  # be there.
  #
  #   provider.cache_writehandle(filecollection) do
  #     Dir.mkdir(filecollection.cache_full_path)
  #     File.open("#{filecollection.cache_full_path}/abcd","w") do |fh|
  #       fh.write "data"
  #     end
  #   end
  def cache_writehandle(userfile)
    cb_error "Error: provider is offline."   unless self.online
    cb_error "Error: provider is read_only." if self.read_only
    cache_prepare(userfile)
    localpath = cache_full_path(userfile)
    SyncStatus.ready_to_modify_cache(userfile) do
      if userfile.is_a?(FileCollection)
        yield
      else # a normal file, just crush it
        File.open(localpath,"w") do |fh|
          yield(fh)
        end
      end
    end
    sync_to_provider(userfile)
  end

  # This method provides a quick way to set the cache's file
  # content to an exact copy of +localfile+, a locally accessible file.
  # The syncronization method +sync_to_provider+ will automatically
  # be called after the copy is performed.
  def cache_copy_from_local_file(userfile, localpath)
    cb_error "Error: provider is offline."   unless self.online
    cb_error "Error: provider is read_only." if self.read_only
    cb_error "Error: file does not exist: #{localpath.to_s}" unless File.exists?(localpath)
    cb_error "Error: incompatible directory '#{localpath}' given for a SingleFile." if
        userfile.is_a?(SingleFile)     && File.directory?(localpath)
    cb_error "Error: incompatible normal file '#{localpath}' given for a FileCollection." if
        userfile.is_a?(FileCollection) && File.file?(localpath)
    dest = cache_full_path(userfile)
    cache_prepare(userfile)
    SyncStatus.ready_to_modify_cache(userfile) do
      needslash=""
      if File.directory?(localpath)
        FileUtils.remove_entry(dest.to_s, true) if File.exists?(dest.to_s) && ! File.directory?(dest.to_s)
        Dir.mkdir(dest.to_s) unless File.directory?(dest.to_s)
        needslash="/"
      else
        FileUtils.remove_entry(dest.to_s, true) if File.exists?(dest.to_s) && File.directory?(dest.to_s)
      end
      rsyncout = ""
      IO.popen("rsync -a -l --delete '#{localpath}#{needslash}' '#{dest}' 2>&1","r") do |fh|
        rsyncout=fh.read
      end
      cb_error "Failed to rsync local file '#{localpath}' to cache file '#{dest}'; rsync reported: #{rsyncout}" unless rsyncout.blank?
    end
    sync_to_provider(userfile)
  end

  # This method provides a quick way to copy the cache's file
  # to an exact copy +localfile+, a locally accessible file.
  # The syncronization method +sync_to_cache+ will automatically
  # be called before the copy is performed.
  #
  # Note that if +localpath+ is a path to an existing filesystem
  # entry, it will be crushed and replaced; this is true even if
  # +localpath+ if of a different type than the +userfile+, e.g.
  # if +userfile+ is a SingleFile and +localpath+ is a path to
  # a existing subdirectory /a/b/c/, then 'c' will be erased and
  # replaced by a file.
  def cache_copy_to_local_file(userfile,localpath)
    cb_error "Error: provider is offline."   unless self.online
    cb_error "Error: provider is read_only." if self.read_only
    sync_to_cache(userfile)
    source = cache_full_path(userfile)
    return true if source.to_s == localpath.to_s
    needslash=""
    if File.directory?(source.to_s)
      FileUtils.remove_entry(localpath.to_s, true) if File.exists?(localpath.to_s) && ! File.directory?(localpath.to_s)
      Dir.mkdir(localpath.to_s) unless File.directory?(localpath.to_s)
      needslash="/"
    else
      FileUtils.remove_entry(localpath.to_s, true) if File.exists?(localpath.to_s) && File.directory?(localpath.to_s)
    end
    rsyncout = ""
    IO.popen("rsync -a -l --delete '#{source}#{needslash}' '#{localpath}' 2>&1","r") do |fh|
      rsyncout=fh.read
    end
    cb_error "Failed to rsync cache file '#{source}' to local file '#{localpath}'; rsync reported: #{rsyncout}" unless rsyncout.blank?
    true
  end

  # Deletes the cached copy of the content of +userfile+;
  # does not affect the real file on the provider side.
  def cache_erase(userfile)
    # cb_error "Error: provider is offline."   unless self.online
    SyncStatus.ready_to_modify_cache(userfile,'ProvNewer') do
      # The cache contains three more levels, try to clean them:
      #   "/CbrainCacheDir/ProviderName/username/34/45/basename"
      begin
        # Get the path for the cached file. It's important
        # to call cache_full_pathname() and NOT cache_full_path(), as
        # it must raise an exception when there is no caching in the provider!
        fullpath = cache_full_pathname(userfile)
        # 1- Remove the basename itself (it's a file or a subdir)
        #FileUtils.remove_entry(fullpath, true) rescue true
        # 2- Remove the last level of the cache, "45", if possible
        level2 = fullpath.parent
        FileUtils.remove_entry(level2,true) rescue true
        # 3- Remove the medium level of the cache, "34", if possible
        level1 = level2.parent
        Dir.rmdir(level1)
        # 4- Remove the top level of the cache, "username", if possible
        level0 = level1.parent
        Dir.rmdir(level0)
      rescue Errno::ENOENT, Errno::ENOTEMPTY => ex
        # Nothing to do if we fail, as we are just trying to clean
        # up the cache structure from bottom to top
      end
    end
    true
  end
  
  # Provides information about the files associated with a Userfile entry
  # that has been synced to the cache. Returns an Array of FileInfo objects
  # representing the individual files. 
  #
  # Though this method will function on SingleFile objects, it is primarily meant
  # to be used on FileCollections to gather information about the individual files
  # in the collection.
  def cache_collection_index(userfile, directory = :all, allowed_types = :regular)
    cb_error "Error: provider is offline."   unless self.online
    cb_error "Error: userfile is not cached." unless userfile.is_locally_cached?
    list = []
    
    if allowed_types.is_a? Array
      types = allowed_types.dup
    else
      types = [allowed_types]
    end
    
    types.map!(&:to_sym)
    types << :file if types.delete(:regular)
    
    Dir.chdir(cache_full_path(userfile).parent) do
      if userfile.is_a? FileCollection
        if directory == :all
          entries = Dir.glob(userfile.name + "/**/*")
        else
          directory = "." if directory == :top
          base_dir = "/" + directory + "/"
          base_dir.gsub!(/\/\/+/, "/")
          base_dir.gsub!(/\/\.\//, "/")
          entries = Dir.entries(userfile.name + base_dir ).reject{ |e| e =~ /^\./ }.inject([]){ |result, e| result << userfile.name + base_dir + e }
        end
      else
        entries = [userfile.name]
      end 
      attlist = [ 'symbolic_type', 'size', 'permissions',
                  'uid',  'gid',  'owner', 'group',
                  'atime', 'ctime', 'mtime' ]
      entries.each do |file_name|
        entry = File.lstat(file_name)
        type = entry.ftype.to_sym
        next unless types.include?(type)
        #next if file_name == "." || file_name == ".."

        fileinfo               = FileInfo.new
        fileinfo.name          = file_name

        bad_attributes = []
        attlist.each do |meth|
          begin
            if meth == 'symbolic_type'
              fileinfo.symbolic_type = entry.ftype.to_sym
              fileinfo.symbolic_type = :regular if fileinfo.symbolic_type == :file
            else  
              val = entry.send(meth)
              fileinfo.send("#{meth}=", val)
            end
          rescue => e
            puts "Method #{meth} not supported: #{e.message}"
            bad_attributes << meth
          end
        end
        attlist -= bad_attributes unless bad_attributes.empty?

        list << fileinfo
      end
    end
    list.sort! { |a,b| a.name <=> b.name }
    list
  end



  #################################################################
  # Official Data API methods (work on userfiles)
  #            - Provider Side Methods -
  #################################################################

  # Deletes the content of +userfile+ on the provider side.
  def provider_erase(userfile)
    cb_error "Error: provider is offline." unless self.online
    cb_error "Error: provider is read_only." if self.read_only
    SyncStatus.ready_to_modify_dp(userfile) do
      impl_provider_erase(userfile)
    end
  end

  # Renames +userfile+ on the provider side.
  # This will also rename the name attribute IN the
  # userfile object. A check for name collision on the
  # provider is performed first. The method returns
  # true if the rename operation was successful.
  def provider_rename(userfile,newname)
    cb_error "Error: provider is offline."   unless self.online
    cb_error "Error: provider is read_only." if self.read_only
    return true if newname == userfile.name
    return false unless Userfile.is_legal_filename?(newname)
    target_exists = Userfile.find_by_name_and_data_provider_id(newname,self.id)
    return false if target_exists
    cache_erase(userfile)
    SyncStatus.ready_to_modify_dp(userfile) do
      impl_provider_rename(userfile,newname.to_s) && userfile.save
    end
  end

  # Move a +userfile+ from the current provider to
  # +otherprovider+ ; note that this method will
  # update the +userfile+'s data_provider_id and
  # save it back to the DB!
  def provider_move_to_otherprovider(userfile,otherprovider)
    cb_error "Error: provider #{self.name} is offline."            unless self.online
    cb_error "Error: provider #{self.name} is read_only."          if self.read_only
    cb_error "Error: provider #{otherprovider.name} is offline."   unless otherprovider.online
    cb_error "Error: provider #{otherprovider.name} is read_only." if otherprovider.read_only
    return true if self.id == otherprovider.id
    target_exists = Userfile.find(:first,
        :conditions => { :name             => userfile.name,
                         :data_provider_id => otherprovider.id,
                         :user_id          => userfile.user_id } )
    return false if target_exists

    # Get path to cached copy on current provider
    sync_to_cache(userfile)
    currentcache = userfile.cache_full_path

    # Copy to other provider
    userfile.data_provider = otherprovider
    otherprovider.cache_copy_from_local_file(userfile,currentcache)

    # Erase on current provider
    userfile.data_provider = self  # temporarily set it back
    provider_erase(userfile)

    # Record InSync on new provider.
    userfile.data_provider = otherprovider  # must return it to true value
    userfile.save
    SyncStatus.ready_to_modify_cache(userfile, 'InSync') do
      true # dummy as it's already in cache, but adjusts the SyncStatus
    end
  end

  # Copy a +userfile+ from the current provider to
  # +otherprovider+. Returns the newly created file.
  # Optionally, rename the file at the same time.
  def provider_copy_to_otherprovider(userfile,otherprovider,newname = nil)
    cb_error "Error: provider #{self.name} is offline."            unless self.online
    cb_error "Error: provider #{otherprovider.name} is offline."   unless otherprovider.online
    cb_error "Error: provider #{otherprovider.name} is read_only." if otherprovider.read_only
    return true  if self.id == otherprovider.id
    return false if newname && ! Userfile.is_legal_filename?(newname)
    return false unless userfile.id # must be a fully saved file
    target_exists = Userfile.find(:first,
        :conditions => { :name             => (newname || userfile.name),
                         :data_provider_id => otherprovider.id,
                         :user_id          => userfile.user_id } )
    return false if target_exists

    # Create new file entry
    newfile                  = userfile.clone
    newfile.data_provider    = otherprovider
    newfile.name             = newname if newname
    newfile.save

    # Copy log
    old_log = userfile.getlog
    newfile.addlog("Copy of file '#{userfile.name}' on DataProvider '#{self.name}'")
    if old_log
      newfile.addlog("---- Original log follows: ----")
      newfile.raw_append_log(old_log)
      newfile.addlog("---- Original log ends here ----")
    end

    # Get path to cached copy on current provider
    sync_to_cache(userfile)
    currentcache = userfile.cache_full_path

    # Copy to other provider
    otherprovider.cache_copy_from_local_file(newfile,currentcache)

    newfile
  end

  # This method provides a way for a client of the provider
  # to get a list of files on the provider's side, files
  # that are not necessarily yet registered as +userfiles+.
  #
  # When called, the method accesses the provider's side
  # and returns an array of objects. These objects should
  # respond to the following accessor methods that describe
  # a remote file:
  #
  # name:: the base filename
  # symbolic_type:: one of :regular, :symlink, :directory
  # size:: size of file in bytes
  # permissions:: an int interpreted in octal, e.g. 0640
  # uid::  numeric uid of owner
  # gid::  numeric gid of the file
  # owner:: string representation of uid, the owner's name
  # group:: string representation of gid, the group's name
  # mtime:: modification time (an int, since Epoch)
  # atime:: access time (an int, since Epoch)
  # ctime:: attribute change time (an int, since Epoch)
  #
  # These attributes match those of the class
  #     Net::SFTP::Protocol::V01::Attributes
  # except for name() which is new.
  #
  # Not all these attributes need to be filled in; nil
  # is often acceptable for some of them. The bare minimum
  # is probably the set 'name', 'type' and 'size' and 'mtime'.
  #
  # The optional user object passed in argument can be used
  # to restrict the list of files returned to only those
  # that match one of the user's properties (e.g. ownership
  # or file location).
  #
  # Note that not all data providers are meant to be browsable.
  def provider_list_all(user=nil)
    cb_error "Error: provider is offline."       unless self.online
    cb_error "Error: provider is not browsable." unless self.is_browsable?
    impl_provider_list_all(user)
  end

  # Provides information about the files associated with a Userfile entry
  # whose actual contents are still only located on a DataProvider (i.e. it has not
  # been synced to the local cache yet). 
  # Though this method will function on SingleFile objects, it is primarily meant
  # to be used on FileCollections to gather information about the individual files
  # in the collection.
  #
  # *NOTE*: this method should gather its information WITHOUT doing a local sync.
  #
  # When called, the method accesses the provider's side
  # and returns an array of FileInfo objects. 
  def provider_collection_index(userfile, *args)
    cb_error "Error: provider #{self.name} is offline." unless self.online
    impl_provider_collection_index(userfile, *args)
  end

  # Opens a filehandle to the remote data file and supplies
  # it to the given block. THIS METHOD IS TO BE AVOIDED;
  # the proper methodology is to cache a file before accessing
  # it locally. This method is meant as a workaround for
  # exceptional situations when syncing is not welcome.
  def provider_readhandle(userfile, *args, &block)
    cb_error "Error: provider #{self.name} is offline." unless self.online
    if userfile.is_locally_synced?
      cache_readhandle(userfile, *args, &block)
    else
      impl_provider_readhandle(userfile, *args, &block)
    end
  end

  # This method is NOT part of the sanctionned API, it
  # is here only FYI. It should be redefined properly
  # in subclasses.
  def provider_full_path(userfile) #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end



  #################################################################
  # Utility Non-API
  #################################################################

  # This method is a TRANSITION utility method; it returns
  # any provider that's read/write for the user. The method
  # is used by interface pages not yet modified to ask the
  # user where files nead to be stored. The hope is that
  # it will return the main provider by default.
  def self.find_first_online_rw(user)
    providers = self.find(:all, :conditions => { :online => true, :read_only => false })
    providers = providers.select { |p| p.can_be_accessed_by?(user) }
    raise "No online rw provider found for user '#{user.login}'" if providers.size == 0
    providers.sort! { |a,b| a.id <=> b.id }
    providers[0]
  end

  def site
    @site ||= self.user.site
  end



  #################################################################
  # ActiveRecord callbacks
  #################################################################

  # Ensure that the system will be in a valid state if this data provider is destroyed.
  def validate_destroy
    unless self.userfiles.empty?
      cb_error "You cannot remove a provider that has still files registered on it."
    end
  end



  #################################################################
  # Implementation-dependant method placeholders
  # All of these methods MUST be implemented in subclasses.
  #################################################################

  protected

  def impl_is_alive? #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end

  def impl_sync_to_cache(userfile) #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end

  def impl_sync_to_provider(userfile) #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end

  def impl_provider_erase(userfile) #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end

  def impl_provider_rename(userfile,newname) #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end

  def impl_provider_list_all(user=nil) #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end
  
  def impl_provider_collection_index(userfile, *args) #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end



  #################################################################
  # Internal cache-handling methods
  #################################################################

  # Returns (and creates if necessary) a unique key
  # for this Ruby process' cache. This key is
  # maintained in a file in the cache_rootdir().
  # It's setup to be a MD5 checksum, 32 hex characters long.
  # Note that this key is also recorded in a RemoteResource
  # object during CBRAIN's validation steps, at launch time.
  def self.cache_md5
    return @@key if self.class_variable_defined?('@@key') && ! @@key.blank?

    # Try to read key from special file in cache root directory
    cache_root = cache_rootdir
    key_file = (cache_root + "DP_Cache_Key.md5").to_s
    if File.exist?(key_file)
      @@key = File.read(key_file)  # a MD5 string, 32 hex characters
      @@key.gsub!(/\W+/,"") unless @@key.blank?
      return @@key          unless @@key.blank?
    end

    # Create a key. We MD5 the hostname, the cache root dir
    # and the time. This should be good enough. It will still
    # work even if the directory is moved about or the computer
    # renamed, as long as the key file is left there.
    keystring  = Socket.gethostname + "|" + cache_root + "|" + Time.now.to_i.to_s
    md5encoder = Digest::MD5.new
    @@key      = md5encoder.hexdigest(keystring).to_s

    # Try to write it back. If the file suddenly has appeared,
    # we ignore our own key and use THAT one instead (race condition).
    begin
      fd = IO::sysopen(key_file, Fcntl::O_WRONLY | Fcntl::O_EXCL | Fcntl::O_CREAT)
      fh = IO.open(fd)
      fh.syswrite(@@key)
      fh.close
      return @@key
    rescue # Oh? Open write failed? Some other process has created it underneath us.
      if ! File.exist?(key_file)
        raise "Error: could not create a proper Data Provider Cache Key in file '#{key_file}' !"
      end
      sleep 2+rand(5) # make sure other process writing to it is done
      @@key = File.read(key_file)
      @@key.gsub!(/\W+/,"") unless @@key.blank?
      raise "Error: could not read a proper Data Provider Cache Key from file '#{key_file}' !" if @@key.blank?
      return @@key
    end
  end

  # This method returns the revision number of the last time
  # the caching system was initialized. If the revision
  # number is unknown, then a strning value of "0" is returned and
  # the method will immediately store the current revision
  # number. The value is stored in a file at the top of the
  # caching system's directory structure.
  def self.cache_revision_of_last_init(force = nil)
    return @@cache_rev if ! force && self.class_variable_defined?('@@cache_rev') && ! @@cache_rev.blank?

    # Try to read rev from special file in cache root directory
    cache_root = cache_rootdir
    rev_file = (cache_root + "DP_Cache_Rev.id").to_s
    if ! force && File.exist?(rev_file)
      @@cache_rev = File.read(rev_file)  # a numeric ID as ASCII
      @@cache_rev.gsub!(/\D+/,"") unless @@cache_rev.blank?
      return @@cache_rev          unless @@cache_rev.blank?
    end

    # Lets use the current revision number then.
    @@cache_rev = self.revision_info.svn_id_rev

    # Try to write it back. If the file suddenly has appeared,
    # we ignore our own rev and use THAT one instead (race condition).
    begin
      if force
        fd = IO::sysopen(rev_file, Fcntl::O_WRONLY | Fcntl::O_CREAT)
      else
        fd = IO::sysopen(rev_file, Fcntl::O_WRONLY | Fcntl::O_EXCL | Fcntl::O_CREAT)
      end
      fh = IO.open(fd)
      fh.syswrite(@@cache_rev + "\n")
      fh.close
      return "0" # String Zero, to indicate it was unknown.
    rescue # Oh? Open write failed? Some other process has created it underneath us.
      if ! File.exist?(rev_file)
        raise "Error: could not create a proper Data Provider Cache Revision Number in file '#{rev_file}' !"
      end
      sleep 2+rand(5) # make sure other process writing to it is done
      @@cache_rev = File.read(rev_file)
      @@cache_rev.gsub!(/\D+/,"") unless @@cache_rev.blank?
      raise "Error: could not read a proper Data Provider Cache Revision Number from file '#{rev_file}' !" if @@cache_rev.blank?
      return "0" # String Zero, to indicate it was unknown.
    end
  end

  # Root directory for ALL DataProviders caches:
  #     "/CbrainCacheDir"
  # This is a class method.
  def self.cache_rootdir #:nodoc:
    Pathname.new(CBRAIN::DataProviderCache_dir)
  end

  # Returns an array of two subdirectory levels where a file
  # is cached. These are two strings of two digits each. For
  # instance, for +hello+, the method returns [ "32", "98" ].
  # Although this method is mostly used internally by the
  # caching system, it can also be used by other data providers
  # which want to build similar directory trees.
  #
  # Note that unlike the other methods in the cache management
  # layer, this method only takes a basename, not a userfile,
  # in argument.
  #
  # This method is mostly obsolete.
  def cache_subdirs_from_name(basename)
    cb_error "DataProvider internal API change incompatibility (string vs userfile)" if basename.is_a?(Userfile)
    s=0    # sum of bytes
    e=0    # xor of bytes
    basename.each_byte { |i| s += i; e ^= i }
    [ sprintf("%2.2d",s % 100), sprintf("%2.2d",e % 100) ]
  end

  # Returns a relative directory path with three components
  # based on the +number+; the path will be in format
  #     "ab/cd/ef"
  # where +ab+, +cd+ et +ef+ components are two digits
  # long extracted directly from +number+. Examples:
  #
  #    Number      Path
  #    ----------- --------
  #    0           00/00/00
  #    5           00/00/05
  #    100         00/01/00
  #    2345        00/23/45
  #    462292      46/22/92
  #    1462292    146/22/92
  #
  # The path is returned as an array of string
  # components, as in
  #
  #    [ "146", "22","92" ]
  def cache_subdirs_from_id(number)
    cb_error "Did not get a proper numeric ID? Got: '#{number.inspect}'." unless number.is_a?(Integer)
    sid = "000000" + number.to_s
    unless sid =~ /^0*(\d*\d\d)(\d\d)(\d\d)$/
      cb_error "Data Provider caching system error: can't create subpath for '#{number}'."
    end
    lower  = Regexp.last_match[1] # 123456 -> 12
    middle = Regexp.last_match[2] # 123456 -> 34
    upper  = Regexp.last_match[3] # 123456 -> 56
    [ lower, middle, upper ]
  end

  # Make, if needed, the three subdirectory levels for a cached file:
  #     mkdir "/CbrainCacheDir/34"
  #     mkdir "/CbrainCacheDir/34/45"
  #     mkdir "/CbrainCacheDir/34/45/77"
  def mkdir_cache_subdirs(userfile) #:nodoc:
    cb_error "DataProvider internal API change incompatibility (string vs userfile)" if userfile.is_a?(String)
    uid = userfile.id
    twolevels = cache_subdirs_from_id(uid)
    level0 = self.class.cache_rootdir
    level1 = level0                          + twolevels[0]
    level2 = level1                          + twolevels[1]
    level3 = level2                          + twolevels[2]
    Dir.mkdir(level1) unless File.directory?(level1)
    Dir.mkdir(level2) unless File.directory?(level2)
    Dir.mkdir(level3) unless File.directory?(level3)
    true
  end

  # Returns the relative path of the three subdirectory levels
  # where a file is cached:
  #     "34/45/77"
  def cache_subdirs_path(userfile) #:nodoc:
    cb_error "DataProvider internal API change incompatibility (string vs userfile)" if userfile.is_a?(String)
    uid  = userfile.id
    dirs = cache_subdirs_from_id(uid)
    Pathname.new(dirs[0]) + dirs[1] + dirs[2]
  end

  # Returns the full path of the two subdirectory levels:
  #     "/CbrainCacheDir/34/45/77"
  def cache_full_dirname(userfile) #:nodoc:
    cb_error "DataProvider internal API change incompatibility (string vs userfile)" if userfile.is_a?(String)
    self.class.cache_rootdir + cache_subdirs_path(userfile)
  end

  # Returns the full path of the cached file:
  #     "/CbrainCacheDir/34/45/77/basename"
  def cache_full_pathname(userfile) #:nodoc:
    cb_error "DataProvider internal API change incompatibility (string vs userfile)" if userfile.is_a?(String)
    basename = userfile.name
    cache_full_dirname(userfile) + basename
  end
  
end

