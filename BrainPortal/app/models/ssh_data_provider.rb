
#
# CBRAIN Project
#
# $Id$
#

require 'rubygems'
require 'net/ssh'
require 'net/sftp'

#
# This class provides an implementation for a data provider
# where the remote files are accessed through +ssh+ and +rsync+.
# The provider's files are stored in a flat directory, one
# level deep, directly specified by the object's +remote_dir+
# attribute. The file "hello" is thus stored in a path like this:
#
#     /remote_dir/hello
#
# For the list of API methods, see the DataProvider superclass.
#
class SshDataProvider < DataProvider

  Revision_info="$Id$"

  def impl_is_alive? #:nodoc:
    ssh_opts = self.ssh_shared_options
    return false unless @master.is_alive?
    dir  = remote_shell_escape(self.remote_dir)
    text = bash_this("ssh -x -n #{ssh_opts} test -d #{dir} '||' echo Fail-Dir 2>&1")
    return(text.blank? ? true : false);
  rescue
    false
  end

  # Please make sure that subclasses that are not
  # browsable resets this value to false.
  def is_browsable? #:nodoc:
    true
  end
  
  def allow_file_owner_change? #:nodoc:
    true
  end

  def impl_sync_to_cache(userfile) #:nodoc:
    localfull   = cache_full_path(userfile)
    remotefull  = provider_full_path(userfile)
    sourceslash = ""

    mkdir_cache_subdirs(userfile)
    if userfile.is_a?(FileCollection)
      Dir.mkdir(localfull) unless File.directory?(localfull)
      sourceslash="/"
    end

    rsync = rsync_over_ssh_prefix
    # It's IMPORTANT that the source be specified with a bare ':' in front.
    text = bash_this("#{rsync} -a -l --delete #{self.rsync_excludes} :#{remote_shell_escape(remotefull)}#{sourceslash} #{shell_escape(localfull)} 2>&1")
    text.sub!(/Warning: Permanently added[^\n]+known hosts.\s*/i,"") # a common annoying warning
    cb_error "Error syncing userfile to local cache: rsync returned:\n#{text}" unless text.blank?
    cb_error "Error syncing userfile to local cache: no destination file found after rsync?\n" unless File.exist?(localfull)
    true
  end

  def impl_sync_to_provider(userfile) #:nodoc:
    localfull   = cache_full_path(userfile)
    remotefull  = provider_full_path(userfile)
    cb_error "Error: file #{localfull} does not exist in local cache!" unless File.exist?(localfull)

    sourceslash = userfile.is_a?(FileCollection) ? "/" : ""
    rsync = rsync_over_ssh_prefix
    # It's IMPORTANT that the destination be specified with a bare ':' in front.
    text = bash_this("#{rsync} -a -l --delete #{self.rsync_excludes} #{shell_escape(localfull)}#{sourceslash} :#{remote_shell_escape(remotefull)} 2>&1")
    text.sub!(/Warning: Permanently added[^\n]+known hosts.\s*/i,"") # a common annoying warning
    cb_error "Error syncing userfile to data provider: rsync returned:\n#{text}" unless text.blank?
    ssh_opts = self.ssh_shared_options
    text = bash_this("ssh -x -n #{ssh_opts} \"test -e \"#{remote_shell_escape(remotefull)}\" && echo DestIsOk\"")
    cb_error "Error syncing userfile to data provider: no destination file found after rsync?\nTest for #{shell_escape(remotefull)} returned: '#{text}'" unless text =~ /DestIsOk/
    true
  end

  def impl_provider_erase(userfile) #:nodoc:
    full     = provider_full_path(userfile)
    ssh_opts = self.ssh_shared_options
    bash_this("ssh -x -n #{ssh_opts} \"bash -c '/bin/rm -rf #{full} >/dev/null 2>&1'\"")
    true
  end

  def impl_provider_rename(userfile,newname) #:nodoc:
    oldpath   = provider_full_path(userfile)
    remotedir = oldpath.parent
    newpath   = remotedir + newname

    oldpath   = oldpath.to_s
    newpath   = newpath.to_s

    Net::SFTP.start(remote_host,remote_user, :port => remote_port, :auth_methods => 'publickey') do |sftp|
      begin
        att = sftp.lstat!(newpath)
        return false # means file exists already
      rescue => ex
        # Nothing to do! An exception means everything is OK, so just go on.
      end
      begin
        sftp.rename!(oldpath,newpath)
        userfile.name = newname
        return true
      rescue => ex
        return false
      end
    end
    false
  end
  
  def impl_provider_readhandle(userfile, rel_path = ".", &block) #:nodoc:
    full_path = provider_full_path(userfile) + rel_path
    IO.popen("ssh #{ssh_shared_options} cat #{remote_shell_escape(full_path)}","r") do |fh|
      cb_error "Error: read handle cannot be provided for non-file." if fh.eof?
      yield(fh)
    end
  end

  def impl_provider_list_all(user=nil) #:nodoc:
    list = []
    attlist = [ 'symbolic_type', 'size', 'permissions',
                'uid',  'gid',  'owner', 'group',
                'atime', 'ctime', 'mtime' ]
    Net::SFTP.start(remote_host,remote_user, :port => remote_port, :auth_methods => 'publickey') do |sftp|
      sftp.dir.foreach(self.browse_remote_dir(user)) do |entry|
        attributes = entry.attributes
        type = attributes.symbolic_type
        next if type != :regular && type != :directory && type != :symlink
        next if entry.name == "." || entry.name == ".."
        next if is_excluded?(entry.name) # in DataProvider

        fileinfo               = FileInfo.new
        fileinfo.name          = entry.name

        bad_attributes = []
        attlist.each do |meth|
          begin
            val = attributes.send(meth)
            fileinfo.send("#{meth}=", val)
          rescue => e
            #puts "Method #{meth} not supported: #{e.message}"
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

  # Allows us to browse a remote directory that changes based on the user.
  def browse_remote_dir(user=nil) #:nodoc:
    self.remote_dir
  end
  
  def impl_provider_collection_index(userfile, directory = :all, allowed_types = :regular) #:nodoc:
    list = []
    
    if allowed_types.is_a? Array
      types = allowed_types.dup
    else
      types = [allowed_types]
    end
      
    types.map!(&:to_sym)
    
    
    Net::SFTP.start(remote_host,remote_user, :port => remote_port, :auth_methods => 'publickey') do |sftp|
       entries = []
       if userfile.is_a? FileCollection
         if directory == :all
           entries = sftp.dir.glob(provider_full_path(userfile).to_s, "**/*")
           entries.each { |e| e.instance_eval { @name = userfile.name + "/" + @name } }
         else
           directory = "." if directory == :top
           base_dir = "/" + directory + "/"
           base_dir.gsub!(/\/\/+/, "/")
           base_dir.gsub!(/\/\.\//, "/")
           entries = sftp.dir.entries(provider_full_path(userfile).to_s + base_dir ).reject{ |e| e.name =~ /^\./}.inject([]) { |result, e| result << e }
         end
       else
         request = sftp.stat(provider_full_path(userfile)) do |response|
           attr = response[:attrs]
           entry = Net::SFTP::Protocol::V01::Name.new(userfile.name,userfile.name,attr)
           entries << entry
         end
         request.wait
       end
       attlist = [ 'symbolic_type', 'size', 'permissions',
                   'uid',  'gid',  'owner', 'group',
                   'atime', 'ctime', 'mtime' ]
       entries.each do |entry|
        attributes = entry.attributes
        type = attributes.symbolic_type
        next unless types.include?(type)
        #next if entry.name == "." || entry.name == ".."
        next if is_excluded?(entry.name) # in DataProvider

        fileinfo               = FileInfo.new
        if entry.name =~ /^#{userfile.name}/
          fileinfo.name          = entry.name
        else
          fileinfo.name          = "#{userfile.name}#{base_dir}#{entry.name}"
        end 

        bad_attributes = []
        attlist.each do |meth|
          begin
            val = attributes.send(meth)
            fileinfo.send("#{meth}=", val)
          rescue => e
            #puts "Method #{meth} not supported: #{e.message}"
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

  # Returns the full path to the content of +userfile+ on
  # the data provider's side. This is to be overriden
  # by subclasses where files are stored differently
  # on the provider's side.
  def provider_full_path(userfile)
    basename = userfile.name
    Pathname.new(remote_dir) + basename
  end
  
  protected

  # Builds a prefix for a +rsync+ command, such as
  #
  #   "rsync -e 'ssh -x -o a=b -o c=d -p port user@host'"
  #
  # Note that this means that remote file specifications for
  # rsync MUST start with a bare ":" :
  #
  #   rsync -e 'ssh_options_here user_host'  :/remote/file  local/file
  def rsync_over_ssh_prefix
    ssh_opts = self.ssh_shared_options
    ssh      = "ssh -x #{ssh_opts}"
    rsync    = "rsync -e #{shell_escape(ssh)}"
    rsync
  end

  # Returns the necessary options to connect to a master SSH
  # command running in the background (which will be started if
  # necessary).
  def ssh_shared_options
    @master ||= SshMaster.find_or_create(remote_user,remote_host,remote_port,"DataProvider")
    @master.start("DataProvider_#{self.name}") # does nothing is it's already started
    @master.ssh_shared_options("auto") # ControlMaster=auto
  end

end

