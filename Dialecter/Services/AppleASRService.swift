import Foundation
import AVFoundation
import Speech
import OSLog

/// A transcription segment returned by the ASR engine
public struct SpeechSegment: Identifiable {
    public let id: UUID = UUID()
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Incremental speech recognition update emitted while recording is active.
public struct LiveTranscriptionUpdate {
    public let segments: [SpeechSegment]
    public let isFinal: Bool
}

/// Interface for speech-to-text transcription service
public protocol ASRServiceProtocol {
    func requestAuthorization() async -> Bool
    func transcribe(audioURL: URL) async throws -> [SpeechSegment]
    func startLiveTranscription(onUpdate: @escaping (Result<LiveTranscriptionUpdate, Error>) -> Void) throws
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func stopLiveTranscription()
    func setLocaleIdentifier(_ identifier: String)
}

/// Concrete implementation of speech-to-text using Apple's native SFSpeechRecognizer.
/// Defaults to the Hong Kong Chinese locale and supports fully offline, on-device transcription where available.
public final class AppleASRService: ASRServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.Dialecter", category: "AppleASRService")
    private var localeIdentifier = "zh-HK"
    private var liveRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var liveRecognitionTask: SFSpeechRecognitionTask?
    
    public init() {}
    
    /// Requests speech recognition authorization from the user
    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    continuation.resume(returning: true)
                default:
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Asynchronously transcribes a local audio file and returns a list of time-stamped speech segments.
    public func transcribe(audioURL: URL) async throws -> [SpeechSegment] {
        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            logger.error("SFSpeechRecognizer could not be initialized for locale \(locale.identifier).")
            throw NSError(domain: "AppleASRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not supported for the selected dialect on this device."])
        }
        
        guard recognizer.isAvailable else {
            logger.error("SFSpeechRecognizer is currently unavailable.")
            throw NSError(domain: "AppleASRService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech Recognition Service is unavailable."])
        }
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true
        
        logger.info("Starting dialect ASR for file: \(audioURL.lastPathComponent)")
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    self?.logger.error("SFSpeechRecognizer recognition task failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else {
                    self?.logger.warning("No speech recognition results returned.")
                    continuation.resume(returning: [])
                    return
                }
                
                if result.isFinal {
                    let bestTranscription = result.bestTranscription
                    var segments: [SpeechSegment] = []
                    
                    // SFSpeechRecognizer provides segment-by-segment details including timestamps
                    for segment in bestTranscription.segments {
                        let text = segment.substring
                        let start = segment.timestamp
                        let duration = segment.duration
                        let end = start + duration
                        
                        // Ignore empty speech intervals
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        
                        segments.append(SpeechSegment(start: start, end: end, text: text))
                    }
                    
                    self?.logger.info("Successfully transcribed \(segments.count) spoken segments.")
                    continuation.resume(returning: segments)
                }
            }
        }
    }

    /// Starts a streaming recognizer. Audio buffers must be supplied through appendAudioBuffer(_:).
    public func startLiveTranscription(onUpdate: @escaping (Result<LiveTranscriptionUpdate, Error>) -> Void) throws {
        stopLiveTranscription()

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw NSError(domain: "AppleASRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not supported for the selected dialect on this device."])
        }

        guard recognizer.isAvailable else {
            throw NSError(domain: "AppleASRService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech Recognition Service is unavailable."])
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        liveRecognitionRequest = request
        liveRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error = error {
                self?.logger.error("Live speech recognition failed: \(error.localizedDescription)")
                onUpdate(.failure(error))
                return
            }

            guard let result = result else { return }
            let segments = Self.makeSegments(from: result.bestTranscription)
            onUpdate(.success(LiveTranscriptionUpdate(segments: segments, isFinal: result.isFinal)))
        }
    }

    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        liveRecognitionRequest?.append(buffer)
    }

    public func stopLiveTranscription() {
        liveRecognitionRequest?.endAudio()
        liveRecognitionTask?.cancel()
        liveRecognitionRequest = nil
        liveRecognitionTask = nil
    }

    public func setLocaleIdentifier(_ identifier: String) {
        localeIdentifier = identifier
    }

    private static func makeSegments(from transcription: SFTranscription) -> [SpeechSegment] {
        transcription.segments.compactMap { segment in
            let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SpeechSegment(
                start: segment.timestamp,
                end: segment.timestamp + segment.duration,
                text: text
            )
        }
    }
}
