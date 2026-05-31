import SwiftUI
import SwiftData

/// Home dashboard view of Cantonese Listener on iPhone.
/// Offers direct control to start a listening session and shows a history list of past recordings.
public struct HomeView: View {
    
    @Environment(\.modelContext) private var modelContext
    @State private var sessionManager = SessionManager()
    @State private var isPulseAnimating = false
    @State private var selectedSessionForDetail: Session? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Premium deep dark background with gradient glow
                Color.black.ignoresSafeArea()
                
                RadialGradient(
                    gradient: Gradient(colors: [Color.red.opacity(0.12), Color.black]),
                    center: .top,
                    startRadius: 2,
                    endRadius: 500
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header Status HUD
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cantonese Listener")
                                .font(.system(.title, design: .rounded))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                            
                            Text(sessionManager.isRecordingLocally ? "Session in Progress..." : "Ready to listen")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(sessionManager.isRecordingLocally ? .red : .secondary)
                        }
                        Spacer()
                        
                        // Status Indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(sessionManager.isRecordingLocally ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                                .shadow(color: sessionManager.isRecordingLocally ? .red : .green, radius: 4)
                            
                            Text(sessionManager.isRecordingLocally ? "RECORDING" : "STANDBY")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Main Start circular button with premium pulse animation
                    VStack {
                        Spacer()
                        
                        Button(action: {
                            if sessionManager.isRecordingLocally {
                                sessionManager.stopSession()
                            } else {
                                sessionManager.startSession()
                            }
                        }) {
                            ZStack {
                                // Double outer pulse rings
                                Circle()
                                    .stroke(sessionManager.isRecordingLocally ? Color.red.opacity(0.4) : Color.red.opacity(0.25), lineWidth: isPulseAnimating ? 20 : 2)
                                    .scaleEffect(isPulseAnimating ? 1.3 : 0.95)
                                    .opacity(isPulseAnimating ? 0.0 : 1.0)
                                    .animation(
                                        .easeInOut(duration: 2.0)
                                        .repeatForever(autoreverses: false),
                                        value: isPulseAnimating
                                    )
                                
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: sessionManager.isRecordingLocally ? [Color.red, Color.orange] : [Color.red.opacity(0.85), Color.red]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 140, height: 140)
                                    .shadow(color: .red.opacity(0.4), radius: 15)
                                
                                VStack(spacing: 8) {
                                    Image(systemName: sessionManager.isRecordingLocally ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 38, weight: .bold))
                                        .foregroundColor(.white)
                                        .scaleEffect(sessionManager.isRecordingLocally ? 0.9 : 1.0)
                                    
                                    Text(sessionManager.isRecordingLocally ? "Tap to Stop" : "Start Listening")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onAppear {
                            isPulseAnimating = true
                        }
                        
                        Spacer()
                    }
                    .frame(height: 200)
                    
                    // Recent Sessions Header
                    HStack {
                        Text("Recent Sessions")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // Session Cards Scroll view
                    if sessionManager.recentSessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.pencil.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.15))
                            
                            Text("No recorded sessions yet")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.secondary)
                            
                            Text("Tap the record button to capture daily conversations and practice listening.")
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
                        Text("• Processing...")
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
