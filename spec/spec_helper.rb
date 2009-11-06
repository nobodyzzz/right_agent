require 'rubygems'

# Nanite uses the JSON gem, which -- if used in a project that also uses ActiveRecord -- MUST be loaded after
# ActiveRecord in order to ensure that a monkey patch is correctly applied. Since Nanite is designed to be compatible
# with Rails, we tentatively try to load AR here, in case RightLink specs are ever executed in a context where
# ActiveRecord is also loaded.
require 'active_record' rescue nil

require 'nanite'
require 'spec'
require 'eventmachine'
require 'fileutils'

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'chef', 'lib', 'providers'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'payload_types', 'lib', 'payload_types'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'config', 'right_link_config'))
require File.join(File.dirname(__FILE__), 'nanite_results_mock')

$:.push File.join(File.dirname( __FILE__), '..', 'actors', 'lib')
$:.push File.join(File.dirname( __FILE__), '..', 'agents', 'lib')
$:.push File.join(File.dirname( __FILE__), '..', 'agents', 'lib', 'common')
$:.push File.join(File.dirname( __FILE__), '..', 'agents', 'lib', 'instance')

NANITE_LOG_PATH = File.dirname(__FILE__)
Nanite::Log.init('dummy', NANITE_LOG_PATH)

at_exit do
  log_file = File.join(File.dirname(__FILE__), 'nanite.dummy.log')
  Nanite::Log.close if RightScale::Platform.windows? && !Nanite::Log.logger.nil?
  File.delete(log_file) if File.file?(log_file)
end

$VERBOSE = nil # Disable constant redefined warning

module RightScale

  module SpecHelpers

    # Setup instance state for tests
    # Use different identity to reset list of past scripts
    def setup_state(identity = '1')
      cleanup_state
      RightScale::InstanceState.const_set(:STATE_FILE, state_file_path)
      RightScale::InstanceState.const_set(:SCRIPTS_FILE, past_scripts_path)
      RightScale::InstanceState.const_set(:BOOT_LOG_FILE, log_path)
      RightScale::InstanceState.const_set(:OPERATION_LOG_FILE, log_path)
      RightScale::InstanceState.const_set(:DECOMMISSION_LOG_FILE, log_path)
      @identity = identity
      @results_factory = RightScale::NaniteResultsMock.new
      Nanite::MapperProxy.send(:class_variable_set, :@@instance, mock('MapperProxy'))
      Nanite::MapperProxy.instance.should_receive(:request).and_yield(@results_factory.success_results).at_least(1)
      Nanite::MapperProxy.instance.should_receive(:push).any_number_of_times
      RightScale::InstanceState.init(@identity)
    end

    # Cleanup files generated by instance state
    def cleanup_state
      delete_if_exists(state_file_path)
      delete_if_exists(past_scripts_path)
      delete_if_exists(log_path)
      FileUtils.rm_rf(File.join(File.dirname(__FILE__), 'lib', 'mock_actors', 'cache'))
    end

    # Path to serialized instance state
    def state_file_path
      File.join(File.dirname(__FILE__), '__state.js')
    end

    # Path to saved passed scripts
    def past_scripts_path
      File.join(File.dirname(__FILE__), '__past_scripts.js')
    end

    # Path to instance boot logs
    def log_path
      File.join(File.dirname(__FILE__), '__nanite.log')
    end

    # Test and delete if exists
    def delete_if_exists(file)
      File.delete(file) if File.file?(file)
    end

    # Setup location of files generated by script execution
    def setup_script_execution
      Dir.glob('__TestScript*').should be_empty
      Dir.glob('[1-9]*').should be_empty
      RightScale::InstanceConfiguration.const_set('CACHE_PATH', File.join(File.dirname(__FILE__), 'cache'))
    end

    # Cleanup files generated by script execution
    def cleanup_script_execution
      FileUtils.rm_rf(RightScale::InstanceConfiguration::CACHE_PATH)
    end
  end
end
