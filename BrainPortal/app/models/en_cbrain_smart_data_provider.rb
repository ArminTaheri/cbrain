
#
# CBRAIN Project
#
# $Id$
#

# This class implements a 'wrapper' data provider that
# acts either as a EnCbrainLocalDataProvider or a EnCbrainSshDataProvider
# depending on whether or not the current hostname matches
# the value of the attribute remote_host.
#
# This means that in the case where the current Rails application
# runs on the same machine as the data provider, the faster
# and more efficient EnCbrainLocalDataProvider will be used.
class EnCbrainSmartDataProvider < DataProvider

  Revision_info="$Id$"

  include SmartDataProviderInterface

  def after_initialize #:nodoc:
    self.select_local_or_network_provider(EnCbrainLocalDataProvider,EnCbrainSshDataProvider)
  end
  
end

