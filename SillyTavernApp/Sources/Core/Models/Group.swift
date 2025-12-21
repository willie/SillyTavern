import Foundation
import Observation

// MARK: - Character Group Model

/// A group chat containing multiple characters.
@Observable
final class CharacterGroup: Identifiable, Hashable {
    let id: UUID
    var name: String
    var members: [GroupMember]
    var activationStrategy: ActivationStrategy
    var generationMode: GenerationMode
    var allowSelfResponse: Bool
    var favoriteMembers: Set<UUID>
    var disabledMembers: Set<UUID>

    // Group-specific settings
    var groupNudge: String
    var jailbreak: String
    var pastChats: [UUID]
    var chatMetadata: [String: JSONValue]

    // File storage
    var fileURL: URL?
    private var rawJSON: [String: JSONValue] = [:]

    init(
        id: UUID = UUID(),
        name: String = "",
        members: [GroupMember] = [],
        activationStrategy: ActivationStrategy = .natural,
        generationMode: GenerationMode = .swap
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.activationStrategy = activationStrategy
        self.generationMode = generationMode
        self.allowSelfResponse = false
        self.favoriteMembers = []
        self.disabledMembers = []
        self.groupNudge = ""
        self.jailbreak = ""
        self.pastChats = []
        self.chatMetadata = [:]
    }

    convenience init(fromJSON json: [String: JSONValue], url: URL? = nil) {
        self.init()
        self.rawJSON = json
        self.fileURL = url
        load(from: json)
    }

    // MARK: - Load from JSON

    func load(from json: [String: JSONValue]) {
        self.rawJSON = json

        self.name = json["name"]?.string ?? ""

        // Load members
        if let memberArray = json["members"]?.array {
            self.members = memberArray.compactMap { value -> GroupMember? in
                guard let memberID = value.string else { return nil }
                return GroupMember(characterID: memberID)
            }
        }

        // Load activation strategy
        if let strategy = json["activation_strategy"]?.int {
            self.activationStrategy = ActivationStrategy(rawValue: strategy) ?? .natural
        }

        // Load generation mode
        if let mode = json["generation_mode"]?.int {
            self.generationMode = GenerationMode(rawValue: mode) ?? .swap
        }

        self.allowSelfResponse = json["allow_self_responses"]?.bool ?? false
        self.groupNudge = json["group_nudge"]?.string ?? ""
        self.jailbreak = json["jailbreak"]?.string ?? ""

        // Load favorites and disabled
        if let favs = json["favorites"]?.array {
            self.favoriteMembers = Set(favs.compactMap { value -> UUID? in
                guard let str = value.string else { return nil }
                return UUID(uuidString: str)
            })
        }

        if let disabled = json["disabled_members"]?.array {
            self.disabledMembers = Set(disabled.compactMap { value -> UUID? in
                guard let str = value.string else { return nil }
                return UUID(uuidString: str)
            })
        }

        // Load past chats
        if let chats = json["past_chats"]?.array {
            self.pastChats = chats.compactMap { value -> UUID? in
                guard let str = value.string else { return nil }
                return UUID(uuidString: str)
            }
        }

        self.chatMetadata = json["chat_metadata"]?.object ?? [:]
    }

    // MARK: - Save to JSON

