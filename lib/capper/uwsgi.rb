# uwsgi configuration variables
_cset(:uwsgi_worker_processes, 4)

# these cannot be overriden
set(:uwsgi_script) { File.join(bin_path, "uwsgi") }
set(:uwsgi_service) { File.join(units_path, "uwsgi.service") }
set(:uwsgi_config) { File.join(config_path, "uwsgi.xml") }
set(:uwsgi_pidfile) { File.join(pid_path, "uwsgi.pid") }

after "deploy:update_code", "uwsgi:setup"
after "deploy:restart", "uwsgi:reload"
after "deploy:start", "uwsgi:start"
after "deploy:stop", "uwsgi:stop"

namespace :uwsgi do
  desc "Generate uwsgi configuration files"
  task :setup, :roles => :app, :except => { :no_release => true } do
    upload_template_file("uwsgi.xml",
                         uwsgi_config,
                         :mode => "0644")
    upload_template_file("uwsgi.sh",
                         uwsgi_script,
                         :mode => "0755")
    if use_systemd
      upload_template_file("uwsgi.service",
                           uwsgi_service,
                           :mode => "0644")
      systemctl "daemon-reload"
      systemctl :enable, :uwsgi
    end
  end

  desc "Start uwsgi"
  task :start, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :start, :uwsgi
    else
      run "#{uwsgi_script} start"
    end
  end

  desc "Stop uwsgi"
  task :stop, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :stop, :uwsgi
    else
      run "#{uwsgi_script} stop"
    end
  end

  desc "Reload uwsgi"
  task :restart, :roles => :app, :except => { :no_release => true } do
    if use_systemd
      systemctl :restart, :uwsgi
    else
      run "#{uwsgi_script} reload"
    end
  end
end
