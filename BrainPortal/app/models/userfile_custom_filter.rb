#
# CBRAIN Project
#
# Custom filter model
#
# Original author: Tarek Sherif 
#
# $Id$
#

#Subclass of CustomFilter representing custom filters for the Userfile resource.
#
#=Parameters filtered:
#[*file_name_type*] The type of filtering done on the filename (+matches+, <tt>begins with</tt>, <tt>ends with</tt> or +contains+).
#[*file_name_term*] The string or substring to search for in the filename.
#[*created_date_type*] The type of filtering done on the creation date (+before+, +on+ or +after+).
#[*created_date_term*] The date to filter against.
#[*size_type*] The type of filtering done on the file size (>, < or =).
#[*size_term*] The file size to filter against.
#[*group_id*] The id of the group to filter on.
#[*tags*] A serialized hash of tags to filter on.
class UserfileCustomFilter < CustomFilter
                          
  Revision_info="$Id$"
  
  #See CustomFilter
  def filter_scope(scope)
    scope = scope_name(scope)  unless self.data["file_name_type"].blank? || self.data["file_name_term"].blank?
    scope = scope_date(scope)  unless self.data["created_date_type"].blank? || self.data["date_term"].blank?
    scope = scope_size(scope)  unless self.data["size_type"].blank? || self.data["size_term"].blank?
    scope = scope_group(scope) unless self.data["group_id"].blank?
    scope
  end
  
  #Virtual attribute for assigning tags to the data hash.
  def tag_ids=(ids)
    self.data["tags"] = Tag.find(ids).collect{ |tag| "#{tag.name}"}
  end
  
  #Convenience method returning only the tags in the data hash.
  def tags
    self.data["tags"] || []
  end
  
  #Convenience method returning only the date_term in the data hash.
  def date_term
    self.data["date_term"]
  end
  
  #Virtual attribute for assigning the data_term to the data hash.
  def date_term=(date)
    self.data["date_term"] = "#{date["date_term(1i)"]}-#{date["date_term(2i)"]}-#{date["date_term(3i)"]}"
  end
  
  private
  
  #Return +scope+ modified to filter the Userfile entry's name.
  def scope_name(scope)
    query = 'userfiles.name'
    term = self.data["file_name_term"]
    if self.data["file_name_type"] == 'match'
      query += ' = ?'
    else
      query += ' LIKE ?'
    end
    
    if self.data["file_name_type"] == 'contain' || self.data["file_name_type"] == 'begin'
      term += '%'
    end
    
    if self.data["file_name_type"] == 'contain' || self.data["file_name_type"] == 'end'
      term = '%' + term
    end
    
    scope.scoped(:conditions  => ["#{query}", term])
  end
  
  #Return +scope+ modified to filter the Userfile entry's creation date.
  def scope_date(scope)
    scope.scoped(:conditions  => ["DATE(userfiles.created_at) #{self.data["created_date_type"]} ?", self.data["date_term"]])
  end
  
  #Return +scope+ modified to filter the Userfile entry's size.
  def scope_size(scope)
    scope.scoped(:conditions  => ["userfiles.size #{self.data["size_type"]} ?", (self.data["size_term"].to_i * 1000)])
  end
  
  #Return +scope+ modified to filter the Userfile entry's group ownership.
  def scope_group(scope)
    scope.scoped(:conditions  => ["userfiles.group_id = ?", self.data["group_id"]])
  end
  
  #Returns the sql query to be executed by the filter.
  #
  #*Example*: If the filter is meant to collect userfiles with a name containing
  #the substring +sub+, the variables method will return the following string:
  #  "(userfiles.name LIKE ?)"
  #The value to be interpolated in place of the '?' (i.e. "%sub%" in this case)
  #is returned by the variables method.
  # def query
  #     if @query.blank?
  #       parse_query
  #     end
  #     @query
  #   end
  #   
  #   #Returns an array of the values to be interpolated into the query string.
  #   #
  #   #*Example*: If the filter is meant to collect userfiles with a name containing
  #   #the substring +sub+, the query method will return the following array:
  #   #  ["%sub%"]
  #   #The query string itself is returned by the query method.
  #   def variables
  #     if @variables.blank?
  #       parse_query
  #     end
  #     @variables
  #   end
  #   
  #   private
  #   
  #   #Converts the filters attributes into an sql query
  #   #which can be constructed using the query and variables methods.
  #   def parse_query    
  #     @query ||= ""
  #     @variables ||= []
  #     
  #     parse_name_query         unless self.file_name_type.blank? || self.file_name_term.blank?
  #     parse_created_date_query unless self.created_date_type.blank? || self.created_date_term.blank?
  #     parse_size_query         unless self.size_type.blank? || self.size_term.blank?
  #     parse_group_query        unless self.group_id.blank?
  #   end
  #   
  #   
  #   #Contruct the portion of the filter query which functions on 
  #   #the Userfile entry's name.
  #   def parse_name_query
  #     query = 'userfiles.name'
  #     term = self.file_name_term
  #     if self.file_name_type == 'match'
  #       query += ' = ?'
  #     else
  #       query += ' LIKE ?'
  #     end
  #     
  #     if self.file_name_type == 'contain' || self.file_name_type == 'begin'
  #       term += '%'
  #     end
  #     
  #     if self.file_name_type == 'contain' || self.file_name_type == 'end'
  #       term = '%' + term
  #     end
  #     
  #     @query += " AND " unless @query.blank?
  #     @query += "(#{query})"
  #     @variables << term
  #   end
  #   
  #   #Contruct the portion of the filter query which functions on 
  #   #the Userfile entry's creation date.
  #   def parse_created_date_query
  #     query = "DATE(userfiles.created_at) #{self.created_date_type} ?"
  #     term = self.created_date_term
  #     
  #     @query += " AND " unless @query.blank?
  #     @query += "(#{query})"
  #     @variables << term
  #   end
  #   
  #   #Contruct the portion of the filter query which functions on 
  #   #the Userfile entry's size.
  #   def parse_size_query
  #     query = "userfiles.size #{self.size_type} ?"
  #     term = (self.size_term.to_i * 1000).to_s  
  #     
  #     @query += " AND " unless @query.blank?
  #     @query += "(#{query})"
  #     @variables << term
  #   end
  #   
  #   #Contruct the portion of the filter query which functions on 
  #   #the Userfile entry's group ownership.
  #   def parse_group_query
  #     query = "userfiles.group_id = ?"
  #     term = self.group_id
  #     
  #     @query += " AND " unless @query.blank?
  #     @query += "(#{query})"
  #     @variables << term
  #   end
end
