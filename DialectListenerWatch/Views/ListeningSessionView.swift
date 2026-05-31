import SwiftUI

/// Active session view on Apple Watch.
/// Optimized for easy wrist-tapping with a massive "Mark" button and clear stopwatch.
public struct ListeningSessionView: View {
    
    @Bindable var connectivityManager: WatchConnectivityManagerWatch
    @Environment(\.dismiss) private var dismiss
    
    @State private var isWaveformAnimating = false
    
    public var body: some View {
        VStack(spacing: 8) {
            
            // Header: Duration and Waveform Ticker
            HStack(spacing: 8) {
                // Waveform micro-animation
                HStack(spacing: 2) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(connectivityManager.recordingState == .recording ? Color.red : Color.gray)
                            .frame(width: 3, height: isWaveformAnimating ? CGFloat.random(in: 6...18) : 8)
                            .animation(
                                connectivityManager.recordingState == .recording
                                ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(index) * 0.1)
                                : .default,
                                value: isWaveformAnimating
                            )
                    }
                }
                .frame(width: 24, height: 20)
                .onAppear {
                    if connectivityManager.recordingState == .recording {
                        isWaveformAnimating = true
                    }
                }
                .onChange(of: connectivityManager.recordingState) { _, newState in
                    isWaveformAnimating = (newState == .recording)
                }
                
                // Duration Counter
                Text(formatDuration(connectivityManager.currentDuration))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(.top, 4)
            
            Spacer()
            
            if connectivityManager.recordingState == .processing {
                // Processing screen
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.orange)
                    Text("Syncing session...")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
            } else {
                // Active Session Controls
                VStack(spacing: 10) {
                    // Massive "Mark" Button for easy access on wrist
                    Button(action: {
                        connectivityManager.addBookmark()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .font(.title3)
                            Text("Mark Point")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.indigo.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.2), radius: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Stop Button
                    Button(action: {
                        connectivityManager.stopSession()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .foregroundColor(.red)
                            Text("Stop")
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .transition(.move(edge: .bottom))
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .background(
            Color.black.ignoresSafeArea()
        )
        .navigationBarBackButtonHidden(true)
        .onChange(of: connectivityManager.activeSessionId) { _, activeId in
            // Automatically dismiss sheet once session ID becomes nil (e.g. stopped)
            if activeId == nil {
                dismiss()
            }
        }
    }
    
    // Format duration helper (mm:ss)
    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ListeningSessionView(connectivityManager: WatchConnectivityManagerWatch())
}
