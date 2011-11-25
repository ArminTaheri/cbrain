module PermissionHelpers
  
  def self.included(includer)
    includer.class_eval do
      helper_method :check_role, :not_admin_user
      before_filter :check_if_locked
    end
  end
  
  #Checks that the current user's role matches +role+.
  def check_role(role)
    current_user && current_user.role.to_sym == role.to_sym
  end
  
  #Checks that the current user is not the default *admin* user.
  def not_admin_user(user)
    user && user.login != 'admin'
  end
  
  #Checks that the current user is the same as +user+. Used to ensure permission
  #for changing account information.
  def edit_permission?(user)
    result = current_user && user && (current_user == user || current_user.role == 'admin' || (current_user.has_role?(:site_manager) && current_user.site == user.site))
  end
  
  #Helper method to render and error page. Will render public/<+status+>.html
  def access_error(status)
    respond_to do |format|
      format.html { render(:file => (Rails.root.to_s + '/public/' + status.to_s + '.html'), :status  => status, :layout => false ) }
      format.xml  { head status }
    end 
  end
  
  # Redirect normal users to the login page if the portal is locked.
  def check_if_locked
    if BrainPortal.current_resource.portal_locked?
      flash.now[:error] ||= ""
      flash.now[:error] += "\n" unless flash.now[:error].blank?
      flash.now[:error] += "This portal is currently locked for maintenance."
      message = BrainPortal.current_resource.meta[:portal_lock_message]
      flash.now[:error] += "\n#{message}" unless message.blank?
      unless current_user && current_user.has_role?(:admin)
        respond_to do |format|
          format.html {redirect_to logout_path unless params[:controller] == "sessions"}
          format.xml  {render :xml => {:message => message}, :status => 503}
        end
      end
    end
  end
end