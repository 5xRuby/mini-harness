# frozen_string_literal: true

module MiniHarness
  # gateway — the websocket edge. GET /ws upgrades the connection; each inbound
  # JSON message {"text": ...} is appended to the session and re-emitted as the
  # 'session/message' event for whatever agent plugin is currently loaded.
  # Disposing the gateway removes the route and closes live connections.
  Gateway = {
    name: 'gateway',
    inject: %i[web sessions],
    apply: lambda do |c, _config|
      connections = []
      # registered first => disposed last (after the route is gone, so no new
      # connections can sneak in while we're closing the old ones)
      c.effect('gateway connections') do
        lambda do
          connections.dup.each do |connection|
            connection.close
          rescue StandardError
            nil
          end
        end
      end

      c.web.route(c, 'GET', '/ws') do |request|
        Async::WebSocket::Adapters::Rack.open(request.env) do |connection|
          connections << connection
          session = c.sessions.open
          unsubscribe = c.sessions.subscribe(session) do |entry|
            connection.write(Protocol::WebSocket::TextMessage.generate(entry))
            connection.flush
          end
          begin
            while (message = connection.read)
              payload = message.parse # JSON with symbolized keys
              c.sessions.say(session, 'user', payload[:text].to_s)
              c.emit('session/message', session, payload)
            end
          rescue Protocol::WebSocket::ClosedError, IOError, Errno::ECONNRESET
            nil # client hangup, or our own close during shutdown — both normal
          end
        ensure
          unsubscribe&.call
          c.sessions.close(session.id) if session
          connections.delete(connection)
        end
      end
      puts '[gateway] ws://.../ws ready'
    end
  }.freeze
end
