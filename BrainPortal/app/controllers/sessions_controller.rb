
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

# Sesssions controller for the BrainPortal interface
# This controller handles the login/logout function of the site.  
#
# Original author: restful_authentication plugin
# Modified by: Tarek Sherif
class SessionsController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:
  
  before_filter :no_logged_in_user, :only => [:new, :create]
  
  api_available

  def new #:nodoc:
    reqenv   = request.env
    rawua    = reqenv['HTTP_USER_AGENT'] || 'unknown/unknown'
    ua       = HttpUserAgent.new(rawua)
    @browser = ua.browser_name    || "(unknown browser)"
    
    respond_to do |format|
      format.html
      format.xml
      format.txt
    end
  end

  def create #:nodoc:    
    portal = BrainPortal.current_resource

    self.current_user = User.authenticate(params[:login], params[:password])

    # Bad login/password?
    if ! logged_in?
      flash[:error] = 'Invalid user name or password.'
      Kernel.sleep 3 # Annoying, as it blocks the instance for other users too. Sigh.
      
      respond_to do |format|
        format.html { render :action => 'new' }
        format.xml  { render :nothing => true, :status  => 401 }
      end
      return
    end

    # Account locked?
    if self.current_user.account_locked?
      self.current_user = nil
      flash.now[:error] = "This account is locked, please write to #{User.admin.email || "the support staff"} to get this account unlocked."
      respond_to do |format|
        format.html { render :action => 'new' }
        format.xml  { render :nothing => true, :status  => 401 }
      end
      return
    end

    # Portal locked?
    if portal.portal_locked? && !current_user.has_role?(:admin_user)
      self.current_user = nil
      flash.now[:error] = 'The system is currently locked. Please try again later.'
      respond_to do |format|
        format.html { render :action => 'new' }
        format.xml  { render :nothing => true, :status  => 401 }
      end
      return
    end

    # Everything OK
    current_session.activate
    #if params[:remember_me] == "1"
    #  current_user.remember_me unless current_user.remember_token?
    #  cookies[:auth_token] = { :value => self.current_user.remember_token , :expires => self.current_user.remember_token_expires_at }
    #end
    
    current_session.load_preferences_for_user(current_user)

    # Record the best guess for browser's remote host name
    reqenv = request.env
    from_ip = reqenv['HTTP_X_FORWARDED_FOR'] || reqenv['HTTP_X_REAL_IP'] || reqenv['REMOTE_ADDR']
    if from_ip
      if from_ip =~ /^[\d\.]+$/
        addrinfo = Socket.gethostbyaddr(from_ip.split(/\./).map(&:to_i).pack("CCCC")) rescue [ from_ip ]
        from_host = addrinfo[0]
      else
        from_host = from_ip # already got name?!?
      end
    else
       from_ip   = '0.0.0.0'
       from_host = 'unknown'
    end
    current_session[:guessed_remote_ip]   = from_ip
    current_session[:guessed_remote_host] = from_host

    # Record the user agent
    raw_agent = reqenv['HTTP_USER_AGENT'] || 'unknown/unknown'
    current_session[:raw_user_agent]     = raw_agent

    # Record that the user logged in
    parsed   = HttpUserAgent.new(raw_agent)
    browser  = (parsed.browser_name    || 'unknown browser')
    brow_ver = (parsed.browser_version || '?')
    os       = (parsed.os_name         || 'unknown OS')
    pretty   = "#{browser} #{brow_ver} on #{os}"
    current_user.addlog("Logged in from #{request.remote_ip} using #{pretty}")
    portal.addlog("User #{current_user.login} logged in from #{request.remote_ip} using #{pretty}")
    
    if current_user.has_role?(:admin_user)
      current_session[:active_group_id] = "all"
    end
    
    respond_to do |format|
      format.html { redirect_back_or_default(start_page_path) }
      format.xml  { render :nothing => true, :status  => 200 }
    end

  end
  
  def show #:nodoc:
    if current_user
      render :nothing  => true, :status  => 200
    else
      render :nothing  => true, :status  => 401
    end
  end

  def destroy #:nodoc:
    unless current_user
      redirect_to new_session_path
      return
    end
    
    portal = BrainPortal.current_resource
    current_session.deactivate if current_session
    current_user.addlog("Logged out") if current_user
    portal.addlog("User #{current_user.login} logged out") if current_user
    self.current_user.forget_me if logged_in?
    cookies.delete :auth_token
    current_session.clear_data!
    #reset_session
    flash[:notice] = "You have been logged out."
    
    respond_to do |format|
      format.html { redirect_to new_session_path }
      format.xml  { render :nothing => true, :status  => 200 }
    end
  end

  private
  
  def no_logged_in_user
    if current_user
      redirect_to start_page_path
    end
  end

end
