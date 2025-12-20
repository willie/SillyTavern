import Foundation
import Observation

// MARK: - Chat State

/// Manages the state and logic for a single chat session.
@Observable @MainActor
final class ChatState {
    // Current chat
    var chat: Chat?
    var character: CharacterCard?

    // Message state
    var messages: [Message] = []
    var inputText: String = ""

    // Generation state
    var isGenerating: Bool = false
    var streamingText: String = ""
    var error: ChatError?

    // Token tracking
    var tokenCount: Int = 0
    var maxContextTokens: Int = 8192

    // Dependencies
    private var provider: (any LLMProvider)?
    private var settings: PromptSettings = PromptSettings()
    private var worldInfo: [WorldInfoEntry] = []
    private var extensionPrompts: ExtensionPrompts = ExtensionPrompts()
    private var tokenizer: (any Tokenizer)?
    private var model: String = "gpt-4o"
    private var personaName: String = "User"
    private var personaDescription: String = ""

    // MARK: - Configuration

    /// Configure the chat with a character and provider
    func configure(
        character: CharacterCard,
        provider: any LLMProvider,
        settings: PromptSettings = PromptSettings(),
        worldInfo: [WorldInfoEntry] = [],
        extensionPrompts: ExtensionPrompts = ExtensionPrompts(),
        tokenizer: (any Tokenizer)? = nil,
        model: String = "gpt-4o",
        personaName: String = "User",
        personaDescription: String = ""
    ) {
        self.character = character
        self.provider = provider
        self.settings = settings
        self.worldInfo = worldInfo
        self.extensionPrompts = extensionPrompts
        self.tokenizer = tokenizer
        self.model = model
        self.maxContextTokens = settings.maxContextTokens
        self.personaName = personaName
        self.personaDescription = personaDescription

        // Add first message if available
        if !character.first_mes.isEmpty && messages.isEmpty {
            let firstMessage = Message(
                role: .assistant,
                content: substituteParams(character.first_mes)
            )
            messages.append(firstMessage)
        }
    }

    // MARK: - Send Message

    /// Send a user message and generate a response
    func send() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }
        guard let character = character, let provider = provider else {
            error = .notConfigured
            return
        }

        let userMessage = Message(role: .user, content: inputText)
        messages.append(userMessage)
        inputText = ""

        await generate(character: character, provider: provider)
    }

    /// Regenerate the last assistant message
    func regenerate() async {
        guard !isGenerating else { return }
        guard let character = character, let provider = provider else { return }

        // Remove last assistant message if present
        if let last = messages.last, last.role == .assistant {
            messages.removeLast()
        }

        await generate(character: character, provider: provider)
    }

    /// Continue the last assistant message
    func continueGeneration() async {
        guard !isGenerating else { return }
        guard let character = character, let provider = provider else { return }

        await generate(character: character, provider: provider, type: .continue)
    }

    // MARK: - Generation

    private func generate(
        character: CharacterCard,
        provider: any LLMProvider,
        type: GenerationType = .normal
    ) async {
        isGenerating = true
        streamingText = ""
        error = nil

        do {
            // Build the prompt
            var promptBuilder = PromptBuilder(
                character: character,
                settings: settings,
                worldInfo: worldInfo,
                extensionPrompts: extensionPrompts
            )
            promptBuilder.personaName = personaName
            promptBuilder.personaDescription = personaDescription.isEmpty ? nil : personaDescription

            // Use custom tokenizer if provided, else use provider's
            let tokenCounter: @Sendable (String) -> Int = { [tokenizer, model] text in
                if let tokenizer = tokenizer {
                    return tokenizer.countTokens(text)
                }
                return provider.countTokens(text, model: model)
            }

            let builtPrompt = promptBuilder.build(
                chatHistory: messages,
                type: type,
                tokenCounter: tokenCounter
            )

            tokenCount = builtPrompt.tokenCount

            // Options
            let options = LLMOptions(
                maxTokens: settings.maxResponseTokens,
                temperature: 0.7
            )

            // Stream the response
            let stream = try await provider.send(
                messages: builtPrompt.messages,
                model: self.model,
                options: options
            )

            // Handle continue type
            var continuePrefix = ""
            if type == .continue, let last = messages.last, last.role == .assistant {
                continuePrefix = last.content
                messages.removeLast()
            }

            // Create placeholder message
            let assistantMessage = Message(role: .assistant, content: continuePrefix)
            messages.append(assistantMessage)

            for try await chunk in stream {
                streamingText += chunk
                // Update the last message with streaming content
                if let index = messages.indices.last {
                    messages[index].content = continuePrefix + streamingText
                }
            }

            // Finalize
            streamingText = ""

        } catch let llmError as LLMError {
            error = .providerError(llmError)
            // Remove the placeholder message on error
            if let last = messages.last, last.content.isEmpty || last.content == streamingText {
                messages.removeLast()
            }
        } catch {
            self.error = .unknown(error)
            if let last = messages.last, last.content.isEmpty {
                messages.removeLast()
            }
        }

        isGenerating = false
    }

    // MARK: - Message Actions

    /// Delete a message at index
    func deleteMessage(at index: Int) {
        guard messages.indices.contains(index) else { return }
        messages.remove(at: index)
    }

    /// Edit a message
    func editMessage(at index: Int, newContent: String) {
        guard messages.indices.contains(index) else { return }
        messages[index].content = newContent
    }

    /// Clear all messages
    func clearChat() {
        messages.removeAll()

        // Re-add first message
        if let character = character, !character.first_mes.isEmpty {
            let firstMessage = Message(
                role: .assistant,
                content: substituteParams(character.first_mes)
            )
            messages.append(firstMessage)
        }
    }

    // MARK: - Helpers

    private func substituteParams(_ text: String) -> String {
        var result = text
        let charName = character?.name ?? "Character"

        result = result.replacingOccurrences(of: "{{char}}", with: charName)
        result = result.replacingOccurrences(of: "{{Char}}", with: charName)
        result = result.replacingOccurrences(of: "{{user}}", with: personaName)
        result = result.replacingOccurrences(of: "{{User}}", with: personaName)

        return result
    }

    /// Update the token count based on current messages
    func updateTokenCount() {
        let tokenizer = self.tokenizer ?? TokenCounter.defaultTokenizer
        tokenCount = messages.reduce(0) { $0 + tokenizer.countTokens($1.content) }
    }
}

// MARK: - Chat Error

enum ChatError: Error, LocalizedError {
    case notConfigured
    case providerError(LLMError)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Chat not configured. Please select a character and configure API settings."
        case .providerError(let error):
            return error.localizedDescription
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
