# mini-harness

[English](README.md) | 中文

一個仿 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 形狀的迷你 agent harness，用來實戰 [cordis](https://rubygems.org/gems/cordis) gem：整個 app 就是一棵 cordis plugin tree，跑在單一 async reactor 上（Falcon + Sinatra + async-websocket）。

## 結構

| Plugin | 形狀 | 提供 |
|---|---|---|
| `WebServer` | `Cordis::Service` | `:web` — 內嵌 Falcon + Sinatra；route 註冊是掛在呼叫者 fiber 上的 revertible effect，plugin 卸載時 route 自動消失 |
| `Sessions` | `Cordis::Service` | `:sessions` — in-memory 對話 store + 即時 fan-out，並提供 agent 逐段回覆用的 streaming API |
| `Llm` | `Cordis::Service` | `:llm` — 薄薄包住 [ruby_llm](https://rubyllm.com)；HTTP 走 async-http-faraday，與 reactor 協作不阻塞 |
| `Gateway` | function plugin | `GET /ws` websocket 端點；收到的訊息轉成 `session/message` 事件 |
| `ChatUI` | function plugin | 瀏覽器前端（Hotwire Turbo）：上行 form POST `/messages`，下行唯讀 websocket `/stream` 推 turbo-stream 片段 |
| `LlmAgent` / `EchoAgent` | function plugin | 監聽 `session/message` 回覆 — 可在伺服器不停機下熱換 |

## 執行

```
bundle install
bundle exec ruby boot.rb        # Ctrl-C 整棵樹 LIFO 收乾淨
open http://localhost:9292      # 瀏覽器聊天
websocat ws://localhost:9292/ws # 或走原生 websocket：{"text":"hello"}
```

## 啟用真的 LLM agent

未設定時掛的是佔位 `EchoAgent`。設好 DeepSeek API key 後改掛 `Llm` + `LlmAgent`，回覆會逐 chunk 串流到瀏覽器：

```
export DEEPSEEK_API_KEY=sk-...
bundle exec ruby boot.rb
```

要換 provider/model，組樹時傳 config 即可——ruby_llm 支援的 provider 都能用：

```ruby
ctx.plugin(MiniHarness::Llm, { provider: :openai, model: 'gpt-4o', api_key_env: 'OPENAI_API_KEY' })
ctx.plugin(MiniHarness::LlmAgent)
```

config 只存環境變數的「名字」，key 本身在載入時才從環境讀取。

## 自我檢查

啟動 → HTTP/WS 對話 → 熱換 agent → streaming 驗證 → 收樹：

```
bundle exec ruby smoke.rb
```
