import Foundation

// MARK: - OpenRouter Provider

/// Provider for OpenRouter API.
/// Routes to various models (OpenAI, Anthropic, Meta, Mistral, etc.) through a unified API.
struct OpenRouterProvider: LLMProvider {
    let id = "openrouter"
    let name = "OpenRouter"
    let supportsStreaming = true
    let supportsVision = true
    let supportsTools = true

    private let apiKey: String
    private let baseURL: URL
    private let appName: String
    private let siteURL: String?

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        appName: String = "SillyTavern",
        siteURL: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.appName = appName
        self.siteURL = siteURL
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

                    if httpResponse.statusCode == 402 {
                        continuation.finish(throwing: LLMError.serverError(
                            statusCode: 402,
                            message: "Insufficient credits. Please add credits to your OpenRouter account."
                        ))
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

        if httpResponse.statusCode == 402 {
            throw LLMError.serverError(
                statusCode: 402,
                message: "Insufficient credits. Please add credits to your OpenRouter account."
            )
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

        let modelsResponse = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

        return modelsResponse.data.map { model in
            LLMModel(
                id: model.id,
                name: model.name,
                contextLength: model.contextLength,
                supportsVision: model.architecture?.modality?.contains("image") ?? false,
                supportsTools: true  // Most models support tools through OpenRouter
            )
        }
    }

    // MARK: - Token Counting

    func countTokens(_ text: String, model: String) -> Int {
        // Use appropriate estimation based on model family
        let modelLower = model.lowercased()

        if modelLower.contains("claude") {
            return Int(Double(text.count) / 3.8)
        } else if modelLower.contains("llama") || modelLower.contains("mistral") {
            return Int(Double(text.count) / 3.5)
        } else {
            // Default GPT-style tokenization
            return text.count / 4
        }
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

        // OpenRouter-specific headers
        request.setValue(appName, forHTTPHeaderField: "X-Title")
        if let siteURL = siteURL {
            request.setValue(siteURL, forHTTPHeaderField: "HTTP-Referer")
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { messageToDict($0) },
            "max_tokens": options.maxTokens,
            "stream": stream
        ]

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
        if !options.stopSequences.isEmpty {
            body["stop"] = options.stopSequences
        }

        // OpenRouter-specific options
        body["transforms"] = ["middle-out"]  // Enables context window optimization

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

        if let name = message.name {
            dict["name"] = name
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

    private var defaultModels: [LLMModel] {
        [
            // OpenAI models
            LLMModel(id: "openai/gpt-4o", name: "GPT-4o", contextLength: 128_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "openai/gpt-4o-mini", name: "GPT-4o Mini", contextLength: 128_000, supportsVision: true, supportsTools: true),

            // Anthropic models
            LLMModel(id: "anthropic/claude-3.5-sonnet", name: "Claude 3.5 Sonnet", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "anthropic/claude-3-opus", name: "Claude 3 Opus", contextLength: 200_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "anthropic/claude-3-haiku", name: "Claude 3 Haiku", contextLength: 200_000, supportsVision: true, supportsTools: true),

            // Meta models
            LLMModel(id: "meta-llama/llama-3.1-405b-instruct", name: "Llama 3.1 405B", contextLength: 131_072, supportsVision: false, supportsTools: true),
            LLMModel(id: "meta-llama/llama-3.1-70b-instruct", name: "Llama 3.1 70B", contextLength: 131_072, supportsVision: false, supportsTools: true),

            // Mistral models
            LLMModel(id: "mistralai/mistral-large", name: "Mistral Large", contextLength: 128_000, supportsVision: false, supportsTools: true),
            LLMModel(id: "mistralai/mixtral-8x22b-instruct", name: "Mixtral 8x22B", contextLength: 65_536, supportsVision: false, supportsTools: true),

            // Google models
            LLMModel(id: "google/gemini-pro-1.5", name: "Gemini Pro 1.5", contextLength: 1_000_000, supportsVision: true, supportsTools: true),
        ]
    }
}

// MARK: - Response Types (OpenAI-compatible)

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

private struct OpenRouterModelsResponse: Decodable {
    let data: [ModelInfo]

    struct ModelInfo: Decodable {
        let id: String
        let name: String
        let contextLength: Int
        let architecture: Architecture?

        enum CodingKeys: String, CodingKey {
            case id, name, architecture
            case contextLength = "context_length"
        }

        struct Architecture: Decodable {
            let modality: String?
        }
    }
}
