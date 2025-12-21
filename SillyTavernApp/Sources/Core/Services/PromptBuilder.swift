import Foundation

// MARK: - Injection Position

/// Controls where prompts are positioned in the final message list.
enum InjectionPosition: Int, Codable, Sendable {
    /// Prompt is positioned based on its order relative to other prompts
    case relative = 0
    /// Prompt is injected at a specific depth in the chat history
    case absolute = 1
}

// MARK: - Prompt Role (uses LLMRole from LLMProvider)

typealias PromptRole = LLMRole

// MARK: - Prompt Entry

/// A single prompt entry to be included in the final message list.
struct PromptEntry: Identifiable, Sendable {
    let id: UUID
    var identifier: String
    var role: PromptRole
    var content: String
    var enabled: Bool

    // Positioning
    var injectionPosition: InjectionPosition
    var injectionDepth: Int
    var injectionOrder: Int

    // Flags
    var isSystemPrompt: Bool
    var forbidOverrides: Bool
    var isMarker: Bool

    // Relative positioning (for extension prompts)
    var relativePosition: RelativePosition?

    init(
        identifier: String,
        role: PromptRole = .system,
        content: String,
        enabled: Bool = true,
        injectionPosition: InjectionPosition = .relative,
        injectionDepth: Int = 4,
        injectionOrder: Int = 100,
        isSystemPrompt: Bool = true,
        forbidOverrides: Bool = false,
        isMarker: Bool = false,
        relativePosition: RelativePosition? = nil
    ) {
        self.id = UUID()
        self.identifier = identifier
        self.role = role
        self.content = content
        self.enabled = enabled
        self.injectionPosition = injectionPosition
        self.injectionDepth = injectionDepth
        self.injectionOrder = injectionOrder
        self.isSystemPrompt = isSystemPrompt
        self.forbidOverrides = forbidOverrides
        self.isMarker = isMarker
        self.relativePosition = relativePosition
    }
}

/// Position relative to a marker (typically 'main')
struct RelativePosition: Sendable {
    var marker: String
    var offset: Int  // Positive = after, Negative = before
}

// MARK: - Generation Type

/// The type of generation being performed.
enum GenerationType: String, Sendable {
    case normal
    case impersonate
    case swipe
    case regenerate
    case quiet
    case `continue`
}

// MARK: - Prompt Settings

/// Settings that control prompt assembly.
struct PromptSettings: Sendable {
    // Main prompts
    var mainPrompt: String = "Write {{char}}'s next reply in a fictional chat between {{char}} and {{user}}."
    var jailbreakPrompt: String = ""
    var nsfwPrompt: String = ""

    // Formatting
    var scenarioFormat: String = "[Scenario: {{scenario}}]"
    var personalityFormat: String = "[{{char}}'s personality: {{personality}}]"
    var worldInfoFormat: String = "[Details of the fictional world the RP is set in:\n{{info}}]"

    // Special prompts
    var impersonationPrompt: String = ""
    var groupNudgePrompt: String = ""
    var continueNudgePrompt: String = ""

    // Token limits
    var maxContextTokens: Int = 8192
    var maxResponseTokens: Int = 1024

    // Behavior flags
    var pinExamples: Bool = false
    var sendIfEmpty: String = ""
}

// MARK: - Extension Prompts

/// Container for extension-injected prompts (memory, vectors, etc.)
struct ExtensionPrompts: Sendable {
    var summary: ExtensionPrompt?
    var authorsNote: ExtensionPrompt?
    var vectorsMemory: ExtensionPrompt?
    var smartContext: ExtensionPrompt?
    var depthPrompt: ExtensionPrompt?
    var custom: [String: ExtensionPrompt] = [:]
}

struct ExtensionPrompt: Sendable {
    var value: String
    var role: PromptRole
    var position: Int  // Depth in chat
    var enabled: Bool
}

// MARK: - Built Prompt Result

/// The result of prompt building - ready to send to an LLM.
struct BuiltPrompt: Sendable {
    var messages: [LLMMessage]
    var tokenCount: Int
    var debugInfo: DebugInfo?

    struct DebugInfo: Sendable {
        var promptOrder: [String]
        var tokenBreakdown: [String: Int]
        var trimmedMessages: Int
    }
}

// MARK: - Prompt Builder

/// Assembles prompts for chat completion based on SillyTavern's logic.
///
/// Prompt order (from original openai.js):
/// 1. worldInfoBefore
/// 2. main (system prompt)
/// 3. worldInfoAfter
/// 4. charDescription
/// 5. charPersonality
/// 6. scenario
/// 7. personaDescription
/// 8. nsfw, jailbreak
/// 9. User prompts
/// 10. Chat history (with absolute prompts injected at depth)
/// 11. Control prompts (impersonate, quietPrompt) - always last
struct PromptBuilder {
    let character: CharacterCard
    let settings: PromptSettings
    let worldInfo: [WorldInfoEntry]
    let extensionPrompts: ExtensionPrompts

