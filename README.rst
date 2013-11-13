======
capper
======

:Author: `Benedikt Böhm <bb@xnull.de>`_
:Web: http://github.com/zenops/capper
:Git: ``git clone https://github.com/zenops/capper``

Capper is a collection of opinionated Capistrano recipes.

Rationale
=========

Most web applications are deployed the same way. While capistrano itself is
already quite opinionated, maintaining a multitude of applications feels like
copy&paste very fast.

Capper provides sane defaults and many recipes for technologies typically used
with Ruby and Python deployments to make ``config/deploy.rb`` much more
declarative and terse.

Release Notes
=============

v1.0.0 (14/07/2012)
  capper has been in production for about 1 year and its API is now considered stable.

Usage
=====

Capper recipes should be loaded via ``Capfile`` like this::

  require "capper"

  load "capper/bundler"
  load "capper/rails"
  load "capper/rvm"
  load "capper/unicorn"

  load "config/deploy"

  load "capper/multistage"

Note: capper does not support capistranos default deploy recipe, instead an
enhanced copy is shipped directly with capper and enabled by default.

Multistage
----------

Capper provides a clean DSL syntax for multistage support. In contrast to
capistrano-ext you don't have to create a bunch of tiny files in
``config/deploy/`` but instead use DSL sugar in ``config/deploy.rb``::

  stage :production do
    server "app1.example.com", :app, :db, :primary => true
    server "app2.example.com", :app
  end

  stage :staging do
    server "staging.example.com", :app, :db, :primary => true
    set :rails_env, "staging"
    set :branch, "staging"
  end

Note: the multistage recipe must be loaded after ``config/deploy`` otherwise
it cannot know the defined stages.

Templates
---------

Capper provides a powerful yet simple mechanism to upload scripts and config
files rendered from templates during deploy. Template files are stored in
``config/deploy/templates`` but are rarely needed since capper recipes already
contain required template files.

To upload a custom template create an ERb file and upload it with
``upload_template_file``::

  upload_template_file("myscript.sh", "#{bin_path}/myscript", :mode => "0755")

The above command will upload ``config/deploy/templates/myscript.sh.erb`` to
the specified path. Inside the template all capistrano options (current_path,
application, etc) are available.

systemd integration
-----------------

Capper provides integration with a systemd user session running for the user
that is being deployed to. Capper will upload service units and enable/start
these accordingly.

If you don't use systemd simply::

  set :use_systemd, false

Recipes
=======

The following recipes are included in capper.

base
----

The base recipe is an enhanced version of capistranos default deploy recipe. It
is loaded automatically and provides the basic opinions capper has about
deployment:

- The application is deployed to a dedicated user account with the same name as
  the application.

- The parent path for these user accounts defaults to ``/var/app``.

- No sudo privileges are ever needed.

- Releases are cleaned up by default.

- The application is deployed via ``remote_cache`` and ``git``.

The ``deploy:finalize_update`` task has been enhanced to make symlinks
declarative in ``config/deploy.rb``::

  set :symlinks, {
    "config/database.yml" => "config/database.yml",
    "shared/uploads" => "public/uploads"
  }

The above snippet will create symlinks from
``#{shared_path}/config/database.yml`` to
``#{release_path}/config/database.yml`` and from
``#{shared_path}/uploads`` to
``#{release_path}/public/uploads`` after ``deploy:update_code`` has run.


airbrake
--------

The airbrake recipe is merely a copy of airbrakes native capistrano integration
without after/before hooks, so airbrake notifications can be enabled on-demand
in stage blocks::

  stage :production do
    ...
    after "deploy", "airbrake:notify"
  end

bundler
-------

The bundler recipe is an extension of bundlers native capistrano integration:

- During ``bundle:install`` it is ensured that a known-to-work bundler version
  (specified via ``bundler_version``) is installed.

