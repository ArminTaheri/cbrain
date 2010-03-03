
#
# CBRAIN Project
#
# Original author: Pierre Rioux
#
# $Id$
#


#
# This class is used to model the synchronization status of
# the contents of userfiles. The records are mostly used and
# managed by the DataProvider class; they are not really
# meant to be useful to anybody else.
#
# Each record contains the information about the status
# of one pair of [ userfile_id, remote_resource_id ];
# the remote_resource_id identifies the local CACHE of
# either a Bourreau or a BrainPortal with that ID.
#
# A non-existing record for such a pair means that the
# data exist on the Provider side and no known copy exist in
# the RemoteResource (cache) side.
#
# The possible status keywords are:
#
# ProvNewer::    No known content on cache side, or content
#                on DP side known to be newer (default when
#                there are no SyncStatus object at all)
# CacheNewer::   Content on cache side known to be newer than on DP
# InSync::       Cache contains a sync'ed version of DP's content
# ToCache::      DP content is being copied to cache 
# ToProvider::   Cache content is being copied to DP
# Corrupted::    Some transfer ToProvider never completed
#
# The model also uses two timestamps fields outside of Rail's
# standard created_at and updated_at:
#
# synced_at::    The last time the userfile's content was
#                requested for synchronization in one direction
#                or the other, and the synchronization was
#                actually performed and successful.
# accessed_at::  The last time the object's content was
#                requested for synchronization in one direction
#                or the other; unlike synced_at this timestamp
#                is updated even if the synchronization might
#                not actually have been performed because
#                the content was already synchronized and
#                younger than the RemoteResource's threshold
#                (specified by its cache_trust_expire).
class SyncStatus < ActiveRecord::Base

  Revision_info="$Id$"

  CheckInterval   = 10.seconds
  CheckMaxWait    = 24.hours
  TransferTimeout = 12.hours
  DebugMessages   = false

  belongs_to              :userfile
  belongs_to              :remote_resource

  # This uniqueness restriction is VERY IMPORTANT.
  # It's expected to make the create!() method return
  # an exception in get_or_create_status().
  validates_uniqueness_of :remote_resource_id, :scope => :userfile_id


  # This method normally returns the value of
  # the attribute +accessed_at+ but if it's not
  # yet set, it uses the value of +updated_at+ .
  def accessed_at
    val = super
    val = updated_at if val.blank?
    val
  end

  # This method normally returns the value of
  # the attribute +synced_at+ but if it's not
  # yet set, it returns a value WAY in the
  # past (2 years ago)
  def synced_at
    val = super
    val = 2.years.ago if val.blank?
    val
  end

  # This method will block until the content of the
  # file on the data provider is available to be copied
  # to the local cache.
  def self.ready_to_copy_to_cache(userfile)

    # For brand new files, the userfile_id is nil,
    # so we simply skip the sync mechanism altogether.
    userfile_id = userfile.id
    unless userfile_id
      return yield
    end

    state  = self.get_or_create_status(userfile_id)
    puts "SYNC: ToCache: #{state.pretty} Enter" if DebugMessages

    # Wait until no other local client is copying the file's content
    # in one direction or the other.
    allok = repeat_every_formax_untilblock(CheckInterval,CheckMaxWait) do
      state.reload
      state.invalidate_old_status
      puts "SYNC: ToCache: #{state.pretty} Check" if DebugMessages
      state.status !~ /^To/  # no ToProvider or ToCache
    end
    puts "SYNC: ToCache: #{state.pretty} Proceed" if DebugMessages

    if ! allok # means timeout occured
      oldstate = state.status
      state.update_attributes( :status => "ProvNewer" )
      raise "Sync error: timeout waiting for file '#{userfile_id}' " +
            "in '#{oldstate}' for operation 'ToCache'."
    end

    # No need to do anything if the data is already in sync!
    if state.status == "InSync"
      state.update_attributes( :accessed_at => Time.now )
      return true
    end

    if state.status == "Corrupted"
      raise "Sync error: file '#{userfile_id}' marked 'Corrupted' " +
            "for operation 'ToCache'."
    end

    # Adjust state to let all other processes know what
    # WE want to do now. This will lock out other clients.
    state.update_attributes( :status => "ToCache" )
    puts "SYNC: ToCache: #{state.pretty} Update" if DebugMessages

    # Wait until all other clients out there are done
    # transfering content to the DP side. We don't care
    # if other clients are also copying to their cache, though.
    allok = repeat_every_formax_untilblock(CheckInterval,CheckMaxWait) do
      others = self.get_status_of_other_caches(userfile_id)
      uploading = others.detect { |o| o.status == "ToProvider" }
      puts "SYNC: ToCache: #{uploading.pretty} Other" if uploading && DebugMessages
      uploading.nil?
    end

    if ! allok # means timeout occured
      state.update_attributes( :status => "ProvNewer" )
      raise "Sync error: timeout waiting for other clients for " +
            "file '#{userfile_id}' for operation 'ToCache'."
    end

    # Now, perform the sync_to_cache operation.
    begin
      puts "SYNC: ToCache: #{state.pretty} YIELD" if DebugMessages
      implstatus = yield
      state.update_attributes( :status => "InSync", :accessed_at => Time.now, :synced_at => Time.now )
      puts "SYNC: ToCache: #{state.pretty} Finish" if DebugMessages
      return implstatus
    rescue => implerror
      state.update_attributes( :status => "ProvNewer" ) # cache is no good
      puts "SYNC: ToCache: #{state.pretty} Except" if DebugMessages
      raise implerror
    end

  end



  # This method will block until the content of the
  # file in the cache is available to be copied
  # to the data provider.
  def self.ready_to_copy_to_dp(userfile)

    # For brand new files, the userfile_id is nil,
    # so we simply skip the sync mechanism altogether.
    userfile_id = userfile.id
    unless userfile_id
      return yield
    end

    state  = self.get_or_create_status(userfile_id)
    puts "SYNC: ToProv: #{state.pretty} Enter" if DebugMessages

    # Wait until no other local client is copying the file's content
    # in one direction or the other.
    allok = repeat_every_formax_untilblock(CheckInterval,CheckMaxWait) do
      state.reload
      state.invalidate_old_status
      puts "SYNC: ToProv: #{state.pretty} Check" if DebugMessages
      state.status !~ /^To/  # no ToProvider or ToCache
    end
    puts "SYNC: ToProv: #{state.pretty} Proceed" if DebugMessages

    if ! allok # means timeout occured
      oldstate = state.status
      state.update_attributes( :status => "CacheNewer" )
      raise "Sync error: timeout waiting for file '#{userfile_id}' " +
            "in '#{oldstate}' for operation 'ToProvider'."
    end

    # No need to do anything if the data is already in sync!
    if state.status == "InSync"
      state.update_attributes( :accessed_at => Time.now )
      return true
    end

    # Adjust state to let all other processes know what
    # WE want to do now. This will lock out other clients.
    state.update_attributes( :status => "ToProvider" )
    puts "SYNC: ToProv: #{state.pretty} Update" if DebugMessages

    # Wait until all other clients out there are done
    # transfering content to/from the provider, one way or the other.
    allok = repeat_every_formax_untilblock(CheckInterval,CheckMaxWait) do
      others = self.get_status_of_other_caches(userfile_id)
      uploading = others.detect { |o| o.status =~ /^To/ }
      puts "SYNC: ToProv: #{uploading.pretty} Other" if uploading && DebugMessages
      uploading.nil?
    end

    if ! allok # means timeout occured
      state.update_attributes( :status => "CacheNewer" )
      raise "Sync error: timeout waiting for other clients for " +
            "file '#{userfile_id}' for operation 'ToProvider'."
    end

    # Now, perform the ToProvider operation.
    begin
      # Let's tell every other clients that their cache is now
      # obsolete.
      puts "SYNC: ToProv: #{state.pretty} Others => ProvNewer" if DebugMessages
      others = self.get_status_of_other_caches(userfile_id)
      others.each { |o| o.update_attributes( :status => "ProvNewer" ) }
      # Call the provider's implementation of the sync operation.
      puts "SYNC: ToProv: #{state.pretty} YIELD" if DebugMessages
      implstatus = yield
      state.update_attributes( :status => "InSync", :accessed_at => Time.now, :synced_at => Time.now )
      puts "SYNC: ToProv: #{state.pretty} Finish" if DebugMessages
      return implstatus
    rescue => implerror
      state.update_attributes( :status => "Corrupted" ) # provider is no good
      puts "SYNC: ToProv: #{state.pretty} Except" if DebugMessages
      raise implerror
    end

  end



  # This method will block until the content of the
  # file in the cache is available to be modified.
  # It doesn't care about the status of the provider.
  def self.ready_to_modify_cache(userfile, final_status = 'CacheNewer')

    # For brand new files, the userfile_id is nil,
    # so we simply skip the sync mechanism altogether.
    userfile_id = userfile.id
    unless userfile_id
      return yield
    end

    state  = self.get_or_create_status(userfile_id)
    puts "SYNC: ModCache: #{state.pretty} Enter" if DebugMessages

    # Wait until no other local client is copying the file's content
    # in one direction or the other.
    allok = repeat_every_formax_untilblock(CheckInterval,CheckMaxWait) do
      state.reload
      state.invalidate_old_status
      puts "SYNC: ModCache: #{state.pretty} Check" if DebugMessages
      state.status !~ /^To/  # no ToProvider or ToCache
    end
    puts "SYNC: ModCache: #{state.pretty} Proceed" if DebugMessages

    if ! allok # means timeout occured
      oldstate = state.status
      raise "Sync error: timeout waiting for file '#{userfile_id}' " +
            "in '#{oldstate}' for operation 'ModifyCache'."
    end

    # Adjust state to let all other processes know that
    # we want to modify the cache. "ToCache" is not exactly
    # true, as we are not copying from the DP, but it will
    # still lock out other processes trying to start data
    # operations, which is what we want.
    state.update_attributes( :status => "ToCache" ) # TODO not exactly true
    puts "SYNC: ModCache: #{state.pretty} Update" if DebugMessages

    # Now, perform the ModifyCache operation
    begin
      puts "SYNC: ModCache: #{state.pretty} YIELD" if DebugMessages
      implstatus = yield
      if final_status == "ProvNewer"
        state.destroy
      else
        state.update_attributes( :status => final_status )
      end
      puts "SYNC: ModCache: #{state.pretty} Finish" if DebugMessages
      return implstatus
    rescue => implerror
      state.update_attributes( :status => "ProvNewer" ) # cache is no longer good
      puts "SYNC: ModCache: #{state.pretty} Except" if DebugMessages
      raise implerror
    end

  end



  # This method will block until the content of the
  # file on the data provider is available to be modified.
  # It doesn't care about the status of the cache.
  def self.ready_to_modify_dp(userfile)

    # For brand new files, the userfile_id is nil,
    # so we simply skip the sync mechanism altogether.
    userfile_id = userfile.id
    unless userfile_id
      return yield
    end

    state  = self.get_or_create_status(userfile_id)
    puts "SYNC: ModProv: #{state.pretty} Entering" if DebugMessages

    # Wait until no other local client is copying the file's content
    # in one direction or the other.
    allok = repeat_every_formax_untilblock(CheckInterval,CheckMaxWait) do
      state.reload
      state.invalidate_old_status
      puts "SYNC: ModProv: #{state.pretty} Check" if DebugMessages
      state.status !~ /^To/  # no ToProvider or ToCache
    end
    puts "SYNC: ModProv: #{state.pretty} Proceed" if DebugMessages

    if ! allok # means timeout occured
      oldstate = state.status
      state.update_attributes( :status => "CacheNewer" )
      raise "Sync error: timeout waiting for file '#{userfile_id}' " +
            "in '#{oldstate}' for operation 'ModifyProvider'."
    end

    # Adjust state to let all other processes know that
    # we want to modify the provider side. "ToProvider" is not
    # exactly true, as we are not copying to the DP, but it will
    # still lock out other processes trying to start data
    # operations, which is what we want.
    state.update_attributes( :status => "ToProvider" ) # TODO not exactly true
    puts "SYNC: ModProv: #{state.pretty} Update" if DebugMessages

    # Wait until all other clients out there are done
    # transfering content to/from the provider, one way or the other.
    allok = repeat_every_formax_untilblock(CheckInterval,CheckMaxWait) do
      others = self.get_status_of_other_caches(userfile_id)
      uploading = others.detect { |o| o.status =~ /^To/ }
      puts "SYNC: ModProv: #{uploading.pretty} Other" if uploading && DebugMessages
      uploading.nil?
    end

    if ! allok # means timeout occured
      raise "Sync error: timeout waiting for other clients for " +
            "file '#{userfile_id}' for operation 'ModifyProvider'."
    end

    # Now, perform the ModifyProvider operation.
    begin
      puts "SYNC: ModProv: #{state.pretty} YIELD" if DebugMessages
      implstatus = yield
      others = self.get_status_of_other_caches(userfile_id)
      others.each { |o| o.destroy } # Zap all other status fields...
      state.destroy                 # ... then zap ours. A bit like ProvNewer.
      puts "SYNC: ModProv: Destroyed ALL" if DebugMessages
      return implstatus
    rescue => implerror
      state.update_attributes( :status => "Corrupted" ) # dp is no longer good
      puts "SYNC: ModProv: #{state.pretty} Except" if DebugMessages
      raise implerror
    end
  end

  # This method does two things:
  #
  # Changes an object's InSync status if this state has been
  # recorded too long ago according to the current
  # RemoteResource's configuration for cache_trust_expire.
  #
  # Changes an object's status if it's been too long since
  # it has been updated, when the status was an action operation
  # that was aborted.
  def invalidate_old_status

    # "InSync" state is too old for current RemoteResource
    myself = RemoteResource.current_resource
    expire = myself.cache_trust_expire # in seconds before now
    expire = nil if expire && expire < 3600 # we don't accept thresholds less than one hour
    expire = 2.years.to_i if expire and expire > 2.years.to_i
    if expire and self.status == "InSync" && self.synced_at < Time.now - expire
      puts "SYNC: Invalid: #{self.pretty} InSync Is Too Old" if DebugMessages
      self.update_attributes( :status => "ProvNewer" )
      return
    end

    # ToProvider or ToCache states are too old (aborted?)
    if self.updated_at && self.updated_at < Time.now - TransferTimeout
      self.update_attributes( :status => "Corrupted" ) if self.status == "ToProvider"
      self.update_attributes( :status => "ProvNewer" ) if self.status == "ToCache"
      return
    end

  end

  # For debugging: prints a pretty summary of this object.
  def pretty #:nodoc:
     self.id.to_s + "=" + self.remote_resource.name + "/" + self.status.to_s
  end



  protected

  # Fetch (or create if necessary) the SyncStatus object
  # that tracks the particular pair ( +userfile_id+ , +remote_resource_id+ ).
  def self.get_or_create_status(userfile_id)
    state = self.create!(
      :userfile_id        => userfile_id,
      :remote_resource_id => CBRAIN::SelfRemoteResourceId,
      :status             => "ProvNewer",
      :accessed_at        => Time.now,
      :synced_at          => 2.years.ago
    ) rescue nil
    puts "SYNC: Status: #{state.pretty} Create" if   state && DebugMessages
    puts "SYNC: Status: Exist"                  if ! state && DebugMessages
    # if we can't create it (because of validation rules), it already exists
    state ||= self.find(:first, :conditions => {
                                :userfile_id        => userfile_id,
                                :remote_resource_id => CBRAIN::SelfRemoteResourceId,
                                })
    state.invalidate_old_status
    state
  end

  # Fetch the list of all SyncStatus objects that track the
  # sync states associated with +userfile_id+ on caches
  # OTHER than the one for +res_id+; you can pass
  # +nil+ to +res_id+ to get them all.
  def self.get_status_of_other_caches(userfile_id,res_id = CBRAIN::SelfRemoteResourceId)
    states = self.find(:all, :conditions => { :userfile_id => userfile_id } )
    if res_id
      states = states.select { |s| s.remote_resource_id != res_id }
    end
    states.each { |s| s.invalidate_old_status }
    states
  end

  private

  # Repeats a block of code every +numseconds+, for up to +maxseconds+,
  # or until the block returns a true value. Returns false
  # if the +maxseconds+ time is exceeded.
  def self.repeat_every_formax_untilblock(numseconds,maxseconds) #:nodoc:
    starttime = Time.now
    endtime   = starttime+maxseconds
    stopnow   = false
    while (Time.now < endtime) do
      stopnow = yield
      break if stopnow
      sleep numseconds.to_i
    end
    stopnow
  end

  # This method changes the status attribute
  # in the current task object to +to_state+ but
  # also makes sure the current value is +from_state+ .
  # The change is performed in a transaction where
  # the record is locked, to ensure the transition is
  # not trashed by another process. The method returns
  # true if the transition was successful, and false
  # if anything went wrong.
  def status_transition(from_state, to_state)
    SyncStatus.transaction do
      self.lock!
      return false if self.status != from_state 
      return true  if from_state == to_state # NOOP
      self.status = to_state
      self.save!
    end
    true
  end

  # This method acts like status_transition(),
  # but it raises a CbrainTransitionException
  # on failures.
  def status_transition!(from_state, to_state)
    unless status_transition(from_state,to_state)
      ohno = CbrainTransitionException.new(
        "Sync status was changed before lock was acquired for sync object '#{self.id}'.\n" +
        "Expected: '#{from_state}' found: '#{self.status}'."
      )
      ohno.original_object = self
      ohno.from_state      = from_state
      ohno.to_state        = to_state
      ohno.found_state     = self.status
      raise ohno
    end
    true
  end

end
