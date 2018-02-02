require 'fileutils'
require_relative './clone_job'

module Helpers
  def signatures_match?(payload_body, github_signature)
    return true if Sinatra::Base.development?
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['PUBLISHIP_SECRET_TOKEN'], payload_body)
    Rack::Utils.secure_compare(signature, github_signature)
  end

  def process_payload(payload)
    @pr_number       = payload['number']
    @pr_id       = payload['pull_request']['id']
    @originating_repo = payload['repository']['full_name']
    @originating_hostname = payload['repository']['html_url'].match(%r{//(.+?)/})[1]
    @language = payload['repository']['language']
  end

  def merge_pr_into_master?(payload)
    payload['action'] == 'closed' && \
    payload['pull_request']['merged'] == true && \
    payload['pull_request']['base']['ref'] == 'master'
  end
end