    // Optional persona
    var personaDescription: String?
    var personaName: String?

    // MARK: - Build

    /// Build the final prompt for sending to an LLM.
    func build(
        chatHistory: [LLMMessage],
        type: GenerationType = .normal,
        quietPrompt: String? = nil,
        tokenCounter: @Sendable (String) -> Int = { $0.count / 4 }  // Simple estimate
    ) -> BuiltPrompt {
        var prompts: [PromptEntry] = []
        var absolutePrompts: [PromptEntry] = []
        var debugOrder: [String] = []
        var tokenBreakdown: [String: Int] = [:]

        // 1. Build world info (before)
        let (worldInfoBefore, worldInfoAfter) = buildWorldInfo(chatHistory: chatHistory)
        if !worldInfoBefore.isEmpty {
            let formatted = formatWorldInfo(worldInfoBefore)
            prompts.append(PromptEntry(
                identifier: "worldInfoBefore",
                content: formatted
            ))
        }

        // 2. Main prompt (system prompt) - can be overridden by character
        let mainContent = resolveMainPrompt()
        prompts.append(PromptEntry(
            identifier: "main",
            content: mainContent,
            isSystemPrompt: true,
            isMarker: true
        ))

        // 3. World info (after)
        if !worldInfoAfter.isEmpty {
            let formatted = formatWorldInfo(worldInfoAfter)
            prompts.append(PromptEntry(
                identifier: "worldInfoAfter",
                content: formatted
            ))
        }

        // 4. Character description
        if !character.description.isEmpty {
            prompts.append(PromptEntry(
                identifier: "charDescription",
                content: character.description
            ))
        }

        // 5. Character personality (formatted)
        if !character.personality.isEmpty {
            let formatted = formatPersonality(character.personality)
            prompts.append(PromptEntry(
                identifier: "charPersonality",
                content: formatted
            ))
        }

        // 6. Scenario (formatted)
        if !character.scenario.isEmpty {
            let formatted = formatScenario(character.scenario)
            prompts.append(PromptEntry(
                identifier: "scenario",
                content: formatted
            ))
        }

        // 7. Persona description
        if let persona = personaDescription, !persona.isEmpty {
            prompts.append(PromptEntry(
                identifier: "personaDescription",
                content: persona
            ))
        }

        // 8. NSFW prompt
        if !settings.nsfwPrompt.isEmpty {
            prompts.append(PromptEntry(
                identifier: "nsfw",
                content: settings.nsfwPrompt,
                isSystemPrompt: true
            ))
        }

        // 9. Jailbreak prompt - can be overridden by character
        let jailbreakContent = resolveJailbreakPrompt()
        if !jailbreakContent.isEmpty {
            prompts.append(PromptEntry(
                identifier: "jailbreak",
                content: jailbreakContent,
                isSystemPrompt: true
            ))
        }

        // 10. Character's depth prompt (absolute position)
        if let depthPrompt = character.depth_prompt, !depthPrompt.prompt.isEmpty {
            absolutePrompts.append(PromptEntry(
                identifier: "characterDepthPrompt",
                role: PromptRole(rawValue: depthPrompt.role) ?? .system,
                content: depthPrompt.prompt,
                injectionPosition: .absolute,
                injectionDepth: depthPrompt.depth,
                injectionOrder: 100
            ))
        }

        // 11. Extension prompts (summary, author's note, vectors)
        if let summary = extensionPrompts.summary, summary.enabled, !summary.value.isEmpty {
            absolutePrompts.append(PromptEntry(
                identifier: "summary",
                role: summary.role,
                content: summary.value,
                injectionPosition: .absolute,
                injectionDepth: summary.position
            ))
        }

        if let authorsNote = extensionPrompts.authorsNote, authorsNote.enabled, !authorsNote.value.isEmpty {
            absolutePrompts.append(PromptEntry(
                identifier: "authorsNote",
                role: authorsNote.role,
                content: authorsNote.value,
                injectionPosition: .absolute,
                injectionDepth: authorsNote.position
            ))
        }

        if let vectors = extensionPrompts.vectorsMemory, vectors.enabled, !vectors.value.isEmpty {
            absolutePrompts.append(PromptEntry(
                identifier: "vectorsMemory",
                role: .system,
                content: vectors.value,
                injectionPosition: .absolute,
                injectionDepth: vectors.position
            ))
        }

        // Build control prompts (always last)
        var controlPrompts: [PromptEntry] = []

        if type == .impersonate && !settings.impersonationPrompt.isEmpty {
            controlPrompts.append(PromptEntry(
                identifier: "impersonate",
                content: substituteParams(settings.impersonationPrompt)
            ))
        }

        if let quiet = quietPrompt, !quiet.isEmpty {
            controlPrompts.append(PromptEntry(
                identifier: "quietPrompt",
                content: quiet
            ))
        }

        // Calculate token budget
        let reservedTokens = 3  // For assistant primer
        var tokenBudget = settings.maxContextTokens - settings.maxResponseTokens - reservedTokens

        // Reserve tokens for control prompts
        for prompt in controlPrompts {
            let tokens = tokenCounter(prompt.content)
            tokenBudget -= tokens
            tokenBreakdown[prompt.identifier] = tokens
        }

        // Convert prompts to messages and count tokens
        var messages: [LLMMessage] = []

        for prompt in prompts where prompt.enabled && !prompt.content.isEmpty {
            let substituted = substituteParams(prompt.content)
            let tokens = tokenCounter(substituted)

            if tokens <= tokenBudget {
                messages.append(LLMMessage(role: prompt.role, content: substituted))
                tokenBudget -= tokens
                tokenBreakdown[prompt.identifier] = tokens
                debugOrder.append(prompt.identifier)
            }
        }

        // Add chat history with absolute prompt injection
        let (historyMessages, trimmedCount) = buildChatHistory(
            chatHistory: chatHistory,
            absolutePrompts: absolutePrompts,
            tokenBudget: tokenBudget,
            tokenCounter: tokenCounter
        )
        messages.append(contentsOf: historyMessages)

        // Add control prompts at the end
        for prompt in controlPrompts {
            let substituted = substituteParams(prompt.content)
            messages.append(LLMMessage(role: prompt.role, content: substituted))
            debugOrder.append(prompt.identifier)
        }

        // Calculate total tokens
        let totalTokens = messages.reduce(0) { $0 + tokenCounter($1.content.textValue) }

        return BuiltPrompt(
            messages: messages,
            tokenCount: totalTokens,
            debugInfo: BuiltPrompt.DebugInfo(
                promptOrder: debugOrder,
                tokenBreakdown: tokenBreakdown,
                trimmedMessages: trimmedCount
            )
        )
    }

