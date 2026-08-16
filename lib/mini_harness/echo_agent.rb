# frozen_string_literal: true

module MiniHarness
  # echo-agent — placeholder for the real (LLM) agent: listens for session
  # messages and replies. Hot-swappable: dispose it and load another agent
  # while the gateway keeps serving.
  EchoAgent = {
    name: 'echo-agent',
    inject: [:sessions],
    apply: lambda do |c, _config|
      c.on('session/message') do |session, payload|
        c.sessions.say(session, 'agent', "echo: #{payload[:text]}")
      end
      puts '[agent] echo agent listening'
      -> { puts '[agent] echo agent gone' }
    end
  }.freeze
end
