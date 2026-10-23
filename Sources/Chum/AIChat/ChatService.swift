import Foundation
import ChumCore

/// Sends chat discussions to the configured BYOK provider. Three request
/// shapes cover the five providers: OpenAI-compatible (OpenAI, Mistral,
/// OpenRouter), Anthropic, and Google. Non-streaming for now — one request
/// per turn, the response arrives whole.
enum ChatService {
    enum Provider: String {
        case openai
        case anthropic
        case google
        case mistral
        case openrouter
    }

    /// Sensible defaults per provider; the Settings model field overrides.
    /// Model names age fast — the field is free text on purpose.
    static func defaultModel(for provider: String) -> String {
        switch provider {
        case "anthropic": return "claude-sonnet-4-20250514"
        case "google": return "gemini-2.5-flash"
        case "mistral": return "mistral-large-latest"
        case "openrouter": return "openrouter/auto"
        default: return "gpt-4o-mini"
        }
    }

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: AppSettings.aiModelKey) ?? ""
        return stored.isEmpty ? defaultModel(for: AppSettings.aiProvider) : stored
    }

    /// Sends the conversation and returns the assistant's reply.
    /// Errors carry a user-facing message (status line, no alerts).
    static func send(messages: [ChatMessage]) async throws -> String {
        guard let key = APIKeyStore.read(), !key.isEmpty else {
            throw chatError("No API key — add it in Settings → AI Chat")
        }
        let provider = AppSettings.aiProvider
        let request = try buildRequest(provider: provider, apiKey: key, messages: messages)
        let (data, response): (Data, URLResponse)
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            let session = URLSession(configuration: configuration)
            (data, response) = try await session.data(for: request)
        } catch {
            throw chatError("Network: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw chatError("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw chatError("Provider returned \(http.statusCode): \(Self.errorBody(data))")
        }
        guard let reply = parseReply(provider: provider, data: data) else {
            throw chatError("Could not read the reply")
        }
        return reply
    }

    // MARK: - Request building

    private static func buildRequest(provider: String, apiKey: String, messages: [ChatMessage]) throws -> URLRequest {
        switch provider {
        case "anthropic":
            return try request(
                url: "https://api.anthropic.com/v1/messages",
                headers: [
                    "x-api-key": apiKey,
                    "anthropic-version": "2023-06-01",
                ],
                body: AnthropicBody(model: model, messages: messages.map(AnthropicMessage.init))
            )
        case "google":
            return try request(
                url: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent",
                headers: ["x-goog-api-key": apiKey],
                body: GoogleBody(contents: messages.map(GoogleContent.init))
            )
        default:
            let base: String
            switch provider {
            case "mistral": base = "https://api.mistral.ai/v1"
            case "openrouter": base = "https://openrouter.ai/api/v1"
            default: base = "https://api.openai.com/v1"
            }
            return try request(
                url: "\(base)/chat/completions",
                headers: ["Authorization": "Bearer \(apiKey)"],
                body: OpenAIBody(model: model, messages: messages.map(OpenAIMessage.init))
            )
        }
    }

    private static func request<T: Encodable>(url: String, headers: [String: String], body: T) throws -> URLRequest {
        guard let url = URL(string: url) else {
            throw chatError("Invalid provider URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: - Response parsing

    private static func parseReply(provider: String, data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch provider {
        case "anthropic":
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { ($0["text"] as? String) }.joined()
        case "google":
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            return parts.compactMap { ($0["text"] as? String) }.joined()
        default:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else { return nil }
            return message["content"] as? String
        }
    }

    // MARK: - Wire types

    private struct OpenAIMessage: Encodable {
        let role: String
        let content: String
        init(_ message: ChatMessage) {
            role = message.role.rawValue
            content = message.text
        }
    }

    private struct OpenAIBody: Encodable {
        let model: String
        let messages: [OpenAIMessage]
    }

    private struct AnthropicMessage: Encodable {
        let role: String
        let content: String
        init(_ message: ChatMessage) {
            role = message.role.rawValue
            content = message.text
        }
    }

    private struct AnthropicBody: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [AnthropicMessage]
        init(model: String, messages: [AnthropicMessage]) {
            self.model = model
            self.max_tokens = 1024
            self.messages = messages
        }
    }

    private struct GooglePart: Encodable {
        let text: String
    }

    private struct GoogleContent: Encodable {
        let role: String
        let parts: [GooglePart]
        init(_ message: ChatMessage) {
            role = message.role == .assistant ? "model" : "user"
            parts = [GooglePart(text: message.text)]
        }
    }

    private struct GoogleBody: Encodable {
        let contents: [GoogleContent]
    }

    // MARK: - Errors

    private struct ChatError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func chatError(_ message: String) -> ChatError {
        ChatError(message: message)
    }

    private static func errorBody(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["error"] as? [String: Any],
              let text = message["message"] as? String else { return "no details" }
        return String(text.prefix(200))
    }
}
