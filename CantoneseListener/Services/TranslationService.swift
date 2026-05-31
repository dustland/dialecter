import Foundation
import OSLog
#if canImport(Translation)
import Translation
#endif

/// Pluggable translation service to convert Cantonese colloquial text to Written Mandarin Chinese.
public protocol TranslationServiceProtocol {
    func translate(_ segments: [SpeechSegment]) async throws -> [TranscriptLine]
}

/// A premium Translation service using Google's Gemini API to achieve high-fidelity Cantonese to Written Chinese translation.
/// Understands slangs, particles, English code-switching, and cultural context.
public final class GeminiTranslationService: TranslationServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.CantoneseListener", category: "GeminiTranslationService")
    private let apiKey: String?
    
    public init(apiKey: String? = nil) {
        // Reads from Info.plist or secure storage if present
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
    }
    
    public func translate(_ segments: [SpeechSegment]) async throws -> [TranscriptLine] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            logger.warning("Gemini API Key missing. Falling back to local translation engine.")
            throw NSError(domain: "GeminiTranslationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key Missing"])
        }
        
        guard !segments.isEmpty else { return [] }
        
        // Prepare segments payload
        let inputLines = segments.map { "[\($0.start)-\($0.end)]: \($0.text)" }.joined(separator: "\n")
        
        let prompt = """
        You are an expert bilingual Cantonese-to-Mandarin translator in Hong Kong.
        Translate the following timestamped colloquial Cantonese segments line-by-line into standard Written Chinese (Mandarin).
        Do not explain. Preserve the exact time frames. Maintain the exact line count. Keep formatting as JSON:
        [
          {"start": 1.2, "end": 4.5, "cantonese": "佢今日好似冇返工啵。", "translation": "他今天好像没上班。"}
        ]
        
        Segments to translate:
        \(inputLines)
        """
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GeminiTranslationService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid API response from Gemini server."])
        }
        
        // Parse Gemini JSON response
        struct GeminiResponse: Codable {
            struct Candidate: Codable {
                struct Content: Codable {
                    struct Part: Codable {
                        let text: String
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let jsonString = decoded.candidates.first?.content.parts.first?.text else {
            throw NSError(domain: "GeminiTranslationService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to extract text from Gemini response."])
        }
        
        struct TranslatedItem: Codable {
            let start: Double
            let end: Double
            let cantonese: String
            let translation: String
        }
        
        let jsonBytes = Data(jsonString.utf8)
        let items = try JSONDecoder().decode([TranslatedItem].self, from: jsonBytes)
        
        return items.map { item in
            TranscriptLine(
                startTimestamp: item.start,
                endTimestamp: item.end,
                cantoneseText: item.cantonese,
                translationText: item.translation
            )
        }
    }
}

/// Fallback dictionary-based translator for offline or mock operation.
/// Translates common colloquial Cantonese pronouns, auxiliary verbs, and particles into standard Mandarin Chinese.
public final class LocalRuleTranslationService: TranslationServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.CantoneseListener", category: "LocalRuleTranslationService")
    
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
    
    public func translate(_ segments: [SpeechSegment]) async throws -> [TranscriptLine] {
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
            
            return TranscriptLine(
                startTimestamp: segment.start,
                endTimestamp: segment.end,
                cantoneseText: segment.text,
                translationText: translated
            )
        }
    }
}

/// Composite service which attempts Gemini if configured, iOS 18 Translation API if on compatible systems, and falls back to LocalRule translation.
public final class SmartTranslationService: TranslationServiceProtocol {
    
    private let logger = Logger(subsystem: "com.dustland.CantoneseListener", category: "SmartTranslationService")
    private let geminiService: GeminiTranslationService
    private let localService: LocalRuleTranslationService
    
    public init(geminiApiKey: String? = nil) {
        self.geminiService = GeminiTranslationService(apiKey: geminiApiKey)
        self.localService = LocalRuleTranslationService()
    }
    
    public func translate(_ segments: [SpeechSegment]) async throws -> [TranscriptLine] {
        // 1. Try Gemini first
        do {
            let results = try await geminiService.translate(segments)
            logger.info("SmartTranslation: Successfully completed via Gemini.")
            return results
        } catch {
            logger.warning("SmartTranslation: Gemini Translation skipped or failed (\(error.localizedDescription)). Trying iOS Translation API...")
        }
        
        // 2. Try iOS 18 native Translation Framework if available
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                logger.info("SmartTranslation: Attempting iOS 18 Native Translation API.")
                var lines: [TranscriptLine] = []
                
                // Set up local Translation configurations
                let config = Translator.Configuration(sourceLanguage: .init(identifier: "zh-HK"), targetLanguage: .init(identifier: "zh-CN"))
                let translator = try await Translator(configuration: config)
                
                for segment in segments {
                    let response = try await translator.translate(segment.text)
                    lines.append(TranscriptLine(
                        startTimestamp: segment.start,
                        endTimestamp: segment.end,
                        cantoneseText: segment.text,
                        translationText: response.targetText
                    ))
                }
                
                logger.info("SmartTranslation: Successfully completed via iOS 18 Translation API.")
                return lines
            } catch {
                logger.error("SmartTranslation: iOS 18 Translation API failed: \(error.localizedDescription)")
            }
        }
        #endif
        
        // 3. Fallback to offline rule dictionary
        logger.info("SmartTranslation: Falling back to offline dictionary engine.")
        return try await localService.translate(segments)
    }
}
