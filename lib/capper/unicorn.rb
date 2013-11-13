# unicorn configuration variables
_cset(:unicorn_worker_processes, 4)
_cset(:unicorn_timeout, 30)

# these cannot be overriden
set(:unicorn_script) { File.join(bin_path, "unicorn") }
set(:unicorn_service) { File.join(units_path, "unicorn.service") }
set(:unicorn_config) { File.join(config_path, "unicorn.rb") }
set(:unicorn_pidfile) { File.join(pid_path, "unicorn.pid") }

after "deploy:update_code", "unicorn:setup"
after "deploy:restart", "unicorn:upgrade"
after "deploy:start", "unicorn:start"
after "deploy:stop", "unicorn:stop"

namespace :unicorn do
  desc "Generate unicorn configuration files"
  task :setup, :roles => :app, :except => { :no_release => true } do
    upload_template_file("unicorn.rb",
                         unicorn_config,
                         :mode => "0644")
    upload_template_file("unicorn.sh",
                         unicorn_script,
                         :mode => "0755")
    if use_systemd
      upload_template_file("unicorn.service",
                           unicorn_service,
                           :mode => "0755")
      systemctl "daemon-reload"
      systemctl :enable, :unicorn
    end
  end

  desc "Start unicorn"
  task :start, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :start, :unicorn
    else
      run "#{unicorn_script} start"
    end
  end

  desc "Stop unicorn"
  task :stop, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :stop, :unicorn
    else
      run "#{unicorn_script} stop"
    end
  end

  desc "Restart unicorn"
  task :restart, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :restart, :unicorn
    else
      run "#{unicorn_script} upgrade"
    end
  end

  desc "Upgrade unicorn with zero downtime"
  task :upgrade, :roles => :app, :except => { :no_release => true } do
    run "#{unicorn_script} upgrade"
  end

  desc "Kill unicorn (this should only be used if all else fails)"
  task :kill, :roles => :app, :except => { :no_release => true } do
    run "#{unicorn_script} kill"
  end

  desc "Add a new worker to the currently running process"
  task :addworker, :roles => :app, :except => { :no_release => true } do
    run "#{unicorn_script} addworker"
  end

  desc "Remove a worker from the currently running process"
  task :delworker, :roles => :app, :except => { :no_release => true } do
    run "#{unicorn_script} delworker"
  end

  desc "Rotate all logfiles in the currently running process"
  task :logrotate, :roles => :app, :except => { :no_release => true } do
    run "#{unicorn_script} logrotate"
  end
end
