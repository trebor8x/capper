require 'benchmark'
require 'yaml'
require 'capistrano/recipes/deploy/scm'
require 'capistrano/recipes/deploy/strategy'

def _cset(name, *args, &block)
  unless exists?(name)
    set(name, *args, &block)
  end
end

# =========================================================================
# These variables MUST be set in the client capfiles. If they are not set,
# the deploy will fail with an error.
# =========================================================================

_cset(:application) { abort "Please specify the name of your application, set :application, 'foo'" }
_cset(:repository)  { abort "Please specify the repository that houses your application's code, set :repository, 'foo'" }

# =========================================================================
# These variables may be set in the client capfile if their default values
# are not sufficient.
# =========================================================================

_cset(:user) { application }

_cset(:scm, :git)
_cset(:deploy_via, :remote_cache)

_cset(:deploy_to) { "/var/app/#{application}" }
_cset(:revision)  { source.head }

_cset(:maintenance_basename, "maintenance")

_cset(:use_systemd, true)

# =========================================================================
# These variables should NOT be changed unless you are very confident in
# what you are doing. Make sure you understand all the implications of your
# changes if you do decide to muck with these!
# =========================================================================

_cset(:source)            { Capistrano::Deploy::SCM.new(scm, self) }
_cset(:real_revision)     { source.local.query_revision(revision) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } } }

_cset(:strategy)          { Capistrano::Deploy::Strategy.new(deploy_via, self) }

# If overriding release name, please also select an appropriate setting for :releases below.
_cset(:release_name)      { set :deploy_timestamped, true; Time.now.utc.strftime("%Y%m%d%H%M%S") }

_cset :releases_dir,      "releases"
_cset :shared_dir,        "shared"
_cset :current_dir,       "current"

_cset(:releases_path)     { File.join(deploy_to, releases_dir) }
_cset(:shared_path)       { File.join(deploy_to, shared_dir) }
_cset(:current_path)      { File.join(deploy_to, current_dir) }
_cset(:release_path)      { File.join(releases_path, release_name) }

_cset(:bin_path)          { File.join(deploy_to, "bin") }
_cset(:pid_path)          { File.join(shared_path, "pids") }
_cset(:log_path)          { File.join(shared_path, "log") }
_cset(:config_path)       { File.join(shared_path, "config") }
_cset(:units_path)        { File.join(deploy_to, ".config/systemd/user") }

_cset(:releases)          { capture("ls -x #{releases_path}", :except => { :no_release => true }).split.sort }
_cset(:current_release)   { releases.length > 0 ? File.join(releases_path, releases.last) : nil }
_cset(:previous_release)  { releases.length > 1 ? File.join(releases_path, releases[-2]) : nil }

_cset(:current_revision)  { capture("cat #{current_path}/REVISION",     :except => { :no_release => true }).chomp }
_cset(:latest_revision)   { capture("cat #{current_release}/REVISION",  :except => { :no_release => true }).chomp }
_cset(:previous_revision) { capture("cat #{previous_release}/REVISION", :except => { :no_release => true }).chomp if previous_release }

set(:internal_shared_children, fetch(:internal_shared_children, []) | %w(cache config log pids system))

# some tasks, like symlink, need to always point at the latest release, but
# they can also (occassionally) be called standalone. In the standalone case,
# the timestamped release_path will be inaccurate, since the directory won't
# actually exist. This variable lets tasks like symlink work either in the
# standalone case, or during deployment.
_cset(:latest_release) { exists?(:deploy_timestamped) ? release_path : current_release }

# set proper unicode locale, so gemspecs with unicode chars will not crash
# bundler. see https://github.com/capistrano/capistrano/issues/70
set(:default_environment, fetch(:default_environment).merge({
  'LANG' => 'en_US.UTF-8'
}))

# add some colors and hide certain messages
require 'capistrano_colors/configuration'
require 'capistrano_colors/logger'

