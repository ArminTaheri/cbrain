
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

# Network Operation Center controller
# Basically just shows status information.
class NocController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  # Provides a graphical daily snapshot of activity
  def daily
    this_morning   = DateTime.now.midnight
    refresh_every  = 120.seconds
    #this_morning = 7.years.ago # uncomment to artifically show all historical data

    @myself        = RemoteResource.current_resource
    @bourreaux     = Bourreau.where([ "updated_at > ?", 1.month.ago ]).order(:name).all # must have been toggled within a month

    @active_tasks  = CbrainTask.active.count
    @data_transfer = SyncStatus.where("sync_status.status" => [ 'ToCache', 'ToProvider' ])
                               .joins(:userfile)
                               .sum("userfiles.size")
                               .to_i # because we sometimes get the string "0" ?!?

    #@active_tasks = rand(500)  # uncomment to make visual tests
    #@data_transfer = rand(500_000_000_000)  # uncomment to make visual tests

    @status_counts = @bourreaux.map do |b|     # bourreau_id => { 'New' => 2, ... }, ...
      s2c = b.cbrain_tasks.where(["updated_at > ?",this_morning]).group(:status).count
      [ b.id, s2c ]
    end.to_h

    @cached_files = (@bourreaux + [ @myself ]).map do |b|
      size = SyncStatus.where(:remote_resource_id => b.id)
                       .where([ "sync_status.updated_at > ?", this_morning ])
                       .joins(:userfile)
                       .sum("userfiles.size")
                       .to_i # because we sometimes get the string "0"  ?!?
      [ b.id, size ]
    end.to_h

    @created_files = Userfile.where([ "userfiles.created_at > ?", this_morning ])
                             .joins(:data_provider)
                             .order("data_providers.name")
                             .group("data_providers.id")
                             .sum("userfiles.size")

    # Refresh
    myurl = "#{request.protocol}#{request.host_with_port}#{request.fullpath}"
    response.headers["Refresh"] = "#{refresh_every};#{myurl}"

    render :action => :daily, :layout => false # layout already in view file
  end

end
