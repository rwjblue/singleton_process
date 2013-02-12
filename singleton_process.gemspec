# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |gem|
  gem.name          = "singleton_process"
  gem.version       = File.read(File.join(lib, 'singleton_process','VERSION'))
  gem.authors       = ["Robert Jackson"]
  gem.email         = ["robert.w.jackson@me.com"]
  gem.description   = %q{Ensure that a given process is only running once. Helpful for ensure that scheduled tasks do not overlap if they run longer than the scheduled interval.}
  gem.summary       = %q{Ensure that a given process is only running once.}
  gem.homepage      = "https://github.com/rjackson/singleton_process"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency 'rspec', '~>2.12.0'
  gem.add_development_dependency 'childprocess', '~>0.3.8'
end
