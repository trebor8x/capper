# configuration variables
_cset(:delayed_job_workers, {})

# these cannot be overriden
set(:delayed_job_script) { File.join(bin_path, "delayed_job") }
set(:delayed_job_service) { File.join(units_path, "delayed_job@.service") }

after "deploy:update_code", "delayed_job:setup"
after "deploy:restart", "delayed_job:restart"
after "deploy:start", "delayed_job:start"
after "deploy:stop", "delayed_job:stop"

namespace :delayed_job do
  desc "Generate DelayedJob configuration files"
  task :setup, :roles => :worker, :except => { :no_release => true } do
    upload_template_file("delayed_job.sh",
                         delayed_job_script,
                         :mode => "0755")
    if use_systemd
      upload_template_file("delayed_job@.service",
                           delayed_job_service,
                           :mode => "0755")
      systemctl "daemon-reload"
      delayed_job_workers.each do |name|
        systemctl :enable, "delayed_job@#{name}"
      end
    end
  end

  desc "Start delayed job workers"
  task :start, :roles => :app, :except => { :no_release => true } do
    delayed_job_workers.each do |name|
      if use_systemd
        systemctl :start, "delayed_job@#{name}"
      else
        run "#{delayed_job_script} start #{name}"
      end
    end
  end

  desc "Stop delayed job workers"
  task :stop, :roles => :app, :except => { :no_release => true } do
    delayed_job_workers.each do |name|
      if use_systemd
        systemctl :stop, "delayed_job@#{name}"
      else
        run "#{delayed_job_script} stop #{name}"
      end
    end
  end

  desc "Restart delayed job workers"
  task :restart, :roles => :app, :except => { :no_release => true } do
    delayed_job_workers.each do |name|
      if use_systemd
        systemctl :restart, "delayed_job@#{name}"
      else
        run "#{delayed_job_script} restart #{name}"
      end
    end
  end
end
