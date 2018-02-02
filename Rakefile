require 'resque/tasks'
require_relative './config/redis'

task 'resque:setup' do
  configure_redis
  ENV['QUEUE'] = '*'
  require_relative './lib/clone_job'
end

desc 'Alias for resque:work (To run workers on Heroku)'
task 'jobs:work' => 'resque:work'

namespace :deploy do
  desc 'Deploy the app'
  task :production do
    branch = ENV['BRANCH'] || 'master'
    app = 'github-repository-sync'
    remote = "git@heroku.com:#{app}.git"

    system "heroku maintenance:on --app #{app}"
    system "git push --force #{remote} #{branch}:master"
    system "heroku run rake db:migrate --app #{app}"
    system "heroku maintenance:off --app #{app}"
  end
end
