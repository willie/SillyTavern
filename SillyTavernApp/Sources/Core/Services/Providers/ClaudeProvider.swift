import Foundation

// MARK: - Claude Provider

/// Provider for Anthropic Claude API.
/// Supports Claude 3 family (Opus, Sonnet, Haiku) and Claude 3.5 models.
struct ClaudeProvider: LLMProvider {
    let id = "claude"
    let name = "Claude"
    let supportsStreaming = true
    let supportsVision = true
    let supportsTools = true

    private let apiKey: String
    private let baseURL: URL
    private let anthropicVersion = "2023-06-01"

    init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    // MARK: - Streaming

    func send(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        let request = try buildRequest(messages: messages, model: model, options: options, stream: true)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 401 {
                        continuation.finish(throwing: LLMError.invalidAPIKey)
                        return
                    }

                    if httpResponse.statusCode == 429 {
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                            .flatMap { TimeInterval($0) }
                        continuation.finish(throwing: LLMError.rateLimited(retryAfter: retryAfter))
                        return
                    }

                    if httpResponse.statusCode >= 400 {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.finish(throwing: LLMError.serverError(
                            statusCode: httpResponse.statusCode,
                            message: errorBody
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        // SSE format: "event: content_block_delta" followed by "data: {...}"
                        guard line.hasPrefix("data: ") else { continue }

                        let jsonString = String(line.dropFirst(6))

                        guard let data = jsonString.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
                            continue
                        }

                        switch event.type {
                        case "content_block_delta":
                            if let delta = event.delta, let text = delta.text {
                                continuation.yield(text)
                            }
                        case "message_stop":
                            break
                        case "error":
                            if let error = event.error {
                                continuation.finish(throwing: LLMError.serverError(
                                    statusCode: 500,
                                    message: error.message
                                ))
                                return
                            }
                        default:
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.networkError(error))
                }
            }
        }
    }

    // MARK: - Non-Streaming

    func complete(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions
    ) async throws -> String {
        let request = try buildRequest(messages: messages, model: model, options: options, stream: false)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw LLMError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        }

        if httpResponse.statusCode >= 400 {
            let errorMessage = String(data: data, encoding: .utf8)
            throw LLMError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let completion = try JSONDecoder().decode(MessageResponse.self, from: data)

        // Extract text from content blocks
        let text = completion.content
            .compactMap { block -> String? in
                if case .text(let text) = block {
                    return text
                }
                return nil
            }
            .joined()

        return text
    }

    // MARK: - Models

    func models() async throws -> [LLMModel] {
        // Claude doesn't have a models endpoint, return known models
        return defaultModels
    }

    // MARK: - Token Counting

    func countTokens(_ text: String, model: String) -> Int {
        // Claude uses a similar tokenization to GPT models
        // Slightly more efficient for most text
        return Int(Double(text.count) / 3.8)
    }

    // MARK: - Private Helpers

    private func buildRequest(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Claude requires system message to be separate
        let (systemPrompt, conversationMessages) = extractSystemPrompt(from: messages)

        var body: [String: Any] = [
            "model": model,
            "messages": conversationMessages.map { messageToDict($0) },
            "max_tokens": options.maxTokens,
            "stream": stream
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        // Add optional parameters
        if options.temperature != 0.7 {
            body["temperature"] = options.temperature
        }
        if options.topP != 1.0 {
            body["top_p"] = options.topP
        }
        if let topK = options.topK {
            body["top_k"] = topK
        }
        if !options.stopSequences.isEmpty {
            body["stop_sequences"] = options.stopSequences
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func extractSystemPrompt(from messages: [LLMMessage]) -> (String?, [LLMMessage]) {
        var systemParts: [String] = []
        var conversationMessages: [LLMMessage] = []

        for message in messages {
            if message.role == .system {
                systemParts.append(message.content.textValue)
            } else {
                conversationMessages.append(message)
            }
        }

        let systemPrompt = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return (systemPrompt, conversationMessages)
    }

    private func messageToDict(_ message: LLMMessage) -> [String: Any] {
        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.content {
        case .text(let text):
            dict["content"] = text
        case .multipart(let parts):
            dict["content"] = parts.map { partToDict($0) }
        }

        return dict
    }

    private func partToDict(_ part: LLMContentPart) -> [String: Any] {
        switch part {
        case .text(let text):
            return ["type": "text", "text": text]
        case .imageURL(let url):
            // Claude doesn't support URL references, would need to fetch and convert
            return ["type": "text", "text": "[Image: \(url)]"]
        case .imageData(let data, let mimeType):
            return [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }
    }

    private var defaultModels: [LLMModel] {
        [
            LLMModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "claude-opus-4-20250514", name: "Claude Opus 4", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "claude-3-opus-20240229", name: "Claude 3 Opus", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "claude-3-haiku-20240307", name: "Claude 3 Haiku", contextLength: 200_000, supportsVision: true, supportsTools: true),
        ]
    }
}

// MARK: - Response Types

private struct MessageResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }

    enum ContentBlock: Decodable {
        case text(String)
        case toolUse(id: String, name: String, input: [String: Any])

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "text":
                let text = try container.decode(String.self, forKey: .text)
                self = .text(text)
            case "tool_use":
                let id = try container.decode(String.self, forKey: .id)
                let name = try container.decode(String.self, forKey: .name)
                // Tool input is complex JSON, store as dictionary
                self = .toolUse(id: id, name: name, input: [:])
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown content block type: \(type)"
                )
            }
        }
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let index: Int?
    let delta: Delta?
    let error: ErrorInfo?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }

    struct ErrorInfo: Decodable {
        let type: String
        let message: String
    }
}
