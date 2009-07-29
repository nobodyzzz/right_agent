require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'common', 'agent_identity'))

# Common options parser
module RightScale
  module CommonParser

    # Parse common options between rad and rnac
    def parse_common(opts, options)

      opts.on("--test") do 
        options[:user] = 'nanite'
        options[:pass] = 'testing'
        options[:vhost] = '/nanite'
        options[:host] = 'localhost'
        options[:test] = true
      end

      opts.on("-i", "--identity ID") do |id|
        options[:base_id] = id
      end

      opts.on("-t", "--token TOKEN") do |t|
        options[:token] = t
      end

      opts.on("-r", "--prefix PREFIX") do |p|
        options[:prefix] = p
      end

      opts.on("-u", "--user USER") do |user|
        options[:user] = user
      end

      opts.on("-p", "--pass PASSWORD") do |pass|
        options[:pass] = pass
      end

      opts.on("-v", "--vhost VHOST") do |vhost|
        options[:vhost] = vhost
      end

      opts.on("-P", "--port PORT") do |port|
        options[:port] = port
      end

      opts.on("-h", "--host HOST") do |host|
        options[:host] = host
      end

      opts.on_tail("--help") do
        RDoc::usage_from_file(__FILE__)
        exit
      end

      opts.on_tail("--version") do
        puts version
        exit
      end
    end

    # Generate agent or mapper identity from options
    # Build identity from base_id, token, prefix and agent name
    #
    # === Parameters
    # options<Hash>:: Hash containting identity components
    #
    # === Return
    # options<Hash>::
    def resolve_identity(options)
      if options[:base_id]
        base_id = options[:base_id].to_i
        if base_id.abs.to_s != options[:base_id]
          puts "** Identity needs to be a positive integer"
          exit(1)
        end
        name = options[:agent] || 'mapper'
        options[:identity] = AgentIdentity.new(options[:prefix] || 'rs', name, base_id, options[:token]).to_s
      end
    end

  end
end