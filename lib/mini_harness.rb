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
    if agent.nil? && ENV['DEEPSEEK_API_KEY']
      fibers << ctx.plugin(Llm)
      fibers << ctx.plugin(LlmAgent)
    else
      fibers << ctx.plugin(agent || EchoAgent)
    end
    fibers
  end
end
