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

    // Save handler - called after messages change to persist to disk
    var saveHandler: (() async -> Void)?

    // Generation task for cancellation support
    private var generationTask: Task<Void, Never>?

    // Dependencies
    private var provider: (any LLMProvider)?
    private var promptSettings: PromptSettings = PromptSettings()
    private var llmOptions: LLMOptions = LLMOptions()
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
        options: LLMOptions = LLMOptions(),
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
        self.llmOptions = options
        self.worldInfo = worldInfo
        self.extensionPrompts = extensionPrompts
        self.tokenizer = tokenizer
        self.model = model
        self.maxContextTokens = settings.maxContextTokens
        self.personaName = personaName
        self.personaDescription = personaDescription
    }

    // MARK: - Stop Generation

    /// Stop the current generation
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        streamingText = ""
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

        // Save after adding user message
        await saveHandler?()

        // Run generation in a cancellable task
        generationTask = Task {
            await generate(chatFile: chatFile, character: character, provider: provider)
        }
        await generationTask?.value
    }

    /// Regenerate the last assistant message
    func regenerate() async {
        guard !isGenerating else { return }
        guard let chatFile = chatFile, let character = character, let provider = provider else { return }

        // Remove last assistant message if present
        if let last = chatFile.messages.last, !last.is_user {
            chatFile.messages.removeLast()
        }

        generationTask = Task {
            await generate(chatFile: chatFile, character: character, provider: provider)
        }
        await generationTask?.value
    }

    /// Continue the last assistant message
    func continueGeneration() async {
        guard !isGenerating else { return }
        guard let chatFile = chatFile, let character = character, let provider = provider else { return }

        generationTask = Task {
            await generate(chatFile: chatFile, character: character, provider: provider, type: .continue)
        }
        await generationTask?.value
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

            // Stream the response
            let stream = try await provider.send(
                messages: builtPrompt.messages,
                model: self.model,
                options: llmOptions
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
                // Check for cancellation
                if Task.isCancelled {
                    // Keep the partial response
                    break
                }
                streamingText += chunk
                // Update the last message with streaming content
                if let lastMessage = chatFile.messages.last {
                    lastMessage.mes = continuePrefix + streamingText
                }
            }

            // Finalize
            streamingText = ""
            generationTask = nil

            // Save after generation completes (even if cancelled, save partial response)
            await saveHandler?()

        } catch let llmError as LLMError {
            error = .providerError(llmError)
            // Remove the placeholder message on error
            if let last = chatFile.messages.last, last.mes.isEmpty || last.mes == streamingText {
                chatFile.messages.removeLast()
            }
            // Save after cleanup
            await saveHandler?()
        } catch {
            self.error = .unknown(error)
            if let last = chatFile.messages.last, last.mes.isEmpty {
                chatFile.messages.removeLast()
            }
            // Save after cleanup
            await saveHandler?()
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

            let stream = try await provider.send(
                messages: builtPrompt.messages,
                model: self.model,
                options: llmOptions
            )

            var newSwipeContent = ""
            for try await chunk in stream {
                newSwipeContent += chunk
                streamingText = newSwipeContent
            }

            // Add the new swipe
            lastMessage.addSwipe(newSwipeContent)
            streamingText = ""

            // Save after swipe completes
            await saveHandler?()

        } catch {
            self.error = .unknown(error)
        }

        isGenerating = false
    }

    // MARK: - Message Actions

    /// Delete a message at index
    func deleteMessage(at index: Int) async {
        guard let chatFile = chatFile else { return }
        chatFile.deleteMessage(at: index)
        await saveHandler?()
    }

    /// Edit a message
    func editMessage(at index: Int, newContent: String) async {
        guard let chatFile = chatFile else { return }
        guard chatFile.messages.indices.contains(index) else { return }
        chatFile.messages[index].mes = newContent
        await saveHandler?()
    }

    /// Truncate messages after index and regenerate
    func regenerateFrom(index: Int) async {
        guard let chatFile = chatFile else { return }

        // Remove all messages after this index
        while chatFile.messages.count > index + 1 {
            chatFile.messages.removeLast()
        }

        // Save the truncation
        await saveHandler?()

        // Regenerate from the last message
        await regenerate()
    }

    /// Clear all messages and start fresh
    func clearChat() async {
        guard let chatFile = chatFile, let character = character else { return }

        chatFile.clearMessages()

        // Re-add first message
        if !character.first_mes.isEmpty {
            let firstMessage = substituteParams(character.first_mes)
            chatFile.addCharacterMessage(firstMessage)
        }

        await saveHandler?()
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
