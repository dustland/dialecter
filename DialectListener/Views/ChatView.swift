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

    private let chatService = DialectChatService()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    gradient: Gradient(colors: [Color.green.opacity(0.08), Color.black]),
                    center: .topTrailing,
                    startRadius: 2,
                    endRadius: 520
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        inputPanel
                        resultPanel
                    }
                    .padding(18)
                }
            }
            .navigationTitle(AppText.t("Chat", "畅聊"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: dictationManager.transcript) { _, newValue in
                guard dictationManager.isRecording else { return }
                inputText = newValue
            }
            .onDisappear {
                dictationManager.stop()
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppText.t("Practice a phrase", "练一句"))
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)

            HStack(spacing: 8) {
                Label(AppText.t("Mandarin input", "普通话输入"), systemImage: "text.quote")
                Text("->")
                    .foregroundColor(.secondary)
                Label(settings.chatTargetDialect.title, systemImage: "bubble.left.and.bubble.right.fill")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundColor(.secondary)
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $inputText)
                .font(.system(.body, design: .rounded))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .padding(12)
                .background(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .cornerRadius(14)
                .overlay(alignment: .topLeading) {
                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(AppText.t("Type Mandarin here, or tap the mic.", "输入普通话，或点麦克风说一句。"))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
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
                        Text(AppText.t("Translate", "转换"))
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(canTranslate ? Color.cyan : Color.white.opacity(0.08))
                    .foregroundColor(canTranslate ? .black : .secondary)
                    .cornerRadius(14)
                }
                .disabled(!canTranslate)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(18)
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppText.t("Result", "结果"))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)

            if let result {
                resultBlock(title: settings.chatTargetDialect.title, text: result.dialectText, prominent: true)
                resultBlock(title: AppText.t("Pronunciation", "发音"), text: result.pronunciation, prominent: false)
                resultBlock(title: AppText.t("Note", "提示"), text: result.usageNote, prominent: false)

                Button(action: speakResult) {
                    Label(AppText.t("Play", "播放"), systemImage: "speaker.wave.2.fill")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            } else {
                Text(AppText.t("Converted text and pronunciation will appear here.", "转换后的文字和发音会显示在这里。"))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(18)
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
