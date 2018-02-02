require 'sinatra/base'
require 'json'
require 'redis'
require 'base64'

require_relative '../config/redis'
require_relative './helpers'
require_relative './cloner'

class RepositorySync < Sinatra::Base
  set :root, File.dirname(__FILE__)
  if Sinatra::Base.development?
    require 'dotenv'
    Dotenv.load
  end

  configure do
    configure_redis
  end

  get '/' do
    'You\'ll want to make a POST to /sync. Check the README for more info.'
  end

  post '/receive' do
    # trim trailing slashes
    request.path_info.sub!(%r{/$}, '')

    # ensure there's a payload
    request.body.rewind
    payload_body = request.body.read.to_s
    halt 400, 'Missing body payload!' if payload_body.nil? || payload_body.empty?

    # ensure signature is correct
    github_signature = request.env['HTTP_X_HUB_SIGNATURE']
    halt 400, 'Signatures didn\'t match!' unless signatures_match?(payload_body, github_signature)

    @payload = JSON.parse(payload_body)
    halt 202, "Payload was not for master, was for #{@payload['pull_request']['base']['ref']}, aborting." unless merge_pr_into_master?(@payload)

    # keep some important vars
    process_payload(@payload)

    Resque.enqueue(CloneJob, @pr_number, @pr_id, @originating_hostname, @originating_repo, @language)
  end

  helpers Helpers
end
