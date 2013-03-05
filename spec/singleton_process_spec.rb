require 'timeout'
require 'tempfile'
require 'spec_helper'
require 'childprocess'

require File.join(File.dirname(__FILE__), '../lib/singleton_process')

describe SingletonProcess do
  let(:random_pid)   { rand(99999)}
  let(:process_name) {'testing'}
  let(:pidfile_dir)  {Pathname.new('tmp/pids')}
  let(:pidfile_path) {"#{pidfile_dir.join(process_name)}.pid")}

  let(:spawn_command) do
    [ File.join(*RbConfig::CONFIG.values_at('bindir', 'RUBY_INSTALL_NAME')),
      "-I", File.expand_path("../../lib", __FILE__),
      "-r", "singleton_process",
      "-e", """
          trap(:INT) {puts '#{successful_output}'; exit;};
          SingletonProcess.new('#{process_name}').lock;
          while true; sleep 0.01; end;
        """
    ]
  end

  before :all do
    pidfile_dir.mkpath
  end

  before do
    @original_name = $PROGRAM_NAME
  end

  after do
    $PROGRAM_NAME = @original_name
    singleton.send(:delete_pidfile)
  end

  def write_random_pid
    pidfile_path.open('w'){|io| io.write "#{random_pid}\n"}
  end

  describe '.new' do
    let(:tmp_pathname) {Pathname.new('/tmp')}

    it "should accept a name." do
      instance = described_class.new(process_name)
      instance.name.should eql(process_name)
    end

    it "should accept a root_path." do
      instance = described_class.new(process_name, :root_path => tmp_pathname)
      instance.root_path.should eql(tmp_pathname)
    end

    it "should convert root_path to a Pathname." do
      instance = described_class.new(process_name, :root_path => '/tmp')
      instance.root_path.should eql(tmp_pathname)
    end

    it "should set root_path to Rails.root if not specified." do
      stub_const('Rails', double('rails',:root => tmp_pathname))
      instance = described_class.new(process_name)
      instance.root_path.should eql(tmp_pathname)
    end

    it "should accept and save an application name." do
      instance = described_class.new(process_name, :app_name => 'blah')
      instance.app_name.should eql('blah')
    end
  end

  subject(:singleton) {described_class.new(process_name)}

  describe "#name=" do
    it "should be private." do
      singleton.respond_to?(:name=).should be_false
      singleton.respond_to?(:name=, true).should be_true
    end
  end

  describe "#lock" do
    let(:expected_error) {SingletonProcess::AlreadyRunningError}

    context "when it is not already running" do
      it "should write the current PID to the pidfile." do
        singleton.lock
        written_pid = singleton.pidfile_path.read.to_i
        written_pid.should eql(Process.pid)
      end

      it "should set the $PROGRAM_NAME." do
        singleton.lock
        $PROGRAM_NAME.should_not eql(@original_name)
      end
    end

    context "when it is already running" do
      context "in the same process" do
        it "should raise an error." do
          instance1 = described_class.new('blah')
          instance2 = described_class.new('blah')

          instance1.lock
          expect{instance2.lock}.to raise_error(expected_error)
        end
      end

      context "in separate processes" do
        let(:successful_output) {'Ran successfully!'}
        let(:process_name) {'spawn_test'}

        let(:initial_process_output)  {Tempfile.new('output')}
        let(:initial_process) do
          process = ChildProcess.build(*spawn_command)
          process.io.stderr = process.io.stdout = initial_process_output
          process
        end

        let(:second_process_output)  {Tempfile.new('output')}
        let(:second_process) do
          process = ChildProcess.build(*spawn_command)
          process.io.stderr = process.io.stdout = second_process_output
          process
        end

        after do
          initial_process.stop
          second_process.stop

          initial_process_output.close
          second_process_output.close
        end

        it "should raise an error." do
          pidfile_path.exist?.should be_false

          initial_process.start

          start_time = Time.now
          while Time.now - start_time < 15
            break if pidfile_path.exist?
            sleep 0.01
          end
          pidfile_path.exist?.should be_true

          second_process.start

          begin
            second_process.poll_for_exit(15)
          rescue ChildProcess::TimeoutError
            raise "Child process didn't exit properly."
          end

          second_process_output.rewind
          second_process_output.read.should match(/AlreadyRunningError/)
          second_process.crashed?.should be_true

          Process.kill(:INT, initial_process.pid)

          begin
            initial_process.poll_for_exit(5)
          rescue Timeout::Error
            raise "Child process didn't exit properly."
          end

          initial_process_output.rewind
          initial_process_output.read.should eql("#{successful_output}\n")
          initial_process.exit_code.should eql(0)
        end
      end
    end
  end

  describe "#lock_or_exit" do
    context "when it is not already running" do
      it "should be running." do
        singleton.lock
        singleton.pid.should eql(Process.pid)
      end
    end

    context "when it is already running" do
      it "should call exit." do
        instance1 = described_class.new(process_name)
        instance1.lock

        expect{singleton.lock_or_exit}.to raise_error(SystemExit)
      end
    end
  end

  describe "run!" do
    it "should yield." do
      ran = false
      singleton.run! { ran = true }
      ran.should be_true
    end

    it "should call #lock." do
      singleton.should_receive(:lock)
      singleton.run!
    end

    it "should call #unlock." do
      singleton.should_receive(:unlock)
      singleton.run!
    end
  end

  describe "#unlock" do
    it "should delete the pid file." do
      singleton.lock
      singleton.running?.should be_true
      singleton.unlock
      singleton.running?.should be_false
    end
  end

  describe "#running?" do
    context "when the pid file exists" do
      let(:pidfile) {pidfile_path.open('a')}

      before do
        write_random_pid
      end

      after do
        pidfile_path.unlink
      end

      it "should return true when the pid file is locked." do
        pidfile.flock(File::LOCK_EX | File::LOCK_NB).should be_true

        singleton.running?.should be_true
      end

      it "should return false when there is no lock." do
        singleton.running?.should be_false
      end
    end

    it "should return false when the process is not running." do
      pidfile_path.unlink if pidfile_path.exist?
      singleton.running?.should be_false
    end
  end

  describe "#pid" do

    it "should return the pid from pidfile_path." do
      pidfile_path.open('w') {|io| io.write "#{random_pid}\n" }
      singleton.should_receive(:running?).and_return(true)
      singleton.pid.should eql(random_pid)
    end

    it "should return nil unless the process is running?." do
      singleton.pid.should be_nil
    end
  end

  describe "#pidfile_path" do
    it "should return the proper path based on the processes name." do
      singleton.pidfile_path.expand_path.should eql(pidfile_path.expand_path)
    end
  end
end