colorize([
  { :match => /executing `multistage.*/,   :color => :hide,    :level => 2, :prio => 0 },
  { :match => /executing `.*/,             :color => :yellow,  :level => 2, :prio => -10, :attribute => :bright, :prepend => "== Currently " },
  { :match => /executing ".*/,             :color => :magenta, :level => 2, :prio => -20 },
  { :match => /sftp upload complete/,      :color => :hide,    :level => 2, :prio => -20 },

  { :match => /sftp upload/,               :color => :hide,    :level => 1, :prio => -10 },
  { :match => /^transaction:.*/,           :color => :blue,    :level => 1, :prio => -10, :attribute => :bright },
  { :match => /.*out\] (fatal:|ERROR:).*/, :color => :red,     :level => 1, :prio => -10 },
  { :match => /Permission denied/,         :color => :red,     :level => 1, :prio => -20 },
  { :match => /sh: .+: command not found/, :color => :magenta, :level => 1, :prio => -30 },

  { :match => /^err ::/,                   :color => :red,     :level => 0, :prio => -10 },
  { :match => /.*/,                        :color => :blue,    :level => 0, :prio => -20, :attribute => :bright },
])

# do not trace by default
logger.level = Capistrano::Logger::DEBUG

# =========================================================================
# These are helper methods that will be available to your recipes.
# =========================================================================

# Temporarily sets an environment variable, yields to a block, and restores
# the value when it is done.
def with_env(name, value)
  saved, ENV[name] = ENV[name], value
  yield
ensure
  ENV[name] = saved
end

# make sure a block and all commands within are only executed for servers
# matching the specified role even if ROLES or HOSTS is specified on the
# command line, in which case capistrano matches all servers by default. *sigh*
def ensure_role(role, &block)
  if task = current_task
    servers = find_servers_for_task(task)
  else
    servers = find_servers
  end

  servers = servers.select do |server|
    self.roles[role.to_sym].include?(server)
  end

  return if servers.empty?

  original, ENV['HOSTS'] = ENV['HOSTS'], servers.map { |s| s.host }.join(',')

  begin
    yield
  ensure
    ENV['HOSTS'] = original
  end
end

# logs the command then executes it locally.
# returns the command output as a string
def run_locally(cmd)
  logger.trace "executing locally: #{cmd.inspect}" if logger
  output_on_stdout = nil
  elapsed = Benchmark.realtime do
    output_on_stdout = `#{cmd}`
  end
  if $?.to_i > 0 # $? is command exit code (posix style)
    raise Capistrano::LocalArgumentError, "Command #{cmd} returned status code #{$?}"
  end
  logger.trace "command finished in #{(elapsed * 1000).round}ms" if logger
  output_on_stdout
end

# confirm if a conditoin is true (e.g. after 6pm)
def confirm_if(prompt="Continue? ")
  if yield
    yes = HighLine.new.agree(prompt) do |q|
      q.overwrite = false
      q.default = 'n'
    end

    unless yes
      exit(-1)
    end
  end
end

# =========================================================================
# These are the tasks that are available to help with deploying web apps,
# and specifically, Rails applications. You can have cap give you a summary
# of them with `cap -T'.
# =========================================================================