    func toJSON() -> [String: JSONValue] {
        var json = rawJSON

        json["name"] = .string(name)
        json["members"] = .array(members.map { .string($0.characterID) })
        json["activation_strategy"] = .number(Double(activationStrategy.rawValue))
        json["generation_mode"] = .number(Double(generationMode.rawValue))
        json["allow_self_responses"] = .bool(allowSelfResponse)
        json["group_nudge"] = .string(groupNudge)
        json["jailbreak"] = .string(jailbreak)
        json["favorites"] = .array(favoriteMembers.map { .string($0.uuidString) })
        json["disabled_members"] = .array(disabledMembers.map { .string($0.uuidString) })
        json["past_chats"] = .array(pastChats.map { .string($0.uuidString) })
        json["chat_metadata"] = .object(chatMetadata)

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
    var enabledMembers: [GroupMember] {
        members.filter { !disabledMembers.contains($0.id) }
    }

    /// Add a member to the group
    func addMember(_ member: GroupMember) {
        guard !members.contains(where: { $0.characterID == member.characterID }) else { return }
        members.append(member)
    }

    /// Remove a member from the group
    func removeMember(_ member: GroupMember) {
        members.removeAll { $0.id == member.id }
        favoriteMembers.remove(member.id)
        disabledMembers.remove(member.id)
    }

    /// Toggle member enabled state
    func toggleMember(_ member: GroupMember) {
        if disabledMembers.contains(member.id) {
            disabledMembers.remove(member.id)
        } else {
            disabledMembers.insert(member.id)
        }
    }

    /// Toggle member favorite state
    func toggleFavorite(_ member: GroupMember) {
        if favoriteMembers.contains(member.id) {
            favoriteMembers.remove(member.id)
        } else {
            favoriteMembers.insert(member.id)
        }
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: CharacterGroup, rhs: CharacterGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Group Member

/// A member of a group, referencing a character.
struct GroupMember: Identifiable, Hashable {
    let id: UUID
    let characterID: String

    // Cached reference to the actual character (not persisted)
    var character: CharacterCard?

    init(id: UUID = UUID(), characterID: String, character: CharacterCard? = nil) {
        self.id = id
        self.characterID = characterID
        self.character = character
    }

    // Implement Hashable manually to exclude the character reference
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(characterID)
    }

    static func == (lhs: GroupMember, rhs: GroupMember) -> Bool {
        lhs.id == rhs.id && lhs.characterID == rhs.characterID
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
    var selectedNextSpeaker: GroupMember?
    var speakingHistory: [UUID] = []

    /// Get the next speaker based on activation strategy
    func getNextSpeaker(lastMessage: String? = nil, lastSpeakerName: String? = nil) -> GroupMember? {
        guard let group = group else { return nil }
        let enabled = group.enabledMembers

        guard !enabled.isEmpty else { return nil }

        switch group.activationStrategy {
        case .natural:
            // Natural mode uses mentions and talkativeness
            return selectNaturalOrder(
                from: enabled,
                input: lastMessage,
                bannedName: group.allowSelfResponse ? nil : lastSpeakerName
            )

        case .list:
            // Round-robin through enabled members
            let speaker = enabled[currentSpeakerIndex % enabled.count]
            currentSpeakerIndex = (currentSpeakerIndex + 1) % enabled.count
            return speaker

        case .manual:
            // Use selected speaker or first enabled
            return selectedNextSpeaker ?? enabled.first

        case .pooled:
            // Weighted random based on talkativeness
            return selectPooledSpeaker(from: enabled)
        }
    }

    /// Select speaker using natural order strategy
    /// Priority: 1) Mentioned characters, 2) Talkativeness roll, 3) Random fallback
    private func selectNaturalOrder(from members: [GroupMember], input: String?, bannedName: String?) -> GroupMember? {
        guard !members.isEmpty else { return nil }

        var activatedMembers: [GroupMember] = []

        // 1. Find mentions in input (excluding banned speaker)
        if let input = input, !input.isEmpty {
            let inputWords = extractWords(from: input.lowercased())
            for member in members {
                guard let character = member.character else { continue }
                guard character.name != bannedName else { continue }

                let nameWords = extractWords(from: character.name.lowercased())
                if inputWords.contains(where: { nameWords.contains($0) }) {
                    activatedMembers.append(member)
                    break // Only add one mention
                }
            }
        }

        // 2. Activation by talkativeness (shuffled, excluding banned)
        var chattyMembers: [GroupMember] = []
        let shuffledMembers = members.shuffled()

        for member in shuffledMembers {
            guard let character = member.character else { continue }
            guard character.name != bannedName else { continue }

            let talkativeness = character.talkativeness
            let rollValue = Double.random(in: 0...1)

            if talkativeness >= rollValue {
                activatedMembers.append(member)
            }
            if talkativeness > 0 {
                chattyMembers.append(member)
            }
        }

        // 3. Pick random if no one activated
        if activatedMembers.isEmpty {
            let pool = chattyMembers.isEmpty ? members : chattyMembers
            // Filter out banned speaker
            let validPool = pool.filter { $0.character?.name != bannedName }
            if let random = validPool.randomElement() {
                return random
            }
            // If all are banned (shouldn't happen), just pick first
            return members.first
        }

        // Return first activated (prioritizes mentions)
        return activatedMembers.first
    }

    /// Extract words from text for mention matching
    private func extractWords(from text: String) -> Set<String> {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
        return Set(words)
    }

    /// Select speaker using pooled (weighted) strategy
    private func selectPooledSpeaker(from members: [GroupMember]) -> GroupMember? {
        guard !members.isEmpty else { return nil }

        // Calculate weights based on talkativeness
        let weights: [(member: GroupMember, weight: Double)] = members.map { member in
            let talkativeness = member.character?.talkativeness ?? 0.5
            // Convert talkativeness (0-1) to weight (0.1-1.0)
            let weight = max(0.1, talkativeness)
            return (member, weight)
        }

        // Random weighted selection
        let totalWeight = weights.reduce(0) { $0 + $1.weight }
        var random = Double.random(in: 0..<totalWeight)

        for (member, weight) in weights {
            random -= weight
            if random <= 0 {
                return member
            }
        }

        return members.last
    }

    /// Record that a character spoke
    func recordSpeaker(_ member: GroupMember) {
        speakingHistory.append(member.id)
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
