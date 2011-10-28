
#
# CBRAIN Project
#
# Bourreau controller for the BrainPortal interface
#
# Original author: Pierre Rioux
#
# $Id$
#

# RESTful controller for managing the Bourreau (remote execution server) resource. 
# All actions except +index+ and +show+ require *admin* privileges.
class BourreauxController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__]
  
  api_available :except  => :row_data

  before_filter :login_required
  before_filter :manager_role_required, :except  => [:index, :show, :row_data, :load_info]
   
  def index #:nodoc:
    @filter_params["sort_hash"]["order"] ||= "remote_resources.type"
    @filter_params["sort_hash"]["dir"] ||= "DESC"
    @header_scope = RemoteResource.find_all_accessible_by_user(current_user)
    @bourreaux    = base_filtered_scope @header_scope.includes(:user, :group)

    if current_user.has_role? :admin
      @filter_params['details'] = 'on' unless @filter_params.has_key?('details')
    end
    
    respond_to do |format|
      format.html
      format.xml  { render :xml => @bourreaux }
      format.js
    end
  end
  
  def show #:nodoc:
    @users    = current_user.available_users
    @bourreau = RemoteResource.find(params[:id])

    cb_notice "Execution Server not accessible by current user." unless @bourreau.can_be_accessed_by?(current_user)

    @info = @bourreau.info

    myusers = current_user.available_users

    stats = ModelsReport.gather_task_statistics(
               :users     => myusers,
               :bourreaux => @bourreau
         )


    status_stats     = stats[0]
    @statuses        = status_stats[:statuses]
    @statuses_list   = status_stats[:statuses_list]
    @user_tasks_info = status_stats[:user_task_info]

    type_stats       = stats[1]
    @types           = type_stats[:types]
    @types_list      = type_stats[:types_list]
    @user_types_info = type_stats[:user_types_info]

    
    @log = @bourreau.getlog

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @bourreau }
    end

  end
  
  def new #:nodoc:
    bourreau_group_id = ( current_project && current_project.id ) || current_user.own_group.id
    @users    = current_user.available_users
    @groups   = current_user.available_groups
    @bourreau = Bourreau.new( :user_id   => current_user.id,
                              :group_id  => bourreau_group_id,
                              :cache_trust_expire => 1.month.to_i.to_s,
                              :online    => true
                            )
    sensible_defaults(@bourreau)
    render :partial => "new"
  end
  
  def edit #:nodoc:
    @bourreau = RemoteResource.find(params[:id])
    
    cb_notice "Execution Server not accessible by current user." unless @bourreau.has_owner_access?(current_user)
    
    @users  = current_user.available_users
    @groups = current_user.available_groups

    sensible_defaults(@bourreau)

    respond_to do |format|
      format.html { render :action => :edit }
      format.xml  { render :xml => @bourreau }
    end

  end

  def create #:nodoc:
    fields    = params[:bourreau]

    @bourreau = Bourreau.new( fields )
    @bourreau.save

    if @bourreau.errors.empty?
      flash[:notice] = "Execution Server successfully created."
      
      respond_to do |format|
        format.js  { redirect_to :action => :index, :format => :js }
        format.xml { render :xml => @bourreau }
      end
    else
      respond_to do |format|
        format.js  { render :partial => "shared/failed_create", :locals => {:model_name => "bourreau"} }
        format.xml { render :xml => @bourreau.errors.to_xml, :status => :unprocessable_entity   }
      end
    end
  end

  def update #:nodoc:

    id        = params[:id]
    @bourreau = RemoteResource.find(id)
    
    cb_notice "This #{@bourreau.class.to_s} not accessible by current user." unless @bourreau.has_owner_access?(current_user)

    fields    = @bourreau.is_a?(Bourreau) ? params[:bourreau] : params[:brain_portal]
    
    subtype = fields.delete(:type)
  
    old_dp_cache_dir = @bourreau.dp_cache_dir
    @bourreau.update_attributes(fields)

    @users  = current_user.available_users
    @groups = current_user.available_groups
    unless @bourreau.errors.empty?
      respond_to do |format|
        format.html do
          render :action => 'edit'
        end
        format.xml { render :xml  => @bourreau.errors, :status  => :unprocessable_entity}
      end
      return
    end

    # Adjust task limits, and store them into the meta data store
    syms_limit_users = @users.map { |u| "task_limit_user_#{u.id}".to_sym }
    add_meta_data_from_form(@bourreau, [ :task_limit_total, :task_limit_user_default ] + syms_limit_users )

    if old_dp_cache_dir != @bourreau.dp_cache_dir
      old_ss = SyncStatus.where( :remote_resource_id => @bourreau.id )
      old_ss.each do |ss|
        ss.destroy rescue true
      end
      info_message = "Since the Data Provider cache directory has been changed, all\n" +
                     "synchronization status objects were reset.\n"
      unless old_dp_cache_dir.blank?
        host = @bourreau.ssh_control_host
        host = @bourreau.actres_host      if host.blank?
        host = 'localhost'                if host.blank?
        info_message += "You may have to clean up the content of the old cache directory\n" +
                        "'#{old_dp_cache_dir}' on host '#{host}'\n"
      end
      Message.send_message(current_user,
        :message_type => :system,
        :critical     => true,
        :header       => "Data Provider cache directory changed for #{@bourreau.class} '#{@bourreau.name}'",
        :description  => info_message
      )
    end

    flash[:notice] = "#{@bourreau.class.to_s} #{@bourreau.name} successfully updated"

    respond_to do |format|
      format.html do
        if params[:tool_management] != nil 
          redirect_to(:controller => "tools", :action =>"tool_management")
        else
          redirect_to(bourreaux_url)
        end
      end
      format.xml { head :ok }
    end
  end

  def destroy #:nodoc:
    id        = params[:id]
    @bourreau = RemoteResource.find(id)
    
    raise CbrainDeleteRestrictionError.new("Execution Server not accessible by current user.") unless @bourreau.has_owner_access?(current_user)
    
    @bourreau.destroy
    
    flash[:notice] = "Execution Server successfully deleted."
      
    respond_to do |format|
      format.js  { redirect_to :action => :index, :format => :js}
      format.xml { head :ok }
    end
  rescue ActiveRecord::DeleteRestrictionError => e
    flash[:error] = "Execution Server destruction failed: #{e.message.humanize}."
    
    respond_to do |format|
      format.js  { redirect_to :action => :index, :format => :js}
      format.xml { head :conflict }
    end
  end
  
  def row_data #:nodoc:
    @remote_resource = RemoteResource.find_accessible_by_user(params[:id], current_user)
    render :partial => 'bourreau_table_row', :locals  => { :bourreau  => @remote_resource }
  end

  def load_info #:nodoc:

    if params[:current_value].blank?
      render :text  => ""
      return
    end

    @bourreau  = Bourreau.find(params[:current_value])

    respond_to do |format|
      format.html { render :partial => 'load_info', :locals => { :bourreau => @bourreau } }
      format.xml  { render :xml     => @bourreau   }
    end

  rescue => ex
    #render :text  => "#{ex.class} #{ex.message}\n#{ex.backtrace.join("\n")}"
    render :text  => '<strong style="color:red">No Information Available</strong>'
  end
  
  def refresh_ssh_keys #:nodoc:
    refreshed_bourreaux = []
    skipped_bourreaux   = []

    RemoteResource.find_all_accessible_by_user(current_user).each do |b|
      if b.is_alive?
        info = b.info
        ssh_key = info.ssh_public_key
        b.ssh_public_key = ssh_key
        b.save
        refreshed_bourreaux << b.name
      else
        skipped_bourreaux << b.name
      end
    end
    
    if refreshed_bourreaux.size > 0
      flash[:notice] = "SSH public keys have been refreshed for these Servers: " + refreshed_bourreaux.join(", ") + "\n"
    end
    if skipped_bourreaux.size > 0
      flash[:error]  = "These Servers are not alive and SSH keys couldn't be updated: " + skipped_bourreaux.join(", ") + "\n"
    end
    
    respond_to do |format|
      format.html { redirect_to :action  => :index }
      format.xml  { render :xml  => { "refreshed_bourreaux"  => refreshed_bourreaux.size, "skipped_bourreaux"  => skipped_bourreaux.size } }
    end   
  end

  def start #:nodoc:
    @bourreau = Bourreau.find(params[:id])

    cb_notice "Execution Server '#{@bourreau.name}' not accessible by current user."           unless @bourreau.can_be_accessed_by?(current_user)
    cb_notice "Execution Server '#{@bourreau.name}' is not yet configured for remote control." unless @bourreau.has_ssh_control_info?
    cb_notice "Execution Server '#{@bourreau.name}' has already been alive for #{pretty_elapsed(@bourreau.info.uptime)}." if @bourreau.is_alive?

    # New behavior: if a bourreau is marked OFFLINE we turn in back ONLINE.
    unless @bourreau.online?
      @bourreau.online=true
      @bourreau.save
    end

    @bourreau.start_tunnels
    cb_error "Could not start master SSH connection and tunnels for '#{@bourreau.name}'." unless @bourreau.ssh_master.is_alive?

    started_ok = @bourreau.start
    alive_ok   = started_ok && (sleep 3) && @bourreau.is_alive?
    workers_ok = false

    if alive_ok
      @bourreau.addlog("Rails application started by user #{current_user.login}.")
      @bourreau.reload if @bourreau.auth_token.blank? # New bourreaux? Token will have just been created.
      res = @bourreau.send_command_start_workers rescue nil
      workers_ok = true if res && res[:command_execution_status] == "OK"
    end

    # Messages

    flash[:notice] = ""
    flash[:error]  = ""

    if alive_ok
      flash[:notice] = "Execution Server '#{@bourreau.name}' started."
    elsif started_ok
      flash[:error] = "Execution Server '#{@bourreau.name}' was started but did not reply to first inquiry:\n" +
                      @bourreau.operation_messages
    else
      flash[:error] = "Execution Server '#{@bourreau.name}' could not be started. Diagnostics:\n" +
                      @bourreau.operation_messages
    end

    if workers_ok
      flash[:notice] += "\nWorkers on Execution Server '#{@bourreau.name}' started."
    elsif alive_ok
      flash[:error] += "However, we couldn't start the workers."
    end
    
    respond_to do |format|
      format.html { redirect_to :action => :index }
      format.xml  { head workers_ok ? :ok : :internal_server_error  }  # TODO change internal_server_error ?
    end  

  end

  def stop #:nodoc:
    @bourreau = Bourreau.find(params[:id])

    cb_notice "Execution Server '#{@bourreau.name}' not accessible by current user."           unless @bourreau.can_be_accessed_by?(current_user)
    cb_notice "Execution Server '#{@bourreau.name}' is not yet configured for remote control." unless @bourreau.has_ssh_control_info?

    begin
      res = @bourreau.send_command_stop_workers
      raise "Failed command to stop workers" unless res && res[:command_execution_status] == "OK" # to trigger rescue
      @bourreau.addlog("Workers stopped by user #{current_user.login}.")
      flash[:notice] = "Workers on Execution Server '#{@bourreau.name}' stopped."
    rescue
      flash[:notice] = "It seems we couldn't stop the workers on Execution Server '#{@bourreau.name}'. They'll likely die by themselves."
    end

    @bourreau.online = true # to trick layers below into doing the 'stop' operation
    success = @bourreau.stop
    @bourreau.addlog("Rails application stopped.") if success
    @bourreau.online = false
    @bourreau.save
    flash[:notice] += "\nExecution Server '#{@bourreau.name}' stopped. Tunnels stopped." if success
    flash[:error]   = "Failed to stop tunnels for '#{@bourreau.name}'."                  if ! success
    
    respond_to do |format|
      format.html { redirect_to :action => :index }
      format.xml { head :ok  }
    end

  rescue => e
    flash[:error] = e.message
    respond_to do |format|
      format.html { redirect_to :action => :index }
      format.xml { render :xml  => { :message  => e.message }, :status  => 500 }
    end
  end

  private

  # Adds sensible default values to some field for
  # new objects, or existing ones being edited.
  def sensible_defaults(portal_or_bourreau)
    if portal_or_bourreau.is_a?(BrainPortal)
      if portal_or_bourreau.site_url_prefix.blank?
        guess = "http://" + request.env["HTTP_HOST"] + "/"
        portal_or_bourreau.site_url_prefix = guess
      end
    end

    if portal_or_bourreau.dp_ignore_patterns.nil? # not blank, nil!
      portal_or_bourreau.dp_ignore_patterns = [ ".DS_Store", "._*" ]
    end
  end

end
