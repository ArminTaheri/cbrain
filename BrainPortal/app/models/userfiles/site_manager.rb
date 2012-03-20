
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.  
#

class SiteManager < NormalUser
  
  def available_tools  #:nodoc:
    Tool.where( ["tools.user_id = ? OR tools.group_id IN (?) OR tools.user_id IN (?)", self.id, self.group_ids, self.site.user_ids])
  end
  
  def available_groups  #:nodoc:
    group_scope = Group.where(["groups.id IN (select groups_users.group_id from groups_users where groups_users.user_id=?) OR groups.site_id=?", self.id, self.site_id])
    group_scope = group_scope.where("groups.name <> 'everyone'")
    group_scope = group_scope.where(["groups.type NOT IN (?)", InvisibleGroup.descendants.map(&:to_s).push("InvisibleGroup") ])      
  
    
    group_scope
  end
  
  def available_tasks  #:nodoc:
    CbrainTask.where( ["cbrain_tasks.user_id = ? OR cbrain_tasks.group_id IN (?) OR cbrain_tasks.user_id IN (?)", self.id, self.group_ids, self.site.user_ids] )
  end
  
  def available_users  #:nodoc:
    self.site.users
  end
  
end