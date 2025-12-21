import Foundation

// MARK: - Gemini Provider

/// Provider for Google Gemini API.
/// Supports Gemini Pro, Gemini Flash, and vision-capable models.
struct GeminiProvider: LLMProvider {
    let id = "gemini"
    let name = "Gemini"
    let supportsStreaming = true
    let supportsVision = true
    let supportsTools = true

    private let apiKey: String
    private let baseURL: URL

    init(apiKey: String, baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!) {
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

                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
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

                        guard let data = jsonString.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamResponse.self, from: data),
                              let text = chunk.candidates?.first?.content?.parts?.first?.text else {
                            continue
                        }

                        continuation.yield(text)
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

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
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

        let completion = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        guard let text = completion.candidates?.first?.content?.parts?.first?.text else {
            throw LLMError.invalidResponse
        }

        return text
    }

    // MARK: - Models

    func models() async throws -> [LLMModel] {
        // Gemini API has a models endpoint
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            return defaultModels
        }

        let modelsResponse = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)

        return modelsResponse.models.compactMap { model -> LLMModel? in
            guard model.supportedGenerationMethods.contains("generateContent") else { return nil }
            return LLMModel(
                id: model.name.replacingOccurrences(of: "models/", with: ""),
                name: model.displayName,
                contextLength: model.inputTokenLimit ?? 32_000,
                supportsVision: model.supportedGenerationMethods.contains("generateContent"),
                supportsTools: true
            )
        }
    }

    // MARK: - Token Counting

    func countTokens(_ text: String, model: String) -> Int {
        // Gemini has efficient tokenization, roughly 4 chars per token
        return text.count / 4
    }

    // MARK: - Private Helpers

    private func buildRequest(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions,
        stream: Bool
    ) throws -> URLRequest {
        // Endpoint: /models/{model}:generateContent or :streamGenerateContent
        let endpoint = stream ? "streamGenerateContent" : "generateContent"
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent("models/\(model):\(endpoint)"), resolvingAgainstBaseURL: false)!

        if stream {
            urlComponents.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        }

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build contents and extract system instruction
        let (systemInstruction, contents) = buildContents(from: messages)

        var body: [String: Any] = [
            "contents": contents
        ]

        if let system = systemInstruction {
            body["systemInstruction"] = [
                "parts": [["text": system]]
            ]
        }

        // Generation config
        var generationConfig: [String: Any] = [
            "maxOutputTokens": options.maxTokens
        ]

        if options.temperature != 0.7 {
            generationConfig["temperature"] = options.temperature
        }
        if options.topP != 1.0 {
            generationConfig["topP"] = options.topP
        }
        if let topK = options.topK {
            generationConfig["topK"] = topK
        }
        if !options.stopSequences.isEmpty {
            generationConfig["stopSequences"] = options.stopSequences
        }

        body["generationConfig"] = generationConfig

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildContents(from messages: [LLMMessage]) -> (systemInstruction: String?, contents: [[String: Any]]) {
        var systemParts: [String] = []
        var contents: [[String: Any]] = []

        for message in messages {
            if message.role == .system {
                systemParts.append(message.content.textValue)
                continue
            }

            // Gemini uses "user" and "model" roles
            let role = message.role == .user ? "user" : "model"

            var parts: [[String: Any]] = []

            switch message.content {
            case .text(let text):
                parts.append(["text": text])
            case .multipart(let contentParts):
                for part in contentParts {
                    switch part {
                    case .text(let text):
                        parts.append(["text": text])
                    case .imageURL(let url):
                        // Gemini doesn't support URL references, would need to fetch
                        parts.append(["text": "[Image: \(url)]"])
                    case .imageData(let data, let mimeType):
                        parts.append([
                            "inlineData": [
                                "mimeType": mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                }
            }

            contents.append([
                "role": role,
                "parts": parts
            ])
        }

        let systemInstruction = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return (systemInstruction, contents)
    }

    private var defaultModels: [LLMModel] {
        [
            LLMModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", contextLength: 1_000_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "gemini-2.0-flash-lite", name: "Gemini 2.0 Flash Lite", contextLength: 1_000_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", contextLength: 1_000_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", contextLength: 2_000_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", contextLength: 1_000_000, supportsVision: true, supportsTools: true),
            LLMModel(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", contextLength: 2_000_000, supportsVision: true, supportsTools: true),
        ]
    }
}

// MARK: - Response Types

private struct GenerateContentResponse: Decodable {
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
        let index: Int?
    }

    struct Content: Decodable {
        let parts: [Part]?
        let role: String?
    }

    struct Part: Decodable {
        let text: String?
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
    }
}

private struct StreamResponse: Decodable {
    let candidates: [GenerateContentResponse.Candidate]?
    let usageMetadata: GenerateContentResponse.UsageMetadata?
}

private struct GeminiModelsResponse: Decodable {
    let models: [ModelInfo]

    struct ModelInfo: Decodable {
        let name: String
        let displayName: String
        let supportedGenerationMethods: [String]
        let inputTokenLimit: Int?
        let outputTokenLimit: Int?
    }
}
