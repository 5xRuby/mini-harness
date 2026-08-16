# mini-harness — agent notes

仿 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)(本機:`~/ghq/github.com/deepseek-ai/deepseek-harness`)形狀的迷你 agent harness,同時是 [cordis](https://rubygems.org/gems/cordis) gem 的實戰場。整個 app = 一棵 cordis plugin tree,跑在單一 async reactor 上。實驗性專案,機制正確優先於功能覆蓋。

cordis gem 的源頭是姊妹專案 `~/RubyPrjs/cordis-rb`(它自己的 agents.md 記了 framework 層的設計決策);harness 這邊發現 framework 缺口時,回那邊開 feature 輪,不要在這裡 monkey-patch。

## 技術棧(已定案)

- **Falcon**:唯一「每 request 一個 fiber、與 plugin tree 共用 reactor」的主流 server,沒有替代品。內嵌啟動:`Falcon::Server.new(Falcon::Server.rack_middleware(app, cache: false), endpoint)` + `task = server.run`,disposer `task.stop`。
- **Sinatra** 管 HTTP;**async-websocket** 的 Rack adapter 管 WS:route 裡 `Async::WebSocket::Adapters::Rack.open(request.env) { |conn| ... }` 回傳 rack triple,Sinatra `halt(*result)` 放行。
- 用第三方 gem API 前先讀本機安裝的 gem 原始碼(`gem contents <name>`),不要憑記憶。

## 架構

| Plugin | 形狀 | 提供 |
|---|---|---|
| `WebServer` | `Cordis::Service` | `:web` — Falcon + Sinatra,動態 route 表 |
| `Sessions` | `Cordis::Service` | `:sessions` — in-memory 對話 store + sink fan-out |
| `Gateway` | function plugin | `GET /ws`;訊息 → `session/message` 事件;卸載時關現存連線 |
| `EchoAgent` | function plugin | 佔位 agent,監聽 `session/message` 回覆;可熱換 |

`MiniHarness.plug(ctx, url:)` 依依賴序組樹並回傳 fibers 陣列。

## 設計決策

- **Route 註冊是 revertible effect,掛在呼叫者的 fiber 上**:`c.web.route(c, 'GET', '/x') { ... }` —— plugin 卸載,route 自動消失,server 不重啟。cordis-rb 沒有 traceable proxy,所以 caller ctx 要顯式傳入(第一個參數),需要 per-caller 語意的 service method 都比照辦理。
- **Agent 是獨立 plugin**,只靠 `session/message` 事件與 gateway 解耦 —— 熱換 agent(dispose 舊、plugin 新)期間 gateway 持續服務,這是本專案要展示的核心能力。
- Gateway 用一個先註冊的 effect 收現存連線(LIFO:route 先拆、連線後關,新連線進不來)。
- Sessions 的 sink fan-out 逐個 rescue —— 死連線不擋其他 sink。

## 踩過的坑(重要)

- **`Protocol::WebSocket` 的 `message.parse` 會 symbolize JSON keys**:server 端是 `payload[:text]`,不是 `payload['text']`。
- **`fiber.await` 對「依賴未滿足的 pending fiber」立即返回**(await 只等 in-flight transition)。組完樹要 `fibers.each(&:await)` 依依賴序等,才算 settle;只 await 最後一個會在依賴鏈載完前繼續跑,WS 測試就吊死在等永遠不會來的回覆。
- client 提早斷線時 server 端 write 會 EPIPE(falcon 記 warning,無害);我方 sink 已 rescue。
- Ruby 4 的 IO::Buffer experimental 警告來自 async 的 resolver:入口檔開頭 `Warning[:experimental] = false`。
- **`Protocol::WebSocket::TextMessage.generate` 會 JSON 編碼**;推 raw 文字(如 turbo-stream HTML)要用 `TextMessage.new`。
- **async 2.44 的 scheduler 在 run loop 層攔截 Interrupt**,`Sync do ... rescue Interrupt` 接不到;要 graceful shutdown 得自己 `Signal.trap(:INT)` + self-pipe 喚醒 main fiber(見 boot.rb)。
- **沒 system prompt 的 LLM 會自稱 ChatGPT**——是幻覺不是接錯 provider;用 `RUBYLLM_DEBUG=1` 看實際請求驗證。

## 慣例

- 驗證:`bundle exec ruby smoke.rb`(啟動 → WS 對話 → 熱換 agent → 404 → 收樹,四個 ok + `smoke ok`)。改了行為就跑;新的非平凡邏輯往 smoke.rb 加 expect,先不引入 rspec。
- 手動跑:`bundle exec ruby boot.rb`,`websocat ws://localhost:9292/ws` 丟 `{"text":"hello"}`。
- commit 前只對變更的 .rb 檔逐一 `rubocop -A`(不碰 .yml);`.rubocop.yml` 已關 Metrics、Style/Documentation、Naming/ConstantName(function plugin 的 Hash 常數比照 class 命名)。
- commit 作者:ryudoawaru <ryudoawaru@gmail.com>(repo-local 已設);commit message 英文。
