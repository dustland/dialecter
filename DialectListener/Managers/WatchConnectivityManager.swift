import Foundation
import WatchConnectivity
import OSLog

/// State of the host iPhone recording app
public enum RecordingState: String, Codable {
    case idle
    case recording
    case processing
    case error
}

/// Manages WatchConnectivity session on the iPhone.
/// Acts as the bridge between Watch commands and local iPhone recording/data operations.
@Observable
@MainActor
public final class WatchConnectivityManager: NSObject {
    
    private let logger = Logger(subsystem: "com.dustland.DialectListener", category: "WatchConnectivityManager")
    private var session: WCSession?
    
    // Observable states to drive SwiftUI views
    public var isWatchSupported: Bool = false
    public var isReachable: Bool = false
    public var activeSessionId: UUID? = nil
    public var recordingState: RecordingState = .idle
    public var currentDuration: TimeInterval = 0.0
    public var errorMessage: String? = nil
    
    // Closures to be wired by the App/Coordinator for business logic execution
    public var onStartSessionRequested: ((UUID) -> Void)?
    public var onStopSessionRequested: (() -> Void)?
    public var onAddBookmarkRequested: ((TimeInterval) -> Void)?
    
    public override init() {
        super.init()
        self.isWatchSupported = WCSession.isSupported()
        if isWatchSupported {
            self.session = WCSession.default
            self.session?.delegate = self
            self.session?.activate()
            logger.info("WatchConnectivity session initialized on iPhone.")
        } else {
            logger.warning("WatchConnectivity is not supported on this iPhone device.")
        }
    }
    
    /// Sends a status update payload back to the Apple Watch to keep it synchronized.
    public func sendStatusUpdate(state: RecordingState, duration: TimeInterval, sessionId: UUID?) {
        guard let session = session, session.isReachable else {
            logger.debug("Cannot send status update: WCSession is not reachable.")
            return
        }
        
        let payload: [String: Any] = [
            WatchConnectivityProtocol.Key.command: WatchConnectivityProtocol.HostState.statusUpdate,
            WatchConnectivityProtocol.Key.state: state.rawValue,
            WatchConnectivityProtocol.Key.duration: duration,
            WatchConnectivityProtocol.Key.sessionId: sessionId?.uuidString ?? ""
        ]
        
        session.sendMessage(payload, replyHandler: nil) { [weak self] error in
            self?.logger.error("Failed to send status update to watch: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.logger.error("WCSession activation failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.recordingState = .error
            } else {
                self.logger.info("WCSession activated successfully. State: \(activationState.rawValue)")
                self.isReachable = session.isReachable
            }
        }
    }
    
    public func sessionDidBecomeInactive(_ session: WCSession) {
        logger.info("WCSession became inactive.")
    }
    
    public func sessionDidDeactivate(_ session: WCSession) {
        logger.info("WCSession deactivated. Reactivating session...")
        // Required for multi-watch switching
        WCSession.default.activate()
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.logger.info("WCSession reachability changed to: \(session.isReachable)")
        }
    }
    
    /// Handles incoming immediate messages from the Apple Watch
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.info("Received message from Watch: \(message)")
        
        guard let command = message[WatchConnectivityProtocol.Key.command] as? String else {
            replyHandler([WatchConnectivityProtocol.Key.command: "ERROR", "message": "Missing command key"])
            return
        }
        
        Task { @MainActor in
            switch command {
            case WatchConnectivityProtocol.WatchCommand.startSession:
                let sessionIdString = message[WatchConnectivityProtocol.Key.sessionId] as? String ?? ""
                let sessionId = UUID(uuidString: sessionIdString) ?? UUID()
                
                self.activeSessionId = sessionId
                self.recordingState = .recording
                self.logger.info("Watch requested START_SESSION with ID: \(sessionId)")
                
                // Fire callback to start local recording
                self.onStartSessionRequested?(sessionId)
                
                replyHandler([WatchConnectivityProtocol.Key.command: "ACK"])
                
            case WatchConnectivityProtocol.WatchCommand.stopSession:
                self.logger.info("Watch requested STOP_SESSION")
                
                // Fire callback to stop local recording
                self.onStopSessionRequested?()
                
                self.recordingState = .processing
                replyHandler([WatchConnectivityProtocol.Key.command: "ACK"])
                
            case WatchConnectivityProtocol.WatchCommand.addBookmark:
                let timestamp = message[WatchConnectivityProtocol.Key.timestamp] as? Double ?? 0.0
                self.logger.info("Watch requested ADD_BOOKMARK at timestamp: \(timestamp)")
                
                // Fire callback to add a bookmark in active session
                self.onAddBookmarkRequested?(timestamp)
                
                replyHandler([WatchConnectivityProtocol.Key.command: "ACK"])
                
            default:
                self.logger.warning("Unknown command received from watch: \(command)")
                replyHandler([WatchConnectivityProtocol.Key.command: "ERROR", "message": "Unknown command"])
            }
        }
    }
}
