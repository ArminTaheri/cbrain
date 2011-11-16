
#
# CBRAIN Project
#
# Users controller for the BrainPortal interface
#
# Original author: restful_authentication plugin
# Modified by: Tarek Sherif
#
# $Id$
#

#RESTful controller for the User resource.
class UsersController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__]

  before_filter :login_required,        :except => [:request_password, :send_password]  
  before_filter :manager_role_required, :except => [:show, :edit, :update, :request_password, :send_password]  
  
  def index #:nodoc:
    @filter_params["sort_hash"]["order"] ||= 'users.full_name'
    
    sort_order = "#{@filter_params["sort_hash"]["order"]} #{@filter_params["sort_hash"]["dir"]}"
    
    @header_scope = current_user.available_users
    
    @users = base_filtered_scope @header_scope.includes( [:groups, :site] ).order( sort_order )

    # Precompute file and task counts.
    @users_file_counts = {}
    @users_task_counts = {}
    Userfile.where(:user_id => @users.map(&:id)).select("user_id, count(user_id) as u_cnt").group(:user_id).all.each do |t|
      @users_file_counts[t.user_id] = t.u_cnt
    end
    CbrainTask.where(:user_id => @users.map(&:id)).select("user_id, count(user_id) as u_cnt").group(:user_id).all.each do |t|
      @users_task_counts[t.user_id] = t.u_cnt
    end
    
    respond_to do |format|
      format.html # index.html.erb
      format.js
      format.xml  { render :xml => @users }
    end
  end
  
  # GET /user/1
  # GET /user/1.xml
  def show #:nodoc:
    @user = User.find(params[:id], :include => :groups)
    
    cb_error "You don't have permission to view this page.", :redirect  => home_path unless edit_permission?(@user)

    @default_data_provider  = DataProvider.find_by_id(@user.meta["pref_data_provider_id"])
    @default_bourreau       = Bourreau.find_by_id(@user.meta["pref_bourreau_id"]) 
    @log                    = @user.getlog()

    # Create disk usage statistics table
    stats_options = { :users            => [@user],
                      :providers        => DataProvider.find_all_accessible_by_user(@user).all,
                      :remote_resources => [],
                    }
    @report_stats    = ApplicationController.helpers.gather_dp_usage_statistics(stats_options)

    # Keys and arrays into statistics tables, for HTML output
    @report_dps         = @report_stats['!dps!'] # does not include the 'all' column, if any
    @report_rrs         = @report_stats['!rrs!']
    @report_users       = @report_stats['!users!'] # does not include the 'all' column, if any
    @report_dps_all     = @report_stats['!dps+all?!']      # DPs   + 'all'?
    @report_users_all   = @report_stats['!users+all?!']    # users + 'all'?
    

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @userfile }
    end
  end

  def new #:nodoc:
    @user = User.new
    render :partial => "new"
  end

  def create #:nodoc:
    cookies.delete :auth_token
    # protects against session fixation attacks, wreaks havoc with 
    # request forgery protection.
    # uncomment at your own risk
    # reset_session
    params[:user] ||= {}
    login     = params[:user].delete :login
    role      = params[:user].delete :role
    group_ids = params[:user].delete :group_ids
    site_id   = params[:user].delete :site_id

    no_password_reset_needed = params.delete(:no_password_reset_needed) == "1"
 
    @user = User.new(params[:user])

    if current_user.has_role? :admin
      @user.login     = login     if login
      @user.role      = role      if role
      @user.group_ids = group_ids if group_ids
      @user.site_id   = site_id   if site_id
    end

    if current_user.has_role? :site_manager
      @user.login     = login     if login
      @user.group_ids = group_ids if group_ids
      if role 
        if role == 'site_manager'
          @user.role = 'site_manager'
        else
          @user.role = 'user'
        end
      end
      @user.site = current_user.site
    end

    @user.password_reset = no_password_reset_needed ? false : true
    @user.save
    
    if @user.errors.empty?
      flash[:notice] = "User successfully created."
      current_user.addlog_context(self,"Created account for user '#{@user.login}'")
      @user.addlog_context(self,"Account created by '#{current_user.login}'")
      if @user.email.blank? || @user.email =~ /example/i || @user.email !~ /@/
        flash[:notice] += "Since this user has no proper E-Mail address, no welcome E-Mail was sent."
      else
        flash[:notice] += "\nA welcome E-Mail is being sent to '#{@user.email}'."
        CbrainMailer.registration_confirmation(@user,params[:user][:password],no_password_reset_needed).deliver rescue nil
      end
      redirect_to :action => :index, :format => :js
    else
      respond_to do |format|                                                                  
        format.js {render :partial  => 'shared/failed_create', :locals  => {:model_name  => 'user' }}
      end
    end
  end

  # PUT /users/1
  # PUT /users/1.xml
  def update #:nodoc:
    @user = User.find(params[:id], :include => :groups)
    params[:user] ||= {}
    cb_error "You don't have permission to view this page.", :redirect  => home_path unless edit_permission?(@user)
    
    params[:user][:group_ids] ||=   WorkGroup.all(:joins  =>  :users, :conditions => {"users.id" => @user.id}).map { |g| g.id.to_s }
    params[:user][:group_ids]  |= SystemGroup.all(:joins  =>  :users, :conditions => [ "users.id = ? AND groups.type <> \"InvisibleGroup\"", @user.id ] ).map { |g| g.id.to_s }
    
    if params[:user][:password]
      params[:user].delete :password_reset
      @user.password_reset = current_user.id == @user.id ? false : true
    end

    if params[:user].has_key?(:time_zone) && (params[:user][:time_zone].blank? || !ActiveSupport::TimeZone[params[:user][:time_zone]])
      params[:user][:time_zone] = nil # change "" to nil
    end
    
    role           = params[:user].delete :role
    group_ids      = params[:user].delete :group_ids
    site_id        = params[:user].delete :site_id
    account_locked = params[:user].delete :account_locked
    
    @user.attributes = params[:user]
    
    if current_user.has_role? :admin
      @user.role           = role             if role
      @user.group_ids      = group_ids        if group_ids
      @user.site_id        = site_id          if site_id
      @user.account_locked = (account_locked == "1")
      @user.destroy_user_sessions if @user.account_locked 
    end
    
    if current_user.has_role? :site_manager
      @user.group_ids = group_ids if group_ids
      if role 
        if role == 'site_manager'
          @user.role = 'site_manager'
        else
          @user.role = 'user'
        end
      end
      @user.site = current_user.site
    end
    
    if params[:meta]
      add_meta_data_from_form(@user, [:pref_userfiles_per_page, :pref_bourreau_id, :pref_data_provider_id])
    end
    
    respond_to do |format|
      if @user.save
        flash[:notice] = "User #{@user.login} was successfully updated."
        format.html { redirect_to @user }
        format.xml  { head :ok }
      else
        flash.now[:error] ||= ""
        @user.errors.each do |field, message|
          flash.now[:error] += "#{field} #{message}.\n".humanize
        end
        format.html { render :action => "show" }
        format.xml  { render :xml => @user.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy #:nodoc:
    if current_user.has_role? :admin
      @user = User.find(params[:id])
    elsif current_user.has_role? :site_manager
      @user = current_user.site.users.find(params[:id])
    end
    
    @user.destroy 
    
    flash[:notice] = "User '#{@user.login}' destroyed" 

    respond_to do |format|
      format.js  { redirect_to :action => :index, :format => :js}
      format.xml { head :ok }
    end
  rescue ActiveRecord::DeleteRestrictionError => e
    flash[:error]  = "User not destroyed: #{e.message}"
    
    respond_to do |format|
      format.js  { redirect_to :action => :index, :format => :js}
      format.xml { head :conflict }
    end
  end

  def switch #:nodoc:
    if current_user.has_role? :admin
      @user = User.find(params[:id])
    elsif current_user.has_role? :site_manager
      @user = current_user.site.users.find(params[:id])
    end

    myportal = RemoteResource.current_resource
    myportal.addlog("Admin user '#{current_user.login}' switching to user '#{@user.login}'")
    current_user.addlog("Switching to user '#{@user.login}'")
    @user.addlog("Switched from user '#{current_user.login}'")

    current_session.clear_data!
    current_user = @user
    current_session[:user_id] = @user.id
    
    redirect_to home_path
  end
  
  def request_password #:nodoc:
  end
  
  def send_password #:nodoc:
    @user = User.where( :login  => params[:login], :email  => params[:email] ).first

    if @user
      @user.password_reset = true
      @user.set_random_password
      if @user.save
        CbrainMailer.forgotten_password(@user).deliver
        flash[:notice] = "#{@user.full_name}, your new password has been sent to you via e-mail. You should receive it shortly."
        flash[:notice] += "\nIf you do not receive your new password within 24hrs, please contact your admin."
        redirect_to login_path
      else
        flash[:error] = "Unable to reset password.\nPlease contact your admin."
        redirect_to :action  => :request_password
      end
    else
      flash[:error] = "Unable to find user with login #{params[:login]} and email #{params[:email]}.\nPlease contact your admin."
      redirect_to :action  => :request_password
    end
  end

end
