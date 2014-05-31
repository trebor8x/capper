_cset(:ruby_exec_prefix, "")
_cset(:ruby) { "#{ruby_exec_prefix} ruby" }
_cset(:rake) { "#{ruby_exec_prefix} rake" }

before "deploy:setup", "gemrc:setup"

namespace :gemrc do
  desc "Setup global ~/.gemrc file"
  task :setup do
    run "mkdir -p #{deploy_to}"
    put("gem: --no-ri --no-rdoc", "#{deploy_to}/.gemrc")
  end
end
