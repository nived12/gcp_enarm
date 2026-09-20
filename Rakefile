# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks

# parallel:create / parallel:load_schema / parallel_rspec — see bin/ci-test.
# Test-only, so guard the require: the gem is not in the production bundle.
begin
  require "parallel_tests/tasks"
rescue LoadError
  nil
end
