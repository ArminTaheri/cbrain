#
#
# CBRAIN Project
#
# This is a replacement for the drmaa.rb library; this particular subclass
# of class Scir implements the SGE interface.
#
# Original author: Pierre Rioux
#
# $Id$
#

class ScirSge < Scir

  Revision_info="$Id$"

  class Session < Scir::Session

    def update_job_info_cache
      @job_info_cache = {}
      IO.popen("qstat -xml 2>/dev/null","r") do |input|
        paragraphs = input.read.split(/(<\/?job_list)/)
        paragraphs.each_index do |i|
          next unless paragraphs[i] == "<job_list"
          next unless paragraphs[i+1] =~ /<JB_job_number>([^<]+)/
          jid = Regexp.last_match[1]
          next unless paragraphs[i+1] =~ /<state>(\w+)/
          statechar = Regexp.last_match[1]
          state     = statestring_to_stateconst(statechar)
          @job_info_cache[jid.to_s] = { :drmaa_state => state }
        end
      end
    end

    def statestring_to_stateconst(state)
      return Scir::STATE_RUNNING        if state =~ /r/i
      return Scir::STATE_USER_SUSPENDED if state =~ /s/i
      return Scir::STATE_USER_ON_HOLD   if state =~ /h/i
      return Scir::STATE_QUEUED_ACTIVE  if state =~ /q/i
      return Scir::STATE_UNDETERMINED
    end

    def hold(jid)
      IO.popen("qhold #{shell_escape(jid)} 2>&1") do |i|
        p = i.read
        raise "Error holding: #{p}" unless p =~ /modified hold of/i
        return
      end
    end

    def release(jid)
      IO.popen("qrls #{shell_escape(jid)} 2>&1") do |i|
        p = i.read
        raise "Error releasing: #{p}" unless p =~ /modified hold of/i
        return
      end
    end

    def suspend(jid)
      raise "There is no 'suspend' action implemented yet for SGE clusters"
    end

    def resume(jid)
      raise "There is no 'resume' action implemented yet for SGE clusters"
    end

    def terminate(jid)
      IO.popen("qdel #{shell_escape(jid)} 2>&1") do |i|
        p = i.read
        raise "Error deleting: #{p}" unless p =~ /has deleted job|has registered/i
        return
      end
    end

    def queue_tasks_tot_max
      queue = Scir.cbrain_config[:default_queue] || ""
      queueopt = queue.blank? ? "" : "-q #{shell_escape(queue)}"
      tot = max = nil
      IO.popen("qstat #{queueopt} -f 2>&1","r") do |fh|
        # queuename                      qtype resv/used/tot. load_avg arch          states
        # ---------------------------------------------------------------------------------
        # all.q@montague.bic.mni.mcgill. BIP   0/0/2          0.12     lx24-x86
        fh.readlines.each do |line|
          if line.match(/(\d+)\/(\d+)\/(\d+)\s+\d+\./)  # Note that the report can contain DATES, like 25/12/2010
            tot ||= 0
            max ||= 0
            tot += Regexp.last_match[2].to_i
            max += Regexp.last_match[3].to_i
          end
        end
      end
      if tot.blank? || max.blank?
        [ "unparsable", "unparsable" ]
      else
        [ tot.to_s, max.to_s ]
      end
    rescue
      [ "exception", "exception" ]
    end

    private

    def qsubout_to_jid(txt)
      if txt && txt =~ /Your job (\d+)/i
        return Regexp.last_match[1]
      end
      raise "Cannot find job ID from qsub output"
    end

  end

  class JobTemplate < Scir::JobTemplate

    def qsub_command
      raise "Error, this class only handle 'command' as /bin/bash and a single script in 'arg'" unless
        self.command == "/bin/bash" && self.arg.size == 1
      raise "Error: stdin not supported" if self.stdin

      command  = ""
      command += "cd #{shell_escape(self.wd)};"     if self.wd
      command += "qsub "
      command += "-S /bin/bash "                    # Always
      command += "-r no "                           # Always
      command += "-cwd "                            if self.wd
      command += "-N #{shell_escape(self.name)} "   if self.name
      command += "-o #{shell_escape(self.stdout)} " if self.stdout
      command += "-e #{shell_escape(self.stderr)} " if self.stderr
      command += "-j y "                            if self.join
      command += "-q #{shell_escape(self.queue)} "  unless self.queue.blank?
      command += " #{Scir.cbrain_config[:extra_qsub_args]} "     unless Scir.cbrain_config[:extra_qsub_args].blank?
      command += "-l h_rt=#{self.walltime.to_i} "   unless self.walltime.blank?
      command += "#{shell_escape(self.arg[0])}"

      command
    end

  end

end

