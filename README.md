# mini-harness

English | [中文](README.zh.md)

A miniature agent harness shaped after [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness), built as a proving ground for the [cordis](https://rubygems.org/gems/cordis) gem: the whole app is one cordis plugin tree running on a single async reactor (Falcon + Sinatra + async-websocket).

## Structure

| Plugin | Shape | Provides |
|---|---|---|
| `WebServer` | `Cordis::Service` | `:web` — embedded Falcon + Sinatra; route registration is a revertible effect on the caller's fiber, so routes vanish when their plugin is disposed |
| `Sessions` | `Cordis::Service` | `:sessions` — in-memory conversation store with live fan-out, plus a streaming API for incremental agent replies |
| `Llm` | `Cordis::Service` | `:llm` — thin wrapper over [ruby_llm](https://rubyllm.com); HTTP via async-http-faraday so calls cooperate with the reactor |
| `Gateway` | function plugin | `GET /ws` websocket endpoint; inbound messages become `session/message` events |
| `ChatUI` | function plugin | Browser frontend (Hotwire Turbo): uplink form POST `/messages`, read-only downlink websocket `/stream` pushing turbo-stream fragments |
| `LlmAgent` / `EchoAgent` | function plugin | Listens for `session/message` and replies — hot-swappable while the server keeps serving |

## Run

```
bundle install
bundle exec ruby boot.rb        # Ctrl-C unwinds the whole tree LIFO
open http://localhost:9292      # chat in the browser
websocat ws://localhost:9292/ws # or over raw websocket: {"text":"hello"}
```

## Enabling the real LLM agent

Without configuration the tree mounts the placeholder `EchoAgent`. Set a DeepSeek API key and the tree mounts `Llm` + `LlmAgent` instead, streaming replies chunk by chunk into the browser:

```
export DEEPSEEK_API_KEY=sk-...
bundle exec ruby boot.rb
```

To use another provider/model, pass config when assembling the tree — any provider ruby_llm supports works:

```ruby
ctx.plugin(MiniHarness::Llm, { provider: :openai, model: 'gpt-4o', api_key_env: 'OPENAI_API_KEY' })
ctx.plugin(MiniHarness::LlmAgent)
```

Only the env var *name* lives in config; the key itself is read from the environment at load time.

## Self-check

Boots the tree, talks to it over HTTP and websocket, hot-swaps the agent, exercises streaming, then unwinds:

```
bundle exec ruby smoke.rb
```
