import Foundation
import Speech
import OSLog

/// A transcription segment returned by the ASR engine
public struct SpeechSegment: Identifiable {
    public let id: UUID = UUID()
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
}

/// Interface for speech-to-text transcription service
public protocol ASRServiceProtocol {
    func requestAuthorization() async -> Bool
    func transcribe(audioURL: URL) async throws -> [SpeechSegment]
}

/// Concrete implementation of Speech-to-Text using Apple's native SFSpeechRecognizer.
/// Configured for Cantonese (zh-HK) and supports fully offline, on-device transcription where available.
public final class AppleASRService: ASRServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.CantoneseListener", category: "AppleASRService")
    private let locale = Locale(identifier: "zh-HK") // Optimized for Hong Kong Cantonese
    
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
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            logger.error("Cantonese SFSpeechRecognizer could not be initialized.")
            throw NSError(domain: "AppleASRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cantonese Speech Recognizer is not supported on this device."])
        }
        
        guard recognizer.isAvailable else {
            logger.error("SFSpeechRecognizer is currently unavailable.")
            throw NSError(domain: "AppleASRService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech Recognition Service is unavailable."])
        }
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        // Request on-device offline recognition to protect privacy and run without cellular network
        request.requiresOnDeviceRecognition = true
        
        logger.info("Starting Cantonese ASR for file: \(audioURL.lastPathComponent)")
        
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
                    
                    self?.logger.info("Successfully transcribed \(segments.count) spoken segments in Cantonese.")
                    continuation.resume(returning: segments)
                }
            }
        }
    }
}
