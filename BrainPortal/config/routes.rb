
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

# CBRAIN Routing Table

CbrainRailsPortal::Application.routes.draw do
  
  # Session
  resource  :session do
    member do
      post 'mozilla_persona_auth'
    end
  end
  
  # Control channel
  resources :controls,       :controller => :controls

  # Standard CRUD resources
  resources :sites
  resources :custom_filters
  resources :tool_configs
  resources :tags

  # Standard CRUD resources, with extra methods

  resources :feedbacks
  
  resources :messages do
    collection do
      delete 'delete_messages'
    end
  end

  resources :users do
    member do
      get  'change_password'
      post 'switch'
    end
    collection do
      get  'request_password'
      post 'send_password'
    end
  end

  resources :groups do
    collection do
      get  'switch_panel'
      post 'unregister'
      post 'switch'
    end
  end
  
  resources :invitations, :only => [:new, :create, :update, :destroy]

  resources :bourreaux do
    member do
      post 'start'
      post 'stop'
      get  'row_data'
    end
    collection do
      get  'load_info'
      get  'rr_disk_usage'
      get  'rr_access'
      post 'cleanup_caches'
      get  'rr_access_dp'
    end
  end

  resources :data_providers do
    member do
      get  'browse'
      post 'register'
      get  'is_alive'
    end
    collection do
      get  'dp_access'
      get  'dp_transfers'
    end
  end

  resources :userfiles do
    member do
      get  'content'
      get  'display'
      post 'sync_to_cache'
      post 'extract_from_collection'
    end
    collection do
      get    'download'
      get    'new_parent_child'
      post   'create_parent_child'
      delete 'delete_files'
      post   'create_collection'
      put    'update_multiple'
      post   'change_provider'
      post   'compress'
      post   'archive_management'
      post   'quality_control'
      post   'quality_control_panel'
      post   'manage_persistent'
      post   'sync_multiple'
    end
  end

  resources :tasks do
    collection do
      post 'new', :path => 'new', :as => 'new'
      post 'operation'
      get  'batch_list'
      post 'update_multiple'
    end
  end

  resources :tools do
    collection do
      get    'tool_config_select'
      post   'assign_tools'
    end
  end

  resources :exception_logs, :only => [:index, :show] do
    delete :destroy, :on => :collection
  end

  # Special named routes
  root  :to                       => 'portal#welcome'
  match '/home'                   => 'portal#welcome'
  match '/credits'                => 'portal#credits'
  match '/about_us'               => 'portal#about_us'
  match '/login'                  => 'sessions#new'
  match '/session_status'         => 'sessions#show'
  match '/logout'                 => 'sessions#destroy'
  match '/filter_proxy'           => 'application#filter_proxy'

  # JIV java applet ; TODO remove and make part of a multi-file viewer framework (TBI)
  match '/jiv'                    => 'jiv#index'
  match '/jiv/show'               => 'jiv#show'

  # Report Maker
  match "/report",                :controller => :portal, :action => :report

  # Licence handling
  match '/show_license/:license', :controller => :portal, :action => :show_license
  match '/sign_license/:license', :controller => :portal, :action => :sign_license, :via => :post
  
  # Portal log
  match '/portal_log', :controller => :portal, :action => :portal_log

end

