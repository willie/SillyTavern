import Foundation
import Observation

// MARK: - Character Group Model

/// A group chat containing multiple characters.
/// Matches SillyTavern's group format exactly.
@Observable
final class CharacterGroup: Identifiable, Hashable {
    // ID is a string timestamp (e.g., "1703289600000"), not UUID
    let id: String
    var name: String
    var members: [String]  // Avatar filenames (e.g., "Nikki.png")
    var activationStrategy: ActivationStrategy
    var generationMode: GenerationMode
    var allowSelfResponse: Bool

    // These are avatar filename strings, not UUIDs
    var favoriteMembers: Set<String>
    var disabledMembers: Set<String>

    // Group-specific settings
    var avatarURL: String?
    var fav: Bool
    var groupNudge: String
    var jailbreak: String
    var chats: [String]       // Chat IDs (SillyTavern format)
    var chatID: String?       // Current active chat ID
    var chatMetadata: [String: JSONValue]
    var pastMetadata: [String: JSONValue]

    // Auto-mode settings
    var autoModeDelay: Int
    var generationModeJoinPrefix: String
    var generationModeJoinSuffix: String
    var hideMutedSprites: Bool
    var dateLastChat: Int?

    // File storage
    var fileURL: URL?
    private var rawJSON: [String: JSONValue] = [:]

    // MARK: - Cached character references (not persisted)

    /// Resolved character cards for members (populated by GroupStore)
    var resolvedMembers: [CharacterCard] = []

    init(
        id: String = String(Int(Date().timeIntervalSince1970 * 1000)),
        name: String = ""
    ) {
        self.id = id
        self.name = name
        self.members = []
        self.activationStrategy = .natural
        self.generationMode = .swap
        self.allowSelfResponse = false
        self.favoriteMembers = []
        self.disabledMembers = []
        self.avatarURL = nil
        self.fav = false
        self.groupNudge = ""
        self.jailbreak = ""
        self.chats = []
        self.chatID = nil
        self.chatMetadata = [:]
        self.pastMetadata = [:]
        self.autoModeDelay = 5
        self.generationModeJoinPrefix = ""
        self.generationModeJoinSuffix = ""
        self.hideMutedSprites = false
        self.dateLastChat = nil
    }

    convenience init(fromJSON json: [String: JSONValue], url: URL? = nil) {
        // ID can be string or number in SillyTavern
        let id: String
        if let idString = json["id"]?.string {
            id = idString
        } else if let idNum = json["id"]?.number {
            id = String(Int(idNum))
        } else {
            id = String(Int(Date().timeIntervalSince1970 * 1000))
        }
        self.init(id: id)
        self.rawJSON = json
        self.fileURL = url
        load(from: json)
    }

    // MARK: - Load from JSON

    func load(from json: [String: JSONValue]) {
        self.rawJSON = json
        self.name = json["name"]?.string ?? ""

        // Members are avatar filenames
        if let memberArray = json["members"]?.array {
            self.members = memberArray.compactMap { $0.string }
        }

        if let strategy = json["activation_strategy"]?.int {
            self.activationStrategy = ActivationStrategy(rawValue: strategy) ?? .natural
        }
        if let mode = json["generation_mode"]?.int {
            self.generationMode = GenerationMode(rawValue: mode) ?? .swap
        }

        self.allowSelfResponse = json["allow_self_responses"]?.bool ?? false
        self.avatarURL = json["avatar_url"]?.string
        self.fav = json["fav"]?.bool ?? false
        self.groupNudge = json["group_nudge"]?.string ?? ""
        self.jailbreak = json["jailbreak"]?.string ?? ""

        // Favorites and disabled are avatar filename strings
        if let favs = json["favorites"]?.array {
            self.favoriteMembers = Set(favs.compactMap { $0.string })
        }
        if let disabled = json["disabled_members"]?.array {
            self.disabledMembers = Set(disabled.compactMap { $0.string })
        }

        // Chat IDs - handle both string and number
        if let chatArray = json["chats"]?.array {
            self.chats = chatArray.compactMap { value -> String? in
                if let str = value.string { return str }
                if let num = value.number { return String(Int(num)) }
                return nil
            }
        }
        if let chatIDStr = json["chat_id"]?.string {
            self.chatID = chatIDStr
        } else if let chatIDNum = json["chat_id"]?.number {
            self.chatID = String(Int(chatIDNum))
        }

        self.chatMetadata = json["chat_metadata"]?.object ?? [:]
        self.pastMetadata = json["past_metadata"]?.object ?? [:]

        // Auto-mode settings
        self.autoModeDelay = json["auto_mode_delay"]?.int ?? 5
        self.generationModeJoinPrefix = json["generation_mode_join_prefix"]?.string ?? ""
        self.generationModeJoinSuffix = json["generation_mode_join_suffix"]?.string ?? ""
        self.hideMutedSprites = json["hideMutedSprites"]?.bool ?? false
        self.dateLastChat = json["date_last_chat"]?.int
    }

