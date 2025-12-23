import Foundation
import Observation

// MARK: - Chat Message (Mirrors SillyTavern JSONL format)

/// A chat message matching SillyTavern's JSONL message format.
/// Each message in a chat file is one JSON line with this structure.
@Observable
final class ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID

    // MARK: - Core Fields (SillyTavern format)

    /// Name of the sender (character name or user name)
    var name: String

    /// Whether this message is from the user (true) or character (false)
    var is_user: Bool

    /// Timestamp when message was sent (ISO8601 or humanized format)
    var send_date: String

    /// The message text content
    var mes: String

    // MARK: - Swipes (alternate responses)

    /// Array of alternate message responses
    var swipes: [String]?

    /// Index of currently selected swipe
    var swipe_id: Int?

    // MARK: - Extra Data

    /// Additional message metadata
    var extra: MessageExtra?

    // MARK: - Computed Properties

    /// Get the currently displayed message (respects swipe selection)
    var displayedMessage: String {
        if let swipes = swipes, let swipeId = swipe_id, swipeId < swipes.count {
            return swipes[swipeId]
        }
        return mes
    }

    /// Whether this message has multiple swipes
    var hasSwipes: Bool {
        guard let swipes = swipes else { return false }
        return swipes.count > 1
    }

    /// Number of swipes available
    var swipeCount: Int {
        swipes?.count ?? 1
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        is_user: Bool,
        mes: String,
        send_date: String? = nil
    ) {
        self.id = id
        self.name = name
        self.is_user = is_user
        self.mes = mes
        self.send_date = send_date ?? Self.currentTimestamp()
    }

    /// Create a user message
    static func userMessage(_ content: String, name: String = "User") -> ChatMessage {
        ChatMessage(name: name, is_user: true, mes: content)
    }

    /// Create a character message
    static func characterMessage(_ content: String, name: String) -> ChatMessage {
        ChatMessage(name: name, is_user: false, mes: content)
    }

    // MARK: - Swipe Management

    /// Add a new swipe (alternate response)
    func addSwipe(_ content: String) {
        if swipes == nil {
            swipes = [mes]  // First swipe is the original message
        }
        swipes?.append(content)
        swipe_id = (swipes?.count ?? 1) - 1
    }

    /// Navigate to the next swipe
    func nextSwipe() {
        guard let swipes = swipes, swipes.count > 1 else { return }
        swipe_id = ((swipe_id ?? 0) + 1) % swipes.count
    }

    /// Navigate to the previous swipe
    func previousSwipe() {
        guard let swipes = swipes, swipes.count > 1 else { return }
        let current = swipe_id ?? 0
        swipe_id = current > 0 ? current - 1 : swipes.count - 1
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case name, is_user, send_date, mes, swipes, swipe_id, extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.is_user = try container.decode(Bool.self, forKey: .is_user)

        // Handle send_date as either string or number (SillyTavern can use both)
        if let dateString = try? container.decode(String.self, forKey: .send_date) {
            self.send_date = dateString
        } else if let dateNumber = try? container.decode(Double.self, forKey: .send_date) {
            // Convert numeric timestamp to string (milliseconds since epoch)
            self.send_date = String(Int(dateNumber))
        } else {
            self.send_date = Self.currentTimestamp()
        }

        self.mes = try container.decode(String.self, forKey: .mes)
        self.swipes = try container.decodeIfPresent([String].self, forKey: .swipes)
        self.swipe_id = try container.decodeIfPresent(Int.self, forKey: .swipe_id)
        self.extra = try container.decodeIfPresent(MessageExtra.self, forKey: .extra)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(is_user, forKey: .is_user)
        try container.encode(send_date, forKey: .send_date)
        try container.encode(mes, forKey: .mes)
        try container.encodeIfPresent(swipes, forKey: .swipes)
        try container.encodeIfPresent(swipe_id, forKey: .swipe_id)
        try container.encodeIfPresent(extra, forKey: .extra)
    }

    // MARK: - Helpers

    /// Generate current timestamp in SillyTavern format
    static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy @ h:mma"
        return formatter.string(from: Date())
    }
}

// MARK: - Message Extra (additional metadata)

/// Additional message metadata. Uses raw JSON storage to preserve all fields during round-trip.
struct MessageExtra: Codable, Equatable {
    /// Raw JSON storage for preserving all fields
    private var rawJSON: [String: JSONValue]

    // MARK: - Common Accessors

    /// API used for generation (e.g., "openai", "anthropic")
    var api: String? {
        get { rawJSON["api"]?.string }
        set { rawJSON["api"] = newValue.map { .string($0) } }
    }

    /// Model used for generation
    var model: String? {
        get { rawJSON["model"]?.string }
        set { rawJSON["model"] = newValue.map { .string($0) } }
    }

    /// Message type (e.g., "narrator", "comment")
    var type: String? {
        get { rawJSON["type"]?.string }
        set { rawJSON["type"] = newValue.map { .string($0) } }
    }

    /// Custom display text (rendered differently from mes)
    var display_text: String? {
        get { rawJSON["display_text"]?.string }
        set { rawJSON["display_text"] = newValue.map { .string($0) } }
    }

    /// Character bias injected
    var bias: String? {
        get { rawJSON["bias"]?.string }
        set { rawJSON["bias"] = newValue.map { .string($0) } }
    }

    /// Whether this is a system/hidden message
    var is_system: Bool? {
        get { rawJSON["is_system"]?.bool }
        set { rawJSON["is_system"] = newValue.map { .bool($0) } }
    }

    /// Token count (if available)
    var token_count: Int? {
        get { rawJSON["token_count"]?.int }
        set { rawJSON["token_count"] = newValue.map { .number(Double($0)) } }
    }

    /// Generation time in milliseconds
    var gen_time: Int? {
        get { rawJSON["gen_time"]?.int }
        set { rawJSON["gen_time"] = newValue.map { .number(Double($0)) } }
    }

    // MARK: - Generic Access

    /// Get any value by key
    subscript(key: String) -> JSONValue? {
        get { rawJSON[key] }
        set { rawJSON[key] = newValue }
    }

    // MARK: - Initialization

    init() {
        self.rawJSON = [:]
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawJSON = try container.decode([String: JSONValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawJSON)
    }

    // MARK: - Equatable

    static func == (lhs: MessageExtra, rhs: MessageExtra) -> Bool {
        lhs.rawJSON == rhs.rawJSON
    }
}

// MARK: - Media Attachment

struct MediaAttachment: Codable, Equatable {
    var url: String
    var type: String?  // "image", "video", etc.
    var title: String?
}

// MARK: - File Attachment

struct FileAttachment: Codable, Equatable {
    var url: String
    var name: String
    var size: Int?
    var created: Double?
    var text: String?
}