    // MARK: - Private Helpers

    /// Resolve the main prompt, applying character override if allowed.
    private func resolveMainPrompt() -> String {
        // Character can override the main prompt via system_prompt field
        if !character.system_prompt.isEmpty {
            return character.system_prompt
        }
        return settings.mainPrompt
    }

    /// Resolve the jailbreak prompt, applying character override if allowed.
    private func resolveJailbreakPrompt() -> String {
        // Character can override via post_history_instructions field
        if !character.post_history_instructions.isEmpty {
            return character.post_history_instructions
        }
        return settings.jailbreakPrompt
    }

    /// Build world info entries that match the current chat context.
    private func buildWorldInfo(chatHistory: [LLMMessage]) -> (before: [WorldInfoEntry], after: [WorldInfoEntry]) {
        // Combine recent chat for keyword matching
        let recentContext = chatHistory.suffix(10)
            .map { $0.content.textValue }
            .joined(separator: "\n")

        var beforeEntries: [WorldInfoEntry] = []
        var afterEntries: [WorldInfoEntry] = []

        for entry in worldInfo where entry.enabled {
            // Check if entry matches
            if entryMatches(entry, context: recentContext) {
                // Position 0 = before main, Position 1 = after main
                if entry.position == 0 {
                    beforeEntries.append(entry)
                } else {
                    afterEntries.append(entry)
                }
            }
        }

        // Sort by order
        beforeEntries.sort { $0.order < $1.order }
        afterEntries.sort { $0.order < $1.order }

        return (beforeEntries, afterEntries)
    }