    // MARK: - Save to JSON

    func toJSON() -> [String: JSONValue] {
        var json = rawJSON

        json["id"] = .string(id)
        json["name"] = .string(name)
        json["members"] = .array(members.map { .string($0) })
        json["activation_strategy"] = .number(Double(activationStrategy.rawValue))
        json["generation_mode"] = .number(Double(generationMode.rawValue))
        json["allow_self_responses"] = .bool(allowSelfResponse)
        if let avatarURL = avatarURL {
            json["avatar_url"] = .string(avatarURL)
        }
        json["fav"] = .bool(fav)
        json["group_nudge"] = .string(groupNudge)
        json["jailbreak"] = .string(jailbreak)
        json["favorites"] = .array(favoriteMembers.map { .string($0) })
        json["disabled_members"] = .array(disabledMembers.map { .string($0) })
        json["chats"] = .array(chats.map { .string($0) })
        if let chatID = chatID {
            json["chat_id"] = .string(chatID)
        }
        json["chat_metadata"] = .object(chatMetadata)
        json["past_metadata"] = .object(pastMetadata)
        json["auto_mode_delay"] = .number(Double(autoModeDelay))
        json["generation_mode_join_prefix"] = .string(generationModeJoinPrefix)
        json["generation_mode_join_suffix"] = .string(generationModeJoinSuffix)
        json["hideMutedSprites"] = .bool(hideMutedSprites)
        if let dateLastChat = dateLastChat {
            json["date_last_chat"] = .number(Double(dateLastChat))
        }

        return json
    }

    func toData(prettyPrinted: Bool = true) throws -> Data {
        let json = toJSON()
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(json)
    }

    // MARK: - Member Management

    /// Get enabled members (not in disabledMembers)
    var enabledMembers: [String] {
        members.filter { !disabledMembers.contains($0) }
    }

    /// Get enabled resolved characters
    var enabledCharacters: [CharacterCard] {
        resolvedMembers.filter { !disabledMembers.contains($0.avatar) }
    }

    /// Add a member to the group by avatar filename
    func addMember(_ avatar: String) {
        guard !members.contains(avatar) else { return }
        members.append(avatar)
    }

    /// Remove a member from the group by avatar filename
    func removeMember(_ avatar: String) {
        members.removeAll { $0 == avatar }
        favoriteMembers.remove(avatar)
        disabledMembers.remove(avatar)
    }

    /// Toggle member enabled state
    func toggleMember(_ avatar: String) {
        if disabledMembers.contains(avatar) {
            disabledMembers.remove(avatar)
        } else {
            disabledMembers.insert(avatar)
        }
    }

    /// Toggle member favorite state
    func toggleFavorite(_ avatar: String) {
        if favoriteMembers.contains(avatar) {
            favoriteMembers.remove(avatar)
        } else {
            favoriteMembers.insert(avatar)
        }
    }

    /// Check if a member is enabled
    func isMemberEnabled(_ avatar: String) -> Bool {
        !disabledMembers.contains(avatar)
    }

