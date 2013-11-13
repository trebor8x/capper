# these cannot be overriden
set(:thin_script) { File.join(bin_path, "thin") }
set(:thin_service) { File.join(units_path, "thin.service") }
set(:thin_pidfile) { File.join(pid_path, "thin.pid") }

_cset(:thin_port, 3000)

after "deploy:update_code", "thin:setup"
after "deploy:restart", "thin:restart"
after "deploy:start", "thin:start"
after "deploy:stop", "thin:stop"

namespace :thin do
  desc "Generate thin configuration files"
  task :setup, :roles => :app, :except => { :no_release => true } do
    upload_template_file("thin.sh",
                         thin_script,
                         :mode => "0755")
    if use_systemd
      upload_template_file("thin.service",
                           thin_service,
                           :mode => "0755")
      systemctl "daemon-reload"
      systemctl :enable, :thin
    end
  end

  desc "Start thin"
  task :start, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :start, :thin
    else
      run "#{thin_script} start"
    end
  end

  desc "Stop thin"
  task :stop, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :stop, :thin
    else
      run "#{thin_script} stop"
    end
  end

  desc "Restart thin with zero downtime"
  task :restart, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :restart, :thin
    else
      run "#{thin_script} kill"
      run "#{thin_script} start"
    end
  end
end
