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
      broadcast(session, entry) # a dead sink never blocks the rest
      entry
    end

    # Incremental variant of #say for streaming agents: push fans out
    # {role:, id:, delta:} per chunk; finish appends the accumulated text to
    # history and fans out the final {role:, id:, text:} marker.
    def stream(session, role)
      Streamer.new(self, session, role)
    end

    Streamer = Struct.new(:sessions, :session, :role, :id, :buffer) do
      def initialize(sessions, session, role)
        super(sessions, session, role, SecureRandom.hex(4), +'')
      end

      def push(delta)
        buffer << delta
        sessions.broadcast(session, { role: role, id: id, delta: delta })
      end

      def finish
        entry = { role: role, id: id, text: buffer }
        session.history << entry
        sessions.broadcast(session, entry)
        entry
      end
    end

    def broadcast(session, payload)
      session.sinks.each do |sink|
        sink.call(payload)
      rescue StandardError
        nil
      end
    end

    def subscribe(session, &sink)
      session.sinks << sink
      -> { session.sinks.delete(sink) }
    end
  end
end
