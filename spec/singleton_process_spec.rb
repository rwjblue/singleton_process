require 'timeout'
require 'spec_helper'

require_relative '../lib/singleton_process'

describe SingletonProcess do
  let(:random_pid)   { rand(99999)}
  let(:process_name) {'testing'}
  let(:pidfile_path) {Pathname.new("tmp/pids/#{process_name}.pid")}

  before do
    @original_name = $PROGRAM_NAME
  end

  after do
    $PROGRAM_NAME = @original_name
    singleton.pidfile_path.unlink if singleton.pidfile_path.exist?
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
      instance = described_class.new(process_name, root_path: tmp_pathname)
      instance.root_path.should eql(tmp_pathname)
    end

    it "should convert root_path to a Pathname." do
      instance = described_class.new(process_name, root_path: '/tmp')
      instance.root_path.should eql(tmp_pathname)
    end

    it "should set root_path to Rails.root if not specified." do
      stub_const('Rails', double('rails',:root => tmp_pathname))
      instance = described_class.new(process_name)
      instance.root_path.should eql(tmp_pathname)
    end

    it "should accept and save an application name." do
      instance = described_class.new(process_name, app_name: 'blah')
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

  describe "lock" do
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

        before do
          require 'open3'
          require 'io/wait'
        end

        after do
          Process.kill(:KILL, @pid1) rescue nil
          Process.kill(:KILL, @pid2) rescue nil
        end

        it "should raise an error." do
          pidfile_path.exist?.should be_false
          stdin1, stdout1, stderr1, wait_thr1 = Open3.popen3(*spawn_command)
          @pid1 = wait_thr1[:pid]

          start_time = Time.now
          while Time.now - start_time < 1
            break if pidfile_path.exist?
            sleep 0.01
          end
          pidfile_path.exist?.should be_true

          stdin2, stdout2, stderr2, wait_thr2 = Open3.popen3(*spawn_command)
          @pid2 = wait_thr2[:pid]

          begin
            exit_status = Timeout.timeout(5) { wait_thr2.value }
          rescue Timeout::Error
            raise "Child process didn't exit properly."
          end

          stderr2.read.should match(/AlreadyRunningError/)
          exit_status.success?.should be_false

          stdin2.close; stdout2.close; stderr2.close

          Process.kill(:INT, @pid1)

          begin
            exit_status = Timeout.timeout(5) { wait_thr1.value }
          rescue Timeout::Error
            raise "Child process didn't exit properly."
          end

          stdout1.read.should eql("#{successful_output}\n")
          stdin1.close; stdout1.close; stderr1.close
          exit_status.success?.should be_true
        end
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
      let(:pidfile) {pidfile_path.open('r')}

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

