import Foundation
import AVFoundation
import OSLog

/// Error cases for the Audio Recording Service
public enum AudioRecordingError: Error, LocalizedError {
    case permissionDenied
    case failedToInitializeSession
    case failedToStartRecorder(String)
    case notRecording
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is denied by the user."
        case .failedToInitializeSession:
            return "Failed to configure the system audio session."
        case .failedToStartRecorder(let reason):
            return "Could not start audio recorder: \(reason)"
        case .notRecording:
            return "Audio recorder is not currently recording."
        }
    }
}

/// Manages native iPhone audio recording using AVAudioEngine.
/// Optimized for speech ASR quality (16kHz, mono, AAC format) and handles background sessions.
@Observable
public final class AudioRecorderManager {
    
    private let logger = Logger(subsystem: "com.dustland.DialectListener", category: "AudioRecorderManager")
    
    public var isRecording: Bool = false
    public var currentDuration: TimeInterval = 0.0
    public var activeAudioURL: URL? = nil
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var startTime: Date?
    
    public init() {}
    
    /// Requests microphone permissions from the user.
    public func requestPermissions() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }
    
    /// Starts recording audio into a dedicated file for the specified session ID.
    @discardableResult
    public func startRecording(sessionId: UUID) throws -> URL {
        guard !isRecording else {
            logger.warning("Attempted to start recording while already recording.")
            throw AudioRecordingError.failedToStartRecorder("Already recording")
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Prefer far-field capture over call-style processing. Measurement mode keeps the
            // raw microphone signal closer to what the speech recognizer and saved file need.
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try audioSession.setPreferredSampleRate(48_000)
            try audioSession.setPreferredIOBufferDuration(0.02)
            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to configure AVAudioSession: \(error.localizedDescription)")
            throw AudioRecordingError.failedToInitializeSession
        }
        
        // Define directory to save audio files
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFolderURL = documentDirectory.appendingPathComponent("Sessions", isDirectory: true)
        
        // Ensure folder exists
        try? FileManager.default.createDirectory(at: audioFolderURL, withIntermediateDirectories: true, attributes: nil)
        
        let fileURL = audioFolderURL.appendingPathComponent("\(sessionId.uuidString).caf")
        
        do {
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                do {
                    try self.audioFile?.write(from: buffer)
                } catch {
                    self.logger.error("Failed to write live audio buffer: \(error.localizedDescription)")
                }
                self.onAudioBuffer?(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.audioFile = file
            self.isRecording = true
            self.activeAudioURL = fileURL
            self.startTime = Date()
            self.currentDuration = 0.0

            startTimer()

            logger.info("Successfully started live audio capture at URL: \(fileURL)")
            return fileURL
        } catch {
            logger.error("Failed to setup audio recorder: \(error.localizedDescription)")
            throw AudioRecordingError.failedToStartRecorder(error.localizedDescription)
        }
    }
    
    /// Stops the active recording session, cleans up the AVAudioSession, and returns the file URL and final duration.
    public func stopRecording() throws -> (URL, TimeInterval) {
        guard isRecording, let engine = audioEngine, let audioURL = activeAudioURL else {
            logger.warning("Attempted to stop recording when not recording.")
            throw AudioRecordingError.notRecording
        }
        
        stopTimer()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let duration = currentDuration
        
        // Deactivate audio session to release microphone
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        
        self.audioEngine = nil
        self.audioFile = nil
        self.isRecording = false
        self.activeAudioURL = nil
        self.currentDuration = 0.0
        self.startTime = nil
        
        logger.info("Successfully stopped recording. File size: \(self.getFileSize(at: audioURL)), Duration: \(duration) seconds")
        return (audioURL, duration)
    }
    
    // MARK: - Private Helpers
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            Task { @MainActor in
                self.currentDuration = Date().timeIntervalSince(start)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func getFileSize(at url: URL) -> String {
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = fileAttributes?[FileAttributeKey.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useKB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: fileSize)
        }
        return "Unknown size"
    }
}
