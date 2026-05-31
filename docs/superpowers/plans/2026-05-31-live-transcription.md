# Live Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show dialect transcription and low-latency translation while a listening session is still recording.

**Architecture:** Replace the file-only recording flow with an `AVAudioEngine` buffer flow. The recorder writes microphone buffers to disk and forwards the same buffers to a live `SFSpeechAudioBufferRecognitionRequest`; `SessionManager` publishes live transcript lines and throttles translation updates for the recording HUD.

**Tech Stack:** SwiftUI, SwiftData, AVFoundation, Speech, GitHub Actions/Xcode 26.3.

---

### Task 1: Live ASR API

**Files:**
- Modify: `DialectListener/Services/AppleASRService.swift`

- [ ] Add `LiveTranscriptionUpdate` and live methods to `ASRServiceProtocol`.
- [ ] Implement stateful `startLiveTranscription`, `appendAudioBuffer`, and `stopLiveTranscription` on `AppleASRService`.
- [ ] Keep existing file transcription for fallback/review behavior.

### Task 2: Buffer-Based Recording

**Files:**
- Modify: `DialectListener/Services/AudioRecorderManager.swift`

- [ ] Replace `AVAudioRecorder` with `AVAudioEngine`.
- [ ] Write input buffers to a local CAF audio file.
- [ ] Forward every input buffer through an `onAudioBuffer` callback.
- [ ] Preserve `currentDuration`, `activeAudioURL`, and stop semantics.

### Task 3: Session Live State

**Files:**
- Modify: `DialectListener/Managers/SessionManager.swift`

- [ ] Add live transcript and translation published state.
- [ ] On start, clear live state, start ASR, then start recording.
- [ ] On each ASR update, update live transcript immediately and throttle translation.
- [ ] On stop, end live ASR, save the latest live lines into `Session.transcript`, and avoid duplicate post-stop ASR.

### Task 4: Recording HUD

**Files:**
- Modify: `DialectListener/Views/RecordingHUDView.swift`

- [ ] Replace empty middle space with a live transcript panel.
- [ ] Show dialect text and translation text for each live line.
- [ ] Keep timer, bookmark, and finish controls reachable.

### Task 5: Verification

**Commands:**
- `plutil -lint DialectListener/Info.plist ExportOptions.plist DialectListener.xcodeproj/project.pbxproj`
- `git status --short`
- `gh workflow run testflight.yml --repo dustland/dialecter --ref main`
- `gh run watch <run-id> --repo dustland/dialecter --interval 10 --exit-status`

**Expected:** Xcode archive, IPA export, artifact upload, and TestFlight upload all succeed.
