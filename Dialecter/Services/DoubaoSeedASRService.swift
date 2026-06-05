import Foundation
import AVFoundation
import OSLog

public final class DoubaoSeedASRService: NSObject, StreamingASRServiceProtocol {
    private struct Config {
        let apiKey: String
        let resourceID: String

        static func load() throws -> Config {
            let bundle = Bundle.main
            let apiKey = bundle.object(forInfoDictionaryKey: "DoubaoASRAPIKey") as? String ?? ""
            let resourceID = bundle.object(forInfoDictionaryKey: "DoubaoASRResourceID") as? String ?? ""
            let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanResourceID = resourceID.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanAPIKey.isEmpty, !cleanAPIKey.hasPrefix("$(") else {
                throw NSError(domain: "DoubaoSeedASRService", code: 401, userInfo: [NSLocalizedDescriptionKey: AppText.t("Doubao ASR API key is missing.", "缺少豆包 ASR API Key。")])
            }
            guard !cleanResourceID.isEmpty, !cleanResourceID.hasPrefix("$(") else {
                throw NSError(domain: "DoubaoSeedASRService", code: 402, userInfo: [NSLocalizedDescriptionKey: AppText.t("Doubao ASR resource ID is missing.", "缺少豆包 ASR Resource ID。")])
            }

            return Config(apiKey: cleanAPIKey, resourceID: cleanResourceID)
        }
    }

    private struct ServerPayload: Decodable {
        struct Message: Decodable {
            struct Result: Decodable {
                struct Utterance: Decodable {
                    let definite: Bool?
                    let startTime: Int?
                    let endTime: Int?
                    let text: String

                    private enum CodingKeys: String, CodingKey {
                        case definite
                        case startTime = "start_time"
                        case endTime = "end_time"
                        case text
                    }
                }

                let text: String?
                let utterances: [Utterance]?
            }

            let result: Result?
            let error: String?
        }

        let result: Message.Result?
        let error: String?
    }

    private let logger = Logger(subsystem: "com.dustland.Dialecter", category: "DoubaoSeedASRService")
    private let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
    private let session = URLSession(configuration: .default)
    private let audioQueue = DispatchQueue(label: "com.dustland.Dialecter.doubao-audio")

    private var webSocketTask: URLSessionWebSocketTask?
    private var converter: AVAudioConverter?
    private var outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var pendingPCM = Data()
    private var sequence = 1
    private var emittedFinalTexts = Set<String>()
    private var onEvent: ((StreamingASREvent) -> Void)?
    private var onError: ((Error) -> Void)?
    private var isStopping = false

    public override init() {}

    public func requestAuthorization() async -> Bool {
        true
    }

    public func start(
        onEvent: @escaping (StreamingASREvent) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        stop()

        let config = try Config.load()
        self.onEvent = onEvent
        self.onError = onError
        self.sequence = 1
        self.pendingPCM = Data()
        self.emittedFinalTexts = []
        self.isStopping = false

        var request = URLRequest(url: endpoint)
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(config.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        receiveLoop()

        send(data: Self.fullClientRequest(sequence: sequence))
        sequence += 1
    }

    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        audioQueue.async { [weak self] in
            guard let self, !self.isStopping else { return }
            do {
                let pcm = try self.convertToPCM16(buffer)
                self.pendingPCM.append(pcm)
                self.flushPendingAudio(final: false)
            } catch {
                self.report(error)
            }
        }
    }

    public func stop() {
        isStopping = true
        audioQueue.async { [weak self] in
            guard let self else { return }
            if !self.pendingPCM.isEmpty {
                self.flushPendingAudio(final: false)
            }
            if let task = self.webSocketTask {
                let lastSequence = -max(self.sequence, 2)
                task.send(.data(Self.audioOnlyRequest(sequence: lastSequence, audio: Data()))) { [weak self] error in
                    if let error {
                        self?.report(error)
                    }
                    self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
                }
            }
            self.webSocketTask = nil
            self.converter = nil
            self.pendingPCM = Data()
        }
    }

