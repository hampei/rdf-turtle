#!/usr/bin/env ruby
$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), 'lib')))
require 'rubygems'

namespace :gem do
  desc "Build the rdf-turtle-#{File.read('VERSION').chomp}.gem file"
  task :build => "lib/rdf/turtle/meta.rb" do
    sh "gem build rdf-turtle.gemspec && mv rdf-turtle-#{File.read('VERSION').chomp}.gem pkg/"
  end

  desc "Release the rdf-turtle-#{File.read('VERSION').chomp}.gem file"
  task :release do
    sh "gem push pkg/rdf-turtle-#{File.read('VERSION').chomp}.gem"
  end
end

desc 'Default: run specs.'
task :default => :spec
task :specs => :spec

require 'rspec/core/rake_task'
desc 'Run specifications'
RSpec::Core::RakeTask.new do |spec|
  spec.rspec_opts = %w(--options spec/spec.opts) if File.exists?('spec/spec.opts')
end

desc "Run specs through RCov"
RSpec::Core::RakeTask.new("spec:rcov") do |spec|
  spec.rcov = true
  spec.rcov_opts =  %q[--exclude "spec"]
end

desc "Generate HTML report specs"
RSpec::Core::RakeTask.new("doc:spec") do |spec|
  spec.rspec_opts = ["--format", "html", "-o", "doc/spec.html"]
end

require 'yard'
namespace :doc do
  YARD::Rake::YardocTask.new
end


TTL_DIR = File.expand_path(File.dirname(__FILE__))

# Use SWAP tools expected to be in ../swap
# Download from http://www.w3.org/2000/10/swap/
desc 'Build first, follow and branch tables'
task :meta => "lib/rdf/turtle/meta.rb"

file "lib/rdf/turtle/meta.rb" => ["etc/turtle-ll1.n3", "script/gramLL1"] do |t|
  sh %{
    script/gramLL1 \
      --grammar etc/turtle-ll1.n3 \
      --lang 'http://www.w3.org/ns/formats/Turtle#language' \
      --output lib/rdf/turtle/meta.rb
  }
end

file "etc/turtle-ll1.n3" => "etc/turtle.n3" do
  sh %{
  ( cd ../swap/grammar;
    PYTHONPATH=../.. python ../cwm.py #{TTL_DIR}/etc/turtle.n3 \
      ebnf2bnf.n3 \
      first_follow.n3 \
      --think --data
  )  > etc/turtle-ll1.n3
  }
end

file "etc/turtle.n3" => "etc/turtle.bnf" do
  sh %{
    script/ebnf2ttl -f ttl -o etc/turtle.n3 etc/turtle.bnf
  }
end

file "etc/ebnf.n3" => "etc/ebnf.bnf" do
  sh %{
    script/ebnf2ttl -f ttl -p ebnf -n "http://www.w3.org/ns/formats/EBNF#" -o etc/ebnf.n3 etc/ebnf.bnf
  }
end