require 'open3'
require 'openssl'
require 'jwt'
require 'semverse'
require 'base64'
require 'json'

class Cloner
  GITHUB_DOMAIN = 'github.com'.freeze

  DEFAULTS = {
    :tmpdir               => nil,
    :originating_hostname => GITHUB_DOMAIN,
    :originating_repo     => nil,
    language:                nil,
    pr_number:               nil,
    pr_id:                   nil,
    :git                  => nil
  }.freeze

  RELEASE_LABELS = %w(major minor patch)

  attr_accessor :tmpdir
  attr_accessor :originating_hostname, :originating_repo, :language, :pr_number

  def initialize(options)
    logger.level = Logger::WARN if ENV['RACK_ENV'] == 'test'
    logger.info 'New Cloner instance initialized'

    DEFAULTS.each { |key, value| instance_variable_set("@#{key}", options[key] || value) }
    @tmpdir ||= Dir.mktmpdir('publiship')

    @jwt = establish_jwt
    git_init

    DEFAULTS.keys { |key| logger.info "  * #{key}: #{instance_variable_get("@#{key}")}" }
  end

  def establish_jwt
    private_pem = File.read('publiship.2018-01-25.private-key.pem')
    private_key = OpenSSL::PKey::RSA.new(private_pem)

    # Generate the JWT
    payload = {
      # issued at time
      iat: Time.now.to_i,
      # JWT expiration time (10 minute maximum)
      exp: Time.now.to_i + (10 * 60),
      # GitHub App's identifier
      iss: ENV['GITHUB_IDENTIFIER']
    }

    JWT.encode(payload, private_key, 'RS256')
  end

  def clone
    Bundler.with_clean_env do
      logger.info "Repo cloning to #{tmpdir}/#{@originating_repo}"
      Dir.chdir "#{tmpdir}/#{originating_repo}" do
        # add_remote
        fetch
        checkout

        labels = octokit.labels_for_issue(@originating_repo, @pr_number).map(&:name)
        release_label = labels.select do |l|
          l.casecmp('major').zero? ||
          l.casecmp('minor').zero? ||
          l.casecmp('patch').zero?
        end.first

        # TODO: what if no label found?
        logger.info "Cool, releasing with #{release_label}"

        case @language
        when "Ruby"
          execute_ruby_release(type: release_label)
        end

        logger.info 'fin'
      end
    end
  rescue StandardError => e
    logger.warn(e)
    raise
  ensure
    logger.info "Cleaning up #{tmpdir}"
    FileUtils.rm_rf(tmpdir)
  end

  def remote_name
    @remote_name ||= "origin"
  end

  def url_with_token
    "https://#{token}:x-oauth-basic@#{originating_hostname}/#{originating_repo}.git"
  end

  # Plumbing methods

  def logger
    @logger ||= Logger.new(STDOUT)
  end

  def jwt_client
    @jwt_client ||= Octokit::Client.new(bearer_token: @jwt)
  end

  def octokit
    @octokit ||= Octokit::Client.new(access_token: token)
  end

  def git
    @git ||= begin
      logger.info "Cloning #{originating_repo} from #{originating_hostname}..."
      Git.clone(url_with_token, "#{tmpdir}/#{originating_repo}")
    end
  end

  def token
    @token ||= jwt_client.create_app_installation_access_token(ENV['INSTALLATION_ID'], accept: 'application/vnd.github.machine-man-preview+json').token
  end

  def run_command(*args)
    logger.info "Running command #{args.join(' ')}"
    output, status = Open3.capture2e(*args)
    output = output.gsub(/#{token}/, '<DOTCOM_TOKEN>')
    logger.info "Result: #{output}"
    if status != 0
      report_error(output)
      error = "Command `#{args.join(' ')}` failed"
      error = error.gsub(/#{token}/, '<DOTCOM_TOKEN>')
      raise "#{error}: #{output}"
    end
    output
  end

  def report_error(command_output)
    return unless command_output =~ /Merge conflict|error/i
    body = "Hey, I'm really sorry about this, but there was a merge conflict when "
    body << "I tried to auto-sync the last time, from #{after_sha}:\n"
    body << "\n```\n"
    body << command_output
    body << "\n```\n"
    body << "You'll have to resolve this problem manually, I'm afraid.\n"
    body << "![I'm so sorry](http://media.giphy.com/media/NxKcqJI6MdIgo/giphy.gif)"
    body << "\n\n /cc #{committers.join(' ')}" unless committers.nil?
    octokit.create_issue originating_repo, 'Merge conflict detected', body
  end

  # TODO: do not trust anyone, lots of assumptions here
  def execute_ruby_release(type:)
    version_regex = %r{.version\s*=\s*'([\d\.]+)'}
    gemspec_path = Dir.glob("*.gemspec").first
    gemspec_contents = File.read(gemspec_path)
    version = gemspec_contents.match(version_regex)[1]
    version = Semverse::Version.new(version)
    new_version = "0.0.5"
    gemspec_contents = gemspec_contents.sub(version_regex, ".version = '#{new_version}'")

    gemspec_folder_obj = octokit.contents(@originating_repo,)
    gemspec_file_obj   = gemspec_folder_obj.find { |file| file[:name] == gemspec_path }
    gemspec_file       = octokit.blob(@originating_repo, gemspec_file_obj[:sha])
    gemspec_obj = octokit.contents(@originating_repo, path: gemspec_path)
    gemspec_sha = gemspec_file['sha']
    contents = Base64.encode64(gemspec_contents)
    json = {
      message: "Updating to #{new_version}",
      content: contents,
      sha: gemspec_sha
    }.to_json

    gemspec_file_obj = octokit.update_contents(@originating_repo, gemspec_path, "Release #{new_version}", gemspec_sha, gemspec_contents)
    octokit.add_comment(@originating_repo, @pr_number, "Thanks! This is now out in #{new_version}")
  end

  # Methods that perform sync actions, in order

  def git_init
    git.config('user.name',  ENV['MACHINE_USER_NAME'])
    git.config('user.email', ENV['MACHINE_USER_EMAIL'])
  end

  def add_remote
    logger.info "Adding remote for #{originating_repo} on #{originating_hostname}..."
    git.add_remote(remote_name, url_with_token)
  end

  def fetch
    logger.info "Fetching #{originating_repo}..."
    git.remote(remote_name).fetch
  end

  def checkout
    logger.info "Checking out master"
    run_command('git', 'checkout', 'master')
  end

end
