import SwiftUI
import AVFoundation

public struct ChatView: View {
    @Bindable var settings: AppSettings
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isTranslating = false
    @State private var isPressingVoice = false
    @State private var voiceStartTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool
    @State private var statusText: String?
    @State private var dictationManager = MandarinDictationManager()
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.08), Color.black]),
                center: .topTrailing,
                startRadius: 2,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    messageList
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                        .frame(maxWidth: .infinity, alignment: .top)
                }

                inputPanel
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(.black.opacity(0.72))
            }
        }
        .onChange(of: dictationManager.transcript) { _, newValue in
            guard dictationManager.isRecording else { return }
            inputText = newValue
        }
        .onDisappear {
            voiceStartTask?.cancel()
            voiceStartTask = nil
            dictationManager.stop()
            isInputFocused = false
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                inputField

                inputActionButton
            }

            if let statusText {
                Text(statusText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var inputField: some View {
        TextEditor(text: $inputText)
            .focused($isInputFocused)
            .font(.system(.body, design: .rounded))
            .foregroundColor(.white)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 42, maxHeight: 104)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isPressingVoice ? Color.cyan.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(18)
            .overlay(alignment: .topLeading) {
                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(isPressingVoice ? AppText.t("Release to send", "松开发送") : AppText.t("Type Mandarin", "输入普通话"))
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = true
            }
    }

    @ViewBuilder
    private var inputActionButton: some View {
        if isTranslating {
            ProgressView()
                .tint(.black)
                .frame(width: 44, height: 44)
                .background(Color.cyan)
                .clipShape(Circle())
        } else if canTranslate {
            Button(action: translate) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.cyan)
                    .clipShape(Circle())
            }
        } else {
            Image(systemName: isPressingVoice ? "waveform" : "mic.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isPressingVoice ? .black : .cyan)
                .frame(width: 44, height: 44)
                .background(isPressingVoice ? Color.cyan : Color.white.opacity(0.08))
                .clipShape(Circle())
                .onLongPressGesture(
                    minimumDuration: 0.18,
                    maximumDistance: 44,
                    pressing: { pressing in
                        if pressing {
                            scheduleVoiceMessageStart()
                        } else {
                            finishVoiceMessage()
                        }
                    },
                    perform: {}
                )
        }
    }

    private var messageList: some View {
        LazyVStack(spacing: 12) {
            if messages.isEmpty {
                Spacer()
                    .frame(height: 260)
            } else {
                ForEach(messages) { message in
                    messageBubble(message)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user

        if isUser {
            bubbleContent(message, isUser: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Button {
                speak(message.text)
            } label: {
                bubbleContent(message, isUser: false)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bubbleContent(_ message: ChatMessage, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            Text(message.text)
                .font(.system(.body, design: .rounded))
                .fontWeight(isUser ? .medium : .semibold)
                .foregroundColor(isUser ? .black : .white)
                .fixedSize(horizontal: false, vertical: true)

            if let pronunciation = message.pronunciation, !pronunciation.isEmpty {
                Text(pronunciation)
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.cyan.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = message.note, !note.isEmpty {
                Text(note)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if message.role == .assistant {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(.secondary.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isUser ? Color.cyan.opacity(0.92) : Color.white.opacity(0.08))
        .cornerRadius(16)
    }

    private var canTranslate: Bool {
        !isTranslating && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleVoiceMessageStart() {
        guard voiceStartTask == nil, !isPressingVoice, !dictationManager.isRecording else { return }

        voiceStartTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                beginVoiceMessage()
                voiceStartTask = nil
            }
        }
    }

    private func beginVoiceMessage() {
        guard !isPressingVoice, !dictationManager.isRecording else { return }
        isInputFocused = false
        isPressingVoice = true
        inputText = ""
        statusText = AppText.t("Listening for Mandarin...", "正在听普通话...")

        Task {
            let granted = await dictationManager.requestAuthorization()
            guard granted else {
                await MainActor.run {
                    isPressingVoice = false
                    statusText = AppText.t("Microphone or speech permission is missing.", "缺少麦克风或语音识别权限。")
                }
                return
            }

            do {
                try dictationManager.start()
            } catch {
                await MainActor.run {
                    isPressingVoice = false
                    statusText = error.localizedDescription
                }
            }
        }
    }

    private func finishVoiceMessage() {
        voiceStartTask?.cancel()
        voiceStartTask = nil
        guard isPressingVoice else { return }
        isPressingVoice = false
        dictationManager.stop()

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                let spokenText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spokenText.isEmpty else {
                    statusText = AppText.t("No Mandarin recognized.", "没有识别到普通话。")
                    return
                }
                translate()
            }
        }
    }

    private func translate() {
        dictationManager.stop()
        let textToTranslate = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToTranslate.isEmpty else { return }

        isInputFocused = false
        inputText = ""
        statusText = nil
        isTranslating = true
        messages.append(ChatMessage(role: .user, text: textToTranslate))

        Task {
            do {
                let chatService = DialectChatService(model: settings.aiModel.modelIdentifier)
                let translated = try await chatService.translateMandarin(
                    textToTranslate,
                    to: settings.chatTargetDialect
                )
                await MainActor.run {
                    messages.append(
                        ChatMessage(
                            role: .assistant,
                            text: translated.dialectText,
                            pronunciation: translated.pronunciation,
                            note: translated.usageNote
                        )
                    )
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    statusText = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }

    private func speak(_ text: String) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            statusText = error.localizedDescription
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        guard let voice = AVSpeechSynthesisVoice(language: settings.chatTargetDialect.speechLocaleIdentifier) else {
            statusText = AppText.t("No compatible system voice found.", "没有找到可用的系统语音。")
            return
        }
        utterance.voice = voice
        utterance.rate = 0.45
        speechSynthesizer.speak(utterance)
    }
}

private struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var pronunciation: String?
    var note: String?
}

#Preview {
    ChatView(settings: AppSettings())
}
