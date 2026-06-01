# Dialecter v2 Agent Design

## Goal

Redesign Dialecter around one clear product idea: a single dialect AI agent named 方言家. The app should no longer feel like a recorder plus a translator. It should feel like one conversation where the user can either speak to the agent or let the agent listen to the environment.

The design favors reliability over hidden inference. User action defines intent:

- Tap the composer to type.
- Hold the composer to speak to the agent.
- Toggle ambient listening explicitly when the agent should listen to the environment.

The app does not need to guess whether pressed speech is Mandarin, Cantonese, or ambient speech to decide intent. Pressed speech is always a user message.

## Product Model

Dialecter v2 has one main screen: a conversation with 方言家.

There are no primary tabs for 倾听 and 畅聊. Both behaviors become message types inside the same conversation:

- User messages: typed or dictated Mandarin from the user.
- Agent replies: natural Cantonese text, pronunciation, and optional usage notes.
- Ambient listening messages: sentence-level environment speech and its translation.
- System status: subtle transient state only, such as listening, recognizing, sending, or ambient listening active.

This keeps the mental model simple: everything useful appears in one chronological flow.

## Main Screen

The main screen has three areas:

1. Header
   - Uses the 方言家 logo mark as the product identity.
   - Combines identity and language direction into one compact row.
   - Shows only a compact language pair label, such as 粤语 ↔ 普通话, beside the logo.
   - Provides a small settings button.
   - Avoids model names, provider names, mode names, and technical status.

2. Message area
   - Shows the conversation as a vertical message list.
   - User messages align right.
   - Agent and ambient messages align left.
   - Ambient messages include a small source label, such as 环境倾听.
   - Empty state appears only when there are no messages.

3. Unified composer
   - The composer is the primary control.
   - In idle state, it shows one compact hint: “按住说话，点按输入”.
   - Tapping enters text input mode and opens the keyboard.
   - Holding starts dictation, shows recognized text inside the composer, and sends on release.
   - A small ambient listening control sits inside or beside the composer, visually secondary to direct user input.

## Empty State

The empty state should make the app feel ready, not promotional.

It contains:

- A small agent glyph.
- One short action line: “按住说，或打开倾听”.
- One short capability line: “说普通话，我帮你转成自然粤语。打开环境倾听，我按句子显示对照。”
- One or two subtle example chips, such as “得閒飲茶” and “jyutping”.

The empty state disappears immediately after the first message appears.

## Composer State Machine

The composer has five states:

1. Idle
   - Text: “按住说话，点按输入”.
   - Tap transitions to text editing.
   - Long press transitions to voice recording.

2. Text editing
   - Keyboard is visible.
   - Composer contains editable text.
   - Send button appears only when text is non-empty.
   - Sending appends a user message and requests an agent reply.

3. Voice recording
   - Keyboard is hidden.
   - Composer shows live recognized text.
   - Releasing sends recognized text if non-empty.
   - Releasing with no recognized text returns to idle with a subtle status message.

4. Sending
   - Composer remains available but send action is disabled or shows a compact progress indicator.
   - User message is already appended to the conversation.
   - Agent reply appends when ready.

5. Ambient listening active
   - Ambient control shows active state.
   - Environment speech is grouped by sentence before becoming a message.
   - Composer still supports direct user input unless microphone resources require temporarily disabling it.

## Message Types

User message:

- Right aligned.
- Uses the accent fill color.
- Contains only the user text.

Agent reply:

- Left aligned.
- Contains Cantonese text as the primary line.
- Contains pronunciation as a secondary line when available.
- Contains a short note only when it adds value.
- Tapping the message plays speech.
- Playback is indicated with a small speaker icon, not a large button.

Ambient message:

- Left aligned.
- Contains a small “环境倾听” label.
- Contains source speech as primary text.
- Contains translation as secondary text.
- Must be sentence-level, not word-level.

Status:

- Should be transient and quiet.
- Avoid persistent technical text in the main flow.
- Never show model/provider names in the main screen.

## Visual Direction

The visual direction is black, quiet, and agent-like.

Use:

- A near-black background.
- One restrained accent color for action and translated text.
- Rounded message bubbles with consistent spacing.
- Small, stable icon buttons.
- Lightweight material only where it helps layering, not as decoration.

Avoid:

- Large red recording buttons.
- Mode labels like 会议记录, 高, MiniMax, or provider names in the main flow.
- Landing-page copy.
- Large cards inside cards.
- Decorative gradients, orbs, or one-note purple/blue palettes.

## Settings

Settings remain available from the header, but they should not leak into the main workflow.

Settings can include:

- Ambient listening source language.
- Translation target.
- Chat target dialect.
- Microphone sensitivity.
- AI model selection.
- Live transcript and live translation toggles.

The default main screen should not require users to understand these settings.

## Technical Notes

The existing code can evolve toward this design without replacing the whole app at once:

- Replace `MainTabView` tab structure with a single `AgentView`.
- Merge message rendering patterns from current `HomeView` and `ChatView`.
- Introduce an app-level `AgentMessage` model for user, agent, ambient, and status messages.
- Keep `SessionManager` for ambient listening, but publish sentence-level ambient messages into the shared conversation.
- Keep `DialectChatService` for user-to-agent translation replies.
- Rework the composer into a single reusable SwiftUI component with tap, long press, text editing, and send states.

## Verification

The implementation should be considered correct when:

- First launch shows the empty state and unified composer.
- Tapping the composer opens the keyboard.
- Typing text shows a send button and sends a user message.
- Holding the composer starts voice recognition, displays recognized text, and sends on release.
- Ambient listening can be toggled explicitly.
- Ambient output appears as sentence-level messages in the same conversation.
- Agent replies combine Cantonese, pronunciation, note, and playback in one message bubble.
- Main screen does not show model names, provider names, listening mode, or microphone sensitivity.
- TestFlight workflow builds and uploads successfully.
