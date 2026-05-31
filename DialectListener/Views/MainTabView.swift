import SwiftUI

public struct MainTabView: View {
    @State private var settings = AppSettings()

    public init() {}

    public var body: some View {
        TabView {
            HomeView(settings: settings)
                .tabItem {
                    Label(AppText.t("Listen", "倾听"), systemImage: "waveform.and.mic")
                }

            ChatView(settings: settings)
                .tabItem {
                    Label(AppText.t("Chat", "畅聊"), systemImage: "bubble.left.and.text.bubble.right.fill")
                }
        }
        .tint(.cyan)
    }
}

#Preview {
    MainTabView()
}
