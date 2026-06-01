import SwiftUI
import SwiftData

/// Home dashboard view of Dialecter on iPhone.
/// Offers direct control to start a listening session and shows a history list of past recordings.
public struct HomeView: View {
    
    @Environment(\.modelContext) private var modelContext
    @State private var sessionManager = SessionManager()
    @State private var selectedSessionForDetail: Session? = nil
    
    public init(settings: AppSettings = AppSettings()) {
        _sessionManager = State(initialValue: SessionManager(appSettings: settings))
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    if sessionManager.isRecordingLocally {
                        listeningMessageList
                    } else {
                        sessionList
                    }

                    listenControlBar
                        .padding(.horizontal)
                        .padding(.bottom, 18)
                }
            }
            .onAppear {
                sessionManager.setModelContext(modelContext)
            }
            .sheet(item: $selectedSessionForDetail) { session in
                SessionDetailView(session: session)
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !sessionManager.isRecordingLocally {
                HStack {
                    Text(AppText.t("Recent", "最近"))
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal)
            }

            if sessionManager.recentSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.14))

                    Text(AppText.t("No sessions", "暂无记录"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleSessions) { session in
                        Button(action: {
                            selectedSessionForDetail = session
                        }) {
                            SessionCard(session: session)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
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
        }
    }

    private var visibleSessions: [Session] {
        if sessionManager.isRecordingLocally {
            return Array(sessionManager.recentSessions.prefix(3))
        }
        return sessionManager.recentSessions
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

            Text(sessionManager.isRecordingLocally ? AppText.t("Listening", "倾听中") : AppText.t("Listen", "倾听"))
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            if sessionManager.isRecordingLocally {
                Button(action: {
                    sessionManager.addBookmark(at: sessionManager.recorderManager.currentDuration)
                }) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(formatDuration(sessionManager.recorderManager.currentDuration))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial.opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(18)
    }

    private var listeningMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if sessionManager.liveTranscriptLines.isEmpty {
                        Text(AppText.t("Listening...", "倾听中..."))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
                    } else {
                        ForEach(sessionManager.liveTranscriptLines) { line in
                            listeningMessageBubble(line)
                                .id(line.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .onChange(of: sessionManager.liveTranscriptLines.count) { _, _ in
                guard let lastLine = sessionManager.liveTranscriptLines.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastLine.id, anchor: .bottom)
                }
            }
        }
    }

    private func listeningMessageBubble(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.dialectText)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            if !line.translationText.isEmpty {
                Text(line.translationText)
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.cyan.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleListening() {
        if sessionManager.isRecordingLocally {
            sessionManager.stopSession()
        } else {
            sessionManager.startSession()
        }
    }

    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
