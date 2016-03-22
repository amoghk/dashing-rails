module Dashing
  class << self

    delegate :scheduler, :redis, :connection_uuid, to: :config

    attr_accessor :configuration

    def config
      self.configuration ||= Configuration.new
    end

    def configure
      yield config if block_given?
    end

    def first_dashboard
      files = Dir[config.dashboards_views_path.join('*')].collect { |f| File.basename(f, '.*') }
      files.sort.first
    end

    
    def send_event(id, data, unicast_opts = {})
      unicast = unicast_opts[:unicast]
      conn_uuid = unicast_opts[:conn_uuid]
      if unicast        
        redis.publish(redis_namespace(conn_uuid), data.merge(id: id, updatedAt: Time.now.utc.to_i).to_json)
      else
        connection_uuid.each {|conn,state|          
          redis.publish(redis_namespace(conn), data.merge(id: id, updatedAt: Time.now.utc.to_i).to_json)
        }
      end
    end

    def redis_namespace(conn_uuid)
      "#{Dashing.config.redis_namespace}.#{conn_uuid}"
    end

  end
end

begin
  require 'rails'
rescue LoadError
end

$stderr.puts <<-EOC if !defined?(Rails)
warning: no framework detected.

Your Gemfile might not be configured properly.
---- e.g. ----
Rails:
    gem 'dashing-rails'

EOC

require 'dashing/configuration'

if defined? Rails
  require 'dashing/engine'
  require 'dashing/railtie'
end
