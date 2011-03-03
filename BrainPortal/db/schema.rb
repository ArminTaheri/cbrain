# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20110302182929) do

  create_table "active_record_logs", :force => true do |t|
    t.integer  "ar_id"
    t.string   "ar_class"
    t.text     "log"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "active_record_logs", ["ar_id", "ar_class"], :name => "index_active_record_logs_on_ar_id_and_ar_class"

  create_table "bourreaux_tools", :id => false, :force => true do |t|
    t.integer "tool_id"
    t.integer "bourreau_id"
  end

  add_index "bourreaux_tools", ["bourreau_id"], :name => "index_bourreaux_tools_on_bourreau_id"
  add_index "bourreaux_tools", ["tool_id"], :name => "index_bourreaux_tools_on_tool_id"

  create_table "cbrain_tasks", :force => true do |t|
    t.string   "type"
    t.string   "cluster_jobid"
    t.string   "cluster_workdir"
    t.text     "params"
    t.string   "status"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "user_id"
    t.integer  "bourreau_id"
    t.text     "description"
    t.datetime "launch_time"
    t.text     "prerequisites"
    t.integer  "share_wd_tid"
    t.integer  "run_number"
    t.integer  "group_id"
    t.integer  "tool_config_id"
  end

  add_index "cbrain_tasks", ["bourreau_id"], :name => "index_cbrain_tasks_on_bourreau_id"
  add_index "cbrain_tasks", ["group_id"], :name => "index_cbrain_tasks_on_group_id"
  add_index "cbrain_tasks", ["launch_time"], :name => "index_cbrain_tasks_on_launch_time"
  add_index "cbrain_tasks", ["status"], :name => "index_cbrain_tasks_on_status"
  add_index "cbrain_tasks", ["type"], :name => "index_cbrain_tasks_on_type"
  add_index "cbrain_tasks", ["user_id"], :name => "index_cbrain_tasks_on_user_id"

  create_table "custom_filters", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "user_id"
    t.string   "type"
    t.text     "data"
  end

  add_index "custom_filters", ["type"], :name => "index_custom_filters_on_type"
  add_index "custom_filters", ["user_id"], :name => "index_custom_filters_on_user_id"

  create_table "data_providers", :force => true do |t|
    t.string   "name"
    t.string   "type"
    t.integer  "user_id"
    t.integer  "group_id"
    t.string   "remote_user"
    t.string   "remote_host"
    t.integer  "remote_port"
    t.string   "remote_dir"
    t.boolean  "online"
    t.boolean  "read_only"
    t.text     "description"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "time_of_death"
    t.boolean  "not_syncable",  :default => false
    t.string   "time_zone"
  end

  add_index "data_providers", ["group_id"], :name => "index_data_providers_on_group_id"
  add_index "data_providers", ["type"], :name => "index_data_providers_on_type"
  add_index "data_providers", ["user_id"], :name => "index_data_providers_on_user_id"

  create_table "feedbacks", :force => true do |t|
    t.string   "summary"
    t.text     "details"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "user_id"
  end

  create_table "groups", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "type"
    t.integer  "site_id"
  end

  add_index "groups", ["name"], :name => "index_groups_on_name"
  add_index "groups", ["type"], :name => "index_groups_on_type"

  create_table "groups_users", :id => false, :force => true do |t|
    t.integer "group_id"
    t.integer "user_id"
  end

  add_index "groups_users", ["group_id"], :name => "index_groups_users_on_group_id"
  add_index "groups_users", ["user_id"], :name => "index_groups_users_on_user_id"

  create_table "logged_exceptions", :force => true do |t|
    t.string   "exception_class"
    t.string   "controller_name"
    t.string   "action_name"
    t.text     "message"
    t.text     "backtrace"
    t.text     "environment"
    t.text     "request"
    t.datetime "created_at"
  end

  create_table "messages", :force => true do |t|
    t.string   "header"
    t.text     "description"
    t.text     "variable_text"
    t.string   "message_type"
    t.boolean  "read"
    t.integer  "user_id"
    t.datetime "expiry"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "last_sent"
    t.boolean  "critical"
    t.boolean  "display"
  end

  add_index "messages", ["user_id"], :name => "index_messages_on_user_id"

  create_table "meta_data_store", :force => true do |t|
    t.integer  "ar_id"
    t.string   "ar_class"
    t.string   "meta_key"
    t.text     "meta_value"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "meta_data_store", ["ar_class", "meta_key"], :name => "index_meta_data_store_on_ar_class_and_meta_key"
  add_index "meta_data_store", ["ar_id", "ar_class", "meta_key"], :name => "index_meta_data_store_on_ar_id_and_ar_class_and_meta_key"
  add_index "meta_data_store", ["ar_id", "ar_class"], :name => "index_meta_data_store_on_ar_id_and_ar_class"
  add_index "meta_data_store", ["meta_key"], :name => "index_meta_data_store_on_meta_key"

  create_table "remote_resources", :force => true do |t|
    t.string   "name"
    t.string   "type"
    t.integer  "user_id"
    t.integer  "group_id"
    t.string   "actres_user"
    t.string   "actres_host"
    t.integer  "actres_port"
    t.string   "actres_dir"
    t.boolean  "online"
    t.boolean  "read_only"
    t.text     "description"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "ssh_control_user"
    t.string   "ssh_control_host"
    t.integer  "ssh_control_port"
    t.string   "ssh_control_rails_dir"
    t.integer  "tunnel_mysql_port"
    t.integer  "tunnel_actres_port"
    t.string   "cache_md5"
    t.boolean  "portal_locked"
    t.integer  "cache_trust_expire",    :default => 0
    t.datetime "time_of_death"
    t.text     "ssh_public_key"
    t.string   "time_zone"
    t.string   "site_url_prefix"
    t.string   "dp_cache_dir"
    t.text     "dp_ignore_patterns"
    t.string   "cms_class"
    t.string   "cms_default_queue"
    t.string   "cms_extra_qsub_args"
    t.string   "cms_shared_dir"
    t.integer  "workers_instances"
    t.integer  "workers_chk_time"
    t.string   "workers_log_to"
    t.integer  "workers_verbose"
    t.string   "help_url"
    t.integer  "rr_timeout"
  end

  add_index "remote_resources", ["type"], :name => "index_remote_resources_on_type"

  create_table "sanity_checks", :force => true do |t|
    t.string   "revision_info"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "sessions", :force => true do |t|
    t.string   "session_id", :null => false
    t.text     "data"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "user_id"
    t.boolean  "active"
  end

  add_index "sessions", ["session_id"], :name => "index_sessions_on_session_id"
  add_index "sessions", ["updated_at"], :name => "index_sessions_on_updated_at"

  create_table "sites", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "description"
  end

  create_table "statistics", :force => true do |t|
    t.integer  "bourreau_id"
    t.integer  "user_id"
    t.string   "task_name"
    t.integer  "count"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "sync_status", :force => true do |t|
    t.integer  "userfile_id"
    t.integer  "remote_resource_id"
    t.string   "status"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "accessed_at"
    t.datetime "synced_at"
  end

  add_index "sync_status", ["remote_resource_id"], :name => "index_sync_status_on_remote_resource_id"
  add_index "sync_status", ["userfile_id", "remote_resource_id"], :name => "index_sync_status_on_userfile_id_and_remote_resource_id"
  add_index "sync_status", ["userfile_id"], :name => "index_sync_status_on_userfile_id"

  create_table "tags", :force => true do |t|
    t.string   "name"
    t.integer  "user_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "group_id"
  end

  add_index "tags", ["name"], :name => "index_tags_on_name"
  add_index "tags", ["user_id"], :name => "index_tags_on_user_id"

  create_table "tags_userfiles", :id => false, :force => true do |t|
    t.integer "tag_id"
    t.integer "userfile_id"
  end

  add_index "tags_userfiles", ["tag_id"], :name => "index_tags_userfiles_on_tag_id"
  add_index "tags_userfiles", ["userfile_id"], :name => "index_tags_userfiles_on_userfile_id"

  create_table "tool_configs", :force => true do |t|
    t.text     "description"
    t.integer  "tool_id"
    t.integer  "bourreau_id"
    t.text     "env_array"
    t.text     "script_prologue"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "group_id"
    t.integer  "ncpus"
  end

  add_index "tool_configs", ["bourreau_id"], :name => "index_tool_configs_on_bourreau_id"
  add_index "tool_configs", ["tool_id"], :name => "index_tool_configs_on_tool_id"

  create_table "tools", :force => true do |t|
    t.string   "name"
    t.integer  "user_id"
    t.integer  "group_id"
    t.string   "category"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "cbrain_task_class"
    t.string   "select_menu_text"
    t.text     "description"
  end

  add_index "tools", ["category"], :name => "index_tools_on_category"
  add_index "tools", ["cbrain_task_class"], :name => "index_tools_on_cbrain_task_class"
  add_index "tools", ["group_id"], :name => "index_tools_on_group_id"
  add_index "tools", ["user_id"], :name => "index_tools_on_user_id"

  create_table "user_preferences", :force => true do |t|
    t.integer  "user_id"
    t.integer  "data_provider_id"
    t.text     "other_options"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "bourreau_id"
  end

  add_index "user_preferences", ["user_id"], :name => "index_user_preferences_on_user_id"

  create_table "userfiles", :force => true do |t|
    t.string   "name"
    t.integer  "size",             :limit => 24, :precision => 24, :scale => 0
    t.integer  "user_id"
    t.integer  "parent_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "type"
    t.string   "task"
    t.integer  "group_id"
    t.integer  "data_provider_id"
    t.boolean  "group_writable",                                                :default => false
    t.integer  "num_files"
    t.integer  "format_source_id"
  end

  add_index "userfiles", ["data_provider_id"], :name => "index_userfiles_on_data_provider_id"
  add_index "userfiles", ["format_source_id"], :name => "index_userfiles_on_format_source_id"
  add_index "userfiles", ["group_id"], :name => "index_userfiles_on_group_id"
  add_index "userfiles", ["name"], :name => "index_userfiles_on_name"
  add_index "userfiles", ["type"], :name => "index_userfiles_on_type"
  add_index "userfiles", ["user_id"], :name => "index_userfiles_on_user_id"

  create_table "users", :force => true do |t|
    t.string   "full_name"
    t.string   "login"
    t.string   "email"
    t.string   "crypted_password",          :limit => 40
    t.string   "salt",                      :limit => 40
    t.string   "remember_token"
    t.datetime "remember_token_expires_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "role"
    t.integer  "site_id"
    t.boolean  "password_reset"
    t.string   "time_zone"
    t.string   "city"
    t.string   "country"
    t.datetime "last_connected_at"
  end

  add_index "users", ["login"], :name => "index_users_on_login"
  add_index "users", ["role"], :name => "index_users_on_role"

end
