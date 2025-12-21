import Foundation
import Observation

// MARK: - Character Card (Hybrid Model)

/// A character card using the Native-Dynamic Hybrid pattern.
/// Typed properties for common fields, raw JSON storage for everything else.
/// Supports both V1 (flat) and V2 (nested data:) formats.
@Observable
final class CharacterCard: Identifiable, Hashable {
    let id: UUID
    var fileURL: URL?

    // MARK: - Typed Properties (Common Fields)

    var name: String = ""
    var description: String = ""
    var personality: String = ""
    var scenario: String = ""
    var first_mes: String = ""
    var mes_example: String = ""
    var creator_notes: String = ""
    var system_prompt: String = ""
    var post_history_instructions: String = ""
    var creator: String = ""
    var character_version: String = ""
    var tags: [String] = []
    var alternate_greetings: [String] = []
    var group_only_greetings: [String] = []

    // MARK: - V2 Extension Fields

    var depth_prompt: DepthPrompt?
    var character_book: WorldInfoBook?
    var talkativeness: Double = 0.5
    var fav: Bool = false

    // MARK: - Metadata

    var avatar: String = "none"
    var chat: String = ""
    var create_date: Date?

    // MARK: - Computed Properties

    /// Whether this character is marked as NSFW (based on tags)
    var isNSFW: Bool {
        let nsfwKeywords = ["nsfw", "18+", "adult", "explicit", "mature", "r18", "r-18"]
        return tags.contains { tag in
            nsfwKeywords.contains { keyword in
                tag.lowercased().contains(keyword)
            }
        }
    }

    // MARK: - Raw Storage

    /// Raw JSON storage for preserving unknown fields during round-trip.
    private var rawJSON: [String: JSONValue] = [:]

    /// Whether the original format was V2 (nested data:) or V1 (flat).
    private var isV2Format: Bool = false

    // MARK: - Initialization

    init(id: UUID = UUID(), fileURL: URL? = nil) {
        self.id = id
        self.fileURL = fileURL
    }

    /// Initialize from parsed JSON data.
    convenience init(from json: [String: JSONValue], url: URL? = nil) {
        self.init(fileURL: url)
        load(from: json)
    }

    /// Initialize from JSON data.
    convenience init(from data: Data, url: URL? = nil) throws {
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        self.init(from: json, url: url)
    }

    // MARK: - Load from JSON

    func load(from json: [String: JSONValue]) {
        self.rawJSON = json

        // Detect V2 format (has nested "data" object)
        self.isV2Format = json["data"]?.object != nil

        // Get the data source (nested for V2, flat for V1)
        let data = json["data"]?.object ?? json

        // Core fields
        self.name = data["name"]?.string ?? json["name"]?.string ?? ""
        self.description = data["description"]?.string ?? json["description"]?.string ?? ""
        self.personality = data["personality"]?.string ?? json["personality"]?.string ?? ""
        self.scenario = data["scenario"]?.string ?? json["scenario"]?.string ?? ""
        self.first_mes = data["first_mes"]?.string ?? json["first_mes"]?.string ?? ""
        self.mes_example = data["mes_example"]?.string ?? json["mes_example"]?.string ?? ""

        // V2 extended fields
        self.creator_notes = data["creator_notes"]?.string ?? ""
        self.system_prompt = data["system_prompt"]?.string ?? ""
        self.post_history_instructions = data["post_history_instructions"]?.string ?? ""
        self.creator = data["creator"]?.string ?? ""
        self.character_version = data["character_version"]?.string ?? ""

        // Arrays
        self.tags = data["tags"]?.array?.compactMap(\.string) ?? json["tags"]?.array?.compactMap(\.string) ?? []
        self.alternate_greetings = data["alternate_greetings"]?.array?.compactMap(\.string) ?? []
        self.group_only_greetings = data["group_only_greetings"]?.array?.compactMap(\.string) ?? []

        // ST-specific fields (top-level)
        self.avatar = json["avatar"]?.string ?? "none"
        self.chat = json["chat"]?.string ?? ""
        self.fav = json["fav"]?.bool ?? data["extensions"]?["fav"]?.bool ?? false
        self.talkativeness = json["talkativeness"]?.number ?? data["extensions"]?["talkativeness"]?.number ?? 0.5

        // Create date
        if let dateString = json["create_date"]?.string {
            self.create_date = ISO8601DateFormatter().date(from: dateString)
        }

        // Depth prompt (from extensions)
        if let depthPromptJSON = data["extensions"]?["depth_prompt"]?.object {
            self.depth_prompt = DepthPrompt(
                prompt: depthPromptJSON["prompt"]?.string ?? "",
                depth: depthPromptJSON["depth"]?.int ?? 4,
                role: depthPromptJSON["role"]?.string ?? "system"
            )
        }

        // Character book (embedded lorebook)
        if let bookJSON = data["character_book"]?.object {
            self.character_book = WorldInfoBook(from: bookJSON)
        }
    }