    private func flushPendingAudio(final _: Bool) {
        let packetSize = 16_000 / 5 * 2
        while pendingPCM.count >= packetSize {
            let chunk = pendingPCM.prefix(packetSize)
            pendingPCM.removeFirst(packetSize)
            send(data: Self.audioOnlyRequest(sequence: sequence, audio: Data(chunk)))
            sequence += 1
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleServerFrame(data)
                case .string(let text):
                    self.logger.debug("Unexpected Doubao text frame: \(text)")
                @unknown default:
                    break
                }
                if !self.isStopping {
                    self.receiveLoop()
                }
            case .failure(let error):
                if !self.isStopping {
                    self.report(error)
                }
            }
        }
    }

    private func handleServerFrame(_ data: Data) {
        do {
            let frame = try Self.parseServerFrame(data)
            if let error = frame.error {
                throw NSError(domain: "DoubaoSeedASRService", code: frame.code ?? 500, userInfo: [NSLocalizedDescriptionKey: error])
            }

            guard let payload = frame.payload else { return }
            if let utterances = payload.utterances, !utterances.isEmpty {
                for utterance in utterances {
                    emit(utterance: utterance)
                }
            } else if let text = payload.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emit(text: text, start: 0, end: 0, isFinal: frame.isLastPackage)
            }
        } catch {
            report(error)
        }
    }

    private func emit(utterance: ServerPayload.Message.Result.Utterance) {
        let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let isFinal = utterance.definite ?? false
        if isFinal {
            guard !emittedFinalTexts.contains(text) else { return }
            emittedFinalTexts.insert(text)
        }

        emit(
            text: text,
            start: TimeInterval(utterance.startTime ?? 0) / 1000,
            end: TimeInterval(utterance.endTime ?? 0) / 1000,
            isFinal: isFinal
        )
    }

    private func emit(text: String, start: TimeInterval, end: TimeInterval, isFinal: Bool) {
        let event = StreamingASREvent(start: start, end: max(end, start), text: text, language: .unknown, isFinal: isFinal)
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    private func send(data: Data) {
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error {
                self?.report(error)
            }
        }
    }

    private func convertToPCM16(_ buffer: AVAudioPCMBuffer) throws -> Data {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }

        guard let converter else { return Data() }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            return Data()
        }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw conversionError
        }

        guard let channelData = outputBuffer.int16ChannelData else { return Data() }
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }

    private struct ParsedFrame {
        let isLastPackage: Bool
        let code: Int?
        let error: String?
        let payload: ServerPayload.Message.Result?
    }

    private static func fullClientRequest(sequence: Int) -> Data {
        let payload: [String: Any] = [
            "user": ["uid": "dialecter-ios"],
            "audio": [
                "format": "pcm",
                "rate": 16_000,
                "bits": 16,
                "channel": 1
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "show_utterances": true,
                "vad_segment": true,
                "end_window_size": 800,
                "result_type": "single"
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return makeFrame(messageType: 0x1, flags: 0x1, serialization: 0x1, sequence: sequence, payload: data)
    }

    private static func audioOnlyRequest(sequence: Int, audio: Data) -> Data {
        makeFrame(messageType: 0x2, flags: sequence < 0 ? 0x3 : 0x1, serialization: 0x1, sequence: sequence, payload: audio)
    }

    private static func makeFrame(messageType: UInt8, flags: UInt8, serialization: UInt8, sequence: Int, payload: Data) -> Data {
        var data = Data()
        data.append(0x11)
        data.append((messageType << 4) | flags)
        data.append(serialization << 4)
        data.append(0x00)
        data.appendInt32(sequence)
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private static func parseServerFrame(_ data: Data) throws -> (isLastPackage: Bool, code: Int?, error: String?, payload: ServerPayload.Message.Result?) {
        guard data.count >= 8 else {
            throw NSError(domain: "DoubaoSeedASRService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid ASR response frame."])
        }

        let headerSize = Int(data[0] & 0x0F) * 4
        let messageType = data[1] >> 4
        var offset = headerSize

        if messageType == 0xF {
            guard data.count >= offset + 8 else {
                throw NSError(domain: "DoubaoSeedASRService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid ASR error frame."])
            }
            let code = Int(data.readInt32(at: offset))
            offset += 4
            let size = Int(data.readUInt32(at: offset))
            offset += 4
            let payloadData = data.subdata(in: offset..<min(offset + size, data.count))
            let message = String(data: payloadData, encoding: .utf8) ?? "ASR server error"
            return (false, code, message, nil)
        }

        guard data.count >= offset + 4 else {
            throw NSError(domain: "DoubaoSeedASRService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid ASR response payload."])
        }

        let flags = data[1] & 0x0F
        let isLastPackage = flags == 0x2 || flags == 0x3

        if flags == 0x1 || flags == 0x3 {
            guard data.count >= offset + 4 else {
                throw NSError(domain: "DoubaoSeedASRService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid ASR response sequence."])
            }
            offset += 4
        }

        let size = Int(data.readUInt32(at: offset))
        offset += 4
        guard size > 0, offset + size <= data.count else {
            return (isLastPackage, nil, nil, nil)
        }

        let payloadData = data.subdata(in: offset..<offset + size)
        let jsonObject = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let messageObject = jsonObject?["result"] as? [String: Any] != nil
            ? ["result": jsonObject?["result"] as Any]
            : jsonObject?["message"] as? [String: Any]
        let normalizedData = try JSONSerialization.data(withJSONObject: messageObject ?? [:])
        let decoded = try JSONDecoder().decode(ServerPayload.Message.self, from: normalizedData)
        return (isLastPackage, nil, decoded.error, decoded.result)
    }
}

private extension Data {
    mutating func appendInt32(_ value: Int) {
        var bigEndian = Int32(value).bigEndian
        append(Data(bytes: &bigEndian, count: MemoryLayout<Int32>.size))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size))
    }

    func readInt32(at offset: Int) -> Int32 {
        let value = self[offset..<offset + 4].reduce(Int32(0)) { ($0 << 8) | Int32($1) }
        return value
    }

    func readUInt32(at offset: Int) -> UInt32 {
        self[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
