import Foundation
import OSLog

/// Pluggable translation service to convert colloquial dialect text to written Mandarin Chinese.
public protocol TranslationServiceProtocol {
    func translate(_ segments: [SpeechSegment], target: TranslationTarget) async throws -> [TranscriptLine]
}

public extension TranslationServiceProtocol {
    func translate(_ segments: [SpeechSegment]) async throws -> [TranscriptLine] {
        try await translate(segments, target: .simplifiedChinese)
    }
}

/// A premium translation service using OpenRouter to produce high-fidelity written Chinese.
/// Understands slang, particles, English code-switching, and cultural context.
public final class OpenRouterTranslationService: TranslationServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.DialectListener", category: "OpenRouterTranslationService")
    private let apiKey: String?
    private let model: String
    
    public init(apiKey: String? = nil, model: String = "minimax/minimax-m3") {
        let configuredKey = apiKey
            ?? Bundle.main.object(forInfoDictionaryKey: "OpenRouterAPIKey") as? String
            ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        if let configuredKey, !configuredKey.isEmpty, !configuredKey.hasPrefix("$(") {
            self.apiKey = configuredKey
        } else {
            self.apiKey = nil
        }
        self.model = model
    }
    
    public func translate(_ segments: [SpeechSegment], target: TranslationTarget = .simplifiedChinese) async throws -> [TranscriptLine] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            logger.warning("OpenRouter API Key missing. Falling back to local translation engine.")
            throw NSError(domain: "OpenRouterTranslationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key Missing"])
        }
        
        guard !segments.isEmpty else { return [] }
        
        // Prepare segments payload
        let inputLines = segments.map { "[\($0.start)-\($0.end)]: \($0.text)" }.joined(separator: "\n")
        
        let prompt = """
        You are an expert translator for Chinese dialect learning.
        Translate the following timestamped sentence-level colloquial dialect lines into \(target.promptName).
        Do not explain. Preserve the exact time frames. Maintain the exact line count. Return one JSON object:
        {
          "translations": [
            {"start": 1.2, "end": 4.5, "dialect": "佢今日好似冇返工啵。", "translation": "他今天好像没上班。"}
          ]
        }

        Rules:
        - Each input line is already grouped as one spoken sentence or utterance.
        - Translate the whole utterance meaning, not word by word.
        - If the dialect is Cantonese, preserve the source as dialect and produce natural Mandarin/target language in translation.
        - Never copy the source dialect into translation unless the target language is the same.
        
        Segments to translate:
        \(inputLines)
        """
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Dialecter", forHTTPHeaderField: "X-Title")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenRouterTranslationService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid API response from OpenRouter server."])
        }
        
        struct OpenRouterResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        guard let jsonString = decoded.choices.first?.message.content else {
            throw NSError(domain: "OpenRouterTranslationService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to extract text from OpenRouter response."])
        }
        
        struct TranslatedItem: Codable {
            let start: Double
            let end: Double
            let dialect: String
            let translation: String
        }
        
        let jsonBytes = Data(jsonString.utf8)
        let items: [TranslatedItem]
        if let array = try? JSONDecoder().decode([TranslatedItem].self, from: jsonBytes) {
            items = array
        } else {
            struct WrappedResponse: Codable {
                let translations: [TranslatedItem]
            }
            items = try JSONDecoder().decode(WrappedResponse.self, from: jsonBytes).translations
        }
        
        return items.map { item in
            TranscriptLine(
                startTimestamp: item.start,
                endTimestamp: item.end,
                dialectText: item.dialect,
                translationText: item.translation
            )
        }
    }
}

/// Fallback dictionary-based translator for offline or mock operation.
/// Translates common colloquial dialect pronouns, auxiliary verbs, and particles into standard Mandarin Chinese.
public final class LocalRuleTranslationService: TranslationServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.DialectListener", category: "LocalRuleTranslationService")
    
    // Core mapping dictionary
    private let dict: [String: String] = [
        "佢": "他",
        "佢哋": "他们",
        "我哋": "我们",
        "你哋": "你们",
        "冇": "没有",
        "唔": "不",
        "係": "是",
        "乜": "什么",
        "邊個": "谁",
        "喺": "在",
        "返工": "上班",
        "放工": "下班",
        "食飯": "吃饭",
        "一陣": "一会儿",
        "睇": "看",
        "搵": "找",
        "㗎": "的",
        "喇": "了",
        "啵": "啊",
        "嘅": "的",
        "咗": "了",
        "咪": "别",
        "點樣": "怎样",
        "細路": "小孩",
        "屋企": "家",
        "車房": "车库"
    ]
    
    public init() {}
    
    public func translate(_ segments: [SpeechSegment], target: TranslationTarget = .simplifiedChinese) async throws -> [TranscriptLine] {
        logger.info("Executing local dictionary translation rule set.")
        
        // Simulating minor computation delay
        try? await Task.sleep(for: .milliseconds(300))
        
        return segments.map { segment in
            var translated = segment.text
            
            // Sort keys by descending length so "佢哋" is replaced before "佢"
            let sortedKeys = dict.keys.sorted { $0.count > $1.count }
            
            for key in sortedKeys {
                if let replacement = dict[key] {
                    translated = translated.replacingOccurrences(of: key, with: replacement)
                }
            }
            
            let output: String
            switch target {
            case .simplifiedChinese:
                output = translated
            case .traditionalChinese:
                output = translated.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? translated
            case .english:
                output = segment.text
            }

            return TranscriptLine(
                startTimestamp: segment.start,
                endTimestamp: segment.end,
                dialectText: segment.text,
                translationText: output
            )
        }
    }
}

/// Composite service which attempts OpenRouter if configured and falls back to LocalRule translation.
public final class SmartTranslationService: TranslationServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.DialectListener", category: "SmartTranslationService")
    private let remoteService: OpenRouterTranslationService
    private let localService: LocalRuleTranslationService
    
    public init(openRouterApiKey: String? = nil, model: String = "minimax/minimax-m3") {
        self.remoteService = OpenRouterTranslationService(apiKey: openRouterApiKey, model: model)
        self.localService = LocalRuleTranslationService()
    }
    
    public func translate(_ segments: [SpeechSegment], target: TranslationTarget = .simplifiedChinese) async throws -> [TranscriptLine] {
        // 1. Try OpenRouter first
        do {
            let results = try await remoteService.translate(segments, target: target)
            logger.info("SmartTranslation: Successfully completed via OpenRouter.")
            return results
        } catch {
            logger.warning("SmartTranslation: OpenRouter Translation skipped or failed (\(error.localizedDescription)). Falling back to local rules...")
        }

        // 2. Fallback to offline rule dictionary
        logger.info("SmartTranslation: Falling back to offline dictionary engine.")
        return try await localService.translate(segments, target: target)
    }
}
