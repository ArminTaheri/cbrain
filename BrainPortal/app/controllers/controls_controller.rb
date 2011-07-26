
#
# CBRAIN Project
#
# Controls Controller for RemoteResources
#
# $Id$
#

# This controller provides querying and controlling
# of the current RemoteResource. Information flows
# back and forth on an ActiveResource channel
# called Control.
#
# The kind of actions that it supports is very limited.
# We support 'show' and 'create' only.
class ControlsController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__]

  api_available

  # The 'show' action responds to only a single ID, 'info',
  # and returns a RemoteResourceInfo record encapsulated
  # into a Control object.
  def show
    keyword = params[:id]

    if keyword == 'info'
      myself = RemoteResource.current_resource
      @info = myself.remote_resource_info
      respond_to do |format|
        format.html { head :method_not_allowed }
        format.xml  { render :xml => @info.to_xml }
      end
      return
    end

    respond_to do |format|
      format.html { head :method_not_allowed }
      format.xml  { head :method_not_allowed }
    end
  end

  # The 'create' action receives a Control object
  # encapsulating a RemoteCommand object.
  # It assigns an arbitrary, unique,
  # transient ID to the command object.
  # After the object's command is executed, the
  # command object is returned to the sender,
  # so that information can be sent back.
  #
  # The command object is validated for proper sender/
  # receiver credentials, and then it is passed on
  # to the RemoteResource object representing
  # the current Rails application for processing.
  def create
    @@command_counter ||= 0
    @@command_counter += 1
    command = RemoteCommand.new(params[:control]) # a HASH
    command.id = "#{@@command_counter}-#{Process.pid}-#{Time.now.to_i}" # not useful right now.
    if process_command(command)
      command.command_execution_status = "OK"
    else
      command.command_execution_status = "FAILED"
    end
    respond_to do |format|
      format.html { head :method_not_allowed }
      format.xml do
        headers['Location'] = url_for(:controller => "controls", :action => nil, :id => command[:id])
        render :xml => command.to_xml, :status => :created
      end
    end
  rescue => e  # TODO : inform client somehow ?
    puts "Exception in create command: #{e.message}"
    puts e.backtrace[0..15].join("\n")
    respond_to do |format|
      format.html { head :method_not_allowed }
      format.xml  { head :method_not_allowed }
    end
  end

  #######################################################################
  # Unimplemented/disabled REST CRUD methods
  #######################################################################

  def destroy #:nodoc:
    not_allowed
  end

  def new #:nodoc:
    not_allowed
  end

  def update #:nodoc:
    not_allowed
  end

  def index #:nodoc:
    not_allowed
  end

  def not_allowed #:nodoc:
    respond_to do |format|
      format.html { head :method_not_allowed }
      format.xml  { head :method_not_allowed }
    end
  end

  #######################################################################
  # Command processing
  #######################################################################

  private

  def process_command(command) #:nodoc:
    puts "Received COMMAND: #{command.inspect}" rescue "Exception in inspecting command?!?"

    myself = RemoteResource.current_resource
    myself.class.process_command(command)

    return true

  rescue => exception
    myself ||= RemoteResource.current_resource
    Message.send_internal_error_message(User.find_by_login('admin'),
      "RemoteResource #{myself.name} raised exception processing a message.", # header
      exception,
      command
    )
    return false
  end

end
