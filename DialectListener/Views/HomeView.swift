import SwiftUI
import SwiftData

/// Home dashboard view of Dialecter on iPhone.
/// Offers direct control to start a listening session and shows a history list of past recordings.
public struct HomeView: View {
    
    @Environment(\.modelContext) private var modelContext
    @State private var sessionManager = SessionManager()
    @State private var selectedSessionForDetail: Session? = nil
    @State private var isShowingSettings = false
    
    public init(settings: AppSettings = AppSettings()) {
        _sessionManager = State(initialValue: SessionManager(appSettings: settings))
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Premium deep dark background with gradient glow
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(AppText.t("Dialecter", "方言家"))
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Dialecter")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(sessionManager.isRecordingLocally ? Color.red.opacity(0.9) : Color.green.opacity(0.75))
                                .frame(width: 7, height: 7)

                            Text(sessionManager.isRecordingLocally ? AppText.t("Listening", "倾听中") : AppText.t("Ready", "就绪"))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())

                        Button(action: {
                            isShowingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppText.t("Meeting Notes", "会议字幕"))
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.white)

                        Text(AppText.t("Low-key live transcription and translation for dialect listening.", "低调实时识别与翻译，适合方言倾听练习。"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    HStack {
                        Text(AppText.t("Recent Sessions", "最近记录"))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding(.horizontal)

                    if sessionManager.recentSessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.15))
                            
                            Text(AppText.t("No sessions yet", "还没有记录"))
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.secondary)
                            
                            Text(AppText.t("Start a low-key listening session when you are ready.", "准备好后开始一次低调倾听。"))
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(sessionManager.recentSessions) { session in
                                Button(action: {
                                    selectedSessionForDetail = session
                                }) {
                                    SessionCard(session: session)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let session = sessionManager.recentSessions[index]
                                    sessionManager.deleteSession(session)
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                        .scrollContentBackground(.hidden)
                    }

                    listenControlBar
                        .padding(.horizontal)
                        .padding(.bottom, 18)
                }
            }
            .onAppear {
                sessionManager.setModelContext(modelContext)
            }
            .fullScreenCover(isPresented: $sessionManager.isRecordingLocally) {
                RecordingHUDView(sessionManager: sessionManager)
            }
            .sheet(item: $selectedSessionForDetail) { session in
                SessionDetailView(session: session)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(settings: sessionManager.appSettings)
            }
        }
    }

    private var listenControlBar: some View {
        HStack(spacing: 12) {
            Button(action: toggleListening) {
                Image(systemName: sessionManager.isRecordingLocally ? "stop.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(sessionManager.isRecordingLocally ? .red : .cyan)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(sessionManager.isRecordingLocally ? AppText.t("Listening quietly", "低调倾听中") : AppText.t("Start listening", "开始倾听"))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("\(sessionManager.appSettings.sourceLanguage.title) · \(sessionManager.appSettings.listeningMode.title) · \(sessionManager.appSettings.micSensitivity.title)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(18)
    }

    private func toggleListening() {
        if sessionManager.isRecordingLocally {
            sessionManager.stopSession()
        } else {
            sessionManager.startSession()
        }
    }
}

// MARK: - Subviews

struct SessionCard: View {
    let session: Session
    
    var body: some View {
        HStack(spacing: 16) {
            // Processing status or standard play indicator icon
            ZStack {
                Circle()
                    .fill(session.isProcessed ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: session.isProcessed ? "play.fill" : "hourglass")
                    .foregroundColor(session.isProcessed ? .blue : .orange)
                    .font(.system(size: 16, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch.fill")
                        Text(formatDuration(session.duration))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                        Text("\(session.bookmarks.count)")
                    }
                    
                    if !session.isProcessed {
                        Text(AppText.t("Processing...", "处理中..."))
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.2))
                .font(.footnote)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            // Premium Glassmorphism Card
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    HomeView()
}
