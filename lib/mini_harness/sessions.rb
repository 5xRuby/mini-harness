# frozen_string_literal: true

module MiniHarness
  # :sessions — in-memory conversation store. Each session keeps its history and
  # a list of sinks (live subscribers, e.g. websocket connections); #say appends
  # and fans out synchronously.
  # ponytail: in-memory only; swap the internals for persistence when needed.
  class Sessions < Cordis::Service
    provide :sessions

    Session = Struct.new(:id, :history, :sinks)

    def init
      @store = {}
      puts '[sessions] ready'
      -> { @store.clear }
    end

    def open(id = nil)
      id ||= SecureRandom.hex(4)
      @store[id] ||= Session.new(id, [], [])
    end

    def close(id) = @store.delete(id)

    def say(session, role, text)
      entry = { role: role, text: text }
      session.history << entry
      session.sinks.each do |sink|
        sink.call(entry)
      rescue StandardError
        nil # a sink whose connection died mid-broadcast never blocks the rest
      end
      entry
    end

    def subscribe(session, &sink)
      session.sinks << sink
      -> { session.sinks.delete(sink) }
    end
  end
end