    /// Check if a member is favorited
    func isMemberFavorite(_ avatar: String) -> Bool {
        favoriteMembers.contains(avatar)
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: CharacterGroup, rhs: CharacterGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Activation Strategy

/// Determines how the next speaking character is selected.
enum ActivationStrategy: Int, CaseIterable, Sendable, Codable {
    case natural = 0      // AI decides who speaks based on context
    case list = 1         // Round-robin through enabled members
    case manual = 2       // User manually selects next speaker
    case pooled = 3       // Weighted random from pool

    var title: String {
        switch self {
        case .natural: return "Natural"
        case .list: return "List"
        case .manual: return "Manual"
        case .pooled: return "Pooled"
        }
    }

    var description: String {
        switch self {
        case .natural:
            return "AI decides who speaks based on the conversation context"
        case .list:
            return "Characters speak in order, cycling through the list"
        case .manual:
            return "You select which character speaks next"
        case .pooled:
            return "Random selection weighted by talkativeness"
        }
    }
}

// MARK: - Generation Mode

/// Controls how new messages are generated in group chat.
enum GenerationMode: Int, CaseIterable, Sendable, Codable {
    case swap = 0         // Replace the last AI message with new character
    case append = 1       // Append new message from next character

    var title: String {
        switch self {
        case .swap: return "Swap"
        case .append: return "Append"
        }
    }

    var description: String {
        switch self {
        case .swap:
            return "Regenerate replaces the last AI message"
        case .append:
            return "Regenerate adds a new message from the next character"
        }
    }
}

// MARK: - Group Chat State

/// Additional state for group chat sessions.
@Observable @MainActor
final class GroupChatState {
    var group: CharacterGroup?
    var currentSpeakerIndex: Int = 0
    var selectedNextSpeaker: CharacterCard?
    var speakingHistory: [String] = []  // Avatar filenames

    /// Get the next speaker based on activation strategy
    func getNextSpeaker(lastMessage: String? = nil, lastSpeakerName: String? = nil) -> CharacterCard? {
        guard let group = group else { return nil }
        let enabledChars = group.enabledCharacters

        guard !enabledChars.isEmpty else { return nil }

        switch group.activationStrategy {
        case .natural:
            // Natural mode uses mentions and talkativeness
            return selectNaturalOrder(
                from: enabledChars,
                input: lastMessage,
                bannedName: group.allowSelfResponse ? nil : lastSpeakerName
            )

        case .list:
            // Round-robin through enabled members
            let speaker = enabledChars[currentSpeakerIndex % enabledChars.count]
            currentSpeakerIndex = (currentSpeakerIndex + 1) % enabledChars.count
            return speaker

        case .manual:
            // Use selected speaker or first enabled
            return selectedNextSpeaker ?? enabledChars.first

        case .pooled:
            // Weighted random based on talkativeness
            return selectPooledSpeaker(from: enabledChars)
        }
    }

    /// Select speaker using natural order strategy
    /// Priority: 1) Mentioned characters, 2) Talkativeness roll, 3) Random fallback
    private func selectNaturalOrder(from characters: [CharacterCard], input: String?, bannedName: String?) -> CharacterCard? {
        guard !characters.isEmpty else { return nil }

        var activatedChars: [CharacterCard] = []

        // 1. Find mentions in input (excluding banned speaker)
        if let input = input, !input.isEmpty {
            let inputWords = extractWords(from: input.lowercased())
            for character in characters {
                guard character.name != bannedName else { continue }

                let nameWords = extractWords(from: character.name.lowercased())
                if inputWords.contains(where: { nameWords.contains($0) }) {
                    activatedChars.append(character)
                    break // Only add one mention
                }
            }
        }

        // 2. Activation by talkativeness (shuffled, excluding banned)
        var chattyChars: [CharacterCard] = []
        let shuffledChars = characters.shuffled()

        for character in shuffledChars {
            guard character.name != bannedName else { continue }

            let talkativeness = character.talkativeness
            let rollValue = Double.random(in: 0...1)

            if talkativeness >= rollValue {
                activatedChars.append(character)
            }
            if talkativeness > 0 {
                chattyChars.append(character)
            }
        }

        // 3. Pick random if no one activated
        if activatedChars.isEmpty {
            let pool = chattyChars.isEmpty ? characters : chattyChars
            // Filter out banned speaker
            let validPool = pool.filter { $0.name != bannedName }
            if let random = validPool.randomElement() {
                return random
            }
            // If all are banned (shouldn't happen), just pick first
            return characters.first
        }

        // Return first activated (prioritizes mentions)
        return activatedChars.first
    }

    /// Extract words from text for mention matching
    private func extractWords(from text: String) -> Set<String> {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
        return Set(words)
    }

    /// Select speaker using pooled (weighted) strategy
    private func selectPooledSpeaker(from characters: [CharacterCard]) -> CharacterCard? {
        guard !characters.isEmpty else { return nil }

        // Calculate weights based on talkativeness
        let weights: [(character: CharacterCard, weight: Double)] = characters.map { character in
            let talkativeness = character.talkativeness
            // Convert talkativeness (0-1) to weight (0.1-1.0)
            let weight = max(0.1, talkativeness)
            return (character, weight)
        }

        // Random weighted selection
        let totalWeight = weights.reduce(0) { $0 + $1.weight }
        var random = Double.random(in: 0..<totalWeight)

        for (character, weight) in weights {
            random -= weight
            if random <= 0 {
                return character
            }
        }

        return characters.last
    }

    /// Record that a character spoke
    func recordSpeaker(_ avatar: String) {
        speakingHistory.append(avatar)
        // Keep history limited
        if speakingHistory.count > 100 {
            speakingHistory.removeFirst()
        }
    }

    /// Reset the speaker state
    func reset() {
        currentSpeakerIndex = 0
        selectedNextSpeaker = nil
        speakingHistory.removeAll()
    }
}
