import SwiftUI

public struct MainTabView: View {
    private enum Section: Int {
        case listen
        case chat
    }

    @State private var settings = AppSettings()
    @State private var selectedSection: Section = .listen

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topSwitcher

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
    }

    private var topSwitcher: some View {
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
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(15)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
