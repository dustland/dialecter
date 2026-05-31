import Foundation
import SwiftData
import SwiftUI
import OSLog

/// The central controller coordinating audio recording, Watch synchronization, database persistence, and processing pipeline on the iPhone.
@Observable
@MainActor
public final class SessionManager {
    
    private let logger = Logger(subsystem: "com.dustland.CantoneseListener", category: "SessionManager")
    
    // Core Dependencies
    public let connectivityManager: WatchConnectivityManager
    public let recorderManager: AudioRecorderManager
    public let asrService: ASRServiceProtocol
    public let translationService: TranslationServiceProtocol
    
    // SwiftData Context Holder
    private var modelContext: ModelContext?
    
    // UI State bindings
    public var activeSession: Session? = nil
    public var recentSessions: [Session] = []
    public var isRecordingLocally: Bool = false
    public var isPermissionsGranted: Bool = false
    
    // Simulated timer for periodic status updates back to the watch
    private var watchSyncTimer: Timer?
    
    public init(
        connectivityManager: WatchConnectivityManager = WatchConnectivityManager(),
        recorderManager: AudioRecorderManager = AudioRecorderManager(),
        asrService: ASRServiceProtocol = AppleASRService(),
        translationService: TranslationServiceProtocol = SmartTranslationService()
    ) {
        self.connectivityManager = connectivityManager
        self.recorderManager = recorderManager
        self.asrService = asrService
        self.translationService = translationService
        
        setupConnectivityCallbacks()
        checkPermissions()
    }
    
