# frozen_string_literal: true

module MiniHarness
  # :llm — thin wrapper over ruby_llm. The config stores a credential *reference*
  # (env var name), never the key itself, mirroring the original harness's
  # credential-ref convention. HTTP runs through async-http-faraday so requests
  # cooperate with the shared reactor instead of blocking it.
  class Llm < Cordis::Service
    provide :llm

    DEFAULTS = { provider: :deepseek, model: 'deepseek-chat', api_key_env: 'DEEPSEEK_API_KEY' }.freeze

    def init
      @opts = DEFAULTS.merge(config || {})
      key = ENV.fetch(@opts[:api_key_env])
      RubyLLM.configure do |c|
        c.public_send("#{@opts[:provider]}_api_key=", key)
        c.faraday_adapter = :async_http
      end
      puts "[llm] #{@opts[:provider]}/#{@opts[:model]} ready"
      -> { puts '[llm] gone' }
    end

    # history: [{role: 'user'|'agent', text: String}, ...], last entry is the
    # pending user message. Streams deltas to the block, returns the full reply.
    def ask(history, &on_delta)
      chat = RubyLLM.chat(model: @opts[:model], provider: @opts[:provider], assume_model_exists: true)
      history[0...-1].each do |entry|
        chat.add_message(role: entry[:role] == 'agent' ? :assistant : :user, content: entry[:text])
      end
      response = chat.ask(history.last[:text]) do |chunk|
        on_delta&.call(chunk.content) if chunk.content && !chunk.content.empty?
      end
      response.content
    end
  end
end
