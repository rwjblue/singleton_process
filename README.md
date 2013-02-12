[![Build Status](https://travis-ci.org/rjackson/singleton_process.png)](https://travis-ci.org/rjackson/singleton_process)

# SingletonProcess

Ensure that a given process is only running once. Helpful for ensure that scheduled tasks do not overlap if they run longer than the scheduled interval.

Prior attempts simply used a pid file, and checked if the process specified was still running (by calling `Process.kill(0, pid)`), but 
since the system reuses PID's you can get false positives.  This project uses a locked pid file to ensure that the process is truly still 
running. So basically, if the file is locked the process is still running.

## Supported Rubies

This process is currently tested in nearly every ruby version supported by Travis-CI

* MRI versions 1.8.7, 1.9.2, 1.9.3, 2.0.0
* JRuby running in either 1.8 or 1.9 mode
* Rubinius running in either 1.8 or 1.9 mode

## Installation

Add this line to your application's Gemfile:

    gem 'singleton_process'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install singleton_process

## Usage

The basic usage is quite simple: just supply a process name (will show up in `ps ax` output) and call `#lock`.

```ruby
SingletonProcess.new('long_running_process').lock
```

If you just want to exit if you can't lock call `#lock_or_exit`

```ruby
SingletonProcess.new('long_running_process').lock_or_exit # will call Kernel.exit if it is already running.
```

By default the lock file will be removed when the process exits, but if you need to clear the lock earlier you can call #unlock.

```ruby
process = SingletonProcess.new('long_running_process')
process.lock
# your process here
process.unlock
```

If you want only a specific block of code to be locked call `#run!` with the block.

```ruby
SingletonProcess.new('long_running_process_name').run! do
  # some long running code here
end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
