import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppSettings

    public var body: some View {
        NavigationStack {
            Form {
                Section(AppText.t("Listening", "倾听")) {
                    Picker(AppText.t("Listening Mode", "倾听模式"), selection: $settings.listeningMode) {
                        ForEach(ListeningMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker(AppText.t("Mic Sensitivity", "麦克风灵敏度"), selection: $settings.micSensitivity) {
                        ForEach(MicSensitivity.allCases) { sensitivity in
                            Text(sensitivity.title).tag(sensitivity)
                        }
                    }

                    Toggle(AppText.t("Keep Screen Awake", "录音时保持亮屏"), isOn: $settings.keepScreenAwake)
                }

                Section(AppText.t("Language", "语言")) {
                    Picker(AppText.t("Target Dialect", "识别目标语言"), selection: $settings.sourceLanguage) {
                        ForEach(SourceLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }

                    Picker(AppText.t("Translation Target", "翻译目标"), selection: $settings.translationTarget) {
                        ForEach(TranslationTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }

                    Picker(AppText.t("Chat Target", "畅聊目标"), selection: $settings.chatTargetDialect) {
                        ForEach(ChatTargetDialect.allCases) { dialect in
                            Text(dialect.title).tag(dialect)
                        }
                    }
                }

                Section(AppText.t("Live Recognition", "实时识别")) {
                    Toggle(AppText.t("Live Transcript", "实时字幕"), isOn: $settings.liveTranscriptEnabled)
                    Toggle(AppText.t("Live Translation", "实时翻译"), isOn: $settings.liveTranslationEnabled)
                }
            }
            .navigationTitle(AppText.t("Settings", "设置"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.t("Done", "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(settings: AppSettings())
}
