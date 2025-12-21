import Foundation

// MARK: - Mistral Provider

/// Provider for Mistral AI API.
/// Supports Mistral models including Large, Medium, Small, and Codestral.
struct MistralProvider: LLMProvider {
    let id = "mistral"
    let name = "Mistral"
    let supportsStreaming = true
    let supportsVision = true
    let supportsTools = true

    private let apiKey: String
    private let baseURL: URL

    init(apiKey: String, baseURL: URL = URL(string: "https://api.mistral.ai/v1")!) {
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
                        // SSE format: "data: {...}"
                        guard line.hasPrefix("data: ") else { continue }

                        let jsonString = String(line.dropFirst(6))

                        // End of stream
                        if jsonString == "[DONE]" {
                            break
                        }

                        guard let data = jsonString.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let delta = chunk.choices.first?.delta,
                              let content = delta.content else {
                            continue
                        }

                        continuation.yield(content)
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

        let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)

        guard let content = completion.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        return content
    }

    // MARK: - Models

    func models() async throws -> [LLMModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            return defaultModels
        }

        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)

        return modelsResponse.data.map { model in
            LLMModel(
                id: model.id,
                contextLength: contextLength(for: model.id),
                supportsVision: model.id.contains("pixtral"),
                supportsTools: true
            )
        }
    }

    // MARK: - Token Counting

    func countTokens(_ text: String, model: String) -> Int {
        // Mistral uses similar tokenization to other LLMs
        return text.count / 4
    }

    // MARK: - Private Helpers

    private func buildRequest(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { messageToDict($0) },
            "stream": stream
        ]

        // Add max_tokens
        body["max_tokens"] = options.maxTokens

        // Add optional parameters
        if options.temperature != 0.7 {
            body["temperature"] = options.temperature
        }
        if options.topP != 1.0 {
            body["top_p"] = options.topP
        }
        if options.frequencyPenalty != 0.0 {
            body["frequency_penalty"] = options.frequencyPenalty
        }
        if options.presencePenalty != 0.0 {
            body["presence_penalty"] = options.presencePenalty
        }
        if let seed = options.seed {
            body["random_seed"] = seed
        }
        if !options.stopSequences.isEmpty {
            body["stop"] = options.stopSequences
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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
            return ["type": "image_url", "image_url": ["url": url]]
        case .imageData(let data, let mimeType):
            let base64 = data.base64EncodedString()
            return ["type": "image_url", "image_url": ["url": "data:\(mimeType);base64,\(base64)"]]
        }
    }

    private func contextLength(for model: String) -> Int {
        switch model {
        case let m where m.contains("large"):
            return 128_000
        case let m where m.contains("medium"):
            return 128_000
        case let m where m.contains("small"):
            return 32_000
        case let m where m.contains("codestral"):
            return 256_000
        case let m where m.contains("pixtral"):
            return 128_000
        case let m where m.contains("ministral"):
            return 128_000
        default:
            return 32_000
        }
    }

    private var defaultModels: [LLMModel] {
        [
            LLMModel(id: "mistral-large-latest", name: "Mistral Large", contextLength: 128_000, supportsVision: false, supportsTools: true),
            LLMModel(id: "mistral-medium-latest", name: "Mistral Medium", contextLength: 128_000, supportsVision: false, supportsTools: true),
            LLMModel(id: "mistral-small-latest", name: "Mistral Small", contextLength: 32_000, supportsVision: false, supportsTools: true),
            LLMModel(id: "codestral-latest", name: "Codestral", contextLength: 256_000, supportsVision: false, supportsTools: true),
            LLMModel(id: "pixtral-large-latest", name: "Pixtral Large", contextLength: 128_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "ministral-8b-latest", name: "Ministral 8B", contextLength: 128_000, supportsVision: false, supportsTools: true),
            LLMModel(id: "ministral-3b-latest", name: "Ministral 3B", contextLength: 128_000, supportsVision: false, supportsTools: true),
        ]
    }
}

// MARK: - Response Types

private struct ChatCompletion: Decodable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let index: Int
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let role: String
        let content: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct StreamChunk: Decodable {
    let id: String
    let choices: [StreamChoice]

    struct StreamChoice: Decodable {
        let index: Int
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let role: String?
        let content: String?
    }
}

private struct ModelsResponse: Decodable {
    let data: [ModelInfo]

    struct ModelInfo: Decodable {
        let id: String
    }
}
