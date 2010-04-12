
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

  Revision_info="$Id$"

  before_filter :login_required
  before_filter :manager_role_required, :except  => [:index, :show]
   
  def index #:nodoc:
    if current_user.has_role?(:admin)
      @bourreaux = RemoteResource.all
      @bourreaux.sort! { |a,b| b.class.to_s <=> a.class.to_s } # we depend on 'BrainPortal' > 'Bourreau'
    else
      @bourreaux = Bourreau.find_all_accessible_by_user(current_user)
    end
  end
  
  def show #:nodoc:
    @bourreau = RemoteResource.find(params[:id])

    cb_notice "Execution Server not accessible by current user." unless @bourreau.can_be_accessed_by?(current_user)

    @info = @bourreau.info

    @user_id_name = {}
    User.all.each { |user| @user_id_name[user.id] = user.login }
    
    @user_tasks_info = {}
    begin
       tasks = ActRecTask.find(:all, :conditions => { :bourreau_id => @bourreau.id })
    rescue
       tasks = []
    end

    @statuses = { 'TOTAL' => 0 }
    tasks.each do |t|
      user_id = t.user_id.to_i
      name    = @user_id_name[user_id] || "User-#{user_id}"
      status  = t.status
      @statuses[status]               ||= 0
      @statuses[status]                += 1
      @statuses['TOTAL']               += 1
      @user_tasks_info[name]          ||= {}
      @user_tasks_info[name][status]  ||= 0
      @user_tasks_info[name][status]   += 1
      @user_tasks_info[name]['TOTAL'] ||= 0
      @user_tasks_info[name]['TOTAL']  += 1
    end
    @statuses_list = @statuses.keys.sort.reject { |s| s == 'TOTAL' }
    @statuses_list << 'TOTAL'

    @log = @bourreau.getlog

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @bourreau }
    end

  end
  
  def edit #:nodoc:
    @bourreau = RemoteResource.find(params[:id])
    
    cb_notice "Execution Server not accessible by current user." unless @bourreau.has_owner_access?(current_user)
    
    @users = current_user.available_users
    @groups = current_user.available_groups

    respond_to do |format|
      format.html { render :action => :edit }
      format.xml  { render :xml => @bourreau }
    end

  end

  def new  #:nodoc:
    @bourreau = Bourreau.new( :user_id   => current_user.id,
                              :group_id  => Group.find_by_name(current_user.login).id,
                              :online    => true
                            )

    respond_to do |format|
      format.html { render :action => :new }
      format.xml  { render :xml => @bourreau }
    end

  end

  def create #:nodoc:
    fields    = params[:bourreau]

    @bourreau = Bourreau.new( fields )
    @bourreau.save

    

    if @bourreau.errors.empty?
      flash[:notice] = "Execution Server successfully created."
    end
   
    respond_to do |format|
      format.js
    end
  end

  def update #:nodoc:
    id        = params[:id]
    @bourreau = RemoteResource.find(id)
    
    cb_notice "This #{@bourreau.class.to_s} not accessible by current user." unless @bourreau.has_owner_access?(current_user)

    fields    = @bourreau.is_a?(Bourreau) ? params[:bourreau] : params[:brain_portal]
    
    subtype = fields.delete(:type)
  
    @bourreau.update_attributes(fields)

    @bourreau.save

    if @bourreau.errors.empty?
      if params[:tool_management] != nil 
        redirect_to(:controller => "tools", :action =>"tool_management")
        flash[:notice] = "#{@bourreau.name} successfully updated"
      else
        redirect_to(bourreaux_url)
        flash[:notice] = "#{@bourreau.class.to_s} successfully updated."
      end
    else
      @users = current_user.available_users
      @groups = current_user.available_groups
      render :action => 'edit'
      return
    end

  end

  def destroy #:nodoc:
    id        = params[:id]
    @bourreau = Bourreau.find(id)
    @destroyed = false
    
    cb_notice "Execution Server not accessible by current user." unless @bourreau.has_owner_access?(current_user)

    tasks_left = 0
    begin
      DrmaaTask.adjust_site(@bourreau.id)
      tasks_left = DrmaaTask.find(:all).size
    rescue
    end
    cb_notice "This Execution Server cannot be deleted as there are still #{tasks_left} tasks associated with it." if tasks_left > 0

    if @bourreau.destroy
      @destroyed = true
      flash[:notice] = "Execution Server successfully deleted."
    else
      flash[:error] = "Execution Server destruction failed."
    end

    respond_to do |format|
      format.html {redirect_to :action  => :index}
      format.js
    end

  end
  
  def row_data
    @bourreau = RemoteResource.find_accessible_by_user(params[:id], current_user)
    render :partial => 'bourreau_row_elements', :locals  => {:bour  => @bourreau}
  end

  def start
    @bourreau = Bourreau.find(params[:id])

    cb_notice "This Execution Server not accessible by current user."           unless @bourreau.can_be_accessed_by?(current_user)
    cb_notice "This Execution Server is not yet configured for remote control." unless @bourreau.has_ssh_control_info?
    cb_notice "This Execution Server is already alive."                         if @bourreau.is_alive?

    # New behavior: if a bourreau is marked OFFLINE we turn in back ONLINE.
    unless @bourreau.online?
      #cb_notice "This Execution Server is not marked as online."
      @bourreau.online=true
      @bourreau.save
    end

    @bourreau.start_tunnels
    cb_error "Could not start master SSH connection and tunnels." unless @bourreau.ssh_master.is_alive?
    @bourreau.start

    if @bourreau.is_alive?
      flash[:notice] = "Execution Server started."
      @bourreau.addlog("Rails application started by user #{current_user.login}.")
      begin
        @bourreau.reload if @bourreau.auth_token.blank? # New bourreaux? Token will have just been created.
        @bourreau.send_command_start_workers
        @bourreau.addlog("Workers started too.")
        flash[:notice] += "\nWorkers on Execution Server started."
      rescue
        flash[:notice] += "\nHowever, we couldn't start the workers."
      end
    else
      flash[:error] = "Execution Server could not be started. Diagnostics:\n" +
                      @bourreau.operation_messages
    end

    redirect_to :action => :index

  rescue => e
    flash[:error] = e.message
    redirect_to :action => :index
  end

  def stop
    @bourreau = Bourreau.find(params[:id])

    cb_notice "Execution Server not accessible by current user."           unless @bourreau.can_be_accessed_by?(current_user)
    cb_notice "Execution Server is not yet configured for remote control." unless @bourreau.has_ssh_control_info?

    begin
      @bourreau.send_command_stop_workers
      @bourreau.addlog("Workers stopped by user #{current_user.login}.")
      flash[:notice] = "Workers on Execution Server stopped."
    rescue
      flash[:notice] = "It seems we couldn't stop the workers. They'll likely die by themselves."
    end

    @bourreau.stop
    @bourreau.ssh_master.stop
    @bourreau.addlog("Rails application stopped.")
    flash[:notice] += "\nExecution Server stopped. Tunnels stopped."
    redirect_to :action => :index

  rescue => e
    flash[:error] = e.message
    redirect_to :action => :index
  end

end
