import Foundation
import AVFoundation
import Speech
import OSLog

@Observable
public final class MandarinDictationManager {
    private let logger = Logger(subsystem: "com.dustland.Dialecter", category: "MandarinDictationManager")
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isFinishing = false

    public var isRecording = false
    public var transcript = ""

    public init() {}

    public func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return speechGranted && micGranted
    }

    public func start() throws {
        stop(cancelRecognition: true)
        transcript = ""
        isFinishing = false

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            throw NSError(domain: "MandarinDictationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mandarin speech recognition is unavailable."])
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                Task { @MainActor in
                    self?.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self?.cleanupAfterRecognition()
                    }
                }
            }

            if let error {
                self?.logger.error("Mandarin dictation failed: \(error.localizedDescription)")
                Task { @MainActor in
                    self?.stop(cancelRecognition: true)
                }
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        recognitionRequest = request
        isRecording = true
    }

    public func finish() {
        guard isRecording || recognitionRequest != nil else { return }
        isFinishing = true
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        audioEngine = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public func stop() {
        stop(cancelRecognition: true)
    }

    private func stop(cancelRecognition: Bool) {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        if cancelRecognition {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        isFinishing = false
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanupAfterRecognition() {
        guard isFinishing else { return }
        recognitionTask = nil
        isFinishing = false
    }
}
