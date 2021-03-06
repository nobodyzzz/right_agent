#
# Copyright (c) 2009-2012 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

describe RightScale::Sender do

  include FlexMock::ArgumentTypes

  before(:each) do
    @log = flexmock(RightScale::Log)
    @log.should_receive(:error).by_default.and_return { |m| raise RightScale::Log.format(*m) }
    @log.should_receive(:warning).by_default.and_return { |m| raise RightScale::Log.format(*m) }
    @timer = flexmock("timer", :cancel => true).by_default
  end

  describe "when fetching the instance" do
    before do
      RightScale::Sender.class_eval do
        if class_variable_defined?(:@@instance)
          remove_class_variable(:@@instance) 
        end
      end
    end
    
    it "should return nil when the instance is undefined" do
      RightScale::Sender.instance.should == nil
    end
    
    it "should return the instance if defined" do
      instance = flexmock
      RightScale::Sender.class_eval do
        @@instance = "instance"
      end
      
      RightScale::Sender.instance.should_not == nil
    end
  end

  describe "when monitoring broker connectivity" do
    before(:each) do
      @now = Time.at(1000000)
      flexmock(Time).should_receive(:now).and_return(@now).by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {:ping_interval => 0}).by_default
    end

    it "should start inactivity timer at initialization time" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).with(1000, Proc).and_return(@timer).once
      RightScale::Sender.new(@agent)
    end

    it "should not start inactivity timer at initialization time if ping disabled" do
      flexmock(EM::Timer).should_receive(:new).never
      RightScale::Sender.new(@agent)
    end

    it "should restart inactivity timer only if sufficient time has elapsed since last restart" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).with(1000, Proc).and_return(@timer).once
      instance = RightScale::Sender.new(@agent)
      flexmock(Time).should_receive(:now).and_return(@now + 61)
      flexmock(instance.connectivity_checker).should_receive(:restart_inactivity_timer).once
      instance.message_received
      instance.message_received
    end

    it "should check connectivity if the inactivity timer times out" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once.by_default
      RightScale::Sender.new(@agent)
      instance = RightScale::Sender.instance
      flexmock(Time).should_receive(:now).and_return(@now + 61)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).and_yield.once
      flexmock(instance.connectivity_checker).should_receive(:check).once
      instance.message_received
    end

    it "should check connectivity by sending mapper ping" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).twice
      RightScale::Sender.new(@agent)
      instance = RightScale::Sender.instance
      broker_id = "rs-broker-1-1"
      flexmock(instance).should_receive(:publish).with(on do |request|
        request.type.should == "/mapper/ping";
        request.from.should == "agent"
      end, [broker_id]).and_return([broker_id]).once
      instance.connectivity_checker.check(broker_id)
      instance.pending_requests.size.should == 1
    end

    it "should not check connectivity if terminating" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
      RightScale::Sender.new(@agent)
      instance = RightScale::Sender.instance
      flexmock(instance).should_receive(:publish).never
      instance.terminate
      instance.connectivity_checker.check
    end

    it "should not check connectivity if not connected to broker" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
      RightScale::Sender.new(@agent)
      broker_id = "rs-broker-1-1"
      @broker.should_receive(:connected?).with(broker_id).and_return(false)
      instance = RightScale::Sender.instance
      flexmock(instance).should_receive(:publish).never
      instance.connectivity_checker.check(broker_id)
    end

    it "should ignore ping timeout if never successfully publish ping" do
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      old_ping_timeout = RightScale::Sender::ConnectivityChecker::PING_TIMEOUT
      begin
        RightScale::Sender::ConnectivityChecker.const_set(:PING_TIMEOUT, 0.5)
        EM.run do
          EM.add_timer(1) { EM.stop }
          RightScale::Sender.new(@agent)
          instance = RightScale::Sender.instance
          flexmock(instance).should_receive(:publish).and_return([]).once
          instance.connectivity_checker.check(id = nil)
        end
      ensure
        RightScale::Sender::ConnectivityChecker.const_set(:PING_TIMEOUT, old_ping_timeout)
      end
    end

    it "should ignore messages received if ping disabled" do
      @agent.should_receive(:options).and_return(:ping_interval => 0)
      flexmock(EM::Timer).should_receive(:new).never
      RightScale::Sender.new(@agent)
      RightScale::Sender.instance.message_received
    end

    it "should log an exception if the connectivity check fails" do
      @log.should_receive(:error).with(/Failed connectivity check/, Exception, :trace).once
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once.by_default
      RightScale::Sender.new(@agent)
      instance = RightScale::Sender.instance
      flexmock(Time).should_receive(:now).and_return(@now + 61)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).and_yield.once
      flexmock(instance.connectivity_checker).should_receive(:check).and_raise(Exception)
      instance.message_received
    end

    it "should attempt to reconnect if mapper ping times out" do
      @log.should_receive(:error).with(/Mapper ping via broker/).once
      @agent.should_receive(:options).and_return(:ping_interval => 1000)
      broker_id = "rs-broker-localhost-5672"
      @broker.should_receive(:identity_parts).with(broker_id).and_return(["localhost", 5672, 0, 0]).once
      @agent.should_receive(:connect).with("localhost", 5672, 0, 0, true).once
      old_ping_timeout = RightScale::Sender::ConnectivityChecker::PING_TIMEOUT
      old_max_ping_timeouts = RightScale::Sender::ConnectivityChecker::MAX_PING_TIMEOUTS
      begin
        RightScale::Sender::ConnectivityChecker.const_set(:PING_TIMEOUT, 0.5)
        RightScale::Sender::ConnectivityChecker.const_set(:MAX_PING_TIMEOUTS, 1)
        EM.run do
          EM.add_timer(1) { EM.stop }
          RightScale::Sender.new(@agent)
          instance = RightScale::Sender.instance
          flexmock(instance).should_receive(:publish).with(RightScale::Request, nil).and_return([broker_id])
          instance.connectivity_checker.check
        end
      ensure
        RightScale::Sender::ConnectivityChecker.const_set(:PING_TIMEOUT, old_ping_timeout)
        RightScale::Sender::ConnectivityChecker.const_set(:MAX_PING_TIMEOUTS, old_max_ping_timeouts)
      end
    end
  end

  describe "when validating a target" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker).by_default
      @agent.should_receive(:options).and_return({}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
    end

    it "should accept nil target" do
      @instance.__send__(:validate_target, nil, true).should be_true
    end

    it "should accept named target" do
      @instance.__send__(:validate_target, "name", true).should be_true
    end

    describe "and target is a hash" do

      describe "and selector is allowed" do

        it "should accept :all or :any selector" do
          @instance.__send__(:validate_target, {:selector => :all}, true).should be_true
          @instance.__send__(:validate_target, {"selector" => "any"}, true).should be_true
        end

        it "should reject values other than :all or :any" do
          lambda { @instance.__send__(:validate_target, {:selector => :other}, true) }.
              should raise_error(ArgumentError, /Invalid target selector/)
        end

      end

      describe "and selector is not allowed" do

        it "should reject selector" do
          lambda { @instance.__send__(:validate_target, {:selector => :all}, false) }.
              should raise_error(ArgumentError, /Invalid target hash/)
        end

      end

      describe "and tags is specified" do

        it "should accept tags" do
          @instance.__send__(:validate_target, {:tags => []}, true).should be_true
          @instance.__send__(:validate_target, {"tags" => ["tag"]}, true).should be_true
        end

        it "should reject non-array" do
          lambda { @instance.__send__(:validate_target, {:tags => {}}, true) }.
              should raise_error(ArgumentError, /Invalid target tags/)
        end

      end

      describe "and scope is specified" do

        it "should accept account" do
          @instance.__send__(:validate_target, {:scope => {:account => 1}}, true).should be_true
          @instance.__send__(:validate_target, {"scope" => {"account" => 1}}, true).should be_true
        end

        it "should accept shard" do
          @instance.__send__(:validate_target, {:scope => {:shard => 1}}, true).should be_true
          @instance.__send__(:validate_target, {"scope" => {"shard" => 1}}, true).should be_true
        end

        it "should accept account and shard" do
          @instance.__send__(:validate_target, {"scope" => {:shard => 1, "account" => 1}}, true).should be_true
        end

        it "should reject keys other than account and shard" do
          target = {"scope" => {:shard => 1, "account" => 1, :other => 2}}
          lambda { @instance.__send__(:validate_target, target, true) }.
              should raise_error(ArgumentError, /Invalid target scope/)
        end

        it "should reject empty hash" do
          lambda { @instance.__send__(:validate_target, {:scope => {}}, true) }.
              should raise_error(ArgumentError, /Invalid target scope/)
        end

      end

      describe "and multiple are specified" do

        it "should accept scope and tags" do
          @instance.__send__(:validate_target, {:scope => {:shard => 1}, :tags => []}, true).should be_true
        end

        it "should accept scope, tags, and selector" do
          target = {:scope => {:shard => 1}, :tags => ["tag"], :selector => :all}
          @instance.__send__(:validate_target, target, true).should be_true
        end

        it "should reject selector if not allowed" do
          target = {:scope => {:shard => 1}, :tags => ["tag"], :selector => :all}
          lambda { @instance.__send__(:validate_target, target, false) }.
              should raise_error(ArgumentError, /Invalid target hash/)
        end

      end

      it "should reject keys other than selector, scope, and tags" do
        target = {:scope => {:shard => 1}, :tags => [], :selector => :all, :other => 2}
        lambda { @instance.__send__(:validate_target, target, true) }.
            should raise_error(ArgumentError, /Invalid target hash/)
      end

      it "should reject empty hash" do
        lambda { @instance.__send__(:validate_target, {}, true) }.
            should raise_error(ArgumentError, /Invalid target hash/)
      end

      it "should reject value that is not nil, string, or hash" do
        lambda { @instance.__send__(:validate_target, [], true) }.
            should raise_error(ArgumentError, /Invalid target/)
      end

    end

  end

  describe "when making a push request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker).by_default
      @agent.should_receive(:options).and_return({}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
    end

    it "should validate target" do
      @broker.should_receive(:publish)
      flexmock(@instance).should_receive(:validate_target).with("target", true).once
      @instance.send_push('/foo/bar', nil, "target").should be_true
    end

    it "should create a Push object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.class.should == RightScale::Push
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac')
    end

    it "should set the correct target if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.target.should == 'my-target'
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac', 'my-target')
    end

    it "should set the correct target selectors for fanout if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.tags.should == ['tag']
        push.selector.should == :all
        push.scope.should == {:account => 123}
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac', :tags => ['tag'], :selector => :all, :scope => {:account => 123})
    end

    it "should default the target selector to any" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.tags.should == ['tag']
        push.scope.should == {:account => 123}
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac', :tags => ['tag'], :scope => {:account => 123})
    end

    it "should set correct attributes on the push message" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.type.should == '/welcome/aboard'
        push.token.should_not be_nil
        push.persistent.should be_false
        push.from.should == 'agent'
        push.target.should be_nil
        push.confirm.should be_nil
        push.expires_at.should == 0
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac')
    end

    it 'should queue the push if in offline mode and :offline_queueing enabled' do
      @agent.should_receive(:options).and_return({:offline_queueing => true})
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
      @broker.should_receive(:publish).never
      @instance.enable_offline_mode
      @instance.offline_handler.mode.should == :offline
      @instance.send_push('/welcome/aboard', 'iZac')
      @instance.offline_handler.queue.size.should == 1
    end

    it 'should raise exception if not connected to any brokers and :offline_queueing disabled' do
      @log.should_receive(:error).with(/Failed to publish request/, RightAMQP::HABrokerClient::NoConnectedBrokers).once
      @broker.should_receive(:publish).and_raise(RightAMQP::HABrokerClient::NoConnectedBrokers)
      @agent.should_receive(:options).and_return({:offline_queueing => false})
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      lambda { @instance.send_push('/welcome/aboard', 'iZac') }.should raise_error(RightScale::Sender::TemporarilyOffline)
    end

    it "should store the response handler if given" do
      response_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.confirm.should == true
      end, hsh(:persistent => false, :mandatory => true)).once
      @instance.send_push('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['abc'].response_handler.should == response_handler
    end

    it "should store the request receive time if there is a response handler" do
      response_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      @instance.pending_requests.kind(RightScale::Sender::PendingRequests::PUSH_KINDS).youngest_age.should be_nil
      @instance.send_push('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['abc'].receive_time.should == Time.at(1000000)
      flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
      @instance.pending_requests.kind(RightScale::Sender::PendingRequests::PUSH_KINDS).youngest_age.should == 100
    end

    it "should eventually remove push from pending requests if no response received" do
      response_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc', 'xyz').twice
      @instance.send_push('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['abc'].should_not be_nil
      flexmock(Time).should_receive(:now).and_return(Time.at(1000121))
      @instance.send_push('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['xyz'].should_not be_nil
      @instance.pending_requests['abc'].should be_nil
    end

    it "should log exceptions and re-raise them" do
      @log.should_receive(:error).with(/Failed to publish request/, Exception, :trace).once
      @broker.should_receive(:publish).and_raise(Exception)
      lambda { @instance.send_push('/welcome/aboard', 'iZac') }.should raise_error(RightScale::Sender::SendFailure)
    end
  end

  describe "when making a send_persistent_push request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
    end

    it "should create a Push object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.class.should == RightScale::Push
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_push('/welcome/aboard', 'iZac')
    end

    it "should set correct attributes on the push message" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.type.should == '/welcome/aboard'
        push.token.should_not be_nil
        push.persistent.should be_true
        push.from.should == 'agent'
        push.target.should be_nil
        push.confirm.should be_nil
        push.expires_at.should == 0
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_push('/welcome/aboard', 'iZac')
    end

    it "should default the target selector to any" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.tags.should == ['tag']
        push.scope.should == {:account => 123}
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_push('/welcome/aboard', 'iZac', :tags => ['tag'], :scope => {:account => 123})
    end

    it "should store the response handler if given" do
      response_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |push|
        push.confirm.should == true
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_push('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['abc'].response_handler.should == response_handler
    end

    it "should store the request receive time if there is a response handler" do
      response_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @instance.pending_requests.kind(RightScale::Sender::PendingRequests::PUSH_KINDS).youngest_age.should be_nil
      @instance.send_persistent_push('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['abc'].receive_time.should == Time.at(1000000)
      flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
      @instance.pending_requests.kind(RightScale::Sender::PendingRequests::PUSH_KINDS).youngest_age.should == 100
    end
  end

  describe "when making a send_retryable_request request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      @broker_id = "rs-broker-host-123"
      @broker_ids = [@broker_id]
      @broker = flexmock("Broker", :subscribe => true, :publish => @broker_ids, :connected? => true,
                         :all => @broker_ids, :identity_parts => ["host", 123, 0, 0]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker).by_default
      @agent.should_receive(:options).and_return({:ping_interval => 0, :time_to_live => 100}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
    end

    it "should validate target" do
      @broker.should_receive(:publish).and_return(@broker_ids).once
      flexmock(@instance).should_receive(:validate_target).with("target", false).once
      @instance.send_retryable_request('/foo/bar', nil, "target") {_}.should be_true
    end

    it "should create a Request object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.class.should == RightScale::Request
      end, hsh(:persistent => false, :mandatory => true)).and_return(@broker_ids).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
    end

    it "should set correct attributes on the request message" do
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.type.should == '/welcome/aboard'
        request.token.should_not be_nil
        request.persistent.should be_false
        request.from.should == 'agent'
        request.target.should be_nil
        request.expires_at.should == 1000100
      end, hsh(:persistent => false, :mandatory => true)).and_return(@broker_ids).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
    end

    it "should disable time-to-live if disabled in configuration" do
      @agent.should_receive(:options).and_return({:ping_interval => 0, :time_to_live => 0})
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.expires_at.should == 0
      end, hsh(:persistent => false, :mandatory => true)).and_return(@broker_ids).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
    end

    it "should set the correct target if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.target.should == 'my-target'
      end, hsh(:persistent => false, :mandatory => true)).and_return(@broker_ids).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', 'my-target') {|_|}
    end

    it "should set the correct target selectors if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.tags.should == ['tag']
        request.selector.should == :any
        request.scope.should == {:account => 123}
      end, hsh(:persistent => false, :mandatory => true)).and_return(@broker_ids).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', :tags => ['tag'], :scope => {:account => 123}) {|_|}
    end

    it "should set up for retrying the request if necessary by default" do
      flexmock(@instance).should_receive(:publish_with_timeout_retry).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', 'my-target') {|_|}
    end

    it "should store the response handler" do
      response_handler = lambda {}
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      @instance.send_retryable_request('/welcome/aboard', 'iZac', &response_handler)
      @instance.pending_requests['abc'].response_handler.should == response_handler
    end

    it "should store the request receive time" do
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
      @instance.pending_requests.kind(RightScale::Sender::PendingRequests::REQUEST_KINDS).youngest_age.should be_nil
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['abc'].receive_time.should == Time.at(1000000)
      flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
      @instance.pending_requests.kind(RightScale::Sender::PendingRequests::REQUEST_KINDS).youngest_age.should == 100
    end

    it 'should queue the request if in offline mode and :offline_queueing enabled' do
      @agent.should_receive(:options).and_return({:offline_queueing => true})
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
      @broker.should_receive(:publish).never
      @instance.enable_offline_mode
      @instance.offline_handler.mode.should == :offline
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.offline_handler.queue.size.should == 1
    end

    it 'should raise exception if not connected to any brokers and :offline_queueing disabled' do
      @log.should_receive(:error).with(/Failed to publish request/, RightAMQP::HABrokerClient::NoConnectedBrokers).once
      @broker.should_receive(:publish).and_raise(RightAMQP::HABrokerClient::NoConnectedBrokers)
      @agent.should_receive(:options).and_return({:offline_queueing => false})
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      lambda { @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|} }.should raise_error(RightScale::Sender::TemporarilyOffline)
    end

    it "should dump the pending requests" do
      flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.dump_requests.should == ["#{Time.at(1000000).localtime} <abc>"]
    end

    it "should not allow a selector target" do
      lambda { @instance.send_retryable_request('/welcome/aboard', 'iZac', :selector => :all) }.should raise_error(ArgumentError)
    end

    it "should raise error if there is no callback block" do
      lambda { @instance.send_retryable_request('/welcome/aboard', 'iZac') }.should raise_error(ArgumentError)
    end

    it "should log exceptions and re-raise them" do
      @log.should_receive(:error).with(/Failed to publish request/, Exception, :trace).once
      @broker.should_receive(:publish).and_raise(Exception)
      lambda { @instance.send_retryable_request('/welcome/aboard', 'iZac') {|r|} }.should raise_error(RightScale::Sender::SendFailure)
    end

    describe "with retry" do
      it "should not setup for retry if retry_timeout nil" do
        flexmock(EM).should_receive(:add_timer).never
        @agent.should_receive(:options).and_return({:retry_timeout => nil})
        RightScale::Sender.new(@agent)
        @instance = RightScale::Sender.instance
        @broker.should_receive(:publish).and_return(@broker_ids).once
        @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      end

      it "should not setup for retry if retry_interval nil" do
        flexmock(EM).should_receive(:add_timer).never
        @agent.should_receive(:options).and_return({:retry_interval => nil})
        RightScale::Sender.new(@agent)
        @instance = RightScale::Sender.instance
        @broker.should_receive(:publish).and_return(@broker_ids).once
        @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      end

      it "should not setup for retry if publish failed" do
        flexmock(EM).should_receive(:add_timer).never
        @agent.should_receive(:options).and_return({:retry_timeout => 60, :retry_interval => 60})
        RightScale::Sender.new(@agent)
        @instance = RightScale::Sender.instance
        @broker.should_receive(:publish).and_raise(Exception).once
        @log.should_receive(:error).with(/Failed to publish request/, Exception, :trace).once
        lambda do
          @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
        end.should raise_error(RightScale::Sender::SendFailure)
      end

      it "should setup for retry if retry_timeout and retry_interval not nil and publish successful" do
        flexmock(EM).should_receive(:add_timer).with(60, any).once
        @agent.should_receive(:options).and_return({:retry_timeout => 60, :retry_interval => 60})
        RightScale::Sender.new(@agent)
        @instance = RightScale::Sender.instance
        @broker.should_receive(:publish).and_return(@broker_ids).once
        @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      end

      it "should succeed after retrying once" do
        EM.run do
          token = 'abc'
          result = RightScale::OperationResult.non_delivery(RightScale::OperationResult::RETRY_TIMEOUT)
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return(token).twice
          @agent.should_receive(:options).and_return({:retry_timeout => 0.3, :retry_interval => 0.1})
          RightScale::Sender.new(@agent)
          @instance = RightScale::Sender.instance
          flexmock(@instance.connectivity_checker).should_receive(:check).once
          @broker.should_receive(:publish).and_return(@broker_ids).twice
          @instance.send_retryable_request('/welcome/aboard', 'iZac') do |response|
            result = RightScale::OperationResult.from_results(response)
          end
          EM.add_timer(0.15) do
            @instance.pending_requests.empty?.should be_false
            result = RightScale::Result.new(token, nil, {'from' => RightScale::OperationResult.success}, nil)
            @instance.handle_response(result)
          end
          EM.add_timer(0.3) do
            EM.stop
            result.success?.should be_true
            @instance.pending_requests.empty?.should be_true
          end
        end
      end

      it "should respond with retry if publish fails with no brokers when retrying" do
        EM.run do
          token = 'abc'
          result = RightScale::OperationResult.non_delivery(RightScale::OperationResult::RETRY_TIMEOUT)
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return(token).twice
          @agent.should_receive(:options).and_return({:retry_timeout => 0.3, :retry_interval => 0.1})
          RightScale::Sender.new(@agent)
          @instance = RightScale::Sender.instance
          flexmock(@instance.connectivity_checker).should_receive(:check).never
          @broker.should_receive(:publish).and_return(@broker_ids).ordered.once
          @broker.should_receive(:publish).and_raise(RightAMQP::HABrokerClient::NoConnectedBrokers).ordered.once
          @log.should_receive(:error).with(/Failed to publish request/, RightAMQP::HABrokerClient::NoConnectedBrokers).once
          @log.should_receive(:error).with(/Failed retry for.*temporarily offline/).once
          @instance.send_retryable_request('/welcome/aboard', 'iZac') do |response|
            result = RightScale::OperationResult.from_results(response)
            result.retry?.should be_true
            result.content.should == "lost connectivity"
          end
          EM.add_timer(0.15) do
            EM.stop
            result.retry?.should be_true
            @instance.pending_requests.empty?.should be_true
          end
        end
      end

      it "should respond with non-delivery if publish fails in unknown way when retrying" do
        EM.run do
          token = 'abc'
          result = RightScale::OperationResult.non_delivery(RightScale::OperationResult::RETRY_TIMEOUT)
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return(token).twice
          @agent.should_receive(:options).and_return({:retry_timeout => 0.3, :retry_interval => 0.1})
          RightScale::Sender.new(@agent)
          @instance = RightScale::Sender.instance
          flexmock(@instance.connectivity_checker).should_receive(:check).never
          @broker.should_receive(:publish).and_return(@broker_ids).ordered.once
          @broker.should_receive(:publish).and_raise(Exception.new).ordered.once
          @log.should_receive(:error).with(/Failed to publish request/, Exception, :trace).once
          @log.should_receive(:error).with(/Failed retry for.*send failure/).once
          @instance.send_retryable_request('/welcome/aboard', 'iZac') do |response|
            result = RightScale::OperationResult.from_results(response)
            result.non_delivery?.should be_true
            result.content.should == "retry failed"
          end
          EM.add_timer(0.15) do
            EM.stop
            result.non_delivery?.should be_true
            @instance.pending_requests.empty?.should be_true
          end
        end
      end

      it "should not respond if retry mechanism fails in unknown way" do
        EM.run do
          token = 'abc'
          result = nil
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return(token).twice
          @agent.should_receive(:options).and_return({:retry_timeout => 0.3, :retry_interval => 0.1})
          RightScale::Sender.new(@agent)
          @instance = RightScale::Sender.instance
          flexmock(@instance.connectivity_checker).should_receive(:check).and_raise(Exception).once
          @broker.should_receive(:publish).and_return(@broker_ids).twice
          @log.should_receive(:error).with(/Failed retry for.*without responding/, Exception, :trace).once
          @instance.send_retryable_request('/welcome/aboard', 'iZac') {_}
          EM.add_timer(0.15) do
            EM.stop
            result.should be_nil
            @instance.pending_requests.empty?.should be_false
          end
        end
      end

      it "should timeout after retrying twice" do
        pending 'Too difficult to get timing right for Windows' if RightScale::Platform.windows?
        EM.run do
          result = RightScale::OperationResult.success
          @log.should_receive(:warning).once
          @agent.should_receive(:options).and_return({:retry_timeout => 0.6, :retry_interval => 0.1})
          RightScale::Sender.new(@agent)
          @instance = RightScale::Sender.instance
          flexmock(@instance.connectivity_checker).should_receive(:check).once
          @broker.should_receive(:publish).and_return(@broker_ids).times(3)
          @instance.send_retryable_request('/welcome/aboard', 'iZac') do |response|
            result = RightScale::OperationResult.from_results(response)
          end
          @instance.pending_requests.empty?.should be_false
          EM.add_timer(1) do
            EM.stop
            result.non_delivery?.should be_true
            result.content.should == RightScale::OperationResult::RETRY_TIMEOUT
            @instance.pending_requests.empty?.should be_true
          end
        end
      end

      it "should retry with same request expires_at value" do
        EM.run do
          token = 'abc'
          expires_at = nil
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return(token).twice
          @agent.should_receive(:options).and_return({:retry_timeout => 0.5, :retry_interval => 0.1})
          RightScale::Sender.new(@agent)
          @instance = RightScale::Sender.instance
          flexmock(@instance.connectivity_checker).should_receive(:check).once
          @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
            request.expires_at.should == (expires_at ||= request.expires_at)
          end, hsh(:persistent => false, :mandatory => true)).and_return(@broker_ids).twice
          @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
          EM.add_timer(0.2) { EM.stop }
        end
      end

      describe "and checking connection status" do
        before(:each) do
          @broker_id = "rs-broker-host-123"
          @broker_ids = [@broker_id]
        end

        it "should not check connection if check already in progress" do
          flexmock(EM::Timer).should_receive(:new).and_return(@timer).never
          @instance.connectivity_checker.ping_timer = true
          flexmock(@instance).should_receive(:publish).never
          @instance.connectivity_checker.check(@broker_ids)
        end

        it "should publish ping to mapper" do
          flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
          flexmock(@instance).should_receive(:publish).with(on { |request| request.type.should == "/mapper/ping" },
                                                            @broker_ids).and_return(@broker_ids).once
          @instance.connectivity_checker.check(@broker_id)
          @instance.pending_requests.size.should == 1
        end

        it "should not make any connection changes if receive ping response" do
          flexmock(RightScale::AgentIdentity).should_receive(:generate).and_return('abc').once
          @timer.should_receive(:cancel).once
          flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
          flexmock(@instance).should_receive(:publish).and_return(@broker_ids).once
          @instance.connectivity_checker.check(@broker_id)
          @instance.connectivity_checker.ping_timer.should == @timer
          @instance.pending_requests.size.should == 1
          @instance.pending_requests['abc'].response_handler.call(nil)
          @instance.connectivity_checker.ping_timer.should == nil
        end

        it "should try to reconnect if ping times out repeatedly" do
          @log.should_receive(:warning).with(/timed out after 30 seconds/).twice
          @log.should_receive(:error).with(/reached maximum of 3 timeouts/).once
          flexmock(EM::Timer).should_receive(:new).and_yield.times(3)
          flexmock(@agent).should_receive(:connect).once
          @instance.connectivity_checker.check(@broker_id)
          @instance.connectivity_checker.check(@broker_id)
          @instance.connectivity_checker.check(@broker_id)
          @instance.connectivity_checker.ping_timer.should == nil
        end

        it "should log error if attempt to reconnect fails" do
          @log.should_receive(:warning).with(/timed out after 30 seconds/).twice
          @log.should_receive(:error).with(/Failed to reconnect/, Exception, :trace).once
          flexmock(@agent).should_receive(:connect).and_raise(Exception)
          flexmock(EM::Timer).should_receive(:new).and_yield.times(3)
          @instance.connectivity_checker.check(@broker_id)
          @instance.connectivity_checker.check(@broker_id)
          @instance.connectivity_checker.check(@broker_id)
        end
      end
    end
  end

  describe "when making a send_persistent_request" do
    before(:each) do
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      @broker_id = "rs-broker-host-123"
      @broker_ids = [@broker_id]
      @broker = flexmock("Broker", :subscribe => true, :publish => @broker_ids, :connected? => true,
                         :identity_parts => ["host", 123, 0, 0]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker,
                        :options => {:ping_interval => 0, :time_to_live => 100}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
    end

    it "should create a Request object" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.class.should == RightScale::Request
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac') {|_|}
    end

    it "should set correct attributes on the request message" do
      flexmock(Time).should_receive(:now).and_return(Time.at(1000000))
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.type.should == '/welcome/aboard'
        request.token.should_not be_nil
        request.persistent.should be_true
        request.from.should == 'agent'
        request.target.should be_nil
        request.expires_at.should == 0
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac') {|_|}
    end

    it "should set the correct target if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.target.should == 'my-target'
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac', 'my-target') {|_|}
    end

    it "should set the correct target selectors if specified" do
      @broker.should_receive(:publish).with(hsh(:name => "request"), on do |request|
        request.tags.should == ['tag']
        request.selector.should == :any
        request.scope.should == {:account => 123}
      end, hsh(:persistent => true, :mandatory => true)).once
      @instance.send_persistent_request('/welcome/aboard', 'iZac', :tags => ['tag'], :scope => {:account => 123}) {|_|}
    end

    it "should not set up for retrying the request" do
      flexmock(@instance).should_receive(:publish_with_timeout_retry).never
      @instance.send_persistent_request('/welcome/aboard', 'iZac', 'my-target') {|_|}
    end

    it "should not allow a selector target" do
      lambda { @instance.send_retryable_request('/welcome/aboard', 'iZac', :selector => :all) }.should raise_error(ArgumentError)
    end

    it "should raise error if there is no callback block" do
      lambda { @instance.send_persistent_request('/welcome/aboard', 'iZac') }.should raise_error(ArgumentError)
    end
  end

  describe "when handling a response" do
    before(:each) do
      flexmock(EM).should_receive(:defer).and_yield.by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {:ping_interval => 0}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      flexmock(RightScale::AgentIdentity, :generate => 'token1')
    end

    it "should deliver the response for a Request" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      flexmock(@instance).should_receive(:deliver).with(response, RightScale::Sender::PendingRequest).once
      @instance.handle_response(response)
    end

    it "should deliver the response for a Push" do
      @instance.send_push('/welcome/aboard', 'iZac') {|_|}
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      flexmock(@instance).should_receive(:deliver).with(response, RightScale::Sender::PendingRequest).once
      @instance.handle_response(response)
    end

    it "should not deliver TARGET_NOT_CONNECTED and TTL_EXPIRATION responses for send_retryable_request" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      flexmock(@instance).should_receive(:deliver).never
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::TARGET_NOT_CONNECTED)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::TTL_EXPIRATION)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
    end

    it "should record non-delivery regardless of whether there is a response handler" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::NO_ROUTE_TO_TARGET)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
      @instance.instance_variable_get(:@non_delivery_stats).total.should == 1
    end

    it "should log non-delivery if there is no response handler" do
      @log.should_receive(:info).with(/Non-delivery of/).once
      @instance.send_push('/welcome/aboard', 'iZac')
      non_delivery = RightScale::OperationResult.non_delivery(RightScale::OperationResult::NO_ROUTE_TO_TARGET)
      response = RightScale::Result.new('token1', 'to', non_delivery, 'target1')
      @instance.handle_response(response)
    end

    it "should log a debug message if request no longer pending" do
      @log.should_receive(:debug).with(/No pending request for response/).once
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['token1'].should_not be_nil
      @instance.pending_requests['token2'].should be_nil
      response = RightScale::Result.new('token2', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
    end
  end

  describe "when delivering a response" do
    before(:each) do
      flexmock(EM).should_receive(:defer).and_yield.by_default
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {:ping_interval => 0}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      flexmock(RightScale::AgentIdentity, :generate => 'token1')
    end

    it "should delete all associated pending Request requests" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['token1'].should_not be_nil
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      @instance.pending_requests['token1'].should be_nil
    end

    it "should not delete any pending Push requests" do
      @instance.send_push('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['token1'].should_not be_nil
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      @instance.pending_requests['token1'].should_not be_nil
    end

    it "should delete any associated retry requests" do
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|_|}
      @instance.pending_requests['token1'].should_not be_nil
      @instance.pending_requests['token2'] = @instance.pending_requests['token1'].dup
      @instance.pending_requests['token2'].retry_parent = 'token1'
      response = RightScale::Result.new('token2', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      @instance.pending_requests['token1'].should be_nil
      @instance.pending_requests['token2'].should be_nil
    end

    it "should call the response handler" do
      called = 0
      @instance.send_retryable_request('/welcome/aboard', 'iZac') {|response| called += 1}
      response = RightScale::Result.new('token1', 'to', RightScale::OperationResult.success, 'target1')
      @instance.handle_response(response)
      called.should == 1
    end
  end

  describe "when use offline queueing" do
    before(:each) do
      @broker = flexmock("Broker", :subscribe => true, :publish => ["broker"], :connected? => true,
                         :identity_parts => ["host", 123, 0, 0]).by_default
      @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :options => {:offline_queueing => true}).by_default
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      @instance.initialize_offline_queue
    end

    it 'should queue requests prior to offline handler initialization and then flush once started' do
      old_flush_delay = RightScale::Sender::OfflineHandler::MAX_QUEUE_FLUSH_DELAY
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      begin
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.send_push('/dummy', 'payload')
          @instance.offline_handler.offline?.should be_true
          @instance.offline_handler.state.should == :created
          @instance.offline_handler.instance_variable_get(:@queue).size.should == 1
          @instance.initialize_offline_queue
          @broker.should_receive(:publish).once.and_return { EM.stop }
          @instance.start_offline_queue
          EM.add_timer(1) { EM.stop }
        end
      ensure
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end

    it 'should not queue requests prior to offline handler startup if not offline' do
      old_flush_delay = RightScale::Sender::OfflineHandler::MAX_QUEUE_FLUSH_DELAY
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      begin
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.send_push('/dummy', 'payload')
          @instance.offline_handler.offline?.should be_true
          @instance.offline_handler.state.should == :created
          @instance.offline_handler.instance_variable_get(:@queue).size.should == 1
          @instance.initialize_offline_queue
          @broker.should_receive(:publish).with(Hash, on {|arg| arg.type == "/dummy2"}, Hash).once
          @instance.send_push('/dummy2', 'payload')
          @instance.offline_handler.offline?.should be_false
          @instance.offline_handler.mode.should == :initializing
          @instance.offline_handler.state.should == :initializing
          @instance.offline_handler.instance_variable_get(:@queue).size.should == 1
          @instance.offline_handler.instance_variable_get(:@queue).first[:type].should == "/dummy"
          @broker.should_receive(:publish).with(Hash, on {|arg| arg.type == "/dummy"}, Hash).once
          @instance.start_offline_queue
          EM.add_timer(1) do
            @instance.offline_handler.mode.should == :online
            @instance.offline_handler.state.should == :running
            @instance.offline_handler.instance_variable_get(:@queue).size.should == 0
            EM.stop
          end
        end
      ensure
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end

    it 'should queue requests at front if received after offline handler initialization but before startup' do
      old_flush_delay = RightScale::Sender::OfflineHandler::MAX_QUEUE_FLUSH_DELAY
      RightScale::Sender.new(@agent)
      @instance = RightScale::Sender.instance
      begin
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.send_push('/dummy', 'payload')
          @instance.offline_handler.offline?.should be_true
          @instance.offline_handler.state.should == :created
          @instance.offline_handler.instance_variable_get(:@queue).size.should == 1
          @instance.initialize_offline_queue
          @instance.offline_handler.offline?.should be_false
          @instance.offline_handler.mode.should == :initializing
          @instance.offline_handler.state.should == :initializing
          @instance.enable_offline_mode
          @instance.send_push('/dummy2', 'payload')
          @instance.offline_handler.offline?.should be_true
          @instance.offline_handler.mode.should == :offline
          @instance.offline_handler.state.should == :initializing
          @instance.offline_handler.instance_variable_get(:@queue).size.should == 2
          @instance.offline_handler.instance_variable_get(:@queue).first[:type].should == "/dummy2"
          @instance.start_offline_queue
          @instance.offline_handler.mode.should == :offline
          @instance.offline_handler.state.should == :running
          @broker.should_receive(:publish).with(Hash, on {|arg| arg.type == "/dummy2"}, Hash).once
          @broker.should_receive(:publish).with(Hash, on {|arg| arg.type == "/dummy"}, Hash).once
          @instance.disable_offline_mode
          @instance.offline_handler.state.should == :flushing
          EM.add_timer(1) do
            @instance.offline_handler.mode.should == :online
            @instance.offline_handler.state.should == :running
            @instance.offline_handler.instance_variable_get(:@queue).size.should == 0
            EM.stop
          end
        end
      ensure
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end

    it 'should vote for restart after the maximum number of queued requests is reached' do
      @instance.offline_handler.instance_variable_get(:@restart_vote_count).should == 0
      EM.run do
        @instance.enable_offline_mode
        @instance.offline_handler.queue = ('*' * (RightScale::Sender::OfflineHandler::MAX_QUEUED_REQUESTS - 1)).split(//)
        @instance.send_push('/dummy', 'payload')
        EM.next_tick { EM.stop }
      end
      @instance.offline_handler.queue.size.should == RightScale::Sender::OfflineHandler::MAX_QUEUED_REQUESTS
      @instance.offline_handler.instance_variable_get(:@restart_vote_count).should == 1
    end

    it 'should vote for restart after the threshold delay is reached' do
      old_vote_delay = RightScale::Sender::OfflineHandler::RESTART_VOTE_DELAY
      begin
        RightScale::Sender::OfflineHandler.const_set(:RESTART_VOTE_DELAY, 0.1)
        @instance.offline_handler.instance_variable_get(:@restart_vote_count).should == 0
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload')
          EM.add_timer(0.5) { EM.stop }
        end
        @instance.offline_handler.instance_variable_get(:@restart_vote_count).should == 1
      ensure
        RightScale::Sender::OfflineHandler.const_set(:RESTART_VOTE_DELAY, old_vote_delay)
      end
    end

    it 'should not flush queued requests until back online' do
      old_flush_delay = RightScale::Sender::OfflineHandler::MAX_QUEUE_FLUSH_DELAY
      begin
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload')
          EM.add_timer(0.5) { EM.stop }
        end
      ensure
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end

    it 'should flush queued requests once back online' do
      old_flush_delay = RightScale::Sender::OfflineHandler::MAX_QUEUE_FLUSH_DELAY
      @broker.should_receive(:publish).once.and_return { EM.stop }
      begin
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload')
          @instance.disable_offline_mode
          EM.add_timer(1) { EM.stop }
        end
      ensure
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end

    it 'should stop flushing when going back to offline mode' do
      old_flush_delay = RightScale::Sender::OfflineHandler::MAX_QUEUE_FLUSH_DELAY
      begin
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, 0.1)
        EM.run do
          @instance.enable_offline_mode
          @instance.send_push('/dummy', 'payload')
          @instance.disable_offline_mode
          @instance.offline_handler.state.should == :flushing
          @instance.offline_handler.mode.should == :offline
          @instance.enable_offline_mode
          @instance.offline_handler.state.should == :running
          @instance.offline_handler.mode.should == :offline
          EM.add_timer(1) do
            @instance.offline_handler.state.should == :running
            @instance.offline_handler.mode.should == :offline
            EM.stop
          end
        end
      ensure
        RightScale::Sender::OfflineHandler.const_set(:MAX_QUEUE_FLUSH_DELAY, old_flush_delay)
      end
    end
  end

end
