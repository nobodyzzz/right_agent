# Copyright (c) 2009 RightScale, Inc, All Rights Reserved Worldwide.

module RightScale
  
  # Agent identity management
  class AgentIdentity
    if (ENV['RAILS_ENV'] == nil) || (ENV['RAILS_ENV'] == 'production')
      SEPARATOR_EPOCH = Time.at(1256702400) #Tue Oct 27 21:00:00 -0700 2009
    else
      SEPARATOR_EPOCH = Time.at(1256606908) #Mon Oct 26 18:28:25 -0700 2009
    end

    # Separator used to differentiate between identity components when serialized
    ID_SEPARATOR = '-'

    # Separator used to differentiate between identity components prior to release 3.4
    ID_SEPARATOR_OLD = '*'

    # Identity components
    attr_reader :prefix, :agent_name, :token, :base_id

    # Generate new id
    #
    # === Parameters
    # prefix<String>:: Prefix used to scope identity
    # agent_name<String>:: Name of agent (e.g. 'core', 'instance')
    # base_id<Integer>:: Unique integer value
    # token<String>:: Anonymizing token - Optional, will be generated randomly if not provided
    #
    # === Raise
    # RightScale::Exceptions::Argument:: Invalid argument
    def initialize(prefix, agent_name, base_id, token=nil, delimeter=nil)
      err = "Prefix cannot contain '#{ID_SEPARATOR}'" if prefix && prefix.include?(ID_SEPARATOR)
      err = "Prefix cannot contain '#{ID_SEPARATOR_OLD}'" if prefix && prefix.include?(ID_SEPARATOR_OLD)
      err = "Agent name cannot contain '#{ID_SEPARATOR}'" if agent_name.include?(ID_SEPARATOR)
      err = "Agent name cannot contain '#{ID_SEPARATOR_OLD}'" if agent_name.include?(ID_SEPARATOR_OLD)
      err = "Agent name cannot be nil" if agent_name.nil?
      err = "Agent name cannot be empty" if agent_name.size == 0
      err = "Base ID must be a positive integer" unless base_id.kind_of?(Integer) && base_id >= 0
      err = "Token cannot contain '#{ID_SEPARATOR}'" if token && token.include?(ID_SEPARATOR)
      err = "Token cannot contain '#{ID_SEPARATOR_OLD}'" if token && token.include?(ID_SEPARATOR_OLD)
      raise RightScale::Exceptions::Argument, err if err

      @delimeter  = delimeter || ID_SEPARATOR
      @prefix     = prefix
      @agent_name = agent_name
      @token      = token || Nanite::Identity.generate
      @base_id    = base_id
    end
    
    # Check validity of given serialized identity
    #
    # === Parameters
    # serialized<String>:: Serialized identity to be tested
    #
    # === Return
    # true:: If serialized identity is a valid identity token
    # false:: Otherwise
    def self.valid?(serialized)
      return false unless serialized && serialized.respond_to?(:split) && serialized.respond_to?(:include?)
      serialized = serialized_from_nanite(serialized) if valid_nanite?(serialized)      
      if serialized.include?(ID_SEPARATOR)
        parts = serialized.split(ID_SEPARATOR)
      elsif serialized.include?(ID_SEPARATOR_OLD)
        parts = serialized.split(ID_SEPARATOR_OLD)
      else
        return false
      end

      res = parts.size == 4   &&
            parts[1].size > 0 &&
            parts[2].size > 0 &&
            parts[3].to_i.to_s == parts[3]
    end
    
    # Instantiate by parsing given token
    #
    # === Parameters
    # serialized_id<String>:: Valid serialized agent identity (use 'valid?' to check first)
    #
    # === Return
    # id<RightScale::AgentIdentity>:: Corresponding agent identity
    #
    # === Raise
    # RightScale::Exceptions::Argument:: Serialized agent identity is incorrect
    def self.parse(serialized_id)
      serialized_id = serialized_from_nanite(serialized_id) if valid_nanite?(serialized_id)
      
      if serialized_id.include?(ID_SEPARATOR)
        prefix, agent_name, token, bid = serialized_id.split(ID_SEPARATOR)
        delimeter = ID_SEPARATOR
      elsif serialized_id.include?(ID_SEPARATOR_OLD)
        prefix, agent_name, token, bid = serialized_id.split(ID_SEPARATOR_OLD)
        delimeter = ID_SEPARATOR_OLD
      end

      raise RightScale::Exceptions::Argument, "Invalid agent identity token" unless prefix && agent_name && token && bid
      base_id = bid.to_i
      raise RightScale::Exceptions::Argument, "Invalid agent identity token (Base ID)" unless base_id.to_s == bid

      id = AgentIdentity.new(prefix, agent_name, base_id, token, delimeter)
    end

    # Check validity of nanite name. Checks whether this is a well-formed nanite name,
    # does NOT check validity of the ID itself.
    #
    # === Parameters
    # name<String>:: string to test for well-formedness
    #
    # === Return
    # true:: If name is a valid Nanite name (begins with "nanite-")
    # false:: Otherwise
    def self.valid_nanite?(name)
      !!(name =~ /^(nanite|mapper)-/)
    end

    # Instantiate by parsing given nanite agent identity
    #
    # === Parameters
    # nanite<String>:: Nanite agent identity
    #
    # === Return
    # serialized<String>:: Serialized agent id from nanite id
    def self.serialized_from_nanite(nanite)
      serialized = nanite[7, nanite.length] # 'nanite-'.length == 7
    end

    # Generate nanite agent identity from serialized representation
    #
    # === Parameters
    # serialized<String>:: Serialized agent identity
    #
    # === Return
    # nanite<String>:: Corresponding nanite id
    def self.nanite_from_serialized(serialized)
      nanite = "nanite-#{serialized}"
    end

    # String representation of identity
    #
    # === Return
    # serialized<String>:: Serialized identity
    def to_s
      serialized = "#{@prefix}#{@delimeter}#{@agent_name}#{@delimeter}#{@token}#{@delimeter}#{@base_id}"
    end

    # Comparison operator
    #
    # === Parameters
    # other<AgentIdentity>:: Other agent identity
    #
    # === Return
    # true:: If other is identical to self
    # false:: Otherwise
    def ==(other)
      other.kind_of?(::RightScale::AgentIdentity) &&
      prefix     == other.prefix     &&
      agent_name == other.agent_name &&
      token      == other.token      &&
      base_id    == other.base_id
    end
  
  end
end
