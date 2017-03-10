module MCollective
  class Application
    class Choria < Application
      description "Choria Orchestrator"

      exclude_argument_sections "common", "filter", "rpc"

      option :show_config,
             :arguments => ["--show_config", "--show-config"],
             :description => "Shows the active configuration",
             :type => :boolean

      def post_option_parser(configuration)
        configuration[:agent] = ARGV.shift if ARGV.length >= 1
        configuration[:action] = ARGV.shift if ARGV.length >= 1
      end

      # Validates the configuration
      #
      # @return [void]
      def validate_configuration(configuration)
        Util.loadclass("MCollective::Util::Choria")

        unless configuration[:show_config] || choria.has_client_public_cert?
          abort("A certificate is needed from the Puppet CA for `%s`, please use the `mco request_cert` command" % choria.certname)
        end
      end

      def run
        self.class.usage overview_text

        super
      end

      def main
        if configuration[:show_config]
          show_config
          exit
        end

        puts application_parse_options(true)
      rescue Util::Choria::UserError
        STDERR.puts("Encountered a critical error: %s" % Util.colorize(:red, $!.to_s))

      rescue Util::Choria::Abort
        exit(1)
      end

      def agent_ddls
        @__ddls ||= MCollective::PluginManager.find(:agent, "ddl").map do |agent|
          begin
            MCollective::DDL.new(agent)
          rescue
          end
        end.compact
      end

      def agent_ddl(agent_name)
        agent_ddls.find {|agent| agent.meta[:name] == agent_name}
      end

      def agent_names
        agent_ddls.map {|agent| agent[:name]}
      end

      def overview_text
        out = StringIO.new

        out.puts "mco choria [options] <agent> <action> [agent options] [request options]"
        out.puts
        out.puts "Available Agents:"
        out.puts

        longest = agent_ddls.map{|a| a.meta[:name].size}.max

        if agent_ddls.size > 0
          agent_ddls.each do |agent|
            out.puts "  %-#{longest}s       %s" % [agent.meta[:name], agent.meta[:description]]
          end

          out.puts
          out.puts "See choria <agent> --help for details about the agent"
        else
          out.puts "   No agent DDL files found"
        end

        out.string
      end

      def show_config # rubocop:disable Metrics/MethodLength
        disconnect

        puts "Active Choria configuration:"
        puts
        puts "The active configuration used in Choria comes from using Puppet AIO defaults, querying SRV"
        puts "records and reading configuration files.  The below information shows the completely resolved"
        puts "configuration that will be used when running MCollective commands"
        puts
        puts "MCollective selated:"
        puts
        puts " MCollective Version: %s" % MCollective::VERSION
        puts "  Client Config File: %s" % Util.config_file_for_user
        puts "  Active Config File: %s" % Config.instance.configfile
        puts "   Plugin Config Dir: %s" % File.join(Config.instance.configdir, "plugin.d")
        puts "   Using SRV Records: %s" % choria.should_use_srv?
        puts "          SRV Domain: %s" % choria.srv_domain

        middleware_servers = choria.middleware_servers("puppet", 42222).map {|s, p| "%s:%s" % [s, p]}.join(", ")

        puts "  Middleware Servers: %s" % middleware_servers
        puts

        puppet_server = "%s:%s" % [choria.puppet_server[:target], choria.puppet_server[:port]]
        puppetca_server = "%s:%s" % [choria.puppetca_server[:target], choria.puppetca_server[:port]]
        puppetdb_server = "%s:%s" % [choria.puppetca_server[:target], choria.puppetca_server[:port]]

        puts "Puppet related:"
        puts
        puts "       Puppet Server: %s" % puppet_server
        puts "     PuppetCA Server: %s" % puppetca_server
        puts "     PuppetDB Server: %s" % puppetdb_server
        puts "      Facter Command: %s" % choria.facter_cmd
        puts "       Facter Domain: %s" % choria.facter_domain
        puts

        puts "SSL setup:"
        puts

        valid_ssl = choria.check_ssl_setup(false) rescue false

        if valid_ssl
          puts "     Valid SSL Setup: %s" % [Util.colorize(:green, "yes")]
        else
          puts "     Valid SSL Setup: %s run 'mco choria request_cert'" % [Util.colorize(:red, "no")]
        end

        puts "            Certname: %s" % choria.certname
        puts "       SSL Directory: %s (%s)" % [choria.ssl_dir, File.exist?(choria.ssl_dir) ? Util.colorize(:green, "found") : Util.colorize(:red, "absent")]
        puts "  Client Public Cert: %s (%s)" % [choria.client_public_cert, choria.has_client_public_cert? ? Util.colorize(:green, "found") : Util.colorize(:red, "absent")]
        puts "  Client Private Key: %s (%s)" % [choria.client_private_key, choria.has_client_private_key? ? Util.colorize(:green, "found") : Util.colorize(:red, "absent")]
        puts "             CA Path: %s (%s)" % [choria.ca_path, choria.has_ca? ? Util.colorize(:green, "found") : Util.colorize(:red, "absent")]
        puts "            CSR Path: %s (%s)" % [choria.csr_path, choria.has_csr? ? Util.colorize(:green, "found") : Util.colorize(:red, "absent")]
        puts

        puts "Active Choria configuration settings as found in configuration files:"
        puts

        choria_settings = Config.instance.pluginconf.select {|k, _| k.start_with?("choria")}
        padding = choria_settings.empty? ? 2 : choria_settings.keys.map(&:length).max + 2

        if choria_settings.empty?
          puts "  No custom Choria settings found in your configuration files"
        else
          choria_settings.each do |k, v|
            puts "%#{padding}s: %s" % [k, v]
          end
        end

        puts
      end

      # Creates and cache a Choria helper class
      #
      # @return [Util::Choria]
      def choria
        @_choria ||= Util::Choria.new(configuration[:environment], configuration[:instance], false)
      end
    end
  end
end
