import Foundation

// MARK: - LLM Provider Protocol

/// Protocol for LLM API providers (OpenAI, Claude, etc.)
protocol LLMProvider: Sendable {
    /// Unique identifier for this provider
    var id: String { get }

    /// Display name
    var name: String { get }

    /// Whether this provider supports streaming responses
    var supportsStreaming: Bool { get }

    /// Whether this provider supports vision/image inputs
    var supportsVision: Bool { get }

    /// Whether this provider supports function/tool calling
    var supportsTools: Bool { get }

    /// Send messages and receive a streaming response
    func send(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions
    ) async throws -> AsyncThrowingStream<String, Error>

    /// Send messages and receive a complete response (non-streaming)
    func complete(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions
    ) async throws -> String

    /// Get available models for this provider
    func models() async throws -> [LLMModel]

    /// Estimate token count for text (provider-specific tokenization)
    func countTokens(_ text: String, model: String) -> Int
}

// MARK: - Default Implementations

extension LLMProvider {
    /// Default non-streaming implementation using streaming
    func complete(
        messages: [LLMMessage],
        model: String,
        options: LLMOptions
    ) async throws -> String {
        var result = ""
        for try await chunk in try await send(messages: messages, model: model, options: options) {
            result += chunk
        }
        return result
    }

    /// Default token count estimation (4 chars per token)
    func countTokens(_ text: String, model: String) -> Int {
        text.count / 4
    }
}

// MARK: - LLM Message

struct LLMMessage: Codable, Sendable, Equatable {
    var role: LLMRole
    var content: LLMContent
    var name: String?

    init(role: LLMRole, content: String, name: String? = nil) {
        self.role = role
        self.content = .text(content)
        self.name = name
    }

    init(role: LLMRole, content: LLMContent, name: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
    }

    /// Simple text content
    var text: String? {
        if case .text(let str) = content { return str }
        return nil
    }
}

enum LLMRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

enum LLMContent: Codable, Sendable, Equatable {
    case text(String)
    case multipart([LLMContentPart])

    var textValue: String {
        switch self {
        case .text(let str):
            return str
        case .multipart(let parts):
            return parts.compactMap {
                if case .text(let str) = $0 { return str }
                return nil
            }.joined()
        }
    }
}

enum LLMContentPart: Codable, Sendable, Equatable {
    case text(String)
    case imageURL(String)
    case imageData(Data, mimeType: String)
}

// MARK: - LLM Options

struct LLMOptions: Sendable {
    var maxTokens: Int = 2048
    var temperature: Double = 0.7
    var topP: Double = 1.0
    var frequencyPenalty: Double = 0.0
    var presencePenalty: Double = 0.0
    var stopSequences: [String] = []

    static let `default` = LLMOptions()
}

// MARK: - LLM Model

struct LLMModel: Identifiable, Sendable {
    var id: String
    var name: String
    var contextLength: Int
    var supportsVision: Bool
    var supportsTools: Bool

    init(
        id: String,
        name: String? = nil,
        contextLength: Int = 4096,
        supportsVision: Bool = false,
        supportsTools: Bool = false
    ) {
        self.id = id
        self.name = name ?? id
        self.contextLength = contextLength
        self.supportsVision = supportsVision
        self.supportsTools = supportsTools
    }
}

// MARK: - Provider Errors

enum LLMError: Error, LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)
    case streamingNotSupported
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key"
        case .invalidResponse:
            return "Invalid response from server"
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Rate limited. Retry after \(Int(retry)) seconds"
            }
            return "Rate limited"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .streamingNotSupported:
            return "Streaming not supported by this provider"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        }
    }
}
