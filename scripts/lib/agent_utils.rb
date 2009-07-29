# Helper methods used by scripts
# require and include the RightScale::Utils module
module RightScale
  module Utils

    # Path to RightLink root directory
    def root_path
      RightLinkConfig[:right_link_path]
    end

    # Path to directory containing generated agent configuration files
    def gen_dir
      File.join(root_path, 'generated')
    end
    
    # Path to given agent generated directory
    def gen_agent_dir(agent)
      File.join(gen_dir, agent)
    end

    # Path to actors source files
    def actors_dir
      File.join(root_path, 'actors', 'lib')
    end

    # Path to agents configuration files
    def agents_dir
      File.join(root_path, 'agents')
    end
    
    # Path to given agent directory
    def agent_dir(agent)
      File.join(agents_dir, agent)
    end

    # Path to cert folder
    def certs_dir
      File.expand_path(File.join(root_path, '..', 'certs'))
    end
    
    # Path to scripts folder
    def scripts_dir
      File.join(root_path, 'scripts')
    end

    # Produces a hash with keys as symbols from given hash
    def symbolize(h)
      sym = {}
      h.each do |key, val|
        nk = key.respond_to?(:intern) ? key.intern : key
        sym[nk] = val
      end
      sym
    end

  end
end