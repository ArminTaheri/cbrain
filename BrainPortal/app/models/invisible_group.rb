
#
# CBRAIN Project
#
# Original author: Pierre Rioux
#
# $Id$
#

# This model represents the group specific to a user.
class InvisibleGroup < SystemGroup

  Revision_info=CbrainFileRevision[__FILE__]

  #def can_be_accessed_by?(user, access_requested = :read) #:nodoc:
  #  user.has_role? :admin
  #end

  def can_be_edited_by?(user) #:nodoc:
    user.has_role? :admin
  end
  
end
