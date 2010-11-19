
#
# CBRAIN Project
#
# Groups controller for the BrainPortal interface
#
# Original author: Tarek Sherif
#
# $Id$
#

#RESTful controller for the Group resource.
class GroupsController < ApplicationController

  Revision_info="$Id$"

  before_filter :login_required

  # GET /groups
  # GET /groups.xml
  def index  #:nodoc:    
    @system_groups = current_user.available_groups(:all, :conditions  => {:type  => ["SystemGroup"] | SystemGroup.send(:subclasses).map(&:name)}, :include => [:site], :order  => "groups.type, groups.name")
    @work_groups = current_user.available_groups(:all, :conditions  => {:type  => ["WorkGroup"] | WorkGroup.send(:subclasses).map(&:name)}, :include => [:site], :order  => "groups.type, groups.name")
    
    #For new panel
    @group = WorkGroup.new
    @users = current_user.available_users(:all, :order => :login).reject{|u| u.login == 'admin'}

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @groups }
    end
  end
  
  def show #:nodoc:
    @group = current_user.available_groups(params[:id])
  end

  # GET /groups/1/edit
  def edit  #:nodoc:
    @group = current_user.available_groups(params[:id], :conditions  => {:type  => "WorkGroup"})
    @users = current_user.available_users(:all, :order => :login).reject{|u| u.login == 'admin'}
  end

  # POST /groups
  # POST /groups.xml
  def create  #:nodoc:
    @group = WorkGroup.new(params[:group])
    
    unless current_user.has_role? :admin
      @group.site = current_user.site
    end

    respond_to do |format|
      if @group.save
        flash[:notice] = 'Project was successfully created.'
        format.js
        format.xml  { render :xml => @group, :status => :created, :location => @group }
      else
        @users = current_user.available_users(:all, :order => :login).reject{|u| u.login == 'admin'}
        format.js
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /groups/1
  # PUT /groups/1.xml
  def update #:nodoc:
    @group = WorkGroup.find(params[:id])
    params[:group][:user_ids] ||= []

    respond_to do |format|
      if @group.update_attributes(params[:group])
        flash[:notice] = 'Project was successfully updated.'
        format.html { redirect_to groups_path }
        format.xml  { head :ok }
      else
        @users = current_user.available_users(:all, :order => :login).reject{|u| u.login == 'admin'}
        format.html { render :action => "edit" }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

 
  # DELETE /groups/1
  # DELETE /groups/1.xml
  def destroy  #:nodoc:
    @group = current_user.available_groups(params[:id])
    @group.destroy

    respond_to do |format|
      format.js   {render :partial  => 'shared/destroy', :locals  => {:model_name  => 'group' }}
      format.xml  { head :ok }
    end
  end
  
  def switch #:nodoc:
    redirect_controller = params[:redirect_controller] || :groups
    redirect_action = params[:redirect_action] || :index
    redirect_id = params[:redirect_id]
    
    if params[:id] == "off"
      current_session[:active_group_id] = nil
    else
      @group = current_user.available_groups(params[:id])
      current_session[:active_group_id] = @group.id
    end
    
    redirect_to :controller  => redirect_controller, :action  => redirect_action, :id  => redirect_id
  end

end
