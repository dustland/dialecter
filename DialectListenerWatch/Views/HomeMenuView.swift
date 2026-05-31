import SwiftUI

/// Main menu view on the Apple Watch.
/// Shows status of connectivity and holds the primary CTA to trigger a recording session.
public struct HomeMenuView: View {
    
    @State private var connectivityManager = WatchConnectivityManagerWatch()
    @State private var isPulseAnimating = false
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()
                
                // Status HUD
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectivityManager.isReachable ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .shadow(color: connectivityManager.isReachable ? .green.opacity(0.5) : .clear, radius: 4)
                    
                    Text(connectivityManager.isReachable ? "Connected to iPhone" : "iPhone Disconnected")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                
                Spacer()
                
                // Primary Action Button (Start)
                Button(action: {
                    connectivityManager.startSession()
                }) {
                    ZStack {
                        // Ambient Pulse Effect
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: isPulseAnimating ? 12 : 2)
                            .scaleEffect(isPulseAnimating ? 1.2 : 0.95)
                            .opacity(isPulseAnimating ? 0.0 : 0.8)
                            .animation(
                                .easeInOut(duration: 1.8)
                                .repeatForever(autoreverses: false),
                                value: isPulseAnimating
                            )
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.red.opacity(0.8), Color.orange.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .red.opacity(0.3), radius: 6)
                        
                        VStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Start")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 90, height: 90)
                }
                .buttonStyle(PlainButtonStyle())
                .onAppear {
                    isPulseAnimating = true
                }
                
                Spacer()
            }
            .navigationTitle("Dialect Listener")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                // Elegant dark background with atmospheric radial glow
                RadialGradient(
                    gradient: Gradient(colors: [Color.red.opacity(0.08), Color.black]),
                    center: .center,
                    startRadius: 2,
                    endRadius: 100
                )
            )
            .sheet(isPresented: Binding(
                get: { connectivityManager.recordingState == .recording || connectivityManager.recordingState == .processing },
                set: { _ in }
            )) {
                ListeningSessionView(connectivityManager: connectivityManager)
            }
        }
    }
}

#Preview {
    HomeMenuView()
}
