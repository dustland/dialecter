import Foundation
import SwiftData
import SwiftUI
import UIKit
import OSLog

/// The central controller coordinating audio recording, Watch synchronization, database persistence, and processing pipeline on the iPhone.
@Observable
@MainActor
public final class SessionManager {
    
    private let logger = Logger(subsystem: "com.dustland.DialectListener", category: "SessionManager")
    
    // Core Dependencies
    public let connectivityManager: WatchConnectivityManager
    public let recorderManager: AudioRecorderManager
    public let asrService: ASRServiceProtocol
    public let translationService: TranslationServiceProtocol
    public let appSettings: AppSettings
    
    // SwiftData Context Holder
    private var modelContext: ModelContext?
    
    // UI State bindings
    public var activeSession: Session? = nil
    public var recentSessions: [Session] = []
    public var isRecordingLocally: Bool = false
    public var isPermissionsGranted: Bool = false
    public var liveTranscriptLines: [TranscriptLine] = []
    public var liveTranslationStatus: String = AppText.t("Waiting for speech...", "等待语音...")
    
    // Simulated timer for periodic status updates back to the watch
    private var watchSyncTimer: Timer?
    private var liveTranslationTask: Task<Void, Never>?
    private var lastTranslatedSnapshot: String = ""
    
    public init(
        connectivityManager: WatchConnectivityManager? = nil,
        recorderManager: AudioRecorderManager? = nil,
        asrService: ASRServiceProtocol? = nil,
        translationService: TranslationServiceProtocol? = nil,
        appSettings: AppSettings? = nil
    ) {
        self.connectivityManager = connectivityManager ?? WatchConnectivityManager()
        self.recorderManager = recorderManager ?? AudioRecorderManager()
        self.asrService = asrService ?? AppleASRService()
        self.translationService = translationService ?? SmartTranslationService()
        self.appSettings = appSettings ?? AppSettings()
        
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

            liveTranscriptLines = []
            liveTranslationStatus = AppText.t("Listening...", "倾听中...")
            lastTranslatedSnapshot = ""

            asrService.setLocaleIdentifier(appSettings.sourceLanguage.localeIdentifier)
            try asrService.startLiveTranscription { [weak self] result in
                Task { @MainActor in
                    self?.handleLiveTranscription(result)
                }
            }

            let liveASRService = asrService
            recorderManager.onAudioBuffer = { buffer in
                liveASRService.appendAudioBuffer(buffer)
            }

            // 1. Start audio recording and stream buffers into live ASR
            let fileURL = try recorderManager.startRecording(
                sessionId: sessionId,
                listeningMode: appSettings.listeningMode,
                micSensitivity: appSettings.micSensitivity
            )
            
            // 2. Save Session object in SwiftData database
            let session = Session(id: sessionId, startTime: Date(), audioFilePath: fileURL.lastPathComponent)
            modelContext?.insert(session)
            try modelContext?.save()
            
            // 3. Update active states
            self.activeSession = session
            self.isRecordingLocally = true
            UIApplication.shared.isIdleTimerDisabled = appSettings.keepScreenAwake
            
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
            recorderManager.onAudioBuffer = nil
            asrService.stopLiveTranscription()
            liveTranslationTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            
            // 2. Stop watch sync loop
            stopWatchSyncLoop()
            
            // 3. Update database entity with final details
            session.endTime = Date()
            session.duration = duration
            session.transcript = liveTranscriptLines
            session.isProcessed = !liveTranscriptLines.isEmpty
            try modelContext?.save()
            
            // 4. Transition UI and Connectivity back to idle after live processing
            connectivityManager.recordingState = .idle
            syncWatchState()
            
            self.isRecordingLocally = false
            self.activeSession = nil
            
            // Reload list
            fetchRecentSessions()
            
            logger.info("Session \(session.id) recording stopped. Duration: \(duration)s. Live transcript saved.")
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

    private func handleLiveTranscription(_ result: Result<LiveTranscriptionUpdate, Error>) {
        switch result {
        case .success(let update):
            liveTranscriptLines = mergedTranscriptLines(
                existing: liveTranscriptLines,
                incomingSegments: update.segments
            )
            scheduleLiveTranslation()
        case .failure(let error):
            liveTranslationStatus = AppText.t("Speech recognition paused", "语音识别已暂停") + ": \(error.localizedDescription)"
        }
    }

    private func mergedTranscriptLines(existing: [TranscriptLine], incomingSegments: [SpeechSegment]) -> [TranscriptLine] {
        var merged = existing

        for segment in incomingSegments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let index = merged.firstIndex(where: { isSameLiveSegment($0, segment) }) {
                let oldLine = merged[index]
                merged[index] = TranscriptLine(
                    id: oldLine.id,
                    startTimestamp: segment.start,
                    endTimestamp: segment.end,
                    dialectText: text,
                    translationText: oldLine.dialectText == text ? oldLine.translationText : ""
                )
            } else {
                merged.append(
                    TranscriptLine(
                        startTimestamp: segment.start,
                        endTimestamp: segment.end,
                        dialectText: text,
                        translationText: ""
                    )
                )
            }
        }

        return deduplicatedTranscriptLines(merged.sorted { $0.startTimestamp < $1.startTimestamp })
    }