    // MARK: - Save to JSON

    /// Convert back to JSON, preserving unknown fields.
    func toJSON() -> [String: JSONValue] {
        var json = rawJSON

        if isV2Format {
            // V2 format: update nested data object
            var data = json["data"]?.object ?? [:]
            var extensions = data["extensions"]?.object ?? [:]

            // Core fields
            data["name"] = .string(name)
            data["description"] = .string(description)
            data["personality"] = .string(personality)
            data["scenario"] = .string(scenario)
            data["first_mes"] = .string(first_mes)
            data["mes_example"] = .string(mes_example)

            // Extended fields
            data["creator_notes"] = .string(creator_notes)
            data["system_prompt"] = .string(system_prompt)
            data["post_history_instructions"] = .string(post_history_instructions)
            data["creator"] = .string(creator)
            data["character_version"] = .string(character_version)

            // Arrays
            data["tags"] = .array(tags.map { .string($0) })
            data["alternate_greetings"] = .array(alternate_greetings.map { .string($0) })
            data["group_only_greetings"] = .array(group_only_greetings.map { .string($0) })

            // Extensions
            extensions["fav"] = .bool(fav)
            extensions["talkativeness"] = .number(talkativeness)

            if let depthPrompt = depth_prompt {
                extensions["depth_prompt"] = .object([
                    "prompt": .string(depthPrompt.prompt),
                    "depth": .number(Double(depthPrompt.depth)),
                    "role": .string(depthPrompt.role)
                ])
            }

            data["extensions"] = .object(extensions)

            // Character book
            if let book = character_book {
                data["character_book"] = book.toJSON()
            }

            json["data"] = .object(data)

            // V2 also mirrors some fields at top level for V1 compatibility
            json["name"] = .string(name)
            json["description"] = .string(description)
            json["personality"] = .string(personality)
            json["scenario"] = .string(scenario)
            json["first_mes"] = .string(first_mes)
            json["mes_example"] = .string(mes_example)
            json["tags"] = .array(tags.map { .string($0) })

        } else {
            // V1 format: flat structure
            json["name"] = .string(name)
            json["description"] = .string(description)
            json["personality"] = .string(personality)
            json["scenario"] = .string(scenario)
            json["first_mes"] = .string(first_mes)
            json["mes_example"] = .string(mes_example)
            json["tags"] = .array(tags.map { .string($0) })
        }

        // ST-specific top-level fields
        json["avatar"] = .string(avatar)
        json["chat"] = .string(chat)
        json["fav"] = .bool(fav)
        json["talkativeness"] = .number(talkativeness)

        if let date = create_date {
            json["create_date"] = .string(ISO8601DateFormatter().string(from: date))
        }

        return json
    }

    /// Serialize to JSON data.
    func toData(prettyPrinted: Bool = true) throws -> Data {
        let json = toJSON()
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(json)
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: CharacterCard, rhs: CharacterCard) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Depth Prompt

struct DepthPrompt: Codable, Equatable, Sendable {
    var prompt: String = ""
    var depth: Int = 4
    var role: String = "system"  // system, user, assistant
}

// MARK: - World Info Book (Embedded Lorebook)

@Observable
final class WorldInfoBook: Identifiable, Hashable {
    let id: UUID
    var name: String = ""
    var entries: [WorldInfoEntry] = []
    var fileURL: URL?