namespace :deploy do
  desc <<-DESC
    Deploys your project. This calls `update', `cleanup' and `restart'. Note that \
    this will generally only work for applications that have already been deployed \
    once. For a "cold" deploy, you'll want to take a look at the `deploy:cold' \
    task, which handles the cold start specifically.
  DESC
  task :default do
    update
    restart
    cleanup
  end

  desc <<-DESC
    Prepares one or more servers for deployment. Before you can use any \
    of the Capistrano deployment tasks with your project, you will need to \
    make sure all of your servers have been prepared with `cap deploy:setup'. When \
    you add a new server to your cluster, you can easily run the setup task \
    on just that server by specifying the HOSTS environment variable:

      $ cap HOSTS=new.server.com deploy:setup

    It is safe to run this task on servers that have already been set up; it \
    will not destroy any deployed revisions or data.
  DESC
  task :setup, :except => { :no_release => true } do
    shared = fetch(:internal_shared_children, []) | fetch(:shared_children, [])
    dirs = [deploy_to, bin_path, releases_path, shared_path]
    dirs += shared.map { |d| File.join(shared_path, d) }
    run "mkdir -p #{dirs.join(' ')}"
  end

  desc <<-DESC
    Copies your project and updates the symlink. It does this in a \
    transaction, so that if either `update_code' or `symlink' fail, all \
    changes made to the remote servers will be rolled back, leaving your \
    system in the same state it was in before `update' was invoked. Usually, \
    you will want to call `deploy' instead of `update', but `update' can be \
    handy if you want to deploy, but not immediately restart your application.
  DESC
  task :update do
    transaction do
      update_code
      create_symlink
    end
  end

  desc <<-DESC
    Copies your project to the remote servers. This is the first stage \
    of any deployment; moving your updated code and assets to the deployment \
    servers. You will rarely call this task directly, however; instead, you \
    should call the `deploy' task (to do a complete deploy) or the `update' \
    task (if you want to perform the `restart' task separately).

    You will need to make sure you set the :scm variable to the source \
    control software you are using (it defaults to :git), and the \
    :deploy_via variable to the strategy you want to use to deploy (it \
    defaults to :remote_cache).
  DESC
  task :update_code, :except => { :no_release => true } do
    on_rollback { run "rm -rf #{release_path}; true" }
    strategy.deploy!
    finalize_update
  end

  desc <<-DESC
    [internal] Touches up the released code. This is called by update_code \
    after the basic deploy finishes.

    This task will set up symlinks to the shared directory for the log, system, \
    and tmp/pids directories as well as mappings specified in :symlinks.
  DESC
  task :finalize_update, :except => { :no_release => true } do
    run(fetch(:internal_symlinks, {}).merge(fetch(:symlinks, {})).map do |source, dest|
      "rm -rf #{latest_release}/#{dest} && " +
      "mkdir -p #{File.dirname(File.join(latest_release, dest))} && " +
      "ln -s #{shared_path}/#{source} #{latest_release}/#{dest}"
    end.join(" && "))
  end

  desc <<-DESC
    Deprecated API. This has become deploy:create_symlink, please update your recipes
  DESC
  task :symlink, :except => { :no_release => true } do
    Kernel.warn "[Deprecation Warning] This API has changed, please hook `deploy:create_symlink` instead of `deploy:symlink`."
    create_symlink
  end

  desc <<-DESC
    Updates the symlink to the most recently deployed version. Capistrano works \
    by putting each new release of your application in its own directory. When \
    you deploy a new version, this task's job is to update the `current' symlink \
    to point at the new version. You will rarely need to call this task \
    directly; instead, use the `deploy' task (which performs a complete \
    deploy, including `restart') or the 'update' task (which does everything \
    except `restart').
  DESC
  task :create_symlink, :except => { :no_release => true } do
    on_rollback do
      if previous_release
        run "rm -f #{current_path}; ln -s #{previous_release} #{current_path}; true"
      else
        logger.important "no previous release to rollback to, rollback of symlink skipped"
      end
    end

    run "rm -f #{current_path} && ln -s #{latest_release} #{current_path}"
  end

  desc <<-DESC
    Blank task exists as a hook into which to install your own environment \
    specific behaviour.
  DESC
  task :start, :roles => :app do
    # Empty Task to overload with your platform specifics
  end

  desc <<-DESC
    Blank task exists as a hook into which to install your own environment \
    specific behaviour.
  DESC
  task :stop, :roles => :app do
    # Empty Task to overload with your platform specifics
  end

  desc <<-DESC
    Blank task exists as a hook into which to install your own environment \
    specific behaviour.
  DESC
  task :restart, :roles => :app, :except => { :no_release => true } do
    # Empty Task to overload with your platform specifics
  end

  desc <<-DESC
    Blank task exists as a hook into which to install your own environment \
    specific behaviour.
  DESC
  task :migrate, :roles => :db, :only => { :primary => true } do
    # Empty Task to overload with your platform specifics
  end

  desc <<-DESC
    Deploy and run pending migrations. This will work similarly to the \
    `deploy' task, but will also run any pending migrations (via the \
    `deploy:migrate' task) prior to updating the symlink. Note that the \
    update in this case is not atomic, and transactions are not used, \
    because migrations are not guaranteed to be reversible.
  DESC
  task :migrations do
    update_code
    migrate
    create_symlink
    restart
  end

  desc <<-DESC
    Deploys and starts a `cold' application. This is useful if you have not \
    deployed your application before, or if your application is (for some \
    other reason) not currently running. It will deploy the code, run any \
    pending migrations, and then instead of invoking `deploy:restart', it will \
    invoke `deploy:start' to fire up the application servers.
  DESC
  task :cold do
    update
    migrate
    start
  end

  namespace :rollback do
    desc <<-DESC
      [internal] Points the current symlink at the previous revision.
      This is called by the rollback sequence, and should rarely (if
      ever) need to be called directly.
    DESC
    task :revision, :except => { :no_release => true } do
      if previous_release
        run "rm #{current_path}; ln -s #{previous_release} #{current_path}"
      else
        abort "could not rollback the code because there is no prior release"
      end
    end

    desc <<-DESC
      [internal] Removes the most recently deployed release.
      This is called by the rollback sequence, and should rarely
      (if ever) need to be called directly.
    DESC
    task :cleanup, :except => { :no_release => true } do
      run "if [ `readlink #{current_path}` != #{current_release} ]; then rm -rf #{current_release}; fi"
    end

    desc <<-DESC
      Rolls back to the previously deployed version. The `current' symlink will \
      be updated to point at the previously deployed version, and then the \
      current release will be removed from the servers. You'll generally want \
      to call `rollback' instead, as it performs a `restart' as well.
    DESC
    task :code, :except => { :no_release => true } do
      revision
      cleanup
    end

    desc <<-DESC
      Rolls back to a previous version and restarts. This is handy if you ever \
      discover that you've deployed a lemon; `cap rollback' and you're right \
      back where you were, on the previously deployed version.
    DESC
    task :default do
      revision
      restart
      cleanup
    end
  end

  desc <<-DESC
    Clean up old releases. By default, the last 5 releases are kept on each \
    server (though you can change this with the keep_releases variable). All \
    other deployed revisions are removed from the servers.
  DESC
  task :cleanup, :except => { :no_release => true } do
    count = fetch(:keep_releases, 5).to_i
    local_releases = capture("ls -xt #{releases_path}").split.reverse
    if count >= local_releases.length
      logger.important "no old releases to clean up"
    else
      logger.info "keeping #{count} of #{local_releases.length} deployed releases"
      directories = (local_releases - local_releases.last(count)).map { |release|
        File.join(releases_path, release) }.join(" ")

      run "rm -rf #{directories}"
    end
  end

  namespace :pending do
    desc <<-DESC
      Displays the `diff' since your last deploy. This is useful if you want \
      to examine what changes are about to be deployed. Note that this might \
      not be supported on all SCM's.
    DESC
    task :diff, :except => { :no_release => true } do
      system(source.local.diff(current_revision))
    end

    desc <<-DESC
      Displays the commits since your last deploy. This is good for a summary \
      of the changes that have occurred since the last deploy. Note that this \
      might not be supported on all SCM's.
    DESC
    task :default, :except => { :no_release => true } do
      from = source.next_revision(current_revision)
      system(source.local.log(from))
    end
  end

  namespace :web do
    desc <<-DESC
      Present a maintenance page to visitors. Disables your application's web \
      interface by writing a "#{maintenance_basename}.html" file to each web server. The \
      servers must be configured to detect the presence of this file, and if \
      it is present, always display it instead of performing the request.

      By default, the maintenance page will just say the site is down for \
      "maintenance", and will be back "shortly", but you can customize the \
      page by specifying the REASON and UNTIL environment variables:

        $ cap deploy:web:disable \\
              REASON="hardware upgrade" \\
              UNTIL="12pm Central Time"

      Further customization will require that you write your own task.
    DESC
    task :disable, :roles => :web, :except => { :no_release => true } do
      require 'erb'
      on_rollback { run "rm -f #{shared_path}/system/#{maintenance_basename}.html" }

      warn <<-EOHTACCESS

        # Please add something like this to your site's Apache htaccess to redirect users to the maintenance page.
        # More Info: http://www.shiftcommathree.com/articles/make-your-rails-maintenance-page-respond-with-a-503

        ErrorDocument 503 /system/#{maintenance_basename}.html
        RewriteEngine On
        RewriteCond %{REQUEST_URI} !\.(css|gif|jpg|png)$
        RewriteCond %{DOCUMENT_ROOT}/system/#{maintenance_basename}.html -f
        RewriteCond %{SCRIPT_FILENAME} !#{maintenance_basename}.html
        RewriteRule ^.*$  -  [redirect=503,last]

        # Or if you are using Nginx add this to your server config:

        root #{current_path}/public;
        try_files $uri/index.html $uri.html $uri @application;

        error_page 503 /system/maintenance.html;

        location @application {
            if (-f $document_root/system/maintenance.html) {
                return 503;
            }

            proxy_pass ...;
        }
      EOHTACCESS

      upload_template_file("maintenance.html",
                           "#{shared_path}/system/#{maintenance_basename}.html",
                           :mode => 0644)
    end

    desc <<-DESC
      Makes the application web-accessible again. Removes the \
      "#{maintenance_basename}.html" page generated by deploy:web:disable, which (if your \
      web servers are configured correctly) will make your application \
      web-accessible again.
    DESC
    task :enable, :roles => :web, :except => { :no_release => true } do
      run "rm -f #{shared_path}/system/#{maintenance_basename}.html"
    end
  end
end
