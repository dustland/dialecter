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

    private let logger = Logger(subsystem: "com.dustland.Dialecter", category: "AudioRecorderManager")

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
    public func startRecording(
        sessionId: UUID,
        listeningMode: ListeningMode = .meeting,
        micSensitivity: MicSensitivity = .high
    ) throws -> URL {
        guard !isRecording else {
            logger.warning("Attempted to start recording while already recording.")
            throw AudioRecordingError.failedToStartRecorder("Already recording")
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try configureAudioSession(
                audioSession,
                listeningMode: listeningMode,
                micSensitivity: micSensitivity
            )
            try audioSession.setActive(true)
            configureFarFieldInputIfNeeded(
                audioSession,
                listeningMode: listeningMode,
                micSensitivity: micSensitivity
            )
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

            inputNode.installTap(onBus: 0, bufferSize: bufferSize(for: micSensitivity), format: format) { [weak self] buffer, _ in
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

    private func configureAudioSession(
        _ audioSession: AVAudioSession,
        listeningMode: ListeningMode,
        micSensitivity: MicSensitivity
    ) throws {
        switch listeningMode {
        case .standard:
            try audioSession.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP])
        case .ambient, .meeting:
            // Measurement mode keeps the raw microphone signal closer to what distant
            // speech recognition and saved review audio need. Do not allow Bluetooth
            // HFP here: headset mics commonly apply close-talk beamforming/noise
            // suppression, which is exactly what makes nearby voices disappear.
            try audioSession.setCategory(.record, mode: .measurement, options: [])
        }

        switch micSensitivity {
        case .low:
            try audioSession.setPreferredSampleRate(16_000)
            try audioSession.setPreferredIOBufferDuration(0.04)
        case .medium:
            try audioSession.setPreferredSampleRate(44_100)
            try audioSession.setPreferredIOBufferDuration(0.03)
        case .high:
            try audioSession.setPreferredSampleRate(48_000)
            try audioSession.setPreferredIOBufferDuration(0.02)
        }
    }

    private func configureFarFieldInputIfNeeded(
        _ audioSession: AVAudioSession,
        listeningMode: ListeningMode,
        micSensitivity: MicSensitivity
    ) {
        guard listeningMode != .standard else {
            applyInputGain(audioSession, micSensitivity: micSensitivity)
            return
        }

        if let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? audioSession.setPreferredInput(builtInMic)
            configureWidePickupPattern(for: builtInMic)
        }

        applyInputGain(audioSession, micSensitivity: micSensitivity)
    }

    private func configureWidePickupPattern(for input: AVAudioSessionPortDescription) {
        let usableSources = input.dataSources ?? []
        let preferredSource = usableSources.first { source in
            source.supportedPolarPatterns?.contains(.omnidirectional) == true
        } ?? usableSources.first

        guard let preferredSource else { return }

        try? preferredSource.setPreferredPolarPattern(.omnidirectional)
        try? input.setPreferredDataSource(preferredSource)
    }

    private func applyInputGain(_ audioSession: AVAudioSession, micSensitivity: MicSensitivity) {
        guard audioSession.isInputGainSettable else { return }

        let gain: Float
        switch micSensitivity {
        case .low:
            gain = 0.45
        case .medium:
            gain = 0.7
        case .high:
            gain = 1.0
        }

        try? audioSession.setInputGain(gain)
    }

    private func bufferSize(for sensitivity: MicSensitivity) -> AVAudioFrameCount {
        switch sensitivity {
        case .low: 2048
        case .medium: 1536
        case .high: 1024
        }
    }

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
