#
# CBRAIN Project
#
# $Id$
#

class PerlSourceFile < TextFile

  Revision_info="$Id$"
  
  def self.pretty_type
    "Perl script"
  end

  def self.file_name_pattern
    /\.(pl|pm)$/i
  end
  
end
