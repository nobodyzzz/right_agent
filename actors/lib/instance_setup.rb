#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class InstanceSetup

  include Nanite::Actor

  expose :report_state

  # Boot if and only if instance state is 'booting'
  #
  # === Parameters
  # agent_identity<String>:: Serialized agent identity for current agent
  def initialize(agent_identity)
    @boot_retries = 0
    @agent_identity = agent_identity
    RightScale::InstanceState.init(agent_identity, ARGV.include?('boot'))
    init_boot if RightScale::InstanceState.value == 'booting'
  end

  # Retrieve current instance state
  #
  # === Return
  # state<RightScale::OperationResult>:: Success operation result containing instance state
  def report_state
    state = RightScale::OperationResult.success(RightScale::InstanceState.value)
  end

  protected

  # We start off by setting the instance 'r_s_version' in the core site and
  # then proceed with the actual boot sequence
  #
  # === Return
  # true:: Always return true
  def init_boot
    request("/booter/set_r_s_version", { :agent_identity => @agent_identity, :r_s_version => 5 }) do |r|
      res = RightScale::OperationResult.from_results(r)
      strand("Failed to set_r_s_version", res) unless res.success?
      boot
    end
    true
  end

  # Retrieve software repositories and configure mirrors accordingly then proceed to
  # retrieving and running boot bundle.
  #
  # === Return
  # true:: Always return true
  def boot
    request("/booter/get_repositories", @agent_identity) do |r|
      res = RightScale::OperationResult.from_results(r)
      if res.success?
        reps = res.content.repositories
        @auditor = RightScale::AuditorProxy.new(res.content.audit_id)
        audit = "Using the following software repositories:\n"
        reps.each { |rep| audit += "  - #{rep.to_s}\n" }
        @auditor.create_new_section("Software repositories configured")
        @auditor.append_info(audit)
        configure_repositories(reps)
        run_boot_bundle do |result|
          if result.success?
            RightScale::InstanceState.value = 'operational'
          else
            strand("Failed to run boot scripts", result)
          end
        end
      else
        strand("Failed to retrieve software repositories", res)
      end
    end
    true
  end

  # Log error to local log file and set instance state to stranded
  #
  # === Parameters
  # msg<String>:: Error message that will be audited and logged
  # res<RightScale::OperationResult>:: Operation result with additional information
  #
  # === Return
  # true:: Always return true
  def strand(msg, res)
    RightScale::InstanceState.value = 'stranded'
    msg += ": #{res.content}" if res.content
    @auditor.append_error(msg) if @auditor
    true
  end

  # Configure software repositories
  # Note: the configurators may return errors when the platform is not what they expect,
  # for now log error and keep going (to replicate legacy behavior).
  #
  # === Parameters
  # repositories<Array[<RepositoryInstantiation>]>:: repositories to be configured
  #
  # === Return
  # true:: Always return true
  def configure_repositories(repositories)
    repositories.each do |repo|
      begin
        klass = constantize(repo.name)
        unless klass.nil?
          fz = nil
          if repo.frozen_date
            # gives us date for yesterday since the mirror for today may not have been generated yet
            fz = (Date.parse(repo.frozen_date) - 1).to_s
            fz.gsub!(/-/,"")
          end
          klass.generate("none", repo.base_urls, fz)
        end
      rescue Exception => e
        RightScale::RightLinkLog.error(e.message)
      end
    end
    true
  end

  # Retrieve and run boot scripts
  #
  # === Return
  # true:: Always return true
  def run_boot_bundle
    options = { :agent_identity => @agent_identity, :audit_id => @auditor.audit_id }
    request("/booter/get_boot_bundle", options) do |r|
      res = RightScale::OperationResult.from_results(r)
      if res.success?
        sequence = RightScale::ExecutableSequence.new(res.content)

        # We want to be able to use Chef providers which use EM (e.g. so they can use RightScale::popen3), this means
        # that we need to synchronize the chef thread with the EM thread since providers run synchronously. So create
        # a thread here and run the sequence in it. Use EM.next_tick to switch back to EM's thread.
        Thread.new do
          if sequence.run
             EM.next_tick { yield RightScale::OperationResult.success }
          else
             EM.next_tick { yield RightScale::OperationResult.error("Failed to run boot bundle") }
          end
        end
    
      else
        msg = "Failed to retrieve boot scripts"
        msg += ": #{res.content}" if res.content
        yield RightScale::OperationResult.error(msg)
      end
    end
    true
  end

  # constantize was taken from
  # File rails/activesupport/lib/active_support/inflector.rb, line 346
  #
  # === Parameters
  # camel_cased_word<String>:: Fully qualified contant name
  #
  # === Return
  # constant<Constant>:: Corresponding ruby constant if there is one
  # nil:: Otherwise
  def constantize(camel_cased_word)
    names = camel_cased_word.split('::')
    names.shift if names.empty? || names.first.empty?

    constant = Object
    names.each do |name|
      # modified to return nil instead of raising an const_missing error
      constant = constant && constant.const_defined?(name) ? constant.const_get(name) : nil
    end
    constant
  end

end