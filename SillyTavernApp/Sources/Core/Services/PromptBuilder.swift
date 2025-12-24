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
    var groupNudgePrompt: String = "[Write the next reply only as {{char}}.]"
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

// MARK: - Group Context

/// Context for group chat prompt building.
/// Provides access to all group members and settings for APPEND mode card joining.
/// Note: Not Sendable because it references @Observable model objects.
struct GroupContext {
    let group: CharacterGroup
    let members: [CharacterCard]        // All resolved members
    let currentSpeaker: CharacterCard   // Character generating this message
    let chatMetadata: [String: JSONValue]  // For scenario/mes_example overrides
    let personaName: String?

    /// Get members to include in card joining based on generation mode
    func membersForCardJoin() -> [CharacterCard] {
        switch group.generationMode {
        case .swap:
            return []  // SWAP mode doesn't join cards
        case .append:
            // Include enabled members only
            return members.filter { !group.disabledMembers.contains($0.avatar) }
        case .appendDisabled:
            // Include all members
            return members
        }
    }

    /// Get depth prompts from all eligible members
    func collectDepthPrompts() -> [PromptEntry] {
        guard group.generationMode != .swap else {
            // In SWAP mode, only use current speaker's depth prompt
            return []
        }

        var prompts: [PromptEntry] = []

        for member in members {
            // Skip disabled members unless it's the current speaker
            if group.disabledMembers.contains(member.avatar) && member.id != currentSpeaker.id {
                continue
            }

            if let depthPrompt = member.depth_prompt, !depthPrompt.prompt.isEmpty {
                // Substitute macros with this member's name (not the current speaker).
                let substitutedContent = substituteParamsForMember(depthPrompt.prompt, characterName: member.name)
                prompts.append(PromptEntry(
                    identifier: "memberDepthPrompt_\(member.name)",
                    role: PromptRole(rawValue: depthPrompt.role) ?? .system,
                    content: substitutedContent,
                    injectionPosition: .absolute,
                    injectionDepth: depthPrompt.depth,
                    injectionOrder: 100
                ))
            }
        }

        return prompts
    }