    /// Sets the SwiftData modelContext and loads initial recent sessions.
    public func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        fetchRecentSessions()
    }
    
    /// Checks and requests microphone and speech permissions.
    public func checkPermissions() {
        Task {
            let micGranted = await recorderManager.requestPermissions()
            let speechGranted = await asrService.requestAuthorization()
            await MainActor.run {
                self.isPermissionsGranted = micGranted && speechGranted
                self.logger.info("Microphone and Speech permissions checked. Combined Status: \(self.isPermissionsGranted)")
            }
        }
    }
    
    // MARK: - Core Business Logic
    
    /// Triggers the start of a session (initiated locally from the iPhone UI or remotely from the Watch)
    public func startSession(sessionId: UUID = UUID()) {
        guard isPermissionsGranted else {
            logger.error("Cannot start session: Permissions are missing.")
            connectivityManager.sendStatusUpdate(state: .error, duration: 0, sessionId: nil)
            return
        }
        
        do {
            logger.info("Starting new session with ID: \(sessionId)")
            
            // 1. Start audio recording
            let fileURL = try recorderManager.startRecording(sessionId: sessionId)
            
            // 2. Save Session object in SwiftData database
            let session = Session(id: sessionId, startTime: Date(), audioFilePath: fileURL.lastPathComponent)
            modelContext?.insert(session)
            try modelContext?.save()
            
            // 3. Update active states
            self.activeSession = session
            self.isRecordingLocally = true
            
            // 4. Calibrate Connectivity Manager
            connectivityManager.activeSessionId = sessionId
            connectivityManager.recordingState = .recording
            
            // 5. Start Watch sync loop
            startWatchSyncLoop()
            
            // Immediately sync status back to Watch
            syncWatchState()
            
            logger.info("Session \(sessionId) successfully initialized and persist-saved.")
        } catch {
            logger.error("Failed to start session: \(error.localizedDescription)")
            connectivityManager.errorMessage = error.localizedDescription
            connectivityManager.recordingState = .error
        }
    }
    
    /// Stops the active session, saves database metadata, and triggers background processing.
    public func stopSession() {
        guard isRecordingLocally, let session = activeSession else {
            logger.warning("Stop session requested but no active session is recording.")
            return
        }
        
        do {
            logger.info("Stopping session: \(session.id)")
            
            // 1. Stop audio recorder
            let (_, duration) = try recorderManager.stopRecording()
            
            // 2. Stop watch sync loop
            stopWatchSyncLoop()
            
            // 3. Update database entity with final details
            session.endTime = Date()
            session.duration = duration
            try modelContext?.save()
            
            // 4. Transition UI and Connectivity to processing mode
            connectivityManager.recordingState = .processing
            syncWatchState()
            
            self.isRecordingLocally = false
            self.activeSession = nil
            
            // Reload list
            fetchRecentSessions()
            
            // 5. Trigger ASR and translation processing
            triggerAsyncProcessing(for: session)
            
            logger.info("Session \(session.id) recording stopped. Duration: \(duration)s. Triggered background transcription.")
        } catch {
            logger.error("Failed to stop session cleanly: \(error.localizedDescription)")
        }
    }
    
    /// Adds a bookmark point relative to session start
    public func addBookmark(at timeOffset: TimeInterval) {
        guard let session = activeSession else {
            logger.warning("Attempted to add bookmark but no active session is running.")
            return
        }
        
        let bookmark = Bookmark(timestamp: timeOffset)
        bookmark.session = session
        session.bookmarks.append(bookmark)
        
        do {
            try modelContext?.save()
            logger.info("Bookmark created at \(timeOffset) seconds inside session: \(session.id)")
        } catch {
            logger.error("Failed to save bookmark in database: \(error.localizedDescription)")
        }
    }
    
    /// Deletes a specific session and its associated audio file and bookmarks.
    public func deleteSession(_ session: Session) {
        // Delete audio file
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentDirectory.appendingPathComponent("Sessions").appendingPathComponent(session.audioFilePath)
        try? FileManager.default.removeItem(at: fileURL)
        
        // Remove from SwiftData (cascades bookmarks automatically)
        modelContext?.delete(session)
        try? modelContext?.save()
        
        fetchRecentSessions()
        logger.info("Deleted session and local file: \(session.audioFilePath)")
    }
    
    // MARK: - Private Implementations
    
    private func setupConnectivityCallbacks() {
        connectivityManager.onStartSessionRequested = { [weak self] sessionId in
            self?.startSession(sessionId: sessionId)
        }
        
        connectivityManager.onStopSessionRequested = { [weak self] in
            self?.stopSession()
        }
        
        connectivityManager.onAddBookmarkRequested = { [weak self] timeOffset in
            self?.addBookmark(at: timeOffset)
        }
    }
    
    private func fetchRecentSessions() {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        do {
            self.recentSessions = try modelContext.fetch(descriptor)
            logger.debug("Successfully loaded \(self.recentSessions.count) recent sessions.")
        } catch {
            logger.error("Failed to fetch sessions from SwiftData: \(error.localizedDescription)")
        }
    }
    
    private func startWatchSyncLoop() {
        stopWatchSyncLoop()
        
        // Sync active duration to watch every 2.5 seconds to keep it calibrated and preserve battery
        watchSyncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isRecordingLocally {
                    self.syncWatchState()
                }
            }
        }
    }
    
    private func stopWatchSyncLoop() {
        watchSyncTimer?.invalidate()
        watchSyncTimer = nil
    }
    
    private func syncWatchState() {
        let duration = recorderManager.currentDuration
        connectivityManager.sendStatusUpdate(
            state: connectivityManager.recordingState,
            duration: duration,
            sessionId: connectivityManager.activeSessionId
        )
    }
    
    /// Triggers speech-to-text and translation pipeline in a background task
    private func triggerAsyncProcessing(for session: Session) {
        Task.detached(priority: .background) {
            let logger = Logger(subsystem: "com.dustland.CantoneseListener", category: "BackgroundASRTask")
            
            // Get full audio path on device
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioURL = documentDirectory.appendingPathComponent("Sessions").appendingPathComponent(session.audioFilePath)
            
            var lines: [TranscriptLine] = []
            
            do {
                // Step 1: Run native Cantonese ASR
                let segments = try await self.asrService.transcribe(audioURL: audioURL)
                
                // Step 2: Run translation (smart fallback routing)
                lines = try await self.translationService.translate(segments)
                logger.info("Successfully completed ASR and translation for session: \(session.id)")
            } catch {
                logger.error("Background ASR or translation failed: \(error.localizedDescription). Generating graceful fallback...")
                
                // Graceful fallback in case of errors (e.g. no speech segments, simulator testing)
                lines = [
                    TranscriptLine(
                        startTimestamp: 0.0,
                        endTimestamp: 2.0,
                        cantoneseText: "[語音識別未能完成 / Audio Unrecognized]",
                        translationText: "[翻译暂不可用 / Translation Unavailable]"
                    )
                ]
            }
            
            // Step 3: Update SwiftData models on the main actor
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // Fetch fresh session reference in main context
                let fetchDescriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == session.id })
                if let freshSession = try? self.modelContext?.fetch(fetchDescriptor).first {
                    
                    freshSession.transcript = lines
                    freshSession.isProcessed = true
                    
                    try? self.modelContext?.save()
                    self.logger.info("Session \(freshSession.id) database entry successfully updated with transcripts.")
                    
                    // Reset Watch connectivity status
                    self.connectivityManager.recordingState = .idle
                    self.connectivityManager.activeSessionId = nil
                    self.syncWatchState()
                    
                    // Refresh session list
                    self.fetchRecentSessions()
                }
            }
        }
    }
}
