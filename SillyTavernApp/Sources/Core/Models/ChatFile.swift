import Foundation
import Observation

// MARK: - Chat File (Mirrors SillyTavern JSONL chat file)

/// Represents a complete chat file matching SillyTavern's JSONL format.
/// First line is metadata, subsequent lines are messages.
@Observable
final class ChatFile: Identifiable, Hashable {
    let id: UUID

    /// File URL on disk (nil if not yet saved)
    var fileURL: URL?

    /// Chat file name (without extension)
    var fileName: String

    // MARK: - Metadata (first line of JSONL)

    /// User's display name in this chat
    var user_name: String

    /// Character's name in this chat
    var character_name: String

    /// When the chat was created
    var create_date: String

    /// Additional chat metadata
    var chat_metadata: ChatMetadata

    // MARK: - Messages

    /// All messages in the chat (excluding metadata line)
    var messages: [ChatMessage] = []

    // MARK: - Computed Properties

    /// Preview of the last message for list display
    var lastMessagePreview: String {
        guard let lastMessage = messages.last else { return "" }
        let preview = lastMessage.displayedMessage
        return preview.count > 100 ? String(preview.prefix(100)) + "..." : preview
    }

    /// When the chat was last modified
    var lastModified: Date? {
        guard let url = fileURL else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Message count
    var messageCount: Int { messages.count }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        fileName: String = "New Chat",
        user_name: String = "User",
        character_name: String,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.user_name = user_name
        self.character_name = character_name
        self.create_date = Self.currentTimestamp()
        self.chat_metadata = ChatMetadata()
        self.fileURL = fileURL
    }

    // MARK: - JSONL Parsing

    /// Load chat from JSONL file
    static func load(from url: URL) throws -> ChatFile {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw ChatFileError.emptyFile
        }

        // Parse first line as metadata
        guard let metadataData = lines[0].data(using: .utf8) else {
            throw ChatFileError.invalidMetadata
        }

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(ChatFileMetadata.self, from: metadataData)

        let chatFile = ChatFile(
            fileName: url.deletingPathExtension().lastPathComponent,
            user_name: metadata.user_name,
            character_name: metadata.character_name,
            fileURL: url
        )
        chatFile.create_date = metadata.create_date
        chatFile.chat_metadata = metadata.chat_metadata ?? ChatMetadata()

        // Parse remaining lines as messages
        for i in 1..<lines.count {
            guard let messageData = lines[i].data(using: .utf8) else { continue }
            do {
                let message = try decoder.decode(ChatMessage.self, from: messageData)
                chatFile.messages.append(message)
            } catch {
                print("Failed to parse message at line \(i): \(error)")
            }
        }

        return chatFile
    }

    // MARK: - JSONL Serialization

    /// Convert chat to JSONL format for saving
    func toJSONL() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []  // Compact, no pretty printing

        var lines: [String] = []

        // First line: metadata
        let metadata = ChatFileMetadata(
            user_name: user_name,
            character_name: character_name,
            create_date: create_date,
            chat_metadata: chat_metadata
        )
        let metadataData = try encoder.encode(metadata)
        guard let metadataLine = String(data: metadataData, encoding: .utf8) else {
            throw ChatFileError.encodingFailed
        }
        lines.append(metadataLine)

        // Subsequent lines: messages
        for message in messages {
            let messageData = try encoder.encode(message)
            guard let messageLine = String(data: messageData, encoding: .utf8) else {
                continue
            }
            lines.append(messageLine)
        }

        return lines.joined(separator: "\n")
    }

    /// Save chat to file
    func save(to url: URL? = nil) throws {
        let targetURL = url ?? fileURL
        guard let targetURL = targetURL else {
            throw ChatFileError.noFileURL
        }

        let content = try toJSONL()
        try content.write(to: targetURL, atomically: true, encoding: .utf8)
        self.fileURL = targetURL
    }

    // MARK: - Message Management

    /// Add a user message
    func addUserMessage(_ content: String) {
        let message = ChatMessage.userMessage(content, name: user_name)
        messages.append(message)
    }

    /// Add a character message
    func addCharacterMessage(_ content: String) {
        let message = ChatMessage.characterMessage(content, name: character_name)
        messages.append(message)
    }

    /// Delete a message at index
    func deleteMessage(at index: Int) {
        guard messages.indices.contains(index) else { return }
        messages.remove(at: index)
    }

    /// Clear all messages
    func clearMessages() {
        messages.removeAll()
    }

    // MARK: - Hashable & Equatable

    /// Two ChatFiles are equal if they represent the same file on disk (by fileURL),
    /// or if both are unsaved and have the same UUID.
    static func == (lhs: ChatFile, rhs: ChatFile) -> Bool {
        if let lhsURL = lhs.fileURL, let rhsURL = rhs.fileURL {
            return lhsURL == rhsURL
        }
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        if let url = fileURL {
            hasher.combine(url)
        } else {
            hasher.combine(id)
        }
    }

    // MARK: - Helpers

    static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy @ h:mma"
        return formatter.string(from: Date())
    }
}

// MARK: - Chat File Metadata (first line of JSONL)

/// The metadata structure for the first line of a chat JSONL file
struct ChatFileMetadata: Codable {
    var user_name: String
    var character_name: String
    var create_date: String
    var chat_metadata: ChatMetadata?
}

// MARK: - Chat Metadata

/// Additional metadata stored in chat_metadata field
struct ChatMetadata: Codable, Equatable {
    /// Integrity hash for verification
    var integrity: String?

    /// Custom notes about this chat
    var note: String?

    /// World info books enabled for this chat
    var world_info: [String]?

    /// Any other custom data
    var custom: [String: String]?

    init(integrity: String? = nil, note: String? = nil) {
        self.integrity = integrity
        self.note = note
    }
}

// MARK: - Errors

enum ChatFileError: Error, LocalizedError {
    case emptyFile
    case invalidMetadata
    case encodingFailed
    case noFileURL

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "Chat file is empty"
        case .invalidMetadata: return "Invalid chat metadata"
        case .encodingFailed: return "Failed to encode chat data"
        case .noFileURL: return "No file URL specified for save"
        }
    }
}
