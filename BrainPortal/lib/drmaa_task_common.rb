
#
# CBRAIN Project
#
# Module containing common methods for the DrmaaTask classes
# used on the BrainPortal and Bourreau side; it's important
# to realize that on the BrainPortal side, DrmaaTasks are
# ActiveResource objects, while on the Bourreau side they
# are ActiveRecords. Still, many methods are common, so they've
# been extracted here.
#
# Original author: Pierre Rioux
#
# $Id$
#


module DrmaaTaskCommon

  Revision_info="$Id$"

  # Returns the task's User object.
  def user
    @user ||= User.find(self.user_id)
  end

  # Returns a simple name for the task (without the Drmaa prefix).
  def name
    @name ||= self.class.to_s.gsub(/^Drmaa/,"")
  end

  # Returns the Bourreau object associated with the task.
  def bourreau
    @bourreau ||= Bourreau.find(self.bourreau_id)
  end

  # Returns an ID string containing both the bourreau_id +bid+
  # and the task ID +tid+ in format "bid/tid". Example:
  #     "3/4"   # Bourreau #3, task #4
  def bid_tid
    @bid_tid ||= "#{self.bourreau_id || '?'}/#{self.id || '?'}"
  end

  # Returns an ID string containing both the bourreau_name +bname+
  # and the task ID +tid+ in format "bname/tid". Example:
  #     "Mammouth/4"   # Bourreau 'Mammouth', task #4
  def bname_tid
    @bname_tid ||= "#{self.bourreau.name || '?'}/#{self.id || '?'}"
  end

  # Returns an ID string containing both the bourreau_name +bname+
  # and the task ID +tid+ in format "bname-tid" ; this is suitable to
  # be used as part of a filename. Example:
  #     "Mammouth-4"   # Bourreau 'Mammouth', task #4
  def bname_tid_dashed
    @bname_tid_dashed ||= "#{self.bourreau.name || 'Unk'}-#{self.id || 'Unk'}"
  end

  # List of prerequisites states and the set of states that
  # fulfill them.
  PREREQS_STATES_COVERED_BY = {
 
    'Queued' => {
                  'New'                   => :wait,
                  'Setting Up'            => :wait,
                  'Queued'                => :go,
                  'On Hold'               => :go,
                  'On CPU'                => :go,
                  'Suspended'             => :go,
                  'Data Ready'            => :go,
                  'Post Processing'       => :go,
                  'Completed'             => :go,
                  'Failed To Setup'       => :fail,
                  'Failed To PostProcess' => :fail,
                  'Failed Prerequisites'  => :fail
                },

    'Data Ready' => {
                  'New'                   => :wait,
                  'Setting Up'            => :wait,
                  'Queued'                => :wait,
                  'On Hold'               => :wait,
                  'On CPU'                => :wait,
                  'Suspended'             => :wait,
                  'Data Ready'            => :go,
                  'Post Processing'       => :go,
                  'Completed'             => :go,
                  'Failed To Setup'       => :fail,
                  'Failed To PostProcess' => :fail,
                  'Failed Prerequisites'  => :fail
                },

    'Completed' => {
                  'New'                   => :wait,
                  'Setting Up'            => :wait,
                  'Queued'                => :wait,
                  'On Hold'               => :wait,
                  'On CPU'                => :wait,
                  'Suspended'             => :wait,
                  'Data Ready'            => :wait,
                  'Post Processing'       => :wait,
                  'Completed'             => :go,
                  'Failed To Setup'       => :fail,
                  'Failed To PostProcess' => :fail,
                  'Failed Prerequisites'  => :fail
                },

    'Failed' => {
                  'New'                   => :wait,
                  'Setting Up'            => :wait,
                  'Queued'                => :wait,
                  'On Hold'               => :wait,
                  'On CPU'                => :wait,
                  'Suspended'             => :wait,
                  'Data Ready'            => :wait,
                  'Post Processing'       => :wait,
                  'Completed'             => :fail,
                  'Failed To Setup'       => :go,
                  'Failed To PostProcess' => :go,
                  'Failed Prerequisites'  => :fail
                }

  }

  # This method adds a prerequisite entry in the task's object;
  # the prerequisite will indicate that in order for the task to
  # be set up (when +for_what+ is :for_setup) or to enter post
  # processing (when +for_what+ is :for_post_processing), the
  # +task+ must be in +needed_state+ .
  def add_prerequisites(for_what, task, needed_state = "Completed") #:nodoc:
    cb_error "Prerequisite argument 'for_what' must be :for_setup or :for_post_processing" unless
      for_what.is_a?(Symbol) && (for_what == :for_setup || for_what == :for_post_processing)
    cb_error "Prerequisite argument needed_state='#{needed_state}' is not allowed." unless
      PREREQS_STATES_COVERED_BY[needed_state]
    task_id = task.is_a?(DrmaaTask) ? task.id : task.to_i
    cb_error "Cannot add a prerequisite for a task that depends on itself!" if self.id == task_id
    ttid = "T#{task_id}"
    prereqs         = self.prerequisites || {}
    task_list       = prereqs[for_what]  ||= {}
    task_list[ttid] = needed_state
    self.prerequisites = prereqs # in case it was blank originally
  end

  # This method adds a prerequisite entry in the task's object;
  # the prerequisite will indicate that in order for the task to
  # be set up, the other +task+ must be in +needed_state+ .
  # The argument +task+ can be a task object, or its id.
  def add_prerequisites_for_setup(task, needed_state = "Completed")
    add_prerequisites(:for_setup, task, needed_state)
  end

  # This method adds a prerequisite entry in the task's object;
  # the prerequisite will indicate that in order for the task to
  # be enter post processing, the other +task+ must be in +needed_state+ .
  # The argument +task+ can be a task object, or its id.
  def add_prerequisites_for_post_processing(task, needed_state = "Completed")
    add_prerequisites(:for_post_processing, task, needed_state)
  end

end

