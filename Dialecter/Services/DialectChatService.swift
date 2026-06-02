import Foundation
import OSLog

public struct DialectChatResult: Codable, Equatable {
    public let mandarinText: String
    public let dialectText: String
    public let pronunciation: String
    public let usageNote: String
}

public final class DialectChatService {
    private let logger = Logger(subsystem: "com.dustland.Dialecter", category: "DialectChatService")
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
        \(target.styleGuidance)

        Mandarin:
        \(input)
        """

        struct Payload: Codable {
            let dialectText: String
            let pronunciation: String
            let usageNote: String
        }

        let content = try await sendChatCompletion(prompt: prompt, apiKey: apiKey, enforceJSON: true)
        let jsonString = extractJSONObject(from: content)
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(jsonString.utf8))
        } catch {
            throw NSError(
                domain: "DialectChatService",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "OpenRouter returned text that could not be parsed: \(content)"]
            )
        }
        return DialectChatResult(
            mandarinText: input,
            dialectText: payload.dialectText,
            pronunciation: payload.pronunciation,
            usageNote: payload.usageNote
        )
    }

    private func sendChatCompletion(prompt: String, apiKey: String, enforceJSON: Bool) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Dialecter", forHTTPHeaderField: "X-Title")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        if enforceJSON {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DialectChatService", code: 500, userInfo: [NSLocalizedDescriptionKey: "OpenRouter returned a non-HTTP response."])
        }

        if httpResponse.statusCode != 200 {
            if enforceJSON {
                logger.warning("OpenRouter rejected JSON mode with HTTP \(httpResponse.statusCode). Retrying without response_format.")
                return try await sendChatCompletion(prompt: prompt, apiKey: apiKey, enforceJSON: false)
            }

            let bodyText = String(data: data, encoding: .utf8) ?? "Empty response body"
            throw NSError(
                domain: "DialectChatService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "OpenRouter \(httpResponse.statusCode): \(bodyText)"]
            )
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
        guard let content = decoded.choices.first?.message.content else {
            throw NSError(domain: "DialectChatService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to extract dialect result."])
        }
        return content
    }

    private func extractJSONObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }

        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            return String(trimmed[start...end])
        }

        return trimmed
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
