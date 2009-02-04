class SingleFile < Userfile
  def extract
    success = true
    self.save_content
    
    successful_files = []
    failed_files = []
    nested_files = []
    Dir.chdir(Pathname.new(CBRAIN::Filevault_dir) + self.user.login) do
      if self.name =~ /\.tar(\.gz)?$/
        all_files = `tar tf #{self.name}`.split("\n")
        all_files.each do |file_name|
          if Userfile.find_by_name(file_name)
            failed_files << file_name
          elsif file_name =~ /\//
            nested_files << file_name
          else
            `tar xvf #{self.name} #{file_name}`
            successful_files << file_name
          end
        end
      else
        all_files = `unzip -l #{self.name}`.split("\n")[3..-3].map{ |line|  line.split[3]}
        all_files.each do |file_name|
          if Userfile.find_by_name(file_name)
            failed_files << file_name
          elsif file_name =~ /\//
            nested_files << file_name
          else
            `unzip #{self.name} #{file_name}`
            successful_files << file_name
          end
        end
      end
    end
           
    successful_files.each do |file|
      u = Userfile.new(:tag_ids  => self.tag_ids)
      u.name    = file
      u.user_id = self.user_id
      u.size = File.size(u.vaultname)
      if File.file? u.vaultname
        success = false unless u.save(false)
      end
    end
    
    File.delete(self.vaultname)
    [success, successful_files, failed_files, nested_files]
  end
  
  def content
    @content ||= self.read_content
    @content
  end

  def content=(newcontent)
    @content = newcontent
    self.size = @content.size
    @content
  end
  
  def format_size
    if self.size > 10**9
      "#{self.size/10**9} GB"
    elsif   self.size > 10**6
      "#{self.size/10**6} MB"
    elsif   self.size > 10**3
      "#{self.size/10**3} KB"
    else
      "#{self.size} bytes"     
    end 
  end
  
  def save_content
    return if @content.nil?
    finalname = self.vaultname
    tmpname   = finalname + ".tmp"
    out = File.open(tmpname, "w") { |io| io.write(@content) }
    File.rename(tmpname,finalname)
  end

  def delete_content
    vaultname = self.vaultname
    File.unlink(vaultname) if File.file?(vaultname)
    
    directory = File.dirname(vaultname)
    if (Pathname.new(directory) != self.user.vault_dir) && Dir.entries(directory).size <= 2
      Dir.rmdir(directory) if File.directory?(directory)
    end
    @content=nil
  end
  
  def after_save
    self.save_content
  end
  
  def after_update
    self.save_content
  end
  
  def after_create
    self.save_content
  end
  
  def after_destroy
    self.delete_content
  end
end