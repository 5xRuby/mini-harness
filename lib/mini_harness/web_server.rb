# frozen_string_literal: true

module MiniHarness
  # :web — embedded Falcon serving a Sinatra app whose routes live in a dynamic
  # table. Plugins register routes through #route as revertible effects on their
  # own fiber: dispose the plugin and its routes vanish, no server restart.
  class WebServer < Cordis::Service
    provide :web

    def init
      routes = (@routes = {}) # ["GET", "/path"] => handler(Sinatra request) -> body or rack triple
      app = Sinatra.new do
        set :environment, :production
        set :logging, false

        %i[get post put delete].each do |verb|
          send(verb, '/*') do
            handler = routes[[request.request_method, request.path_info]]
            halt 404, "no route: #{request.request_method} #{request.path_info}\n" unless handler
            result = handler.call(request)
            result.is_a?(Array) ? halt(*result) : result
          end
        end
      end

      endpoint = Async::HTTP::Endpoint.parse(config&.fetch(:url) || 'http://localhost:9292')
      server = Falcon::Server.new(Falcon::Server.rack_middleware(app, cache: false), endpoint)
      task = server.run
      puts "[web] listening on #{endpoint.url}"
      lambda {
        task.stop
        puts '[web] stopped'
      }
    end

    # No traceable proxies in cordis-rb: callers pass their ctx so the route
    # effect lands on *their* fiber and is reverted on their disposal.
    def route(caller_ctx, verb, path, &handler)
      key = [verb.to_s.upcase, path]
      routes = @routes
      caller_ctx.effect("route #{key.join(' ')}") do
        raise ArgumentError, "route already registered: #{key.join(' ')}" if routes.key?(key)

        routes[key] = handler
        -> { routes.delete(key) }
      end
    end
  end
end
