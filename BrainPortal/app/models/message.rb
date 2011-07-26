
#
# CBRAIN Project
#
# $Id$
#

# This class provides a asynchronous communication mechanism
# between any user, group and process to any CBRAIN user.

require 'socket'

class Message < ActiveRecord::Base

  Revision_info=CbrainFileRevision[__FILE__]

  belongs_to :user

  attr_accessor :send_email
  
  # Send a new message to a user, the users of a group, or a site.
  #
  # The +destination+ argument can be a User, a Group, a Site,
  # or an (mixed) array of any of these.
  #
  # Potential options are +message_type+, +header+, +description+,
  # +variable_text+, +expiry+ and +critical+.
  #
  # The +message_type+ option should be one of :notice, :error or :system.
  # The +description+ and +var_text+ are optional. An +expiry+
  # date can also be provided, such that unacknowledged messages
  # disappear from view when they are no longer relevent (for
  # instance, for system broadcast messages).
  #
  # This method will create and update a single Message object for
  # multiple successive calls that have the same +message_type+, +header+
  # and +description+ arguments, and will concatenate
  # and timestamps the successive +var_text+ messages into it.
  #
  # To make the +var_text+ look good, make sure that if your provide
  # multiple lines of text (a list, for instance) the first line
  # is different, as it will be the one that gets prepended with
  # the timestamp.
  #
  # The method returns the list of the messages objects created,
  # updated or simply found (if no update occured).
  def self.send_message(destination, options = {})
    type         = options[:message_type]  || options["message_type"]  ||
                   options[:type]          || options["type"]          || :notice
    header       = options[:header]        || options["header"]        || "No subject"
    description  = options[:description]   || options["description"]   || nil
    var_text     = options[:variable_text] || options["variable_text"] || nil
    expiry       = options[:expiry]        || options["expiry"]        || nil
    critical     = options[:critical]      || options["critical"]      || false
    send_email   = options[:send_email]    || options["send_email"]    || false
    

    # Stringify 'type' we can call with either :notice or 'notice'
    type = type.to_s unless type.is_a? String

    # Consistentize(!) all messages without a description and/or var_text
    description = nil if description.blank?
    var_text    = nil if var_text.blank?

    # What the method returns
    messages_sent = []

    # Find the list of users who will receive the messages
    allusers = find_users_for_destination(destination)

    # Send to all selected users
    allusers.each do |user|

      # Find or create message object
      mess = user.messages.where(
               :message_type => type,
               :header       => header,
               :description  => description,
               :read         => false,
               :critical     => critical 
             ).first || 
             Message.new(
               :user_id      => user.id,
               :message_type => type,
               :header       => header,
               :description  => description,
               :expiry       => expiry,
               :read         => false,
               :critical     => critical 
             )
      
      # If the message is a pure repeat of an existing message,
      # do nothing. Question: do we mark it as unread?
      if var_text.blank? && ! mess.new_record?
        messages_sent << mess
        #mess.read = false; mess.save
        next
      end
        
      # Prepare new variable text
      unless var_text.blank?
        mess.append_variable_text(var_text)
      end

      mess.read      = false
      mess.last_sent = Time.now
      mess.display   = true
      mess.save

      messages_sent << mess
    end
    
    if send_email
      CbrainMailer.cbrain_message(allusers,
        :subject  => header,
        :body     => description + ( var_text.blank? ? "" : "\n#{var_text.strip}" )
      ).deliver
    end

    messages_sent
  end
  
  #Instance method version of send_message.
  #Allows one to create an object and set its attributes,
  #then send it to +destination+.
  def send_me_to(destination)
    Message.send_message(destination, self.attributes.merge({:send_email  => self.send_email}))
  end

  # Given an existing message, send it to other users/group.
  # If the destination users already have the message, nothing
  # is done.
  def forward_to_group(destination)

    # Try to send message to everyone; by setting the var_text to nil,
    # we won't change messages already sent, but we will create
    # new message for new users with a variable_text that is blank.
    found        = self.class.send_message(destination, 
                                    :message_type => self.message_type,
                                    :header       => self.header,
                                    :description  => self.description)

    # Now, if the current message DID have a var_text, we need to copy it to
    # the new messages just sent; these will be detected by
    # the fact that their own variable_text is blank.
    var_text = self.variable_text
    unless var_text.blank?
      found.each do |mess|
        next unless mess.variable_text.blank?
        mess.variable_text = var_text
        mess.save
      end
    end

    found
  end

  # Sends an internal error message where the main context
  # is an exception object.
  def self.send_internal_error_message(destination, header, exception, request_params = {})

    # Params cleanup
    request_params = request_params.clone
    request_params[:password]  = "********" if request_params.has_key?(:password)
    request_params["password"] = "********" if request_params.has_key?("password")

    # Message for normal users
    if destination && !(destination.is_a?(User) && destination.has_role?(:admin))
      Message.send_message(destination,
        :message_type => :error,
        :header       => "Internal error: #{header}",

        :description  => "An internal error occured inside the CBRAIN code.\n"     +
                         "The CBRAIN admins have been alerted are working\n"       +
                         "towards solving the problem.\n",
                       
        :send_email   => false
      ) 
    end
    
    # Message for developers/admin
    Message.send_message(User.find_all_by_role("admin"),
      :message_type  => :error,
      :header        => "Internal error: #{header}; Exception: #{exception.class.to_s}\n",

      :description   => "An internal error occured inside the CBRAIN code.\n"     +
                        "The last 30 caller entries are in attachment ([[View full log][/logged_exceptions]]).\n",

      :variable_text => "=======================================================\n" +
                        "Users: #{find_users_for_destination(destination).map(&:login).join(", ")}\n" +
                        "Hostname: #{Socket.gethostname}\n" +
                        "Process ID: #{Process.pid}\n" +
                        "Process Name: #{$0}\n" +
                        "Params: #{request_params.inspect}\n" +
                        "Exception: #{exception.class.to_s}: #{exception.message}\n" +
                        "\n" +
                        exception.backtrace[0..30].join("\n") +
                        "\n",
                       
      :send_email    => true
    )
  rescue => ex
    puts_red "Exception raised while trying to report an exception!"
    puts_yellow "The original exception was: #{exception.class.to_s}: #{exception.message}\n"
    puts exception.backtrace.join("\n")
    puts_yellow "The new exception is: #{ex.class.to_s}: #{ex.message}\n"
    puts ex.backtrace.join("\n")
    return true
  end

  # Will append the text document in argument to the
  # variable_text attribute, prefixing it with a
  # timestamp.
  def append_variable_text(var_text = nil)
    return if var_text.blank?

    varlines = var_text.split(/\s*\n/)
    varlines.pop   while varlines.size > 0 && varlines[-1] == ""
    varlines.shift while varlines.size > 0 && varlines[0]  == ""

    # Append to existing variable text
    current_text = self.variable_text
    current_text = "" if current_text.blank?
    if varlines.size > 0
      timestamp    = Time.zone.now.strftime("[%Y-%m-%d %H:%M:%S %Z]")
      current_text += timestamp + " " + varlines[0] + "\n"
      varlines.shift
      current_text += varlines.join("\n") + "\n" if varlines.size > 0
    end

    # Reduce size if necessary
    while current_text.size > 65500 && current_text =~ /\n/   # TODO: archive ?
      current_text.sub!(/^[^\n]*\n/,"")
    end

    # Update and create message
    self.variable_text = current_text
  end

  private

  def self.find_users_for_destination(destination) #:nodoc:

    # Find the group(s) associated with the destination
    groups = case destination
              when :admin
                [ Group.find_by_login('admin') ]
              when :nobody
                []
              when Group, User, Site
                [ destination.own_group ]
              when Array
                begin
                  (destination.map &:own_group) | []
                rescue NoMethodError
                  [] #cb_error "Destination not acceptable for send_message."
                end
              else
                [] #cb_error "Destination not acceptable for send_message."
            end

    # Get a unique list of all users from all these groups
    allusers = groups.inject([]) { |flat,group| flat |= group.users }

    # Select the list of users in list of groups; a special case is made
    # when a single group contains only one user along with 'admin', in that case
    # admin is rejected.
    if groups.size == 1 && groups[0].name != 'admin' && allusers.size == 2
      allusers.reject! { |u| u.login == 'admin' }
    end

    allusers
  end

  # Parses a string and replaces special markup with HTML links:
  #    "abcde [[name][/my/path]] def"
  # will return
  #    "abcde <a href="/my/path" class="action_link">name</a>"
  def self.parse_markup(string)
    arr = string.split(/(\[\[.*?\]\])/)
    arr.each_with_index do |str,i|
      next if i % 2 == 0 # nothing to do to outside context
      next unless arr[i] =~ /\[\[(.+?)\]\[(.+?)\]\]/
      name = Regexp.last_match[1]
      link = Regexp.last_match[2]
      link.sub!("/tasks/show/","/tasks/")  # adjustment to old URL API for tasks
      arr[i] = "<a href=\"#{link}\" class=\"action_link\">#{name}</a>"
    end
    arr.join
  end

end
