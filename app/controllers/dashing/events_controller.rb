module Dashing
  class EventsController < ApplicationController
    include ActionController::Live

    def index
      response.headers['Content-Type']      = 'text/event-stream'
      response.headers['X-Accel-Buffering'] = 'no'      
      conn_uuid = params["conn_uuid"]  
      repo_name = params["repo_name"]
      conn_value = {filter: {}, conn_uuid: conn_uuid, repo_name: repo_name, unicast: false}      
      $redis.set("conn_#{conn_uuid}", conn_value.to_json)
      @redis = Dashing.redis
      redis_namespace_to_sub = conn_uuid ? "#{Dashing.config.redis_namespace}.#{conn_uuid}" : "#{Dashing.config.redis_namespace}.*"      
      @redis.subscribe(redis_namespace_to_sub) do |on|
        on.message do |event, data|
          response.stream.write("data: #{data}\n\n")
        end
      end
    rescue IOError
      logger.info "[Dashing][#{Time.now.utc.to_s}] Stream closed"
    ensure      
      $redis.del("conn_#{conn_uuid}")
      @redis.quit
      response.stream.close
    end

  end
end

# Maintain conn_uuid in redis, since each worker will get it's own copy of connection_uuid from configuration