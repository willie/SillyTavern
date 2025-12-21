import Foundation
import Observation

// MARK: - Chat Store

/// Manages chat persistence matching SillyTavern's file structure.
/// Chats are stored as JSONL files in `chats/<character_avatar>/` directories.
@Observable @MainActor
final class ChatStore {
    /// All loaded chats, keyed by character avatar name
    private(set) var chatsByCharacter: [String: [ChatFile]] = [:]

    /// Currently active chat
    var activeChat: ChatFile?

    /// Loading state
    var isLoading = false
    var error: Error?

    private let fileManager = FileManager.default
    private let fileStore = FileStore()

    // MARK: - Directory Structure

    /// Base directory for all chats
    private var chatsDirectory: URL {
        fileStore.chatsDirectory
    }

    /// Get the chat directory for a character (based on avatar name)
    func chatDirectory(for character: CharacterCard) -> URL {
        let avatarName = characterDirectoryName(for: character)
        return chatsDirectory.appendingPathComponent(avatarName, isDirectory: true)
    }

    /// Convert character to directory name (matches SillyTavern's approach)
    private func characterDirectoryName(for character: CharacterCard) -> String {
        // SillyTavern uses the avatar filename without .png extension
        // If avatar is "none", fall back to sanitized character name
        if character.avatar != "none" && !character.avatar.isEmpty {
            return character.avatar.replacingOccurrences(of: ".png", with: "")
        }
        return sanitizeFilename(character.name)
    }

    /// Sanitize a string for use as filename
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    // MARK: - Loading

    /// Load all chats for all characters
    func loadAll() async {
        isLoading = true
        error = nil

        do {
            // Ensure chats directory exists
            try fileManager.createDirectory(at: chatsDirectory, withIntermediateDirectories: true)

            // Get all character directories
            let contents = try fileManager.contentsOfDirectory(
                at: chatsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var loadedChats: [String: [ChatFile]] = [:]

            for itemURL in contents {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                let characterName = itemURL.lastPathComponent
                let chats = try await loadChats(in: itemURL)
                if !chats.isEmpty {
                    loadedChats[characterName] = chats
                }
            }

            chatsByCharacter = loadedChats

        } catch {
            self.error = error
            print("Failed to load chats: \(error)")
        }

        isLoading = false
    }

    /// Load all chats for a specific character
    func loadChats(for character: CharacterCard) async -> [ChatFile] {
        let directory = chatDirectory(for: character)
        do {
            return try await loadChats(in: directory)
        } catch {
            print("Failed to load chats for \(character.name): \(error)")
            return []
        }
    }

    /// Load all chat files from a directory
    private func loadChats(in directory: URL) async throws -> [ChatFile] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var chats: [ChatFile] = []

        for fileURL in contents where fileURL.pathExtension == "jsonl" {
            do {
                let chat = try ChatFile.load(from: fileURL)
                chats.append(chat)
            } catch {
                print("Failed to load chat \(fileURL.lastPathComponent): \(error)")
            }
        }

        // Sort by modification date (most recent first)
        chats.sort { (chat1, chat2) in
            let date1 = chat1.lastModified ?? .distantPast
            let date2 = chat2.lastModified ?? .distantPast
            return date1 > date2
        }

        return chats
    }

    // MARK: - Saving

    /// Save a chat to disk
    func save(_ chat: ChatFile, for character: CharacterCard) async throws {
        let directory = chatDirectory(for: character)

        // Ensure directory exists
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Determine file URL
        let fileURL: URL
        if let existingURL = chat.fileURL {
            fileURL = existingURL
        } else {
            let filename = sanitizeFilename(chat.fileName) + ".jsonl"
            fileURL = directory.appendingPathComponent(filename)
        }

        try chat.save(to: fileURL)

        // Update cache
        let characterKey = characterDirectoryName(for: character)
        if chatsByCharacter[characterKey] == nil {
            chatsByCharacter[characterKey] = []
        }
        if !chatsByCharacter[characterKey]!.contains(where: { $0.id == chat.id }) {
            chatsByCharacter[characterKey]!.insert(chat, at: 0)
        }
    }

    /// Auto-save the active chat
    func saveActiveChat(for character: CharacterCard) async {
        guard let chat = activeChat else { return }
        do {
            try await save(chat, for: character)
        } catch {
            print("Failed to auto-save chat: \(error)")
        }
    }

    // MARK: - Chat Management

    /// Create a new chat for a character
    func createChat(
        for character: CharacterCard,
        userName: String = "User",
        fileName: String? = nil
    ) -> ChatFile {
        let chatName = fileName ?? "Chat \(Date().formatted(date: .abbreviated, time: .shortened))"

        let chat = ChatFile(
            fileName: chatName,
            user_name: userName,
            character_name: character.name
        )

        // Select greeting (first_mes or random from alternate_greetings)
        let greeting: String
        if !character.alternate_greetings.isEmpty && Bool.random() {
            greeting = character.alternate_greetings.randomElement() ?? character.first_mes
        } else {
            greeting = character.first_mes
        }

        // Add first message if character has one
        if !greeting.isEmpty {
            let firstMessage = substituteParams(greeting, character: character, userName: userName)
            chat.addCharacterMessage(firstMessage)
        }

        return chat
    }

    /// Get all chats for a character
    func chats(for character: CharacterCard) -> [ChatFile] {
        let key = characterDirectoryName(for: character)
        return chatsByCharacter[key] ?? []
    }

    /// Delete a chat
    func delete(_ chat: ChatFile, for character: CharacterCard) async throws {
        guard let fileURL = chat.fileURL else { return }

        try fileManager.removeItem(at: fileURL)

        // Update cache
        let key = characterDirectoryName(for: character)
        chatsByCharacter[key]?.removeAll { $0.id == chat.id }
    }

    /// Rename a chat
    func rename(_ chat: ChatFile, to newName: String, for character: CharacterCard) async throws {
        guard let oldURL = chat.fileURL else { return }

        let directory = oldURL.deletingLastPathComponent()
        let newFilename = sanitizeFilename(newName) + ".jsonl"
        let newURL = directory.appendingPathComponent(newFilename)

        try fileManager.moveItem(at: oldURL, to: newURL)

        chat.fileName = newName
        chat.fileURL = newURL
    }

    // MARK: - Helpers

    /// Substitute {{char}} and {{user}} placeholders
    private func substituteParams(_ text: String, character: CharacterCard, userName: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{{char}}", with: character.name)
        result = result.replacingOccurrences(of: "{{Char}}", with: character.name)
        result = result.replacingOccurrences(of: "{{user}}", with: userName)
        result = result.replacingOccurrences(of: "{{User}}", with: userName)
        return result
    }
}

