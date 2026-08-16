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
  fibers = MiniHarness.plug(ctx, url: URL, agent: MiniHarness::EchoAgent)
  agent = fibers.last
  # awaiting in dependency order: by the time a provider is active, its
  # dependents' load transitions are already scheduled
  fibers.each(&:await)

  expect(chat('hello'), { role: 'agent', text: 'echo: hello' }, 'echo agent replies')

  # chat UI: page load, then uplink form POST + downlink turbo-stream websocket
  internet = Async::HTTP::Internet.new
  page = internet.get("#{URL}/", &:read)
  expect(page.include?('turbo-stream-source'), true, 'chat page serves turbo-stream-source')
  sid = page[/name="session" value="(\h+)"/, 1]
  frames = []
  Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{URL}/stream?session=#{sid}")) do |connection|
    internet.post("#{URL}/messages",
                  [['content-type', 'application/x-www-form-urlencoded']],
                  "session=#{sid}&text=hi-ui", &:read)
    2.times { frames << connection.read.to_str }
  end
  expect(frames.join.scan('<turbo-stream ').size, 2, 'stream delivers two turbo-stream fragments')
  expect(frames.join.include?('echo: hi-ui'), true, 'agent reply arrives as turbo-stream')

  # hot-swap the agent while the gateway keeps serving
  agent.dispose
  shout = ctx.plugin({ name: 'shout-agent', inject: [:sessions], apply: lambda { |c, _config|
    c.on('session/message') { |session, payload| c.sessions.say(session, 'agent', payload[:text].upcase) }
  } })
  shout.await
  expect(chat('hello'), { role: 'agent', text: 'HELLO' }, 'hot-swapped agent replies')

  # streaming agent: deltas render incrementally, the final marker adds nothing
  shout.dispose
  stream_agent = ctx.plugin({ name: 'stream-agent', inject: [:sessions], apply: lambda { |c, _config|
    c.on('session/message') do |session, _payload|
      streamer = c.sessions.stream(session, 'agent')
      streamer.push('Hel')
      streamer.push('lo')
      streamer.finish
    end
  } })
  stream_agent.await
  page = internet.get("#{URL}/", &:read)
  sid = page[/name="session" value="(\h+)"/, 1]
  frames = []
  Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{URL}/stream?session=#{sid}")) do |connection|
    internet.post("#{URL}/messages",
                  [['content-type', 'application/x-www-form-urlencoded']],
                  "session=#{sid}&text=stream-me", &:read)
    3.times { frames << connection.read.to_str }
  end
  expect(frames.join.scan('<turbo-stream ').size, 4, 'streamed reply renders container + two deltas')
  expect(frames.join.include?('Hel') && frames.join.include?('lo'), true, 'delta text arrives incrementally')

  status = internet.get("#{URL}/nope", &:status)
  expect(status, 404, 'unregistered route 404s')
  internet.close

  ctx.fiber.dispose
  expect(ctx.registry.size, 0, 'tree unwound')
end

puts 'smoke ok'
