# frozen_string_literal: true

require 'async'
require 'async/http/endpoint'
require 'async/websocket/adapters/rack'
require 'async/websocket/client'
require 'falcon'
require 'sinatra/base'
require 'cordis'
require 'securerandom'
require 'cgi/escape'
require 'ruby_llm'
require 'async/http/faraday' # registers the :async_http Faraday adapter

require_relative 'mini_harness/web_server'
require_relative 'mini_harness/sessions'
require_relative 'mini_harness/gateway'
require_relative 'mini_harness/chat_ui'
require_relative 'mini_harness/echo_agent'
require_relative 'mini_harness/llm'
require_relative 'mini_harness/llm_agent'

module MiniHarness
  # Assemble the plugin tree on ctx. Returns the fibers in load-dependency
  # order — await them in order to know the tree has settled. The last one is
  # the agent (the piece you'd hot-swap while the server keeps running).
  def self.plug(ctx, url: 'http://localhost:9292', agent: nil)
    fibers = [
      ctx.plugin(WebServer, { url: url }),
      ctx.plugin(Sessions),
      ctx.plugin(Gateway),
      ctx.plugin(ChatUI)
    ]
    # LLM_PROVIDER / LLM_MODEL / LLM_API_KEY_ENV override the DeepSeek defaults
    llm_config = { provider: ENV['LLM_PROVIDER']&.to_sym, model: ENV.fetch('LLM_MODEL', nil),
                   api_key_env: ENV.fetch('LLM_API_KEY_ENV', nil) }.compact
    key_env = llm_config[:api_key_env] || Llm::DEFAULTS[:api_key_env]
    if agent.nil? && ENV[key_env]
      fibers << ctx.plugin(Llm, llm_config)
      fibers << ctx.plugin(LlmAgent)
    else
      fibers << ctx.plugin(agent || EchoAgent)
    end
    fibers
  end
end
