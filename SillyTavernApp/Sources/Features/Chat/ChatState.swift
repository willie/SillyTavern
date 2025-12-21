import Foundation
import Observation

// MARK: - Chat State

/// Manages the state and logic for a single chat session.
/// Works with ChatFile for persistence matching SillyTavern's JSONL format.
@Observable @MainActor
final class ChatState {
    // Current chat file (contains messages)
    var chatFile: ChatFile?
    var character: CharacterCard?

    // Input state
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
    private var promptSettings: PromptSettings = PromptSettings()
    private var worldInfo: [WorldInfoEntry] = []
    private var extensionPrompts: ExtensionPrompts = ExtensionPrompts()
    private var tokenizer: (any Tokenizer)?
    private var model: String = "gpt-4o"
    private var personaName: String = "User"
    private var personaDescription: String = ""

    // MARK: - Computed Properties

    /// Current messages from the chat file
    var messages: [ChatMessage] {
        chatFile?.messages ?? []
    }

    /// Whether this chat has any messages (beyond first greeting)
    var hasMessages: Bool {
        guard let file = chatFile else { return false }
        return file.messages.count > 1 ||
               (file.messages.count == 1 && file.messages[0].is_user)
    }

    // MARK: - Configuration

    /// Configure the chat state with a chat file and character
    func configure(
        chatFile: ChatFile,
        character: CharacterCard,
        provider: (any LLMProvider)?,
        settings: PromptSettings = PromptSettings(),
        worldInfo: [WorldInfoEntry] = [],
        extensionPrompts: ExtensionPrompts = ExtensionPrompts(),
        tokenizer: (any Tokenizer)? = nil,
        model: String = "gpt-4o",
        personaName: String = "User",
        personaDescription: String = ""
    ) {
        self.chatFile = chatFile
        self.character = character
        self.provider = provider
        self.promptSettings = settings
        self.worldInfo = worldInfo
        self.extensionPrompts = extensionPrompts
        self.tokenizer = tokenizer
        self.model = model
        self.maxContextTokens = settings.maxContextTokens
        self.personaName = personaName
        self.personaDescription = personaDescription
    }

    // MARK: - Send Message

