import SwiftUI

public struct MainTabView: View {
    private enum Section: Int {
        case listen
        case chat
    }

    @State private var settings = AppSettings()
    @State private var selectedSection: Section = .listen
    @State private var isShowingSettings = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $selectedSection) {
                HomeView(settings: settings)
                    .tag(Section.listen)

                ChatView(settings: settings)
                    .tag(Section.chat)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color.black.ignoresSafeArea())
        .tint(.cyan)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                switcherButton(
                    title: AppText.t("Listen", "倾听"),
                    icon: "waveform.and.mic",
                    section: .listen
                )
                switcherButton(
                    title: AppText.t("Chat", "畅聊"),
                    icon: "bubble.left.and.text.bubble.right.fill",
                    section: .chat
                )
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(15)

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial.opacity(0.18))
    }

    private func switcherButton(title: String, icon: String, section: Section) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSection = section
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(selectedSection == section ? .black : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if selectedSection == section {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.cyan)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
}
