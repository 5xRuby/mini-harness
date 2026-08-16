#!/usr/bin/env ruby
# frozen_string_literal: true

# Self-check: boot the tree, talk to it over HTTP and websocket, hot-swap the
# agent, then unwind. Exits non-zero on any mismatch.
#
#   bundle exec ruby smoke.rb

Warning[:experimental] = false # silence Ruby 4's IO::Buffer notice from async's resolver

require_relative 'lib/mini_harness'
require 'async/http/internet'

URL = 'http://localhost:9293'

def expect(actual, expected, label)
  raise "#{label}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected

  puts "ok: #{label}"
end

def chat(text)
  endpoint = Async::HTTP::Endpoint.parse("#{URL}/ws")
  Async::WebSocket::Client.connect(endpoint) do |connection|
    connection.write(Protocol::WebSocket::TextMessage.generate({ text: text }))
    connection.flush
    connection.read.parse # our own message echoed back to the session first...
    connection.read.parse # ...then the agent's reply
  end
end

ctx = Cordis::Context.new

Sync do
  fibers = MiniHarness.plug(ctx, url: URL)
  agent = fibers.last
  # awaiting in dependency order: by the time a provider is active, its
  # dependents' load transitions are already scheduled
  fibers.each(&:await)

  expect(chat('hello'), { role: 'agent', text: 'echo: hello' }, 'echo agent replies')

  # hot-swap the agent while the gateway keeps serving
  agent.dispose
  shout = ctx.plugin({ name: 'shout-agent', inject: [:sessions], apply: lambda { |c, _config|
    c.on('session/message') { |session, payload| c.sessions.say(session, 'agent', payload[:text].upcase) }
  } })
  shout.await
  expect(chat('hello'), { role: 'agent', text: 'HELLO' }, 'hot-swapped agent replies')

  internet = Async::HTTP::Internet.new
  status = internet.get("#{URL}/nope", &:status)
  expect(status, 404, 'unregistered route 404s')
  internet.close

  ctx.fiber.dispose
  expect(ctx.registry.size, 0, 'tree unwound')
end

puts 'smoke ok'