    /// Send a user message and generate a response
    func send() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }
        guard let chatFile = chatFile, let character = character else {
            error = .notConfigured
            return
        }
        guard let provider = provider else {
            error = .notConfigured
            return
        }

        // Add user message
        chatFile.addUserMessage(inputText)
        inputText = ""

        await generate(chatFile: chatFile, character: character, provider: provider)
    }

    /// Regenerate the last assistant message
    func regenerate() async {
        guard !isGenerating else { return }
        guard let chatFile = chatFile, let character = character, let provider = provider else { return }

        // Remove last assistant message if present
        if let last = chatFile.messages.last, !last.is_user {
            chatFile.messages.removeLast()
        }

        await generate(chatFile: chatFile, character: character, provider: provider)
    }

    /// Continue the last assistant message
    func continueGeneration() async {
        guard !isGenerating else { return }
        guard let chatFile = chatFile, let character = character, let provider = provider else { return }

        await generate(chatFile: chatFile, character: character, provider: provider, type: .continue)
    }

    // MARK: - Generation

    private func generate(
        chatFile: ChatFile,
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
                settings: promptSettings,
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

            // Convert ChatMessages to LLMMessage format for PromptBuilder
            let historyMessages = chatFile.messages.map { msg in
                LLMMessage(
                    role: msg.is_user ? LLMRole.user : LLMRole.assistant,
                    content: msg.displayedMessage,
                    name: msg.name
                )
            }

            let builtPrompt = promptBuilder.build(
                chatHistory: historyMessages,
                type: type,
                tokenCounter: tokenCounter
            )

            tokenCount = builtPrompt.tokenCount

            // Options
            let options = LLMOptions(
                maxTokens: promptSettings.maxResponseTokens,
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
            if type == .continue, let last = chatFile.messages.last, !last.is_user {
                continuePrefix = last.displayedMessage
                chatFile.messages.removeLast()
            }

            // Create placeholder message
            let assistantMessage = ChatMessage.characterMessage(continuePrefix, name: character.name)
            chatFile.messages.append(assistantMessage)

            for try await chunk in stream {
                streamingText += chunk
                // Update the last message with streaming content
                if let lastMessage = chatFile.messages.last {
                    lastMessage.mes = continuePrefix + streamingText
                }
            }

            // Finalize
            streamingText = ""

        } catch let llmError as LLMError {
            error = .providerError(llmError)
            // Remove the placeholder message on error
            if let last = chatFile.messages.last, last.mes.isEmpty || last.mes == streamingText {
                chatFile.messages.removeLast()
            }
        } catch {
            self.error = .unknown(error)
            if let last = chatFile.messages.last, last.mes.isEmpty {
                chatFile.messages.removeLast()
            }
        }

        isGenerating = false
    }

    // MARK: - Swipe Actions

    /// Add a new swipe (regenerate as alternate response)
    func swipe() async {
        guard !isGenerating else { return }
        guard let chatFile = chatFile, let character = character, let provider = provider else { return }
        guard let lastMessage = chatFile.messages.last, !lastMessage.is_user else { return }

        // Initialize swipes array if needed
        if lastMessage.swipes == nil {
            lastMessage.swipes = [lastMessage.mes]
            lastMessage.swipe_id = 0
        }

        // Generate a new response
        isGenerating = true
        streamingText = ""
        error = nil

        do {
            var promptBuilder = PromptBuilder(
                character: character,
                settings: promptSettings,
                worldInfo: worldInfo,
                extensionPrompts: extensionPrompts
            )
            promptBuilder.personaName = personaName
            promptBuilder.personaDescription = personaDescription.isEmpty ? nil : personaDescription

            let tokenCounter: @Sendable (String) -> Int = { [tokenizer, model] text in
                if let tokenizer = tokenizer {
                    return tokenizer.countTokens(text)
                }
                return provider.countTokens(text, model: model)
            }

            // Build prompt without the last assistant message
            let historyMessages = chatFile.messages.dropLast().map { msg in
                LLMMessage(
                    role: msg.is_user ? LLMRole.user : LLMRole.assistant,
                    content: msg.displayedMessage,
                    name: msg.name
                )
            }

            let builtPrompt = promptBuilder.build(
                chatHistory: Array(historyMessages),
                type: .normal,
                tokenCounter: tokenCounter
            )

            let options = LLMOptions(
                maxTokens: promptSettings.maxResponseTokens,
                temperature: 0.7
            )

            let stream = try await provider.send(
                messages: builtPrompt.messages,
                model: self.model,
                options: options
            )

            var newSwipeContent = ""
            for try await chunk in stream {
                newSwipeContent += chunk
                streamingText = newSwipeContent
            }

            // Add the new swipe
            lastMessage.addSwipe(newSwipeContent)
            streamingText = ""

        } catch {
            self.error = .unknown(error)
        }

        isGenerating = false
    }

    // MARK: - Message Actions

    /// Delete a message at index
    func deleteMessage(at index: Int) {
        guard let chatFile = chatFile else { return }
        chatFile.deleteMessage(at: index)
    }

    /// Edit a message
    func editMessage(at index: Int, newContent: String) {
        guard let chatFile = chatFile else { return }
        guard chatFile.messages.indices.contains(index) else { return }
        chatFile.messages[index].mes = newContent
    }

    /// Clear all messages and start fresh
    func clearChat() {
        guard let chatFile = chatFile, let character = character else { return }

        chatFile.clearMessages()

        // Re-add first message
        if !character.first_mes.isEmpty {
            let firstMessage = substituteParams(character.first_mes)
            chatFile.addCharacterMessage(firstMessage)
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
        tokenCount = messages.reduce(0) { $0 + tokenizer.countTokens($1.mes) }
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
