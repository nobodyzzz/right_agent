#--  -*-ruby-*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'rubygems'
require 'bundler/setup'
require 'fileutils'
require 'rake'
require 'rspec/core/rake_task'
require 'rake/rdoctask'
require 'rake/gempackagetask'
require 'rake/clean'

task :default => 'spec'

# == Gem packaging == #

desc "Package all gems"
task :package => :gem
directory 'pkg'
task :gem => 'pkg' do
  Dir['right*_agent'].each do |file|
    Dir.chdir(file) { sh "env PACKAGE_DIR=../pkg rake gem" }
  end
end

CLEAN.include('pkg')

# == Unit specs == #

RIGHT_BOT_ROOT = File.dirname(__FILE__)

# Allows for debugging of order of spec files by reading a specific ordering of
# files from a text file, if present. All too frequently, success or failure
# depends on the order in which tests execute.
RAKE_SPEC_ORDER_FILE_PATH = ::File.join(RIGHT_BOT_ROOT, "rake_spec_order_list.txt")

# Setup path to spec files and spec options
#
# === Parameters
# t(RSpec::Core::RakeTask):: Task instance to be configured
#
# === Return
# t(RSpec::Core::RakeTask):: Configured task
def setup_spec(t)
  t.rspec_opts = ['--options', "\"#{RIGHT_BOT_ROOT}/spec/spec.opts\""]

  # Optionally read or write spec order for debugging purposes
  # Use a stubbed file with the text "FILL ME" to get the spec ordering
  # for the current machine
  if ::File.file?(RAKE_SPEC_ORDER_FILE_PATH)
    if ::File.read(RAKE_SPEC_ORDER_FILE_PATH).chomp == "FILL ME"
      ::File.open(RAKE_SPEC_ORDER_FILE_PATH, "w") do |f|
        f.puts t.spec_files.to_a.join("\n")
      end
    else
      t.spec_files = FileList.new
      ::File.open(RAKE_SPEC_ORDER_FILE_PATH, "r") do |f|
        while (line = f.gets) do
          line = line.chomp
          (t.spec_files << line) if not line.empty?
        end
      end
    end
  end
  t
end

desc 'Run all specs in all specs directories'
RSpec::Core::RakeTask.new(:spec) do |t|
  setup_spec(t)
end

namespace :spec do
  desc 'Run all specs with RCov'
  RSpec::Core::RakeTask.new(:rcov) do |t|
    setup_spec(t)
    t.rcov = true
    t.rcov_opts = lambda { IO.readlines("#{RIGHT_BOT_ROOT}/spec/rcov.opts").map {|l| l.chomp.split ' '}.flatten }
  end

  desc 'Print Specdoc for all specs (excluding plugin specs)'
  RSpec::Core::RakeTask.new(:doc) do |t|
    setup_spec(t)
    t.spec_opts = ['--format', 'specdoc', '--dry-run']
  end
end

# == Documentation == #

desc "Generate API documentation to doc/rdocs/index.html"
Rake::RDocTask.new do |rd|
  rd.rdoc_dir = 'doc/rdocs'
  rd.main = 'README.rdoc'
  rd.rdoc_files.include 'README.rdoc', '*/README.rdoc', "*/lib/**/*.rb"

  rd.options << '--inline-source'
  rd.options << '--line-numbers'
  rd.options << '--all'
  rd.options << '--fileboxes'
  rd.options << '--diagram'
end

# == Emacs integration == #

desc "Rebuild TAGS file"
task :tags do
  sh "rtags -R */{lib,spec}"
end
