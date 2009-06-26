
#
# CBRAIN Project
#
# This is a replacement for the drmaa.rb library; this particular subclass
# of class Scir implements the PBS interface.
#
# Original author: Pierre Rioux
#
# $Id$
#

require 'scir'

class ScirPbsSession < Scir::Session

  Revision_info="$Id$"

  Scir.session_subclass = self.to_s

  def revision_info
    self.class.const_get("Revision_info")
  end

  def job_ps(jid)
    IO.popen("qstat -f #{shell_escape(jid)} 2>/dev/null","r") do |i|
      i.readlines.each do |line|
        next unless line.match(/job_state\s*=\s*(\W+)/)
        return Scir::STATE_RUNNING        if line.match(/ = .*R/i)
        return Scir::STATE_QUEUED_ACTIVE  if line.match(/ = .*Q/i)
        return Scir::STATE_USER_ON_HOLD   if line.match(/ = .*H/i)
        return Scir::STATE_USER_SUSPENDED if line.match(/ = .*S/i)
        return Scir::STATE_UNDETERMINED
      end
    end
    return Scir::STATE_UNDETERMINED
  end

  def hold(jid)
    IO.popen("qhold #{shell_escape(jid)} 2>&1","r") do |i|
      p = i.readlines
      raise "Error holding: #{p.join("\n")}" if p.size > 0
      return
    end
  end

  def release(jid)
    IO.popen("qrls #{shell_escape(jid)} 2>&1","r") do |i|
      p = i.readlines
      raise "Error releasing: #{p.join("\n")}" if p.size > 0
      return
    end
  end

  def suspend(jid)
    raise "There is no 'suspend' action available for PBS clusters"
  end

  def resume(jid)
    raise "There is no 'resume' action available for PBS clusters"
  end

  def terminate(jid)
    IO.popen("qdel #{shell_escape(jid)} 2>&1","r") do |i|
      p = i.readlines
      raise "Error deleting: #{p.join("\n")}" if p.size > 0
      return
    end
  end

  private

  def qsubout_to_jid(i)
    id = i.read
    if id && id =~ /^(\d+)/
      return Regexp.last_match[1]
    end
    raise "Cannot find job ID from qsub output"
  end

end

class ScirPbsJobTemplate < Scir::JobTemplate

  Scir.jobtemplate_subclass = self.to_s

  def qsub_command
    raise "Error, this class only handle 'command' as /bin/bash and a single script in 'arg'" unless
      self.command == "/bin/bash" && self.arg.size == 1
    raise "Error: stdin not supported" if self.stdin

    command  = "qsub "
    command += "-S /bin/bash "                    # Always
    command += "-d #{shell_escape(self.wd)} "     if self.wd
    command += "-N #{shell_escape(self.name)} "   if self.name
    command += "-o #{shell_escape(self.stdout)} " if self.stdout
    command += "-e #{shell_escape(self.stderr)} " if self.stderr
    command += "-j oe "                           if self.join
    command += "-q #{shell_escape(self.queue)} "  if self.queue
    command += " #{CBRAIN::EXTRA_QSUB_ARGS} "     unless CBRAIN::EXTRA_QSUB_ARGS.empty?
    command += "#{shell_escape(self.arg[0])}"

    return command
  end

end
