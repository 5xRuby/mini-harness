#!/usr/bin/env ruby
# frozen_string_literal: true

# Boot the mini-harness: Falcon + Sinatra + websocket gateway + echo agent,
# all as cordis plugins. Ctrl-C unwinds the whole tree in LIFO order.
#
#   bundle exec ruby boot.rb
#   websocat ws://localhost:9292/ws   # then type: {"text":"hello"}
#   curl localhost:9292/status

Warning[:experimental] = false # silence Ruby 4's IO::Buffer notice from async's resolver
$stdout.sync = true # logs flush immediately even when piped

require_relative 'lib/mini_harness'

ctx = Cordis::Context.new

# async's scheduler intercepts Interrupt at the run loop, so a rescue inside
# the Sync block never sees it. Trap SIGINT ourselves and wake the main fiber
# through a self-pipe — the tree then unwinds while the reactor is still alive.
stop_reader, stop_writer = IO.pipe
Signal.trap(:INT) do
  stop_writer.write_nonblock('x')
rescue IO::WaitWritable, IOError
  nil
end

Sync do
  MiniHarness.plug(ctx).each(&:await)

  # a route from a throwaway plugin, to show routes are revertible effects
  ctx.plugin({ name: 'status', inject: [:web], apply: lambda { |c, _config|
    c.web.route(c, 'GET', '/status') { "ok\n" }
  } })

  stop_reader.wait_readable # park until Ctrl-C
  puts "\nshutting down"
  ctx.fiber.dispose
end
