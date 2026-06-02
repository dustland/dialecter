import Foundation
import AVFoundation

public enum ASRLanguage: String, Codable {
    case cantonese
    case mandarin
    case english
    case unknown
}

public struct StreamingASREvent: Identifiable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let language: ASRLanguage
    public let confidence: Double?
    public let isFinal: Bool

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        language: ASRLanguage = .unknown,
        confidence: Double? = nil,
        isFinal: Bool
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.language = language
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

public protocol StreamingASRServiceProtocol: AnyObject {
    func requestAuthorization() async -> Bool
    func start(
        onEvent: @escaping (StreamingASREvent) -> Void,
        onError: @escaping (Error) -> Void
    ) throws
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func stop()
}

public final class AppleFallbackStreamingASRService: StreamingASRServiceProtocol {
    private let appleService: ASRServiceProtocol

    public init(appleService: ASRServiceProtocol = AppleASRService()) {
        self.appleService = appleService
    }

    public func requestAuthorization() async -> Bool {
        await appleService.requestAuthorization()
    }

    public func start(
        onEvent: @escaping (StreamingASREvent) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        try appleService.startLiveTranscription { result in
            switch result {
            case .success(let update):
                for segment in update.segments {
                    onEvent(
                        StreamingASREvent(
                            start: segment.start,
                            end: segment.end,
                            text: segment.text,
                            isFinal: update.isFinal
                        )
                    )
                }
            case .failure(let error):
                onError(error)
            }
        }
    }

    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        appleService.appendAudioBuffer(buffer)
    }

    public func stop() {
        appleService.stopLiveTranscription()
    }
}
