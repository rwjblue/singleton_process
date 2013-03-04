require 'pathname'

class SingletonProcess
  class AlreadyRunningError < RuntimeError; end

  unless defined? VERSION
    VERSION = File.read(File.expand_path('singleton_process/VERSION', File.dirname(__FILE__)))
  end

  attr_accessor :name, :root_path, :app_name
  private :name=

  def initialize(name, options = {})
    self.name      = name
    self.root_path = options.fetch(:root_path, nil)
    self.app_name  = options.fetch(:app_name, nil)
  end

  def root_path=(value)
    @root_path = Pathname.new(value) if value
  end
  private :root_path=

  def root_path
    @root_path ||= defined?(Rails) ? Rails.root : Pathname.new('.')
  end

  def pidfile_path
    pidfile_directory.join("#{name}.pid")
  end

  def lock
    write_pidfile
    at_exit { delete_pidfile }
    $0 = "#{app_name} | #{name} | started #{Time.now}"
  end

  def lock_or_exit
    lock
  rescue AlreadyRunningError
    exit
  end

  def run!
    lock
    yield if block_given?
    unlock
  end

  def unlock
    delete_pidfile
    !running?
  end

  def running?
    if pidfile_path.exist?
      local_pidfile = pidfile_path.open('a')
      !local_pidfile.flock(File::LOCK_EX | File::LOCK_NB)
    else
      false
    end
  ensure
    if local_pidfile
      local_pidfile.flock(File::LOCK_UN)
      local_pidfile.close
    end
  end

  def pid
    running? ? pidfile_path.read.to_i : nil
  end

  private

  def pidfile
    @pidfile ||= pidfile_path.open(File::RDWR|File::CREAT)
  end

  def write_pidfile
    if pidfile.flock(File::LOCK_EX | File::LOCK_NB)
      pidfile.truncate(0)
      pidfile.write("#{Process.pid}\n")
      pidfile.fsync
    else
      raise AlreadyRunningError.new("Process already running: #{pid}")
    end
  end

  def delete_pidfile
    pidfile_path.unlink if pidfile_path.exist?
  end

  def pidfile_directory
    dir = Pathname.new(root_path.join('tmp/pids'))
    dir.mkpath unless dir.directory?
    dir
  end
end

