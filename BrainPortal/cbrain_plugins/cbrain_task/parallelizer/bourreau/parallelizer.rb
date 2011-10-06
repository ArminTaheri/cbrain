
#
# CBRAIN Project
#
# CbrainTask subclass
#
# Original author: Pierre Rioux
#
# $Id$
#

class CbrainTask::Parallelizer < ClusterTask

  Revision_info=CbrainFileRevision[__FILE__]

  after_status_transition 'New', 'Failed Setup Prerequisites', :trigger_cascade_prepreq_failures

  def setup #:nodoc:
    true
  end

  def job_walltime_estimate #:nodoc:
    max = 1.minute
    self.enabled_subtasks.each do |otask|
      wt = otask.job_walltime_estimate || 1.minute
      max = wt if wt > max
    end
    max + (0.1 * max)
  end

  def cluster_commands #:nodoc:
    params   = self.params || {}

    subtasks = self.enabled_subtasks

    commands = [
      "#",
      "# Parallel execution of #{subtasks.size} tasks.",
      "#",
      "",
      "# Initialize the built-in bash seconds counter",
      "SECONDS=0",
      "START=\"`date`\"",
      "",
      "# Function to report when a child exits.",
      "child_is_done() {",
      "  echo One task finished after $SECONDS seconds.",
      "}",
      "",
      "# Let's trigger this function whenever a subprocess exits.",
      "set -b -m",
      "trap child_is_done SIGCHLD"
    ]

    subtasks.each do |otask|
      odir    = otask.full_cluster_workdir
      oscript = otask.qsub_script_basename
      oout    = otask.stdout_cluster_filename
      oerr    = otask.stderr_cluster_filename
      commands += [
        "",
        "# Run task #{otask.fullname}",
        "",
        "if test -d '#{odir}' ; then",
        "  echo Starting script for task '#{otask.fullname}' in background.",
        "  cd '#{odir}'",
        "  /bin/bash #{oscript} > '#{oout}' 2> '#{oerr}' &",
        "else",
        "  echo Could not find workdir of task '#{otask.fullname}'. Skipping.",
        "fi"
      ]
    end

    commands += [
      "",
      "echo Waiting for all tasks to finish, at $START",
      "wait",
      "trap - SIGCHLD",
      "",
      "echo All tasks completed after $SECONDS seconds, at `date`.",
      ""
    ]
    
    commands
  end

  def save_results #:nodoc:
    params   = self.params || {}
    self.addlog("Marking all tasks as ready.")
    self.enabled_subtasks.each do |otask|
      otask.addlog("#{self.fullname} marking me as \"Data Ready\".")
      otask.status_transition!(otask.status, "Data Ready")
      otask.remove_prerequisites_for_post_processing(self)
      otask.save!
      otask.meta[:configure_only] = nil # task becomes normal so it can be manipulated by user
    end
    return true
  end

  # Returns true if all enabled subtasks are
  # either Completed or Failed, which is
  # necessary for restarts.
  def all_subtasks_are?(states = /Completed|Failed|Terminated/) #:nodoc:
    return true if self.enabled_subtasks.all? { |otask| otask.status =~ states }
    self.addlog("Cannot proceed, as subtasks are not in states matching #{states.inspect}.")
    false
  end

  # Since the 'setup' of a parallelizer does nothing (see above in setup()),
  # a failure to setup is rather unlikely! It if happens, it's some sort of system
  # problem, so we just allow 'recovery' by retrying the whole thing.
  def recover_from_setup_failure #:nodoc:
    true
  end

  def restart_at_setup #:nodoc:
    unless self.all_subtasks_are?(/Completed|Failed|Terminated/)
      self.addlog("This task can only be restarted at Setup if its subtasks are all either Completed, Failed, or Terminated.")
      return false
    end
    self.enabled_subtasks.each do |otask|
      otask.add_prerequisites_for_post_processing(self,'Completed')
      otask.meta[:configure_only] = true
      orig_status = otask.status
      if orig_status =~ /Completed|Terminated/
        otask.restart('Setup')
      else
        otask.status_transition(otask.status, "Failed To Setup") if otask.status =~ /Failed (On Cluster|To PostProcess)/ # resets
        otask.recover
      end
      if orig_status !~ /Prerequisites/ && otask.status !~ /^Recover|Restart/
        self.addlog("Could not recover or restart subtask #{otask.fullname}.")
        return false
      end
      otask.save!
    end
    true
  end

  def restart_at_cluster #:nodoc:
    self.addlog("This task cannot be restarted at the Cluster stage.")
    self.addlog("It can be restarted at Setup if subtasks are all either Completed, Failed or Terminated.")
    self.addlog("It can be restarted at Post Processing if all subtasks are Completed.")
    false
  end

  def restart_at_post_processing #:nodoc:
    unless self.all_subtasks_are?(/Completed/)
      self.addlog("This task can only be restarted at Post Processing if its subtasks are all Completed.")
      return false
    end
    self.enabled_subtasks.each do |otask|
      otask.remove_prerequisites_for_post_processing(self)
      otask.meta[:configure_only] = nil
      otask.restart("PostProcess")
      otask.save!
    end
    self.addlog("This parallelizer doesn't need to restart its own post processing.")
    self.addlog("Its subtasks, however, were properly notified to do so.")
    false
  end

  # If a serializer fails its setup prerequisites, then we need
  # to mark its subtasks that are New or Configured the same way.
  def trigger_cascade_prepreq_failures(from_state) #:nodoc
    self.enabled_subtasks.where(:status => [ 'New', 'Configured' ] ).each do |otask|
      otask.addlog("#{self.fullname} indicates setup prereq failure.")
      otask.status_transition(otask.status, 'Failed Setup Prerequisites') rescue true
    end
    true
  end

end