- When used together with the rvm recipe bundles are not installed globally to
  ``shared/bundle`` but instead a gemset specific location is used
  (``shared/bundle/#{gemset}``).

- The option ``ruby_exec_prefix`` is set to ``bundle exec`` for convenience.
  (see ``ruby`` recipe for details)

delayed_job
-----------

The delayed_job recipe provides integration with DelayedJob. A script to
start/stop delayed job workers is uploaded to ``#{bin_path}/delayed_job``. The
script supports multiple instances and priority ranges.

If monit integration has been enabled via ``capper/monit`` workers are
automatically (re)started during deploy and can be specified via
``delayed_job_workers``::

  set :delayed_jobs_workers, {
    :important => 0..1,
    :worker1 => 2..10,
    :worker2 => 2..10
  }

django
------

The django recipe provides setup and migrate tasks for Django.

python
------

The python recipe provides basic support for Python applications. It will
create a symlink from ``#{current_path}/#{application}`` to ``#{current_path}``
for Python namespace support.

rails
-----

The rails recipe sets the default ``rails_env`` to production and includes
tasks for deploying the asset pipeline for rails 3.1 applications. It also
provdes a migrate task for Rails applications.

rvm
---

The rvm recipe is an extension to RVMs native capistrano integration. The
recipe forces the ``rvm_type`` to ``:user`` and will automatically determine
the ruby version and gemset via the projects ``.ruby-version`` and
``.ruby-gemset`` files.

A ``deploy:setup`` hook is provided to ensure the correct rvm, ruby and rubygems
versions are installed on all servers.

ruby
----

The ruby recipe provides basic support for Ruby applications. It will setup a
gemrc file and and variables for ``ruby_exec_prefix`` (such as bundler).

thin
----

The thin recipe provides integration with Thin. A script to manage the
thin process is uploaded to ``#{bin_path}/thin``.

unicorn
-------

The unicorn recipe provides integration with Unicorn. A script to manage the
unicorn process is uploaded to ``#{bin_path}/unicorn``. Additionally this
recipe also manages the unicorn configuration file (in ``config/unicorn.rb``).

The following configuration options are provided:

``unicorn_worker_processes``
  Number of unicorn workers (default: 4)

``unicorn_timeout``
  Timeout after which workers are killed (default: 30)

uwsgi
-----

The uwsgi recipe provides integration with uWSGI. A script to manage the uwsgi
process is uploaded to ``#{bin_path}/uwsgi``. Additionally this recipe also
manages the uwsgi configuration file (in ``config/uwsgi.xml``).

The following configuration options are provided:

``uwsgi_worker_processes``
  Number of uwsgi workers (default: 4)

virtualenv
----------

The virtualenv recipe provides ``deploy:setup`` hooks for virtualenv support.
In addition required Python libraries are installed via pip into this
environment.

whenever
--------

The whenever recipe is a simplified version of whenevers native capistrano
integration. With one application per user account the whole crontab can be
used for whenever. Additionally this recipe take the ``ruby_exec_prefix``
setting into account.
To define the target servers user the cron role.

    server "app1.example.com", :app, :cron

node deployment
--------
read http://big-elephants.com/2012-07/deploying-node-with-capistrano/ about the
the use case.

nave
--------

The nave recipe sets up nave Virtual Environments for Node::

  set :use_nave, true
  set :nave_dir, '~/.nave'
  set :node_version, '0.8.1'

npm
--------

The npm recipe runs npm install after deploy:update_code. When used with the nave
recipe npm install runs ``nave use <ver> npm install``.
Not it is recommended to add npm-shrinkwrap.json into version control to manage npm
dependencies::

  set :npm_cmd, "npm"

forever
--------

The forever recipe starts your app as daemon in the background.
When used with the nave recipe it runs ``nave use <ver> forever [action]``::

  set :forever_cmd, "forever" # e.g. "./node_modules/.bin/forever"
  set :node_env, "production" # the NODE_ENV environment variable used to start the script
  set :main_js, "index.js" # e.g. "./build/main.js" the script you want to start


Contributing to capper
======================

- Check out the latest master to make sure the feature hasn't been implemented
  or the bug hasn't been fixed yet

- Check out the issue tracker to make sure someone already hasn't requested it
  and/or contributed it

- Fork the project

- Start a feature/bugfix branch

- Commit and push until you are happy with your contribution

Copyright
=========

Copyright (c) 2011-2012 Benedikt Böhm. See LICENSE for further details.
