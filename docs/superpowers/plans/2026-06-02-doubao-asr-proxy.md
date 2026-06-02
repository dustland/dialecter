# Doubao ASR Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Apple Speech as the primary listening ASR path with a Doubao/Volcengine streaming ASR service accessed through a server-side proxy.

**Architecture:** The iOS app captures low-processed microphone audio and streams short PCM/Opus frames to a first-party WebSocket proxy. The proxy owns Volcengine credentials, translates app audio frames into Volcengine BigModel Streaming ASR binary WebSocket frames, and streams finalized sentence events back to the app. Apple Speech remains an explicit fallback only.

**Tech Stack:** Swift/SwiftUI, AVAudioEngine, URLSessionWebSocketTask, Cloudflare Workers or a small Node service, Volcengine Doubao BigModel Streaming ASR.

---

### Task 1: Add ASR Provider Settings

**Files:**
- Modify: `DialectListener/Models/AppSettings.swift`
- Modify: `DialectListener/Views/SettingsView.swift`

- [ ] Add `ASRProvider` enum with `doubao`, `aliyun`, and `appleFallback`.
- [ ] Add persisted `asrProvider` and `asrProxyURL` settings.
- [ ] Add a Settings section named `ASR` with provider picker and proxy URL text field.
- [ ] Default provider to `doubao`; default proxy URL to an empty string so the app can show a configuration error instead of silently using Apple Speech.

### Task 2: Define Streaming ASR Event Model

**Files:**
- Create: `DialectListener/Services/StreamingASRService.swift`
- Modify: `DialectListener/Services/AppleASRService.swift`

- [ ] Define `ASRLanguage` values: `cantonese`, `mandarin`, `english`, `unknown`.
- [ ] Define `StreamingASREvent` with `id`, `start`, `end`, `text`, `language`, `confidence`, and `isFinal`.
- [ ] Define `StreamingASRServiceProtocol` with `requestAuthorization()`, `start(onEvent:onError:)`, `appendAudioBuffer(_:)`, and `stop()`.
- [ ] Wrap `AppleASRService` in an `AppleFallbackStreamingASRService` adapter so fallback has the same event interface.

### Task 3: Add Doubao Proxy Client In iOS

**Files:**
- Create: `DialectListener/Services/DoubaoProxyASRService.swift`
- Modify: `DialectListener/Managers/SessionManager.swift`

- [ ] Implement `URLSessionWebSocketTask` connection to `asrProxyURL`.
- [ ] Send a JSON `start` message with sample rate, language hints, and session ID.
- [ ] Convert incoming `AVAudioPCMBuffer` frames to 16 kHz mono PCM frames before sending.
- [ ] Send binary audio frames at 100-200 ms cadence.
- [ ] Decode proxy events into `StreamingASREvent`.
- [ ] On missing proxy URL, surface `请先配置 ASR 服务` and do not start fake listening.

### Task 4: Update Session Message Pipeline

**Files:**
- Modify: `DialectListener/Managers/SessionManager.swift`
- Modify: `DialectListener/Models/Models.swift`
- Modify: `DialectListener/Views/MainTabView.swift`

- [ ] Add per-line state: `recognizing`, `recognized`, `converting`, `done`, `uncertain`.
- [ ] Store language and confidence on each transcript line.
- [ ] Show a subtle per-message status label such as `识别中`, `粤语`, `普通话`, or `不确定`.
- [ ] Only run dialect conversion after ASR finalizes a sentence.
- [ ] If ASR language is Cantonese, convert to Mandarin.
- [ ] If ASR language is Mandarin, convert to Cantonese.
- [ ] If ASR language is unknown, display original text without forced translation.

### Task 5: Implement ASR Proxy

**Files:**
- Create: `services/asr-proxy/package.json`
- Create: `services/asr-proxy/src/index.ts`
- Create: `services/asr-proxy/README.md`

- [ ] Accept WebSocket connections from the iOS app.
- [ ] Require a shared app token before opening upstream ASR.
- [ ] Connect to Volcengine endpoint `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel`.
- [ ] Use server-side environment variables for `VOLCENGINE_APP_ID` and `VOLCENGINE_ACCESS_TOKEN`.
- [ ] Translate app `start` and audio frames into Volcengine full client request / audio only request frames.
- [ ] Normalize Volcengine partial/final ASR responses into app JSON events.
- [ ] Keep the proxy provider-neutral enough to add Aliyun later.

### Task 6: Verification

**Files:**
- Modify as needed from previous tasks.

- [ ] Run `git diff --check`.
- [ ] Run `plutil -lint DialectListener/Info.plist ExportOptions.plist`.
- [ ] Run GitHub Actions TestFlight workflow.
- [ ] Test on iPhone with three scenarios: nearby self speech, table-distance Cantonese, table-distance Mandarin.
- [ ] Confirm Apple Speech is not used when ASR provider is `doubao`.
- [ ] Confirm missing proxy URL fails visibly instead of silently using local ASR.

---

## Required External Inputs

- Volcengine/Doubao Speech AppID.
- Volcengine/Doubao Speech Access Token.
- Confirmation whether the proxy should be Cloudflare Workers, Vercel, or a small Node service on another host.
- Optional shared app token for app-to-proxy authentication.
