
#
# CBRAIN Project
#
# $Id$
#

require 'fileutils'
require 'pathname'

#
# This abstract class describe an external 'data provider'
# for CBRAIN files. The API consist in these methods:
#
# = Status methods:
#
# * is_alive?
# * is_alive!
#
# = Access restriction methods:
#
# * can_be_accessed_by(user)
#
# = Synchronization methods:
#
# * sync_to_cache(userfile)
# * sync_to_provider(userfile)
#
# = Cache-side methods:
#
# * cache_prepare(userfile)
# * cache_full_path(userfile)
# * cache_readhandle(userfile)
# * cache_writehandle(userfile)
# * cache_copy_from_local_file(userfile,localfilename)
# * cache_copy_to_local_file(userfile,localfilename)
# * cache_erase(userfile)
#
# = Provider-side methods:
#
# * provider_erase(userfile)
# * provider_rename(userfile,newname)
# * provider_list_all
#
# Most methods raise an exception if the provider's +online+ attribute is
# false, or if trying to perform some write operation and the provider's
# +read_only+ attribute is true.
#
# = A proper implementation in a subclass must have the following
# methods defined:
#
# * impl_is_alive?
# * impl_sync_to_cache(userfile)
# * impl_sync_to_provider(userfile)
# * impl_provider_erase(userfile)
# * impl_provider_rename(userfile,newname)
# * impl_provider_list_all()
class DataProvider < ActiveRecord::Base

  belongs_to :user
  belongs_to :group

  validates_uniqueness_of :name
  validates_presence_of   :name, :user_id, :group_id

  # This method must not block, and must respond quickly.
  # Returns +true+ or +false+.
  def is_alive?
    return false if self.online == false
    impl_is_alive?
  end

  # Raises an exception if is_alive? is +false+, otherwise
  # it return +true+.
  def is_alive!
    raise "Error: data provider is not accessible right now." unless self.is_alive?
    true
  end

  # Returns true if +user+ can access this provider.
  def can_be_accessed_by(user)
    user.group_ids.include?(group_id)
  end

  # Synchronizes the content of +userfile+ as stored
  # on the provider into the local cache.
  def sync_to_cache(userfile)
    raise "Error: provider is offline." unless self.online
    impl_sync_to_cache(userfile)
  end

  # Synchronizes the content of +userfile+ from the
  # local cache back to the provider.
  def sync_to_provider(userfile)
    raise "Error: provider is offline."   unless self.online
    raise "Error: provider is read_only." if     self.read_only
    impl_sync_to_provider(userfile)
  end

  # Makes sure the local cache is properly configured
  # to receive the content for +userfile+; usually
  # this method is called before writing the content
  # for +userfile+ into the cached file or subdirectory.
  # Note that this method is already called for you
  # when invoking cache_writehandle(userfile).
  def cache_prepare(userfile)
    raise "Error: provider is offline."   unless self.online
    raise "Error: provider is read_only." if     self.read_only
    mkdir_cache_subdirs(userfile.name)
  end

  # Returns the full path to the file or subdirectory
  # where the cached content of +userfile+ is located.
  def cache_full_path(userfile)
    raise "Error: provider is offline."   unless self.online
    cache_full_pathname(userfile.name)
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
  def cache_readhandle(userfile)
    raise "Error: provider is offline."   unless self.online
    sync_to_cache(userfile)
    File.open(cache_full_path(userfile),"r") do |fh|
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
  def cache_writehandle(userfile)
    raise "Error: provider is offline."   unless self.online
    raise "Error: provider is read_only." if self.read_only
    cache_prepare(userfile)
    File.open(cache_full_path(userfile),"w") do |fh|
      yield(fh)
    end
    sync_to_provider(userfile)
  end

  # This method provides a quick way to set the cache's file
  # content to an exact copy of +localfile+, a locally accessible file.
  # The syncronization method +sync_to_provider+ will automatically
  # be called after the copy is performed.
  def cache_copy_from_local_file(userfile,localpath)
    raise "Error: provider is offline."   unless self.online
    raise "Error: provider is read_only." if self.read_only
    raise "Error: file does not exist: #{localpath.to_s}" unless File.exists?(localpath)
    cache_erase(userfile)
    cache_prepare(userfile)
    dest = cache_full_path(userfile)
    FileUtils.cp_r(localpath,dest)
    sync_to_provider(userfile)
  end

  # This method provides a quick way to copy the cache's file
  # to an exact copy +localfile+, a locally accessible file.
  # The syncronization method +sync_to_cache+ will automatically
  # be called before the copy is performed.
  def cache_copy_to_local_file(userfile,localpath)
    raise "Error: provider is offline."   unless self.online
    raise "Error: provider is read_only." if self.read_only
    sync_to_cache(userfile)
    FileUtils.remove_entry(localpath.to_s, true)
    source = cache_full_path(userfile)
    FileUtils.cp_r(source,localpath)
    true
  end

  # Deletes the cached copy of the content of +userfile+;
  # does not affect the real file on the provider side.
  def cache_erase(userfile)
    raise "Error: provider is offline."   unless self.online
    basename = userfile.name
    FileUtils.remove_entry(cache_full_pathname(basename), true)
    begin
      Dir.rmdir(cache_full_dirname(basename))
    rescue
    end
  end

  # Deletes the content of +userfile+ on the provider side.
  def provider_erase(userfile)
    raise "Error: provider is offline."   unless self.online
    raise "Error: provider is read_only." if self.read_only
    cache_erase(userfile)
    impl_provider_erase(userfile)
  end

  # Renames +userfile+ on the provider side.
  # This will also rename the name attribute IN the
  # userfile object. A check for name collision on the
  # provider is performed first. The method returns
  # true if the rename operation was successful.
  def provider_rename(userfile,newname)
    raise "Error: provider is offline."   unless self.online
    raise "Error: provider is read_only." if self.read_only
    return true if newname == userfile.name
    target_exists = Userfile.find_by_name_and_data_provider_id(newname,self.id)
    return false if target_exists
    cache_erase(userfile)
    impl_provider_rename(userfile,newname)
  end

  # This method provides a way for a client of the provider
  # to get a list of files on the provider's side, files
  # that are not necessarily yet registered as +userfiles+.
  #
  # When called, the method accesses the provider's side
  # and returns an array of tuplets; each tuplet is
  #
  #   [ basename, size, type, mtime ]
  #
  # where
  #
  # basename:: is a file basename
  # size::     is in bytes
  # type::     is "regular" or "directory"
  # mtime::    is int seconds since unix epoch
  #
  # Note that not all data providers are meant to be browsable.
  def provider_list_all
    raise "Error: provider is offline."   unless self.online
    impl_provider_list_all
  end


  # This method is a TRANSITION utility method; it returns
  # any provider that's read/write for the user. The method
  # is used by interface pages not yet modified to ask the
  # user where files nead to be stored. The hope is that
  # it will return the main Vault provider by default.
  def self.find_first_online_rw(user)
    providers = self.find(:all, :conditions => { :online => true, :read_only => false })
    providers = providers.select { |p| p.can_be_accessed_by(user) }
    raise "No online rw provider found for user '#{user.login}" if providers.size == 0
    providers.sort! { |a,b| a.id <=> b.id }
    providers[0]
  end



  # ActiveRecord callbacks

  # This creates the PROVIDER's cache directory
  def before_save #:nodoc:
    providerdir = cache_providerdir
    Dir.mkdir(providerdir) unless File.directory?(providerdir)
  end

  # This destroys the PROVIDER's cache directory
  def after_destroy #:nodoc:
    FileUtils.remove_dir(cache_providerdir, true)  # recursive
  end


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

  def impl_provider_list_all #:nodoc:
    raise "Error: method not yet implemented in subclass."
  end



  # This utility method escapes properly any string such that
  # it becomes a literal in a bash command; the string returned
  # will include the surrounding single quotes.
  #
  #   shell_escape("Mike O'Connor")
  #
  # returns
  #
  #   'Mike O'\''Connor'
  def shell_escape(s)
    "'" + s.to_s.gsub(/'/,"'\\\\''") + "'"
  end

  # This utility method runs a bash command, intercepts the output
  # and returns it.
  def bash_this(command)
    #puts "BASH: #{command}"
    fh = IO.popen(command,"r")
    output = fh.read
    fh.close
    output
  end

  # Root directory for ALL DataProviders caches:
  #    "/CbrainCacheDir"
  # This is a class method.
  def self.cache_rootdir #:nodoc:
    Pathname.new(CBRAIN::DataProviderCache_dir)
  end

  # Root directory for DataProvider's cache dir:
  #    "/CbrainCacheDir/ProviderName"
  def cache_providerdir #:nodoc:
    Pathname.new(CBRAIN::DataProviderCache_dir) + self.name
  end

  # Returns an array of two subdirectory levels where a file
  # is cached. These are two strings of two digits each. For
  # instance, for +hello+, the method returns [ "32", "98" ].
  # Although this method is mostly used internally by the
  # caching system, it can also be used by other data providers
  # which want to build similar directory trees.
  def cache_subdirs(basename)
    s=0    # sum of bytes
    e=0    # xor of bytes
    basename.each_byte { |i| s += i; e ^= i }
    [ sprintf("%2.2d",s % 100), sprintf("%2.2d",e % 100) ]
  end

  # Make, if needed, the two subdirectory levels for a cached file:
  # mkdir "/CbrainCacheDir/ProviderName/34"
  # mkdir "/CbrainCacheDir/ProviderName/34/45"
  def mkdir_cache_subdirs(basename) #:nodoc:
    twolevels = cache_subdirs(basename)
    level1 = Pathname.new(cache_providerdir) + twolevels[0]
    level2 = level1                          + twolevels[1]
    Dir.mkdir(level1) unless File.directory?(level1)
    Dir.mkdir(level2) unless File.directory?(level2)
  end

  # Returns the relative path of the two subdirectory levels:
  # "34/45"
  def cache_subdir_path(basename) #:nodoc:
    dirs = cache_subdirs(basename)
    Pathname.new(dirs[0]) + dirs[1]
  end

  # Returns the full path of the two subdirectory levels:
  # "/CbrainCacheDir/ProviderName/34/45"
  def cache_full_dirname(basename) #:nodoc:
    cache_providerdir + cache_subdir_path(basename)
  end

  # Returns the full path of the cached file:
  # "/CbrainCacheDir/ProviderName/34/45/basename"
  def cache_full_pathname(basename) #:nodoc:
    cache_full_dirname(basename) + basename
  end

end

