
#
# CBRAIN Project
#
# Task controller for the BrainPortal interface
#
# Original author: Pierre Rioux
#
# $Id$
#

#Restful controller for the DrmaaTask resource.
class TasksController < ApplicationController

  Revision_info="$Id$"

  before_filter :login_required
   
  def index #:nodoc:
    @bourreaux = available_bourreaux(current_user)
    bourreau_ids = @bourreaux.map { |b| b.id }

    @tasks = ActRecTask.find(:all, :conditions => {
                                     :user_id     => current_user.id,
                                     :bourreau_id => bourreau_ids
                                   } )
    @tasks.each do |t|  # ugly kludge
      t.updated_at = Time.parse(t.updated_at)
      t.created_at = Time.parse(t.created_at)
    end
    
    # Set sort order and make it persistent.
    sort_order = params[:sort_order] || session[:task_sort_order] || 'updated_at'
    sort_dir   = params[:sort_dir]   || session[:task_sort_dir]   || 'DESC'
    session[:task_sort_order] = params[:sort_order] = sort_order
    session[:task_sort_dir]   = params[:sort_dir]   = sort_dir

    @tasks = @tasks.sort do |t1, t2|
      if sort_dir == 'DESC'
        task1 = t2
        task2 = t1
      else
        task1 = t1
        task2 = t2
      end
      
      case sort_order
      when 'type'
        att1 = task1.class.to_s
        att2 = task2.class.to_s
      when 'owner'
        att1 = task1.user.login
        att2 = task2.user.login
      when 'bourreau'
        att1 = task1.bourreau.name
        att2 = task2.bourreau.name
      else
        att1 = task1.send(sort_order)
        att2 = task2.send(sort_order)
      end
      
      if att1.blank? || att2.blank?
        1
      else
        att1 <=> att2
      end
    end
        
    respond_to do |format|
      format.html
      format.js
    end
  end
  
  def summary
    bourreau_ids = available_bourreaux(current_user).collect(&:id)
    @tasks = ActRecTask.find(:all, :conditions => {
                                       :user_id     => current_user.id,
                                       :bourreau_id => bourreau_ids
                                     } )
    @tasks_by_status = @tasks.group_by do |task|
      case task.status
      when /(On CPU|Queued|New)/
        :running
      when /^Failed (T|t)o/
        :failed
      when "(Completed|Data Ready)"
        :completed
      else
        :other
      end
    end
    
    @tasks_by_status = @tasks_by_status.to_hash
    
    @tasks_by_status[:completed] ||= []
    @tasks_by_status[:running] ||= []
    @tasks_by_status[:failed] ||= []
  end

  # GET /tasks/1
  # GET /tasks/1.xml
  def show #:nodoc:
    task_id     = params[:id]
    actrectask  = ActRecTask.find(task_id) # Fetch once...
    bourreau_id = actrectask.bourreau_id
    DrmaaTask.adjust_site(bourreau_id)     # ... to adjust this
    @task = DrmaaTask.find(task_id)        # Fetch twice... :-(

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @task }
    end
  end
  
  def new #:nodoc:
    @task_class = Class.const_get(params[:task].to_s)
    @files = Userfile.find_accessible_by_user(params[:file_ids], current_user, :access_requested  => :read)
    @data_providers = available_data_providers(current_user)

    params[:user_id] = current_user.id

    # Simple case: the task has no parameter page, so submit
    # directly to 'create'
    if ! @task_class.has_args?
      redirect_to :action  => :create, :task  => params[:task], :file_ids  => params[:file_ids], :bourreau_id  => params[:bourreau_id]
      return
    end

    # The page has a parameter page, so get the default values....
    begin
      @default_args  = @task_class.get_default_args(params, current_user.user_preference.other_options[params[:task]])
    rescue CbrainException => e
      flash[:error] = e.to_s
      redirect_to userfiles_path
      return
    rescue => e
      Message.send_internal_error_message(current_user,"Task args for #{@task_class}",e)
      redirect_to userfiles_path
      return
    end
    
    # ... then generate the form.
    respond_to do |format|
      format.html # new.html.erb
    end

  end

  def create #:nodoc:
    @task_class = params[:task].constantize
    unless params[:bourreau_id].blank?
      @task_class.prefered_bourreau_id = params[:bourreau_id]
    else
      @task_class.prefered_bourreau_id = current_user.user_preference.bourreau_id
    end
    @task_class.data_provider_id     = params[:data_provider_id] || current_user.user_preference.data_provider
    
    if params[:save_as_defaults]
      current_user.user_preference.update_options(params[:task]  => @task_class.save_options(params))
      current_user.user_preference.save
    end
        
    begin
      params[:user_id] = current_user.id
      flash[:notice] ||= ""
      flash[:notice] += @task_class.launch(params)
      current_user.addlog_context(self,"Launched #{@task_class.to_s}")
      current_user.addlog_revinfo(@task_class)
    rescue CbrainException => e
      flash[:error] = e.to_s
      if @task_class.has_args?
        redirect_to :action  => :new, :file_ids => params[:file_ids], :task  => params[:task]
      else
        redirect_to userfiles_path
      end
      return
    rescue => e
      Message.send_internal_error_message(current_user,"Task launch for #{@task_class}", e)
      redirect_to userfiles_path
      return
    end
    
    redirect_to :controller => :tasks, :action => :index
  end

  #This action handles requests to modify the status of a given task.
  #Potential operations are:
  #[*Hold*] Put the task on hold (while it is queued).
  #[*Release*] Release task from <tt>On Hold</tt> status (i.e. put it back in the queue).
  #[*Suspend*] Stop processing of the task (while it is on cpu).
  #[*Resume*] Release task from <tt>Suspended</tt> status (i.e. continue processing).
  #[*Terminate*] Kill the task, while maintaining its temporary files and its entry in the database.
  #[*Delete*] Kill the task, delete the temporary files and remove its entry in the database. 
  def operation
    operation   = params[:operation]
    tasklist    = params[:tasklist] || []

    flash[:error]  ||= ""
    flash[:notice] ||= ""

    if operation.nil? || operation.empty?
       flash[:notice] += "Task list has been refreshed.\n"
       redirect_to :action => :index
       return
     end

    if tasklist.empty?
      flash[:error] += "No task selected? Selection cleared.\n"
      redirect_to :action => :index
      return
    end

    affected_tasks = []

    tasklist.each do |task_id|

      begin 
        actrectask  = ActRecTask.find(task_id) # Fetch once...
        bourreau_id = actrectask.bourreau_id
        DrmaaTask.adjust_site(bourreau_id)     # ... to adjust this
        task = DrmaaTask.find(task_id.to_i)    # Fetch twice... :-(
      rescue
        flash[:error] += "Task #{task_id} does not exist, or its Execution Server is currently down.\n"
        next
      end

      continue if task.user_id != current_user.id && current_user.role != 'admin'

      case operation
        when "hold"
          task.status = "On Hold"
          task.save
        when "release"
          task.status = "Queued"
          task.save
        when "suspend"
          task.status = "Suspended"
          task.save
        when "resume"
          task.status = "On CPU"
          task.save
        when "delete"
          task.destroy
        when "terminate"
          task.status = "Terminated"
          task.save
      end

      affected_tasks << task.bname_tid
    end

    message = "Sent '#{operation}' to tasks: #{affected_tasks.join(", ")}"

    current_user.addlog_context(self,message)
    flash[:notice] += message

    redirect_to :action => :index

  end

end
