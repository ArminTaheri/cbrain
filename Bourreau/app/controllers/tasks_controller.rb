
#
# CBRAIN Project
#
# RESTful ActiveResource Controller for DRMAA_Tasks
#
# Original code provided by Jade Meskill, blog owner of
# http://iamruinous.com/2007/10/01/creating-an-activeresource-compatible-controller/
# Obtained his permission on October 27th, 2008.
#
# Modified by Pierre Rioux
#
# $Id$
#

#RESTful controller for the DrmaaTask resource.
class TasksController < ApplicationController

  Revision_info="$Id$"

  before_filter :find_or_initialize_task, :except => [ :index ]
  before_filter :start_bourreau_workers

  # GET /tasks
  # Formats: xml
  # NOT USED ANYMORE!
  def index #:nodoc:
    @tasks = []
    respond_to do |format|
      format.html { head :method_not_allowed }
      
      format.xml { render :xml => @tasks.to_xml }
    end
  end

  # POST /tasks
  # Formats: xml
  def create #:nodoc:
    respond_to do |format|
      format.html { head :method_not_allowed }
      
      @task.status = 'New'
      if @task.save
        BourreauWorker.wake_all
        format.xml do
          headers['Location'] = url_for(:controller => "drmaa_tasks", :action => nil, :id => @task.id)
          render :xml => @task.to_xml, :status => :created
        end
      else
        format.xml { render :xml => @task.errors.to_xml, :status => :unprocessable_entity }
      end
    end
  end
  
  # GET /tasks/<id>
  # Formats: xml
  def show #:nodoc:
    @task.capture_job_out_err
    respond_to do |format|
      format.html { head :method_not_allowed }
      format.xml { render :xml => @task }
    end
  end
  
  # PUT /tasks/<id>
  # Formats: xml
  
  # The only update operation we allow is to the 'status'
  # attribute. The status will be updated to the requested
  # status iff it is an allowable move from the 
  # previous state.
  def update
    respond_to do |format|
      format.html { head :method_not_allowed }

      # Find the hash table where ActiveResource supply the new attributes
      uncameltask = @task.uncamelize
      newparams   = params[uncameltask]
      newstatus   = newparams['status']

      # These actions trigger DRMAA task control actions
      # They will update the "status" field depending on the action's result
      @task.suspend      if newstatus == "Suspended"
      @task.resume       if newstatus == "On CPU"
      @task.hold         if newstatus == "On Hold"
      @task.release      if newstatus == "Queued"
      @task.terminate    if newstatus == "Terminated"

      if !@task.changed?
        format.xml { render :xml => @task.to_xml }
      elsif @task.save
        BourreauWorker.wake_all
        format.xml { render :xml => @task.to_xml }
      else
        format.xml { render :xml => @task.errors.to_xml, :status => :unprocessable_entity }
      end
    end
  end
  
  # DELETE /tasks/<id>
  # Formats: xml
  def destroy #:nodoc:
    respond_to do |format|
      format.html { head :method_not_allowed }
      
      if @task.status !~ /Setting Up|Post Processing/ && @task.destroy
        BourreauWorker.wake_all
        format.xml { head :ok }
      else
        format.xml { render :xml => @task.errors.to_xml, :status => :unprocessable_entity }
      end
    end
  end
  
end
