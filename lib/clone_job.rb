require 'git'
require 'octokit'
require_relative 'cloner'

class CloneJob
  @queue = :default

  def self.perform(pr_number, pr_id, originating_hostname, originating_repo, language)
    cloner = Cloner.new({
      originating_hostname: originating_hostname,
      originating_repo: originating_repo,
      pr_number: pr_number,
      pr_id: pr_id,
      language: language
    })

    cloner.clone
  end
end