    /// Check if a world info entry matches the context.
    private func entryMatches(_ entry: WorldInfoEntry, context: String) -> Bool {
        // Constant entries always match
        if entry.constant { return true }

        let searchContext = entry.case_sensitive ? context : context.lowercased()

        // Check primary keys
        for key in entry.keys where !key.isEmpty {
            let searchKey = entry.case_sensitive ? key : key.lowercased()

            if entry.match_whole_words {
                // Word boundary matching
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: searchKey))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: entry.case_sensitive ? [] : .caseInsensitive) {
                    let range = NSRange(searchContext.startIndex..., in: searchContext)
                    if regex.firstMatch(in: searchContext, range: range) != nil {
                        return checkSecondaryKeys(entry, context: searchContext)
                    }
                }
            } else {
                if searchContext.contains(searchKey) {
                    return checkSecondaryKeys(entry, context: searchContext)
                }
            }
        }

        return false
    }

    /// Check secondary keys (for selective entries).
    private func checkSecondaryKeys(_ entry: WorldInfoEntry, context: String) -> Bool {
        guard entry.selective, !entry.secondary_keys.isEmpty else { return true }

        for key in entry.secondary_keys where !key.isEmpty {
            let searchKey = entry.case_sensitive ? key : key.lowercased()
            if context.contains(searchKey) {
                return true
            }
        }

        return false
    }

    /// Format world info entries into a single string.
    private func formatWorldInfo(_ entries: [WorldInfoEntry]) -> String {
        let combined = entries.map { $0.content }.joined(separator: "\n")
        return substituteParams(settings.worldInfoFormat.replacingOccurrences(of: "{{info}}", with: combined))
    }

    /// Format personality with template.
    private func formatPersonality(_ personality: String) -> String {
        substituteParams(settings.personalityFormat.replacingOccurrences(of: "{{personality}}", with: personality))
    }

    /// Format scenario with template.
    private func formatScenario(_ scenario: String) -> String {
        substituteParams(settings.scenarioFormat.replacingOccurrences(of: "{{scenario}}", with: scenario))
    }

    /// Build chat history with absolute prompt injection.
    private func buildChatHistory(
        chatHistory: [LLMMessage],
        absolutePrompts: [PromptEntry],
        tokenBudget: Int,
        tokenCounter: @Sendable (String) -> Int
    ) -> (messages: [LLMMessage], trimmedCount: Int) {
        var remainingBudget = tokenBudget
        var trimmedCount = 0

        // Sort absolute prompts by depth (higher depth = inserted earlier)
        let sortedAbsolute = absolutePrompts.sorted { $0.injectionDepth > $1.injectionDepth }

        // Process chat history from newest to oldest
        var historyMessages: [(index: Int, message: LLMMessage, tokens: Int)] = []

        for (index, message) in chatHistory.enumerated().reversed() {
            // Message already has correct role, just need to add name if missing
            let messageText = message.content.textValue
            let llmMessage = LLMMessage(
                role: message.role,
                content: messageText,
                name: message.name ?? (message.role == .user ? (personaName ?? "User") : character.name)
            )
            let tokens = tokenCounter(messageText)
            historyMessages.append((index, llmMessage, tokens))
        }

        // Add messages that fit within budget (newest first, then reverse)
        var includedMessages: [(index: Int, message: LLMMessage)] = []

        for (index, message, tokens) in historyMessages {
            if tokens <= remainingBudget {
                includedMessages.append((index, message))
                remainingBudget -= tokens
            } else {
                trimmedCount += 1
            }
        }

        // Reverse to get chronological order
        includedMessages.reverse()

        // Insert absolute prompts at their specified depths
        // Depth is counted from the end (0 = last message, 1 = second to last, etc.)
        for prompt in sortedAbsolute where !prompt.content.isEmpty {
            let depth = prompt.injectionDepth
            let insertIndex = max(0, includedMessages.count - depth)

            let tokens = tokenCounter(prompt.content)
            if tokens <= remainingBudget {
                let llmMessage = LLMMessage(role: prompt.role, content: prompt.content)
                includedMessages.insert((insertIndex, llmMessage), at: insertIndex)
                remainingBudget -= tokens
            }
        }

        let messages = includedMessages.map { $0.message }

        return (messages, trimmedCount)
    }

    /// Substitute common parameters in a string.
    private func substituteParams(_ text: String) -> String {
        var result = text

        // Character placeholders
        result = result.replacingOccurrences(of: "{{char}}", with: character.name)
        result = result.replacingOccurrences(of: "{{Char}}", with: character.name)
        result = result.replacingOccurrences(of: "{{CHARACTER}}", with: character.name)

        // User placeholders
        let userName = personaName ?? "User"
        result = result.replacingOccurrences(of: "{{user}}", with: userName)
        result = result.replacingOccurrences(of: "{{User}}", with: userName)
        result = result.replacingOccurrences(of: "{{USER}}", with: userName)

        // Date/time (basic support)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        result = result.replacingOccurrences(of: "{{date}}", with: formatter.string(from: Date()))

        formatter.dateFormat = "h:mm a"
        result = result.replacingOccurrences(of: "{{time}}", with: formatter.string(from: Date()))

        // Random number
        if result.contains("{{random}}") {
            result = result.replacingOccurrences(of: "{{random}}", with: String(Int.random(in: 1...100)))
        }

        return result
    }
}
