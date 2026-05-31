import Foundation

/// Defines standard message keys and commands for communication between Apple Watch and iPhone.
public enum WatchConnectivityProtocol {
    
    /// Standard payload dictionary keys
    public enum Key {
        public static let command = "command"
        public static let sessionId = "sessionId"
        public static let timestamp = "timestamp"
        public static let state = "state"
        public static let duration = "duration"
        public static let errorMessage = "errorMessage"
    }
    
    /// Commands initiated by the Apple Watch
    public enum WatchCommand {
        /// Starts a new listening session on the iPhone.
        /// Payload: `[Key.command: WatchCommand.startSession, Key.sessionId: UUIDString]`
        public static let startSession = "START_SESSION"
        
        /// Stops the current listening session on the iPhone.
        /// Payload: `[Key.command: WatchCommand.stopSession]`
        public static let stopSession = "STOP_SESSION"
        
        /// Records a bookmark timestamp relative to session start.
        /// Payload: `[Key.command: WatchCommand.addBookmark, Key.timestamp: Double]`
        public static let addBookmark = "ADD_BOOKMARK"
    }
    
    /// Status payloads sent from iPhone back to Apple Watch
    public enum HostState {
        public static let idle = "IDLE"
        public static let recording = "RECORDING"
        public static let processing = "PROCESSING"
        public static let error = "ERROR"
    }
}
