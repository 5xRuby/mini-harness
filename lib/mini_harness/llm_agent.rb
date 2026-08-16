# frozen_string_literal: true

module MiniHarness
  # llm-agent — the real agent: replies to session messages via the :llm
  # service, streaming deltas into the session as they arrive. Same shape as
  # EchoAgent, so the two hot-swap freely.
  LlmAgent = {
    name: 'llm-agent',
    inject: %i[sessions llm],
    apply: lambda do |c, _config|
      c.on('session/message') do |session, _payload|
        streamer = c.sessions.stream(session, 'agent')
        begin
          c.llm.ask(session.history) { |delta| streamer.push(delta) }
          streamer.finish
        rescue StandardError => e
          c.sessions.say(session, 'agent', "[llm error] #{e.message}")
        end
      end
      puts '[agent] llm agent listening'
      -> { puts '[agent] llm agent gone' }
    end
  }.freeze
end
