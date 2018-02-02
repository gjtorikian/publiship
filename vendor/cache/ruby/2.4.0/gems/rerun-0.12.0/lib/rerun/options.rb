require 'optparse'
require 'pathname'
require 'rerun/watcher'
require 'rerun/system'

libdir = "#{File.expand_path(File.dirname(File.dirname(__FILE__)))}"

$spec = Gem::Specification.load(File.join(libdir, "..", "rerun.gemspec"))

module Rerun
  class Options

    extend Rerun::System

    # If you change the default pattern, please update the README.md file -- the list appears twice therein, which at the time of this comment are lines 17 and 119
    DEFAULT_PATTERN = "**/*.{rb,js,coffee,css,scss,sass,erb,html,haml,ru,yml,slim,md,feature,c,h}"
    DEFAULT_DIRS = ["."]

    DEFAULTS = {
        :pattern => DEFAULT_PATTERN,
        :signal => (windows? ? "TERM,KILL" : "TERM,INT,KILL"),
        :wait => 2,
        :notify => true,
        :quiet => false,
        :verbose => false,
        :name => Pathname.getwd.basename.to_s.capitalize,
        :ignore => [],
        :dir => DEFAULT_DIRS,
        :force_polling => false,
    }

    def self.parse args = ARGV

      default_options = DEFAULTS.dup
      options = {
          ignore: []
      }

      opts = OptionParser.new("", 24, '  ') do |opts|
        opts.banner = "Usage: rerun [options] [--] cmd"

        opts.separator ""
        opts.separator "Launches an app, and restarts it when the filesystem changes."
        opts.separator "See http://github.com/alexch/rerun for more info."
        opts.separator "Version: #{$spec.version}"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-d dir", "--dir dir", "directory to watch, default = \"#{DEFAULT_DIRS}\".  Specify multiple paths with ',' or separate '-d dir' option pairs.") do |dir|
          elements = dir.split(",")
          options[:dir] = (options[:dir] || []) + elements
        end

        # todo: rename to "--watch"
        opts.on("-p pattern", "--pattern pattern", "file glob to watch, default = \"#{DEFAULTS[:pattern]}\"") do |pattern|
          options[:pattern] = pattern
        end

        opts.on("-i pattern", "--ignore pattern", "file glob to ignore (can be set many times). To ignore a directory, you must append '/*' e.g. --ignore 'coverage/*'") do |pattern|
          options[:ignore] += [pattern]
        end

        opts.on("-s signal", "--signal signal", "terminate process using this signal. To try several signals in series, use a comma-delimited list. Default: \"#{DEFAULTS[:signal]}\"") do |signal|
          options[:signal] = signal
        end

        opts.on("-w sec", "--wait sec", "after asking the process to terminate, wait this long (in seconds) before either aborting, or trying the next signal in series. Default: #{DEFAULTS[:wait]} sec")

        opts.on("-r", "--restart", "expect process to restart itself, so just send a signal and continue watching. Uses the HUP signal unless overridden using --signal") do |signal|
          options[:restart] = true
          default_options[:signal] = "HUP"
        end

        opts.on("-x", "--exit", "expect the program to exit. With this option, rerun checks the return value; without it, rerun checks that the process is running.") do |dir|
          options[:exit] = true
        end

        opts.on("-c", "--clear", "clear screen before each run") do
          options[:clear] = true
        end

        opts.on("-b", "--background", "disable on-the-fly commands, allowing the process to be backgrounded") do
          options[:background] = true
        end

        opts.on("-n name", "--name name", "name of app used in logs and notifications, default = \"#{DEFAULTS[:name]}\"") do |name|
          options[:name] = name
        end

        opts.on("--force-polling", "use polling instead of a native filesystem scan (useful for Vagrant)") do
          options[:force_polling] = true
        end

        opts.on("--no-growl", "don't use growl [OBSOLETE]") do
          options[:growl] = false
          $stderr.puts "--no-growl is obsolete; use --no-notify instead"
          return
        end

        opts.on("--[no-]notify [notifier]", "send messages through a desktop notification application. Supports growl (requires growlnotify), osx (requires terminal-notifier gem), and notify-send on GNU/Linux (notify-send must be installed)") do |notifier|
          notifier = true if notifier.nil?
          options[:notify] = notifier
        end

        opts.on("-q", "--quiet", "don't output any logs") do
          options[:quiet] = true
        end

        opts.on("--verbose", "log extra stuff like PIDs (unless you also specified `--quiet`") do
          options[:verbose] = true
        end

        opts.on_tail("-h", "--help", "--usage", "show this message") do
          puts opts
          return
        end

        opts.on_tail("--version", "show version") do
          puts $spec.version
          return
        end

        opts.on_tail ""
        opts.on_tail "On top of --pattern and --ignore, we ignore any changes to files and dirs starting with a dot."

      end

      if args.empty?
        puts opts
        nil
      else
        opts.parse! args
        default_options[:cmd] = args.join(" ")

        options = default_options.merge(options)

        options
      end
    end

  end
end