    private var rawJSON: [String: JSONValue] = [:]

    init(id: UUID = UUID(), fileURL: URL? = nil) {
        self.id = id
        self.fileURL = fileURL
    }

    static func == (lhs: WorldInfoBook, rhs: WorldInfoBook) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    convenience init(from json: [String: JSONValue]) {
        self.init()
        self.rawJSON = json
        self.name = json["name"]?.string ?? ""

        if let entriesJSON = json["entries"]?.object {
            self.entries = entriesJSON.compactMap { key, value in
                guard let entryObj = value.object else { return nil }
                return WorldInfoEntry(from: entryObj, uid: key)
            }
        }
    }

    func toJSON() -> JSONValue {
        var json = rawJSON
        json["name"] = .string(name)

        var entriesObj: [String: JSONValue] = [:]
        for entry in entries {
            entriesObj[entry.uid] = entry.toJSON()
        }
        json["entries"] = .object(entriesObj)

        return .object(json)
    }
}

// MARK: - World Info Entry

@Observable
final class WorldInfoEntry: Identifiable {
    let id: UUID
    var uid: String

    // Core fields
    var keys: [String] = []
    var secondary_keys: [String] = []
    var content: String = ""
    var comment: String = ""
    var enabled: Bool = true

    // Matching settings
    var selective: Bool = false
    var constant: Bool = false
    var case_sensitive: Bool = false
    var match_whole_words: Bool = false

    // Position/injection
    var position: Int = 0  // 0=before, 1=after, etc.
    var depth: Int = 4
    var order: Int = 100

    // Timed effects
    var sticky: Int = 0
    var cooldown: Int = 0
    var delay: Int = 0

    // Probability
    var probability: Int = 100

    private var rawJSON: [String: JSONValue] = [:]

    init(id: UUID = UUID(), uid: String = "") {
        self.id = id
        self.uid = uid.isEmpty ? "\(Int(Date().timeIntervalSince1970 * 1000))" : uid
    }

    convenience init(from json: [String: JSONValue], uid: String) {
        self.init(uid: uid)
        self.rawJSON = json

        self.keys = json["key"]?.array?.compactMap(\.string) ?? []
        self.secondary_keys = json["keysecondary"]?.array?.compactMap(\.string) ?? []
        self.content = json["content"]?.string ?? ""
        self.comment = json["comment"]?.string ?? ""
        self.enabled = json["disable"]?.bool != true  // Note: inverted
        self.selective = json["selective"]?.bool ?? false
        self.constant = json["constant"]?.bool ?? false
        self.case_sensitive = json["caseSensitive"]?.bool ?? false
        self.match_whole_words = json["matchWholeWords"]?.bool ?? false
        self.position = json["position"]?.int ?? 0
        self.depth = json["depth"]?.int ?? 4
        self.order = json["order"]?.int ?? 100
        self.sticky = json["sticky"]?.int ?? 0
        self.cooldown = json["cooldown"]?.int ?? 0
        self.delay = json["delay"]?.int ?? 0
        self.probability = json["probability"]?.int ?? 100
    }

    func toJSON() -> JSONValue {
        var json = rawJSON

        json["key"] = .array(keys.map { .string($0) })
        json["keysecondary"] = .array(secondary_keys.map { .string($0) })
        json["content"] = .string(content)
        json["comment"] = .string(comment)
        json["disable"] = .bool(!enabled)  // Note: inverted
        json["selective"] = .bool(selective)
        json["constant"] = .bool(constant)
        json["caseSensitive"] = .bool(case_sensitive)
        json["matchWholeWords"] = .bool(match_whole_words)
        json["position"] = .number(Double(position))
        json["depth"] = .number(Double(depth))
        json["order"] = .number(Double(order))
        json["sticky"] = .number(Double(sticky))
        json["cooldown"] = .number(Double(cooldown))
        json["delay"] = .number(Double(delay))
        json["probability"] = .number(Double(probability))

        return .object(json)
    }
}
