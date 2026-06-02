import SwiftUI
import SwiftData
import AVFoundation
import UIKit

public struct MainTabView: View {
    @State private var settings = AppSettings()
    @State private var isShowingSettings = false

    public init() {}

    public var body: some View {
        AgentView(settings: settings) {
            isShowingSettings = true
        }
        .background(Color.black.ignoresSafeArea())
        .tint(.mint)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings)
        }
    }
}

private struct AgentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: AppSettings

    let onSettings: () -> Void

    @State private var sessionManager: SessionManager
    @State private var messages: [AgentMessage] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var isVoiceRecording = false
    @State private var isPressingComposer = false
    @State private var voiceStartTask: Task<Void, Never>?
    @State private var statusText: String?
    @State private var dictationManager = MandarinDictationManager()
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @FocusState private var isInputFocused: Bool

    init(settings: AppSettings, onSettings: @escaping () -> Void) {
        self.settings = settings
        self.onSettings = onSettings
        _sessionManager = State(initialValue: SessionManager(appSettings: settings))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture {
                    dismissTextInput()
                }

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                messageArea

                composer
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(.black.opacity(0.78))
            }
        }
        .onAppear {
            sessionManager.setModelContext(modelContext)
        }
        .onChange(of: dictationManager.transcript) { _, newValue in
            guard isVoiceRecording else { return }
            inputText = newValue
        }
        .onChange(of: sessionManager.liveTranscriptLines.count) { _, _ in
            syncAmbientMessages()
        }
        .onChange(of: sessionManager.liveTranscriptLines.map(\.translationText).joined(separator: "\n")) { _, _ in
            syncAmbientMessages()
        }
        .onChange(of: sessionManager.liveTranslationStatus) { _, _ in
            syncAmbientMessages()
        }
        .onDisappear {
            voiceStartTask?.cancel()
            voiceStartTask = nil
            dictationManager.stop()
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Image("AppIcon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("\(settings.chatTargetDialect.title) ↔ \(AppText.t("Mandarin", "普通话"))")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 11) {
                    if messages.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 380)
                    } else {
                        ForEach(messages) { message in
                            messageBlock(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissTextInput()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                guard let lastMessage = messages.last else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )

                Image(systemName: "sparkle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.mint)
            }

            Text(AppText.t("Hold to speak, or start listening", "按住说，或打开倾听"))
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text(AppText.t(
                "Speak Mandarin for natural Cantonese. Ambient listening appears sentence by sentence.",
                "说普通话，我帮你转成自然粤语。打开环境倾听，我按句子显示对照。"
            ))
            .font(.system(.callout, design: .rounded))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: 260)

            HStack(spacing: 8) {
                exampleChip("得閒飲茶")
                exampleChip("jyutping")
            }
        }
    }

    private func exampleChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.mint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.mint.opacity(0.1))
            .clipShape(Capsule())
    }

    private func messageBlock(_ message: AgentMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label = message.label {
                Label(label, systemImage: message.iconName)
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Text(message.primaryText)
                .font(.system(.body, design: .rounded))
                .fontWeight(message.kind == .user ? .medium : .semibold)
                .foregroundColor(message.kind == .user ? .black : .white)
                .fixedSize(horizontal: false, vertical: true)

            if let secondaryText = message.secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(message.kind == .user ? .black.opacity(0.72) : .mint.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let noteText = message.noteText, !noteText.isEmpty {
                if message.isProcessing {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.mint)

                        Text(noteText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                } else {
                    Text(noteText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if message.kind == .agent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(message.backgroundColor)
        .cornerRadius(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            guard message.kind == .agent else { return }
            speak(message.primaryText)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ambientButton
                composerField
                sendButton
            }

            if let statusText {
                Text(statusText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var composerField: some View {
        ZStack(alignment: .leading) {
            TextField("", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .font(.system(.body, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit {
                    sendCurrentInput()
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 42, alignment: .center)

            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(isVoiceRecording ? AppText.t("Release to send", "松开发送") : AppText.t("Hold to speak, tap to type", "按住说话，点按输入"))
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.regular)
                    .foregroundColor(.white.opacity(0.44))
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 42, alignment: .center)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isVoiceRecording ? Color.mint.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    handleComposerPressChanged()
                }
                .onEnded { _ in
                    handleComposerPressEnded()
                }
        )
    }

    private var ambientButton: some View {
        Button(action: toggleAmbientListening) {
            Image(systemName: sessionManager.isRecordingLocally ? "stop.fill" : "ear")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(sessionManager.isRecordingLocally ? .black : .mint)
                .frame(width: 40, height: 40)
                .background(sessionManager.isRecordingLocally ? Color.mint : Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var sendButton: some View {
        Button(action: sendCurrentInput) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(canSend ? .black : .white.opacity(0.26))
                .frame(width: 40, height: 40)
                .background(canSend ? Color.mint : Color.white.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !isSending && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginVoiceMessage() {
        guard !isVoiceRecording, !dictationManager.isRecording else { return }
        isInputFocused = false
        isVoiceRecording = true
        inputText = ""
        statusText = AppText.t("Listening...", "正在听你说...")

        Task {
            let granted = await dictationManager.requestAuthorization()
            guard granted else {
                await MainActor.run {
                    isVoiceRecording = false
                    statusText = AppText.t("Microphone or speech permission is missing.", "缺少麦克风或语音识别权限。")
                }
                return
            }

            do {
                try dictationManager.start()
            } catch {
                await MainActor.run {
                    isVoiceRecording = false
                    statusText = error.localizedDescription
                }
            }
        }
    }

    private func finishVoiceMessage() {
        guard isVoiceRecording else { return }
        isVoiceRecording = false
        dictationManager.finish()

        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                let spokenText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spokenText.isEmpty else {
                    statusText = AppText.t("No speech recognized.", "没有识别到语音。")
                    return
                }
                sendCurrentInput()
            }
        }
    }

    private func handleComposerPressChanged() {
        guard !isPressingComposer else { return }
        isPressingComposer = true

        voiceStartTask?.cancel()
        voiceStartTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isPressingComposer, inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                beginVoiceMessage()
            }
        }
    }

    private func handleComposerPressEnded() {
        isPressingComposer = false
        voiceStartTask?.cancel()
        voiceStartTask = nil

        if isVoiceRecording {
            finishVoiceMessage()
        } else {
            startTextInput()
        }
    }

    private func sendCurrentInput() {
        let textToSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty, !isSending else { return }

        inputText = ""
        isInputFocused = false
        statusText = nil
        isSending = true
        messages.append(AgentMessage(kind: .user, primaryText: textToSend))

        Task {
            do {
                let chatService = DialectChatService(model: settings.aiModel.modelIdentifier)
                let result = try await chatService.translateMandarin(textToSend, to: settings.chatTargetDialect)
                await MainActor.run {
                    messages.append(
                        AgentMessage(
                            kind: .agent,
                            primaryText: result.dialectText,
                            secondaryText: result.pronunciation,
                            noteText: result.usageNote
                        )
                    )
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    statusText = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func startTextInput() {
        guard !isVoiceRecording else { return }
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    private func dismissTextInput() {
        guard isInputFocused else { return }
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func toggleAmbientListening() {
        if sessionManager.isRecordingLocally {
            sessionManager.stopSession()
            statusText = nil
        } else {
            sessionManager.startSession()
            statusText = AppText.t("Ambient listening is on.", "环境倾听已开启。")
        }
    }

    private func syncAmbientMessages() {
        for line in sessionManager.liveTranscriptLines {
            let isTranslationPending = settings.liveTranslationEnabled && line.translationText.isEmpty
            let translationNote = isTranslationPending
                ? AppText.t("Translating with AI...", "正在用大模型翻译...")
                : nil

            if let index = messages.firstIndex(where: { $0.sourceID == line.id }) {
                messages[index].primaryText = line.dialectText
                messages[index].secondaryText = line.translationText.isEmpty ? nil : line.translationText
                messages[index].noteText = translationNote
                messages[index].isProcessing = isTranslationPending
            } else {
                messages.append(
                    AgentMessage(
                        kind: .ambient,
                        primaryText: line.dialectText,
                        secondaryText: line.translationText.isEmpty ? nil : line.translationText,
                        noteText: translationNote,
                        isProcessing: isTranslationPending,
                        sourceID: line.id
                    )
                )
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

private struct AgentMessage: Identifiable {
    enum Kind {
        case user
        case agent
        case ambient
    }

    let id = UUID()
    let kind: Kind
    var primaryText: String
    var secondaryText: String?
    var noteText: String?
    var isProcessing: Bool = false
    var sourceID: UUID?

    var label: String? {
        switch kind {
        case .user:
            return AppText.t("Me", "我")
        case .agent:
            return AppText.t("Dialecter", "方言家")
        case .ambient:
            return AppText.t("Ambient", "环境倾听")
        }
    }

    var iconName: String {
        switch kind {
        case .user:
            return "person.fill"
        case .agent:
            return "sparkle"
        case .ambient:
            return "ear"
        }
    }

    var backgroundColor: Color {
        switch kind {
        case .user:
            return Color.mint.opacity(0.9)
        case .agent:
            return Color.white.opacity(0.08)
        case .ambient:
            return Color.white.opacity(0.06)
        }
    }
}

#Preview {
    MainTabView()
}
