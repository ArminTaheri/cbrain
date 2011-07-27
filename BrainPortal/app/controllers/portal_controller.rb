
#
# CBRAIN Project
#
# Contoller for the entrypoint to cbrain
#
# Original author: Tarek Sherif
#
# $Id$
#

#Controller for the entry point into the system.
class PortalController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__]
  
  #Display a user's home page with information about their account.
  def welcome #:nodoc:
    unless current_user
      redirect_to login_path 
      return
    end
    
    @num_files              = current_user.userfiles.size
    @groups                 = current_user.has_role?(:admin) ? current_user.groups.order(:name) : current_user.available_groups.order(:name)
    @default_data_provider  = DataProvider.find_by_id(current_user.meta["pref_data_provider_id"])
    @default_bourreau       = Bourreau.find_by_id(current_user.meta["pref_bourreau_id"])     
        
    if current_user.has_role? :admin
      @active_users = CbrainSession.active_users
      @active_users.unshift(current_user) unless @active_users.include?(current_user)
      if request.post?
        unless params[:clear_sessions].blank?
          CbrainSession.session_class.destroy_all(["updated_at < ?", params[:clear_sessions].to_i.seconds.ago])
        end
        if params[:lock_portal] == "lock"
          BrainPortal.current_resource.lock!
          message = params[:message] || ""
          message = "" if message =~ /\(lock message\)/ # the default string
          BrainPortal.current_resource.meta[:portal_lock_message] = message
          flash.now[:notice] = "This portal has been locked."
        elsif params[:lock_portal] == "unlock"
          BrainPortal.current_resource.unlock!
          flash.now[:notice] = "This portal has been unlocked."
          flash.now[:error] = ""        
        end
      end
    #elsif current_user.has_role? :site_manager
    #  @active_users = CbrainSession.active_users.where( :site_id  => current_user.site_id )
    #  @active_users.unshift(current_user) unless @active_users.include?(current_user)
    end
    
    bourreau_ids = Bourreau.find_all_accessible_by_user(current_user).collect(&:id)
    @tasks = CbrainTask.where( :user_id => current_user.id, :bourreau_id => bourreau_ids )
    @tasks_by_status = @tasks.hashed_partitions do |task|
      case task.status
      when /((#{CbrainTask::COMPLETED_STATUS.join('|')}))/o
        :completed
      when /(#{CbrainTask::RUNNING_STATUS.join('|')})/o
        :running
      when /(#{CbrainTask::FAILED_STATUS.join('|')})/o
        :failed
      else
        :other
      end
    end

    @tasks_by_status[:completed] ||= []
    @tasks_by_status[:running]   ||= []
    @tasks_by_status[:failed]    ||= []
  end
  
  #Display general information about the CBRAIN project.
  def credits #:nodoc:
    # Nothing to do, just let the view show itself.
  end
  
  #Displays more detailed info about the CBRAIN project.
  def about_us #:nodoc:
    myself = RemoteResource.current_resource
    info   = myself.info

    @revinfo = { 'Revision'            => info.revision,
                 'Last Changed Author' => info.lc_author,
                 'Last Changed Rev'    => info.lc_rev,
                 'Last Changed Date'   => info.lc_date
               }

  end
  
end
