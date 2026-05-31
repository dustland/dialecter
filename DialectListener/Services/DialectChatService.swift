import Foundation
import OSLog

public struct DialectChatResult: Codable, Equatable {
    public let mandarinText: String
    public let dialectText: String
    public let pronunciation: String
    public let usageNote: String
}

public final class DialectChatService {
    private let logger = Logger(subsystem: "com.dustland.DialectListener", category: "DialectChatService")
    private let apiKey: String?
    private let model: String

    public init(apiKey: String? = nil, model: String = "openai/gpt-4o-mini") {
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

    public func translateMandarin(_ text: String, to target: ChatTargetDialect) async throws -> DialectChatResult {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw NSError(domain: "DialectChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Input is empty"])
        }

        guard let apiKey else {
            logger.warning("OpenRouter API Key missing. Returning local dialect fallback.")
            return localFallback(for: input, target: target)
        }

        let prompt = """
        You are a dialect conversation coach for Mandarin speakers.
        Convert the Mandarin sentence into natural spoken \(target.promptName).
        Return one JSON object only:
        {
          "dialectText": "我而家想去食飯。",
          "pronunciation": "ngo5 ji4 gaa1 soeng2 heoi3 sik6 faan6",
          "usageNote": "Natural casual phrase."
        }

        Requirements:
        - Keep the dialect practical for real conversation.
        - Use the most natural writing system for \(target.promptName).
        - Use \(target.pronunciationSystem) for pronunciation.
        - Keep usageNote under 20 words.

        Mandarin:
        \(input)
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
            throw NSError(domain: "DialectChatService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid API response from OpenRouter server."])
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

        struct Payload: Codable {
            let dialectText: String
            let pronunciation: String
            let usageNote: String
        }

        let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw NSError(domain: "DialectChatService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to extract dialect result."])
        }

        let payload = try JSONDecoder().decode(Payload.self, from: Data(content.utf8))
        return DialectChatResult(
            mandarinText: input,
            dialectText: payload.dialectText,
            pronunciation: payload.pronunciation,
            usageNote: payload.usageNote
        )
    }

    private func localFallback(for input: String, target _: ChatTargetDialect) -> DialectChatResult {
        DialectChatResult(
            mandarinText: input,
            dialectText: input,
            pronunciation: AppText.t("OpenRouter is not configured.", "未配置 OpenRouter，暂时只能显示原文。"),
            usageNote: AppText.t("Add API key for dialect conversion.", "配置 API Key 后可生成方言。")
        )
    }
}
