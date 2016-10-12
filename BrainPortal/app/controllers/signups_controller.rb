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

class SignupsController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  before_filter :login_required,      :except => [:show, :new, :create, :edit, :destroy, :update, :confirm, :resend_confirm]
  before_filter :admin_role_required, :except => [:show, :new, :create, :edit, :destroy, :update, :confirm, :resend_confirm]

  ################################################################
  # User-accessible action (do not need to be logged in)
  ################################################################

  def show #:nodoc:
    @signup = Signup.find(params[:id]) rescue nil

    unless can_edit?(@signup)
      redirect_to login_path
      return
    end
  end

  def new #:nodoc:
    @signup = Signup.new
  end

  def create #:nodoc:
    @signup = Signup.new(params[:signup])
    @signup.session_id = request.session_options[:id]
    @signup.generate_token

    unless can_edit?(@signup)
      redirect_to login_path
      return
    end

    if ! @signup.save
      render :action => :new
      return
    end

    unless send_confirm_email(@signup)
      flash[:error] = "It seems some error occured. The email notification was probably not sent. There's nothing we can do about this."
    end

    send_admin_notification(@signup)

    sleep 1
    redirect_to :action => :show, :id => @signup.id
  end

  def edit #:nodoc:
    @signup = Signup.find(params[:id]) rescue nil

    unless can_edit?(@signup)
      redirect_to login_path
      return
    end

    render :action => :new
  end

  def update #:nodoc:
    @signup = Signup.find(params[:id]) rescue nil

    unless can_edit?(@signup)
      redirect_to login_path
      return
    end

    @signup.update_attributes(params[:signup])

    if ! @signup.save
      render :action => :new
      return
    end

    flash[:notice] = "The account request has been updated."

    sleep 1
    redirect_to :action => :show, :id => @signup.id
  end

  def destroy #:nodoc:
    @signup = Signup.find(params[:id]) rescue nil

    unless can_edit?(@signup)
      redirect_to login_path
      return
    end

    @signup.destroy
    flash[:notice] = "The account request has been deleted."

    if current_user && current_user.has_role?(:admin_user)
      redirect_to :action => :index
    else
      redirect_to login_path
    end
  end

  # Confirms that a signup person's email address actually belongs to them
  def confirm #:nodoc:
    @signup = Signup.find(params[:id]) rescue nil
    token    = params[:token] || ""

    # Params properly confirms the request? Then record that and show a nice message to user.
    if @signup.present? && token.present? && @signup.confirm_token == token
      @signup.confirmed = true
      @signup.save
      @propose_view = can_edit?(@signup)
      return # renders confirm.html.erb
    end

    # If not, bluntly send user back to someplace else.
    if current_user && current_user.has_role?(:admin_user)
      redirect_to :action => :index
    else
      redirect_to login_path
    end
  end

  def resend_confirm #:nodoc:
    @signup = Signup.find(params[:id]) rescue nil

    unless can_edit?(@signup)
      redirect_to login_path
      return
    end

    if send_confirm_email(@signup)
      flash[:notice] = "A new confirmation email has been sent."
    else
      flash[:error] = "It seems some error occured. Email notification was probably not sent. Try again later, or contact the admins."
    end

    sleep 1
    redirect_to :action => :show, :id => @signup.id
  end

  ################################################################
  # Admin Actions; the current_user must be signed in as an admin.
  ################################################################

  def index #:nodoc:
    @scope = scope_from_session('signups')

    scope_default_order(@scope, 'country')

    @base_scope       = Signup.where({})
    @signups          = @scope.apply(@base_scope)

    # Prepare the Pagination object
    @scope.pagination ||= Scope::Pagination.from_hash({ :per_page => 25 })
    @current_offset = (@scope.pagination.page - 1) * @scope.pagination.per_page

    scope_to_session(@scope, 'signups')

    respond_to do |format|
      format.js
      format.html
    end
  end

  # Administrator action that converts a signup into a user
  def approve
    @signup = Signup.find(params[:id]) rescue nil

    unless can_edit?(@signup)
      flash[:error] = "Could not approve account."
      redirect_to :action => :index
      return
    end

    if @signup.login.blank?
      flash[:error] = "Before approval, a 'login' name must be set."
      redirect_to :action => :edit, :id => @signup.id
      return
    end

    @symbolic_result, @info, @exception_trace = approve_one(@signup)

    if @symbolic_result != :all_ok
      flash.now[:error] = @info.presence || "(Unspecified internal error?!?)"
    end
  end

  # Main entry point for mass operations on requests.
  # Some of these methods render the multi_action view,
  # which expects @results to be an array of quadruplets
  # [ signup, status, message, backtrace ]
  # where +signup+ is a Signup object, and the other three
  # are similar to what the approve_one() method returns.
  def multi_action #:nodoc:
    if params[:commit] =~ /Approve/
      return approve_multi
    end

    if params[:commit] =~ /Fix Login/
      return fix_login_multi
    end

    if params[:commit] =~ /Resend/
      return resend_conf_multi
    end

    if params[:commit] =~ /Delete/
      return delete_multi
    end

    # Default: unknown multi action?
    redirect_to :action => :index
  end

  def delete_multi #:nodoc:
    reqids = params[:reqids] || []
    reqs   = Signup.find(reqids)

    count = 0
    reqs.each do |req|
      count += 1 if req.destroy
    end

    flash[:notice] = "Deleted " + view_pluralize(count, "record") + "."

    redirect_to :action => :index
  end

  def fix_login_multi #:nodoc:
    reqids = params[:reqids] || []
    reqs   = Signup.find(reqids)

    @results = reqs.map do |req|

      next [ req, :no_change, 'No changes', nil ] if req.login.present?

      old   = req.login
      new   = ""

      # Attempt at parsing email
      email = req.email
      if email =~ /\A(\S+)@/
        new = Regexp.last_match[1].downcase.gsub(/\W+/,"")
      end

      # Attempt at using first and last names
      if new.blank?
        new = (req.first[0,1] + req.last).downcase.gsub(/\W+/,"")
      end

      next [ req, :no_change, 'No changes', nil ] if new.blank?

      backtrace = nil
      begin
        req.update_attribute(:login, new)
      rescue => ex
        backtrace = ex.backtrace
      end
      message = backtrace ? "Attempted" : "Adjusted"
      [ req, :adjusted, "#{message}: #{old} => #{new}", backtrace ]

    end

    @results.compact!

    render :action => :multi_action
  end

  def resend_conf_multi #:nodoc:
    reqids = params[:reqids] || []
    reqs   = Signup.find(reqids)

    count = 0

    @results = reqs.map do |req|
      next if req.confirmed? || req.approved_by.present?
      if send_confirm_email(req)
        count += 1
        [ req, :all_ok, "Resent confirmation email", nil ]
      else
        [ req, :failed_confirm, "ERROR: Could not send confirmation email", nil ]
      end
    end

    @results.compact!

    flash[:notice] = "Sent " + view_pluralize(count, "confirmation email") + "."
    render :action => :multi_action
  end

  def approve_multi #:nodoc:
    reqids = params[:reqids] || []
    reqs   = Signup.find(reqids)

    @results = reqs.map do |req|
      symbolic_result, message, backtrace = approve_one(req)
      [ req, symbolic_result, message, backtrace ]
    end

    @results.compact!

    render :action => :multi_action
  end

  # This invokes the Signup model method after_approval() which
  # attempts to create the user based on the signup object's information.
  # The method here returns a triplet [ status, message, backtrace ]
  # where +status+ is a symbol among :all_ok, :failed_approval, :failed_save, or :not_notifiable,
  # +message+ is a message describing the status, and +backtrace+ is the exception trace
  # if an exception was raised.
  def approve_one(signup) #:nodoc:
    result = signup.after_approval

    return [ :failed_save, "ERROR: #{result.diagnostics}", nil ] unless result.success

    user = result.user
    current_user.addlog("Approved account request for user '#{user.login}'")
    user.addlog("Account created after [[signup request][#{signup_path(signup)}]] approved by '#{current_user.login}'")

    # Mark signup object as approved
    info           = result.to_s           rescue nil
    plain_password = result.plain_password rescue nil

    signup.approved_by ||= current_user.login
    signup.approved_at ||= Time.now
    signup.save!

    # Notify user
    if send_account_created_email(signup,plain_password)
      return [ :all_ok, info, nil ]
    else
      return [ :not_notifiable, 'ERROR: The User was created in CBRAIN, but the notification email failed to send.', nil ]
    end

  rescue => ex
    exception_trace = "#{ex.class}: #{ex.message}\n" + ex.backtrace.join("\n")
    return [ :failed_approval, 'ERROR: Exception when approving' , exception_trace ]
  end

  private

  def can_edit?(signup) #:nodoc:
    return false if signup.blank?
    return true  if signup[:session_id] == request.session_options[:id]
    return true  if current_user && current_user.has_role?(:admin_user)
    false
  end

  def send_confirm_email(signup) #:nodoc:
    confirm_url = url_for(:controller => :signups, :action => :confirm, :id => signup.id, :only_path => false, :token => signup.confirm_token)
    CbrainMailer.signup_request_confirmation(signup, confirm_url).deliver
    return true
  rescue => ex
    Rails.logger.error ex.to_s
    return false
  end

  def send_account_created_email(user, plain_password) #:nodoc:
    CbrainMailer.registration_confirmation(user, plain_password).deliver
    return true
  rescue => ex
    Rails.logger.error ex.to_s
    return false
  end

  def send_admin_notification(signup) #:nodoc:
    return unless RemoteResource.current_resource.support_email
    show_url  = url_for(:controller => :signups, :action => :show, :id => signup.id, :only_path => false)
    CbrainMailer.signup_notify_admin(signup, show_url).deliver
    return true
  rescue => ex
    Rails.logger.error ex.to_s
    return false
  end

end

