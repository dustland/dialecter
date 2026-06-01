import SwiftUI
import AVFoundation

public struct ChatView: View {
    @Bindable var settings: AppSettings
    @State private var inputText = ""
    @State private var result: DialectChatResult?
    @State private var isTranslating = false
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
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    resultPanel
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
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
            dictationManager.stop()
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppText.t("Chat", "畅聊"))
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Label(AppText.t("Mandarin", "普通话"), systemImage: "text.quote")
                    Text("->")
                        .foregroundColor(.secondary)
                    Label(settings.chatTargetDialect.title, systemImage: "bubble.left.and.bubble.right.fill")
                }
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(settings.aiModel.title)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $inputText)
                .font(.system(.body, design: .rounded))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 54, maxHeight: 110)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .cornerRadius(16)
                .overlay(alignment: .topLeading) {
                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(AppText.t("Type Mandarin here, or tap the mic.", "输入普通话，或点麦克风说一句。"))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            if let statusText {
                Text(statusText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: toggleDictation) {
                    Image(systemName: dictationManager.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(dictationManager.isRecording ? .red : .cyan)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }

                Button(action: translate) {
                    HStack(spacing: 8) {
                        if isTranslating {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        Text(AppText.t("Send", "发送"))
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canTranslate ? Color.cyan : Color.white.opacity(0.08))
                    .foregroundColor(canTranslate ? .black : .secondary)
                    .cornerRadius(14)
                }
                .disabled(!canTranslate)
            }
        }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result {
                messageBubble(title: AppText.t("You", "你"), text: result.mandarinText, isUser: true)
                messageBubble(title: settings.chatTargetDialect.title, text: result.dialectText, isUser: false)
                resultBlock(title: AppText.t("Pronunciation", "发音"), text: result.pronunciation, prominent: false)
                resultBlock(title: AppText.t("Note", "提示"), text: result.usageNote, prominent: false)

                playButton
            } else {
                Text(AppText.t("Send a Mandarin phrase to get a dialect version and pronunciation.", "发送一句普通话，获取方言说法和发音。"))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var playButton: some View {
        Button(action: speakResult) {
            Label(AppText.t("Play", "播放"), systemImage: "speaker.wave.2.fill")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(14)
        }
    }

    private func messageBubble(title: String, text: String, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(isUser ? .black : .white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(13)
                .background(isUser ? Color.cyan : Color.white.opacity(0.08))
                .cornerRadius(16)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func resultBlock(title: String, text: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(prominent ? .title3 : .body, design: .rounded))
                .fontWeight(prominent ? .bold : .regular)
                .foregroundColor(prominent ? .white : .cyan.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var canTranslate: Bool {
        !isTranslating && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleDictation() {
        if dictationManager.isRecording {
            dictationManager.stop()
            statusText = nil
            return
        }

        Task {
            let granted = await dictationManager.requestAuthorization()
            guard granted else {
                statusText = AppText.t("Microphone or speech permission is missing.", "缺少麦克风或语音识别权限。")
                return
            }

            do {
                dictationManager.transcript = inputText
                try dictationManager.start()
                statusText = AppText.t("Listening for Mandarin...", "正在听普通话...")
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func translate() {
        dictationManager.stop()
        statusText = nil
        isTranslating = true

        Task {
            do {
                let chatService = DialectChatService(model: settings.aiModel.modelIdentifier)
                let translated = try await chatService.translateMandarin(
                    inputText,
                    to: settings.chatTargetDialect
                )
                await MainActor.run {
                    result = translated
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

    private func speakResult() {
        guard let result else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: result.dialectText)
        utterance.voice = AVSpeechSynthesisVoice(language: settings.chatTargetDialect.speechLocaleIdentifier)
        utterance.rate = 0.45
        speechSynthesizer.speak(utterance)
    }
}

#Preview {
    ChatView(settings: AppSettings())
}
