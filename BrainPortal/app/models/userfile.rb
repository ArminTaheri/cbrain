
#
# CBRAIN Project
#
# Userfile model
#
# Original author: Tarek Sherif
#
# $Id$
#

class Userfile < ActiveRecord::Base

  Revision_info="$Id$"

  acts_as_nested_set :dependent => :destroy, :before_destroy => :move_children_to_root
  belongs_to              :user
  has_and_belongs_to_many :tags
  
  validates_uniqueness_of :name, :scope => :user_id
  
  def self.search(type, term = nil)
    filter_name = get_filter_name(type, term)
    files = if type
              case type.to_sym
                when :tag_search
                  find(:all, :include => :tags).select{|f| f.tags.find_by_name(term)} rescue find(:all, :include => :tags)
                when :name_search
                  find(:all, :include => :tags, :conditions => ["name LIKE ?", "%#{term}%"])
                when :minc
                  find(:all, :include => :tags, :conditions => ["name LIKE ?", "%.mnc"])
                when :jiv
                  find(:all, :include => :tags, :conditions => ["name LIKE ? OR name LIKE ?", "%.raw_byte%", "%.header"])
                end
            else
              find(:all, :include =>:tags)
            end
    [files, filter_name]
  end
  
  def self.paginate(files, page)
    WillPaginate::Collection.create(page, 50) do |pager|
      pager.replace(files[pager.offset, pager.per_page])
      pager.total_entries = files.size
      pager
    end
  end
    
  def self.apply_filters(files, filters)
    current_files = files
    
    filters.each do |filter|
      type, term = filter.split(':')
      case type
      when 'name'
        current_files = current_files.select{ |f| f.name =~ /#{term}/ }
      when 'tag'
        current_files = current_files.select{ |f| f.tags.find_by_name(term)  }
      when 'file'
        case term
        when 'jiv'
          current_files = current_files.select{ |f| f.name =~ /(\.raw_byte(\.gz)?|\.header)$/ }
        when 'minc'
          current_files = current_files.select{ |f| f.name =~ /\.mnc$/ }
        end
      end
    end
    
    current_files
  end
    
  def self.get_filter_name(type, term)
    case type
    when 'name_search'
      'name:' + term
    when 'tag_search'
      'tag:' + term
    when 'jiv'
      'file:jiv'
    when 'minc'
      'file:minc'      
    end
  end
  
  def vaultname
    directory = Pathname.new(CBRAIN::Filevault_dir) + self.user.login
    Dir.mkdir(directory) unless File.directory?(directory)
    (directory + self.name).to_s
  end
  
  def list_files
    [self.name]
  end
  
end