    private func isSameLiveSegment(_ line: TranscriptLine, _ segment: SpeechSegment) -> Bool {
        let closeStart = abs(line.startTimestamp - segment.start) < 0.45
        let closeEnd = abs(line.endTimestamp - segment.end) < 0.8
        let sameText = line.dialectText == segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (closeStart && closeEnd) || (sameText && closeStart)
    }

    private func deduplicatedTranscriptLines(_ lines: [TranscriptLine]) -> [TranscriptLine] {
        var output: [TranscriptLine] = []
        for line in lines {
            if let last = output.last,
               last.dialectText == line.dialectText,
               abs(last.startTimestamp - line.startTimestamp) < 0.6 {
                if line.endTimestamp >= last.endTimestamp {
                    output[output.count - 1] = line.translationText.isEmpty && !last.translationText.isEmpty
                        ? TranscriptLine(
                            id: last.id,
                            startTimestamp: line.startTimestamp,
                            endTimestamp: line.endTimestamp,
                            dialectText: line.dialectText,
                            translationText: last.translationText
                        )
                        : line
                }
            } else {
                output.append(line)
            }
        }
        return output
    }

    private func scheduleLiveTranslation() {
        let snapshot = liveTranscriptLines
            .map(\.dialectText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard appSettings.liveTranslationEnabled, !snapshot.isEmpty, snapshot != lastTranslatedSnapshot else { return }
        liveTranslationStatus = AppText.t("Translating...", "翻译中...")
        liveTranslationTask?.cancel()

        liveTranslationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(1600))
                guard let self else { return }

                let lines = await MainActor.run { self.liveTranscriptLines }
                let segments = lines.map {
                    SpeechSegment(start: $0.startTimestamp, end: $0.endTimestamp, text: $0.dialectText)
                }
                let target = await MainActor.run { self.appSettings.translationTarget }
                let translatedLines = try await self.translationService.translate(segments, target: target)

                await MainActor.run {
                    self.liveTranscriptLines = self.mergedTranslatedLines(
                        current: self.liveTranscriptLines,
                        translated: translatedLines
                    )
                    self.lastTranslatedSnapshot = snapshot
                    self.liveTranslationStatus = AppText.t("Live translation", "实时翻译")
                    self.activeSession?.transcript = self.liveTranscriptLines
                    self.activeSession?.isProcessed = true
                    try? self.modelContext?.save()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.liveTranslationStatus = AppText.t("Using local translation fallback", "正在使用本地翻译")
                }
            }
        }
    }

    private func mergedTranslatedLines(current: [TranscriptLine], translated: [TranscriptLine]) -> [TranscriptLine] {
        current.map { line in
            guard let translatedLine = translated.first(where: { isSameTranscriptLine(line, $0) }) else {
                return line
            }

            return TranscriptLine(
                id: line.id,
                startTimestamp: line.startTimestamp,
                endTimestamp: line.endTimestamp,
                dialectText: line.dialectText,
                translationText: translatedLine.translationText
            )
        }
    }

    private func isSameTranscriptLine(_ lhs: TranscriptLine, _ rhs: TranscriptLine) -> Bool {
        normalizedTranscriptText(lhs.dialectText) == normalizedTranscriptText(rhs.dialectText)
    }

    private func normalizedTranscriptText(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Triggers speech-to-text and translation pipeline in a background task
    private func triggerAsyncProcessing(for session: Session) {
        Task(priority: .background) {
            let logger = Logger(subsystem: "com.dustland.DialectListener", category: "BackgroundASRTask")
            
            // Get full audio path on device
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioURL = documentDirectory.appendingPathComponent("Sessions").appendingPathComponent(session.audioFilePath)
            
            let lines: [TranscriptLine]
            
            do {
                // Step 1: Run native dialect ASR
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
                        dialectText: "[語音識別未能完成 / Audio Unrecognized]",
                        translationText: "[翻译暂不可用 / Translation Unavailable]"
                    )
                ]
            }
            
            // Step 3: Update SwiftData models on the main actor
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                let sessionId = session.id
                
                // Fetch fresh session reference in main context
                let fetchDescriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
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
