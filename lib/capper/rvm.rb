load "capper/ruby"

$:.unshift(File.expand_path('./lib', ENV['rvm_path']))
require 'rvm/capistrano'

set(:rvm_type, :user)
set(:rvm_ruby_string, File.read(".rvmrc").gsub(/^rvm use --create (.*)/, '\1').strip)

before "deploy:setup", "rvm:setup"
after "deploy:symlink", "rvm:trust_rvmrc"

namespace :rvm do
  # install the requested ruby if missing
  desc "Install the selected ruby version using RVM."
  task :setup, :except => {:no_release => true} do
    wo_gemset = rvm_ruby_string.gsub(/@.*/, '')

    run("echo silent > ~/.curlrc", :shell => "/bin/bash")
    run("source ~/.rvm/scripts/rvm && " +
        "if ! rvm list rubies | grep -q #{wo_gemset}; then " +
        "rvm install #{wo_gemset}; fi && " +
        "rvm use --create #{rvm_ruby_string} >/dev/null",
        :shell => "/bin/bash")
    run("rm ~/.curlrc")

    # this ensures that Gentoos declare -x RUBYOPT="-rauto_gem" is ignored.
    run "touch ~/.rvm/rubies/#{wo_gemset}/lib/ruby/site_ruby/auto_gem.rb"

    # if specified freeze rubygems version, otherwise don't touch it
    if fetch(:rvm_rubygems_version, false)
      run("rvm rubygems #{rvm_rubygems_version}")
    end
  end

  # prevents interactive rvm dialog
  task :trust_rvmrc, :except => {:no_release => true} do
    run "rvm rvmrc trust #{release_path} >/dev/null"
    run "rvm rvmrc trust #{current_path} >/dev/null"
  end
end
