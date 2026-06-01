# Dialecter v2 Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the tabbed recorder/chat experience with a single 方言家 agent stream and unified composer.

**Architecture:** Implement the first v2 pass inside `MainTabView.swift` to avoid Xcode project churn. Reuse existing managers and services for ambient listening, Mandarin dictation, chat translation, settings, and speech playback. Keep old `HomeView` and `ChatView` in the project for now but remove them from the main navigation path.

**Tech Stack:** SwiftUI, SwiftData, AVFoundation, existing `SessionManager`, `MandarinDictationManager`, `DialectChatService`, `SettingsView`.

---

### Task 1: Replace Main Tab Shell With Agent Shell

**Files:**
- Modify: `DialectListener/Views/MainTabView.swift`

- [x] **Step 1: Replace `TabView` with a single `AgentView`**

Change `MainTabView.body` so it owns `AppSettings` and presents:

```swift
AgentView(settings: settings)
    .sheet(isPresented: $isShowingSettings) {
        SettingsView(settings: settings)
    }
```

Expected result: there are no top tabs for 倾听 and 畅聊.

- [x] **Step 2: Add compact header**

Inside the new view, add a one-line header containing a small logo mark, `粤语 ↔ 普通话`, and a settings button.

- [x] **Step 3: Verify static checks**

Run:

```bash
git diff --check
```

Expected: no output.

### Task 2: Add Single-Column Agent Stream

**Files:**
- Modify: `DialectListener/Views/MainTabView.swift`

- [x] **Step 1: Add `AgentMessage`**

Define local message data with roles:

```swift
private struct AgentMessage: Identifiable {
    enum Kind {
        case user
        case agent
        case ambient
    }

    let id = UUID()
    let kind: Kind
    let primaryText: String
    var secondaryText: String?
    var noteText: String?
    var sourceID: UUID?
}
```

- [x] **Step 2: Render a single reading column**

Render all message types left-aligned in one `ScrollView`, using labels and visual tone instead of left/right chat layout.

- [x] **Step 3: Add empty state**

Show a small glyph, `按住说，或打开倾听`, capability text, and two example chips when there are no messages.

### Task 3: Implement Unified Composer

**Files:**
- Modify: `DialectListener/Views/MainTabView.swift`

- [x] **Step 1: Add composer state**

Add local state for `inputText`, focus, dictation, voice press, sending, and status.

- [x] **Step 2: Idle composer**

Idle composer shows one line: `按住说话，点按输入`.

- [x] **Step 3: Tap to type**

Tapping idle composer enters text mode and opens keyboard.

- [x] **Step 4: Hold to dictate**

Holding idle composer starts `MandarinDictationManager`, streams recognized text into the composer, and releasing sends recognized text.

- [x] **Step 5: Send text**

Sending appends a user message, calls `DialectChatService`, and appends one agent message with Cantonese, pronunciation, note, and playback support.

### Task 4: Ambient Listening In Same Stream

**Files:**
- Modify: `DialectListener/Views/MainTabView.swift`

- [x] **Step 1: Add `SessionManager`**

Create a `SessionManager(settings:)`, set model context on appear, and expose ambient toggle.

- [x] **Step 2: Toggle ambient listening**

The small composer-side ambient button starts/stops `SessionManager`.

- [x] **Step 3: Append ambient sentence messages**

Observe `sessionManager.liveTranscriptLines`, append new sentence-level ambient messages by `TranscriptLine.id`, and keep them in the same stream.

### Task 5: Verification And Release

**Files:**
- Modify: `.github/workflows/testflight.yml`
- Modify: `DEPLOYMENT.md`

- [x] **Step 1: Bump version**

Set `MARKETING_VERSION` to `1.0.10`.

- [x] **Step 2: Local checks**

Run:

```bash
plutil -lint DialectListener.xcodeproj/project.pbxproj DialectListener/Info.plist ExportOptions.plist
git diff --check
```

Expected: plist files OK and no diff whitespace errors.

- [ ] **Step 3: Commit, push, and dispatch TestFlight**

Commit the changes, push `main`, and run the TestFlight workflow.
