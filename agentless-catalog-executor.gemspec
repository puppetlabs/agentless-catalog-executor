# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "ace/version"

Gem::Specification.new do |spec|
  spec.name          = "agentless-catalog-executor"
  spec.version       = ACE::VERSION
  spec.authors       = ["David Schmitt"]
  spec.email         = ["david.schmitt@puppet.com"]

  spec.summary       = 'ACE lets you run remote tasks and catalogs using puppet and bolt.'
  spec.homepage      = "https://github.com/puppetlabs/agentless-catalog-executor"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = "~> 2.5"

  spec.add_dependency "bolt",  ">= 2.9"

  # server-side dependencies cargo culted from https://github.com/puppetlabs/bolt/blob/4418da408643aa7eb5ed64f4c9704b941ea878dc/Gemfile#L10-L16
  spec.add_dependency "hocon", ">= 1.2.5"
  spec.add_dependency "json-schema", ">= 2.8.0"
  spec.add_dependency "puma", ">= 3.12.0"
  spec.add_dependency "puppet", ">= 6.23", "< 8.0.0"
  spec.add_dependency "rack", ">= 2.0.5"
  spec.add_dependency "rails-auth", ">= 2.1.4"
  spec.add_dependency "sinatra", ">= 2.0.4"

  spec.add_development_dependency "bundler", ">= 1.16", "< 3.0.0"
  spec.add_development_dependency "faraday"
  spec.add_development_dependency "rack-test", "~> 1.0"
  spec.add_development_dependency "rake", "~>  13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 0.50"
end
