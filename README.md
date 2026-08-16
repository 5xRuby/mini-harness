# mini-harness

一個仿 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 形狀的迷你 agent harness,用來實戰 [cordis](https://rubygems.org/gems/cordis) gem:整個 app 就是一棵 cordis plugin tree,跑在單一 async reactor 上(Falcon + Sinatra + async-websocket)。

## 結構

| Plugin | 形狀 | 提供 |
|---|---|---|
| `WebServer` | `Cordis::Service` | `:web` — 內嵌 Falcon + Sinatra;route 註冊是掛在呼叫者 fiber 上的 revertible effect,plugin 卸載時 route 自動消失 |
| `Sessions` | `Cordis::Service` | `:sessions` — in-memory 對話 store + 即時 fan-out |
| `Gateway` | function plugin | `GET /ws` websocket 端點;收到的訊息轉成 `session/message` 事件 |
| `EchoAgent` | function plugin | 監聽 `session/message` 回覆 — 真正 LLM agent 的佔位,可在伺服器不停機下熱換 |

## 執行

```
bundle install
bundle exec ruby boot.rb        # Ctrl-C 整棵樹 LIFO 收乾淨
websocat ws://localhost:9292/ws # 輸入 {"text":"hello"}
curl localhost:9292/status
```

自我檢查(啟動 → WS 對話 → 熱換 agent → 收樹):

```
bundle exec ruby smoke.rb
```
