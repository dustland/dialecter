import Foundation
import WatchConnectivity
import OSLog

/// Watch-side recording state matching iPhone host state
public enum WatchRecordingState: String, Codable {
    case idle
    case recording
    case processing
    case error
}

/// Manages WatchConnectivity session on the Apple Watch.
/// Drives the Watch UI and communicates user gestures (Start/Stop/Mark) to the iPhone.
@Observable
@MainActor
public final class WatchConnectivityManagerWatch: NSObject {
    
    private let logger = Logger(subsystem: "com.dustland.DialectListener.watch", category: "WatchConnectivityManagerWatch")
    private var session: WCSession?
    
    // Observable states to drive Watch UI
    public var isReachable: Bool = false
    public var activeSessionId: UUID? = nil
    public var recordingState: WatchRecordingState = .idle
    public var currentDuration: TimeInterval = 0.0
    public var errorMessage: String? = nil
    
    // Internal timer to increment duration locally for fluid UI, calibrated by periodic iPhone syncs
    private var localTimer: Timer?
    private var lastSyncTime: Date = Date()
    
    public override init() {
        super.init()
        if WCSession.isSupported() {
            self.session = WCSession.default
            self.session?.delegate = self
            self.session?.activate()
            logger.info("WCSession initialized on Apple Watch.")
        } else {
            logger.error("WCSession is not supported on this Apple Watch device.")
        }
    }
    
    /// Starts a listening session on the iPhone.
    public func startSession() {
        let newSessionId = UUID()
        self.activeSessionId = newSessionId
        self.recordingState = .recording
        self.currentDuration = 0.0
        self.errorMessage = nil
        
        let payload: [String: Any] = [
            WatchConnectivityProtocol.Key.command: WatchConnectivityProtocol.WatchCommand.startSession,
            WatchConnectivityProtocol.Key.sessionId: newSessionId.uuidString
        ]
        
        sendImmediateMessage(payload) { [weak self] success in
            if success {
                self?.startLocalTimer()
                self?.triggerHaptic(.start)
            } else {
                self?.recordingState = .error
                self?.errorMessage = "Phone unreachable"
            }
        }
    }
    
    /// Stops the active listening session.
    public func stopSession() {
        self.recordingState = .processing
        stopLocalTimer()
        
        let payload: [String: Any] = [
            WatchConnectivityProtocol.Key.command: WatchConnectivityProtocol.WatchCommand.stopSession
        ]
        
        sendImmediateMessage(payload) { [weak self] success in
            if success {
                self?.triggerHaptic(.stop)
                // Go back to idle after successful stop acknowledgement
                self?.recordingState = .idle
                self?.activeSessionId = nil
                self?.currentDuration = 0.0
            } else {
                self?.recordingState = .error
                self?.errorMessage = "Failed to stop recording"
            }
        }
    }
    
    /// Adds a timestamped bookmark to the active session.
    public func addBookmark() {
        guard recordingState == .recording else { return }
        
        let timestamp = currentDuration
        let payload: [String: Any] = [
            WatchConnectivityProtocol.Key.command: WatchConnectivityProtocol.WatchCommand.addBookmark,
            WatchConnectivityProtocol.Key.timestamp: timestamp
        ]
        
        sendImmediateMessage(payload) { [weak self] success in
            if success {
                self?.triggerHaptic(.mark)
                self?.logger.info("Bookmark successfully requested at: \(timestamp)")
            } else {
                self?.logger.warning("Failed to sync bookmark timestamp to iPhone.")
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func sendImmediateMessage(_ message: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let session = session, session.isReachable else {
            logger.error("WCSession is not reachable. iPhone app might not be running.")
            completion(false)
            return
        }
        
        session.sendMessage(message, replyHandler: { reply in
            self.logger.debug("Received ACK from iPhone: \(reply)")
            completion(true)
        }, errorHandler: { error in
            self.logger.error("Error sending message: \(error.localizedDescription)")
            completion(false)
        })
    }
    
    private func startLocalTimer() {
        stopLocalTimer()
        lastSyncTime = Date()
        
        // Setup local UI ticker at 1 second intervals for fluid stopwatch
        localTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.recordingState == .recording {
                    self.currentDuration += 1.0
                }
            }
        }
    }
    
    private func stopLocalTimer() {
        localTimer?.invalidate()
        localTimer = nil
    }
    
    // Abstracted Haptics for Watch cues
    private enum HapticType {
        case start, stop, mark
    }
    
    private func triggerHaptic(_ type: HapticType) {
        #if os(watchOS)
        let device = WKInterfaceDevice.current()
        switch type {
        case .start:
            device.play(.start)
        case .stop:
            device.play(.stop)
        case .mark:
            device.play(.directionUp)
        }
        #endif
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManagerWatch: WCSessionDelegate {
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.logger.error("Watch WCSession activation failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.recordingState = .error
            } else {
                self.logger.info("Watch WCSession activated. State: \(activationState.rawValue)")
                self.isReachable = session.isReachable
            }
        }
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.logger.info("Watch WCSession reachability changed: \(session.isReachable)")
        }
    }
    
    /// Handles updates pushed from iPhone (e.g. status syncing, active state, actual duration calibration)
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let command = message[WatchConnectivityProtocol.Key.command] as? String else { return }
        
        Task { @MainActor in
            if command == WatchConnectivityProtocol.HostState.statusUpdate {
                let stateString = message[WatchConnectivityProtocol.Key.state] as? String ?? ""
                let duration = message[WatchConnectivityProtocol.Key.duration] as? Double ?? 0.0
                let sessionIdString = message[WatchConnectivityProtocol.Key.sessionId] as? String ?? ""
                
                // Align watch state with official iPhone state
                if let rawState = WatchRecordingState(rawValue: stateString.lowercased()) {
                    self.recordingState = rawState
                }
                
                self.currentDuration = duration
                self.activeSessionId = UUID(uuidString: sessionIdString)
                
                // Manage timer state based on iPhone sync state
                if self.recordingState == .recording {
                    if self.localTimer == nil {
                        self.startLocalTimer()
                    }
                } else {
                    self.stopLocalTimer()
                }
                
                self.logger.info("Watch state calibrated by iPhone: \(stateString), duration: \(duration)")
            }
        }
    }
}