    /// Substitute macros with a specific character name (group depth prompts).
    private func substituteParamsForMember(_ text: String, characterName: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{{char}}", with: characterName)
        result = result.replacingOccurrences(of: "{{Char}}", with: characterName)
        result = result.replacingOccurrences(of: "{{CHARACTER}}", with: characterName)

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
/// This follows the hardcoded assembly order from openai.js `populateChatCompletion()`,
/// NOT the user-customizable PromptManager order (which SillyTavern uses for UI ordering).
///
/// Assembly order:
/// 1. worldInfoBefore
/// 2. main (system prompt, can be overridden by character.system_prompt)
/// 3. worldInfoAfter
/// 4. charDescription (joined for group APPEND modes)
/// 5. charPersonality (joined for group APPEND modes)
/// 6. scenario (joined for group APPEND modes, respects chat_metadata override)
/// 7. personaDescription
/// 8. nsfw
/// 9. dialogueExamples (mes_example)
/// 10. jailbreak
/// 11. Depth prompts (absolute position injection)
/// 12. Extension prompts (summary, author's note, vectors)
/// 13. Chat history (with absolute prompts injected at depth by order/role priority)
/// 14. Control prompts (impersonate, groupNudge, quietPrompt) - always last
struct PromptBuilder {
    let character: CharacterCard
    let settings: PromptSettings
    let worldInfo: [WorldInfoEntry]
    let extensionPrompts: ExtensionPrompts

    // Optional persona
    var personaDescription: String?
    var personaName: String?

    // Optional group context for multi-character chats
    var groupContext: GroupContext?

    // MARK: - Build

    /// Build the final prompt for sending to an LLM.
    func build(
        chatHistory: [LLMMessage],
        type: GenerationType = .normal,
        isGroupChat: Bool = false,
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

        // 4-6. Character cards (description, personality, scenario)
        // For group APPEND modes, join all member cards with prefix/suffix
        let (description, personality, scenario, mesExamples) = buildCharacterCards()

        if !description.isEmpty {
            prompts.append(PromptEntry(
                identifier: "charDescription",
                content: description
            ))
        }

        if !personality.isEmpty {
            let formatted = formatPersonality(personality)
            prompts.append(PromptEntry(
                identifier: "charPersonality",
                content: formatted
            ))
        }

        if !scenario.isEmpty {
            let formatted = formatScenario(scenario)
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

        // 9. Dialogue examples (after nsfw, before jailbreak per SillyTavern default order)
        if !mesExamples.isEmpty {
            prompts.append(PromptEntry(
                identifier: "dialogueExamples",
                content: mesExamples
            ))
        }

        // 10. Jailbreak prompt - can be overridden by character
        let jailbreakContent = resolveJailbreakPrompt()
        if !jailbreakContent.isEmpty {
            prompts.append(PromptEntry(
                identifier: "jailbreak",
                content: jailbreakContent,
                isSystemPrompt: true
            ))
        }

        // 11. Depth prompts (from character or all group members)
        if let groupContext = groupContext, groupContext.group.generationMode.joinsCards {
            // Group APPEND modes: collect depth prompts from all eligible members
            absolutePrompts.append(contentsOf: groupContext.collectDepthPrompts())
        } else if let depthPrompt = character.depth_prompt, !depthPrompt.prompt.isEmpty {
            // Single character or SWAP mode: use current character's depth prompt only
            absolutePrompts.append(PromptEntry(
                identifier: "characterDepthPrompt",
                role: PromptRole(rawValue: depthPrompt.role) ?? .system,
                content: depthPrompt.prompt,
                injectionPosition: .absolute,
                injectionDepth: depthPrompt.depth,
                injectionOrder: 100
            ))
        }

        // 12. Extension prompts (summary, author's note, vectors)
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

        // Continue nudge prompt
        if type == .continue && !settings.continueNudgePrompt.isEmpty {
            controlPrompts.append(PromptEntry(
                identifier: "continueNudge",
                content: substituteParams(settings.continueNudgePrompt)
            ))
        }

        // Group nudge prompt (excluded for impersonate, as in SillyTavern)
        if isGroupChat && type != .impersonate && !settings.groupNudgePrompt.isEmpty {
            controlPrompts.append(PromptEntry(
                identifier: "groupNudge",
                content: substituteParams(settings.groupNudgePrompt)
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

    /// Build character cards - joins member cards for group APPEND modes
    private func buildCharacterCards() -> (description: String, personality: String, scenario: String, mesExamples: String) {
        guard let groupContext = groupContext, groupContext.group.generationMode.joinsCards else {
            // Single character or SWAP mode: use current character only
            return (
                description: character.description,
                personality: character.personality,
                scenario: character.scenario,
                mesExamples: character.mes_example
            )
        }

        let group = groupContext.group
        let members = groupContext.membersForCardJoin()
        let userName = personaName ?? "User"

        // Join member cards with prefix/suffix
        var descriptions: [String] = []
        var personalities: [String] = []
        var scenarios: [String] = []
        var mesExamplesArray: [String] = []

        for member in members {
            // Apply prefix/suffix and macro replacement for each field
            if !member.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                descriptions.append(prepareForJoin(
                    value: member.description,
                    fieldName: "Description",
                    characterName: member.name,
                    prefix: group.generationModeJoinPrefix,
                    suffix: group.generationModeJoinSuffix,
                    userName: userName
                ))
            }

            if !member.personality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                personalities.append(prepareForJoin(
                    value: member.personality,
                    fieldName: "Personality",
                    characterName: member.name,
                    prefix: group.generationModeJoinPrefix,
                    suffix: group.generationModeJoinSuffix,
                    userName: userName
                ))
            }

            if !member.scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scenarios.append(prepareForJoin(
                    value: member.scenario,
                    fieldName: "Scenario",
                    characterName: member.name,
                    prefix: group.generationModeJoinPrefix,
                    suffix: group.generationModeJoinSuffix,
                    userName: userName
                ))
            }

            if !member.mes_example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var example = member.mes_example.trimmingCharacters(in: .whitespacesAndNewlines)
                // Ensure mes_example starts with <START>
                if !example.hasPrefix("<START>") {
                    example = "<START>\n" + example
                }
                mesExamplesArray.append(prepareForJoin(
                    value: example,
                    fieldName: "Example Messages",
                    characterName: member.name,
                    prefix: group.generationModeJoinPrefix,
                    suffix: group.generationModeJoinSuffix,
                    userName: userName
                ))
            }
        }

        let joinedDescription = descriptions.joined(separator: "\n")
        let joinedPersonality = personalities.joined(separator: "\n")
        let joinedMesExamples = mesExamplesArray.joined(separator: "\n")

        // Check for scenario override in chat_metadata
        let scenarioOverride = groupContext.chatMetadata["scenario"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let joinedScenario: String
        if !scenarioOverride.isEmpty {
            joinedScenario = substituteParamsForCharacter(scenarioOverride, characterName: character.name)
        } else {
            joinedScenario = scenarios.joined(separator: "\n")
        }

        // Check for mes_example override in chat_metadata
        let mesExampleOverride = groupContext.chatMetadata["mes_example"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalMesExamples: String
        if !mesExampleOverride.isEmpty {
            finalMesExamples = substituteParamsForCharacter(mesExampleOverride, characterName: character.name)
        } else {
            finalMesExamples = joinedMesExamples
        }

        return (joinedDescription, joinedPersonality, joinedScenario, finalMesExamples)
    }

    /// Prepare a field value for joining with prefix/suffix
    private func prepareForJoin(
        value: String,
        fieldName: String,
        characterName: String,
        prefix: String,
        suffix: String,
        userName: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Replace <FIELDNAME> in prefix/suffix and run macro replacement
        let processedPrefix = substituteParamsForCharacter(
            prefix.replacingOccurrences(of: "<FIELDNAME>", with: fieldName, options: .caseInsensitive),
            characterName: characterName
        )

        let processedSuffix = substituteParamsForCharacter(
            suffix.replacingOccurrences(of: "<FIELDNAME>", with: fieldName, options: .caseInsensitive),
            characterName: characterName
        )

        // Run macro replacement on the value itself
        let processedValue = substituteParamsForCharacter(trimmed, characterName: characterName)

        return processedPrefix + processedValue + processedSuffix
    }

    /// Substitute params for a specific character (used in group card joining)
    private func substituteParamsForCharacter(_ text: String, characterName: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{{char}}", with: characterName)
        result = result.replacingOccurrences(of: "{{Char}}", with: characterName)
        result = result.replacingOccurrences(of: "{{CHARACTER}}", with: characterName)

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
    /// Matches SillyTavern's populationInjectionPrompts: groups by depth, then by order (low to high),
    /// then by role priority (assistant, user, system) to reflect post-reversal ordering.
    private func buildChatHistory(
        chatHistory: [LLMMessage],
        absolutePrompts: [PromptEntry],
        tokenBudget: Int,
        tokenCounter: @Sendable (String) -> Int
    ) -> (messages: [LLMMessage], trimmedCount: Int) {
        var remainingBudget = tokenBudget
        var trimmedCount = 0

        // Process chat history from newest to oldest
        var historyMessages: [(index: Int, message: LLMMessage, tokens: Int)] = []

        for (index, message) in chatHistory.enumerated().reversed() {
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
        var includedMessages: [LLMMessage] = []

        for (_, message, tokens) in historyMessages {
            if tokens <= remainingBudget {
                includedMessages.append(message)
                remainingBudget -= tokens
            } else {
                trimmedCount += 1
            }
        }

        // Reverse to get chronological order
        includedMessages.reverse()

        // Build injection messages grouped by depth, order, and role (matches SillyTavern's populationInjectionPrompts)
        let maxDepth = absolutePrompts.map(\.injectionDepth).max() ?? 0
        var totalInserted = 0

        for depth in 0...maxDepth {
            let depthPrompts = absolutePrompts.filter { $0.injectionDepth == depth && !$0.content.isEmpty }
            guard !depthPrompts.isEmpty else { continue }

            // Group by injection order
            var orderGroups: [Int: [PromptEntry]] = [:]
            for prompt in depthPrompts {
                let order = prompt.injectionOrder
                orderGroups[order, default: []].append(prompt)
            }

            // Process order groups from low to high so higher orders end up later in
            // the final array (matching SillyTavern's behavior after its array reversal)
            let orders = orderGroups.keys.sorted(by: <)
            var roleMessages: [LLMMessage] = []

            for order in orders {
                guard let orderPrompts = orderGroups[order] else { continue }

                // Process roles in reverse order (assistant, user, system) so that after
                // appending to roleMessages, the final order matches SillyTavern's post-reversal
                // result where system messages end up last within a depth/order group
                let rolePriority: [PromptRole] = [.assistant, .user, .system]
                for role in rolePriority {
                    let roleContent = orderPrompts
                        .filter { $0.role == role }
                        .map { substituteParams($0.content) }
                        .joined(separator: "\n")

                    if !roleContent.isEmpty {
                        let tokens = tokenCounter(roleContent)
                        if tokens <= remainingBudget {
                            roleMessages.append(LLMMessage(role: role, content: roleContent))
                            remainingBudget -= tokens
                        }
                    }
                }
            }

            // Insert at the correct depth position (depth counted from newest message)
            // SillyTavern counts depth from the END: depth 0 = after newest, depth 1 = one before newest
            if !roleMessages.isEmpty {
                let insertIndex = max(0, includedMessages.count - depth - totalInserted)
                includedMessages.insert(contentsOf: roleMessages, at: insertIndex)
                totalInserted += roleMessages.count
            }
        }

        return (includedMessages, trimmedCount)
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
