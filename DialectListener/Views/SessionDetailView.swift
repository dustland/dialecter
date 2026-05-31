import SwiftUI
import AVFoundation
import OSLog

/// Session detail playback and study page on iPhone.
/// Synchronizes dual-language transcripts with actual audio playback, highlighting current dialogue, and seeks via bookmarks.
public struct SessionDetailView: View {
    
    @Environment(\.dismiss) private var dismiss
    let session: Session
    
    // Playback Engine state
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: TimeInterval = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var playerTimer: Timer?
    
    // UI layout tracking
    @State private var activeLineId: UUID? = nil
    
    public var body: some View {
        ZStack {
            // Dark premium glassmorphism background
            Color.black.ignoresSafeArea()
            
            RadialGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.08), Color.black]),
                center: .bottom,
                startRadius: 2,
                endRadius: 500
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Nav Bar
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text("Review Session")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        // Action menu placeholder
                    }) {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.02))
                
                // Session Metadata Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.startTime.formatted(date: .long, time: .shortened))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        Label(formatDuration(session.duration), systemImage: "clock.fill")
                        Label("\(session.bookmarks.count) Bookmarks", systemImage: "bookmark.fill")
                        if session.isProcessed {
                            Label("Transcribed", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.white.opacity(0.03))
                
                // Active Study / Transcript Reader
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if !session.isProcessed {
                                VStack(spacing: 20) {
                                    ProgressView()
                                        .tint(.orange)
                                    Text("Unified speech recognition and translation is running in the background. Check back in a few seconds!")
                                        .font(.system(.body, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                .padding(.top, 100)
                            } else if session.transcript.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "mic.slash.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.white.opacity(0.2))
                                    Text("No speech recognized in this session.")
                                        .font(.system(.body, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 100)
                            } else {
                                // Time-Synced Dual Language Script View
                                ForEach(session.transcript) { line in
                                    TranscriptLineRow(
                                        line: line,
                                        isActive: currentTime >= line.startTimestamp && currentTime <= line.endTimestamp,
                                        onTap: {
                                            seekAudio(to: line.startTimestamp)
                                        }
                                    )
                                    .id(line.id)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical, 24)
                    }
                    .onChange(of: activeLineId) { _, newLineId in
                        if let lineId = newLineId {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                proxy.scrollTo(lineId, anchor: .center)
                            }
                        }
                    }
                }
                
                // Bookmarks Timeline strip (Horizontal)
                if !session.bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bookmarks TIMELINE")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(session.bookmarks.sorted(by: { $0.timestamp < $1.timestamp })) { bookmark in
                                    Button(action: {
                                        seekAudio(to: bookmark.timestamp)
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "bookmark.fill")
                                                .font(.caption2)
                                            Text(formatDuration(bookmark.timestamp))
                                                .font(.system(.caption, design: .monospaced))
                                                .fontWeight(.bold)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        )
                                        .cornerRadius(12)
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.01))
                }
                
                // Bottom Audio Player controller dock
                VStack(spacing: 12) {
                    // Timeline Scrubbing Bar
                    HStack(spacing: 12) {
                        Text(formatDuration(currentTime))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Slider(value: $currentTime, in: 0...max(0.1, session.duration)) { editing in
                            if !editing {
                                seekAudio(to: currentTime)
                            }
                        }
                        .tint(.blue)
                        
                        Text(formatDuration(session.duration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // Player Primary Buttons
                    HStack(spacing: 40) {
                        // Rate controller button
                        Button(action: {
                            cyclePlaybackRate()
                        }) {
                            Text(String(format: "%.1fx", playbackRate))
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .frame(width: 50)
                        }
                        
                        // Seek backward 5s
                        Button(action: {
                            seekAudio(to: currentTime - 5.0)
                        }) {
                            Image(systemName: "gobackward.5")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        // Play/Pause central trigger
                        Button(action: {
                            togglePlayback()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: .blue.opacity(0.3), radius: 8)
                                
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Seek forward 5s
                        Button(action: {
                            seekAudio(to: currentTime + 5.0)
                        }) {
                            Image(systemName: "goforward.5")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        // Spacer to align rate button
                        Spacer()
                            .frame(width: 50)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.top, 8)
                .background(Color.white.opacity(0.03))
            }
        }
        .onAppear {
            initializeAudioPlayer()
        }
        .onDisappear {
            stopPlayerTimer()
            audioPlayer?.stop()
        }
    }
    
    // MARK: - Playback Logic
    
    private func initializeAudioPlayer() {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentDirectory.appendingPathComponent("Sessions").appendingPathComponent(session.audioFilePath)
        
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.enableRate = true
            player.prepareToPlay()
            self.audioPlayer = player
        } catch {
            Logger(subsystem: "com.dustland.DialectListener", category: "DetailPlayback").error("Failed to load session audio: \(error.localizedDescription)")
        }
    }
    
    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
            stopPlayerTimer()
        } else {
            player.rate = playbackRate
            player.play()
            isPlaying = true
            startPlayerTimer()
        }
    }
    
    private func seekAudio(to timestamp: TimeInterval) {
        let clamped = max(0.0, min(timestamp, session.duration))
        currentTime = clamped
        
        if let player = audioPlayer {
            player.currentTime = clamped
        }
        
        // Calibrate active transcript lines based on seek
        updateActiveTranscriptLine()
    }
    
    private func cyclePlaybackRate() {
        let rates: [Float] = [0.8, 1.0, 1.25, 1.5]
        if let currentIdx = rates.firstIndex(of: playbackRate) {
            let nextIdx = (currentIdx + 1) % rates.count
            playbackRate = rates[nextIdx]
            
            if let player = audioPlayer {
                player.rate = playbackRate
            }
        }
    }
    
    private func startPlayerTimer() {
        stopPlayerTimer()
        playerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = audioPlayer {
                currentTime = player.currentTime
                updateActiveTranscriptLine()
                
                if !player.isPlaying && isPlaying {
                    // Playback finished naturally
                    isPlaying = false
                    stopPlayerTimer()
                    currentTime = 0.0
                }
            }
        }
    }
    
    private func stopPlayerTimer() {
        playerTimer?.invalidate()
        playerTimer = nil
    }
    
    private func updateActiveTranscriptLine() {
        guard session.isProcessed else { return }
        if let matchedLine = session.transcript.first(where: { currentTime >= $0.startTimestamp && currentTime <= $0.endTimestamp }) {
            if activeLineId != matchedLine.id {
                activeLineId = matchedLine.id
            }
        }
    }
    
    // Duration helper
    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Row Subviews

struct TranscriptLineRow: View {
    let line: TranscriptLine
    let isActive: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundColor(isActive ? .blue : .secondary.opacity(0.6))
                    
                    Text(formatDuration(line.startTimestamp))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(isActive ? .blue : .secondary.opacity(0.8))
                    
                    Spacer()
                }
                
                // Original dialect line
                Text(line.dialectText)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(isActive ? .blue : .white)
                    .multilineTextAlignment(.leading)
                
                // Written Chinese Translation Line
                Text(line.translationText)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(isActive ? .blue.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isActive ? Color.blue.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isActive ? Color.blue.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .scaleEffect(isActive ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    // Basic preview stub session
    let session = Session(audioFilePath: "mock.m4a")
    return SessionDetailView(session: session)
}
