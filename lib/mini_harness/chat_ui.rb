# frozen_string_literal: true

module MiniHarness
  # chat-ui — browser frontend as a hot-swappable plugin. Mirrors the original
  # harness's split-direction transport: uplink is a Turbo-intercepted form
  # POST /messages, downlink is a read-only websocket GET /stream that pushes
  # <turbo-stream> fragments (applied to the DOM by Turbo's built-in
  # <turbo-stream-source> element). Turbo itself loads from CDN via a native
  # browser importmap — no asset pipeline.
  ChatUI = {
    name: 'chat-ui',
    inject: %i[web sessions],
    apply: lambda do |c, _config|
      render = lambda do |entry|
        <<~HTML
          <turbo-stream action="append" target="messages"><template>
            <div class="msg #{entry[:role]}"><span class="role">#{entry[:role]}</span>#{CGI.escapeHTML(entry[:text].to_s)}</div>
          </template></turbo-stream>
        HTML
      end

      connections = []
      # registered first => disposed last (route gone before we close streams)
      c.effect('chat-ui connections') do
        lambda do
          connections.dup.each do |connection|
            connection.close
          rescue StandardError
            nil
          end
        end
      end

      c.web.route(c, 'GET', '/') do |request|
        session = c.sessions.open
        stream_url = "ws://#{request.host_with_port}/stream?session=#{session.id}"
        body = <<~HTML
          <!doctype html>
          <html><head>
          <title>mini-harness</title>
          <meta charset="utf-8">
          <script type="importmap">{"imports":{"@hotwired/turbo":"https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/+esm"}}</script>
          <script type="module">
            import "@hotwired/turbo";
            addEventListener("turbo:submit-end", e => e.target.reset());
            new MutationObserver(() => scrollTo(0, document.body.scrollHeight))
              .observe(document.getElementById("messages") ?? document.body, { childList: true, subtree: true });
          </script>
          <style>
            body { font: 15px/1.5 system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; }
            .msg { margin: .4rem 0; padding: .4rem .7rem; border-radius: .5rem; background: #f0f0f0; }
            .msg.agent { background: #e3efff; }
            .role { font-weight: 600; margin-right: .5rem; color: #666; }
            form { display: flex; gap: .5rem; margin-top: 1rem; }
            input[type=text] { flex: 1; padding: .4rem .6rem; }
          </style>
          </head><body>
          <h1>mini-harness</h1>
          <turbo-stream-source src="#{stream_url}"></turbo-stream-source>
          <div id="messages"></div>
          <form method="post" action="/messages">
            <input type="hidden" name="session" value="#{session.id}">
            <input type="text" name="text" autofocus autocomplete="off">
            <button>send</button>
          </form>
          </body></html>
        HTML
        [200, { 'content-type' => 'text/html' }, [body]]
      end

      c.web.route(c, 'POST', '/messages') do |request|
        session = c.sessions.open(request.params['session'])
        text = request.params['text'].to_s.strip
        unless text.empty?
          c.sessions.say(session, 'user', text)
          c.emit('session/message', session, { text: text })
        end
        [200, { 'content-type' => 'text/vnd.turbo-stream.html' }, ['']]
      end

      c.web.route(c, 'GET', '/stream') do |request|
        session = c.sessions.open(request.params['session'])
        Async::WebSocket::Adapters::Rack.open(request.env) do |connection|
          connections << connection
          unsubscribe = c.sessions.subscribe(session) do |entry|
            connection.write(Protocol::WebSocket::TextMessage.new(render.call(entry)))
            connection.flush
          end
          # read-only downlink: the client never sends; read just blocks until close
          while connection.read; end
        ensure
          unsubscribe&.call
          connections.delete(connection)
        end
      end

      puts '[chat-ui] http://.../ ready'
    end
  }.freeze
end
