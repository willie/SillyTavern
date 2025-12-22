import Foundation
import Observation

// MARK: - Chat Store

/// Manages chat persistence matching SillyTavern's file structure.
/// Chats are stored as JSONL files in `chats/<character_avatar>/` directories.
/// Group chats are stored in `group chats/<group_id>/` directories.
@Observable @MainActor
final class ChatStore {
    /// All loaded chats, keyed by character avatar name
    private(set) var chatsByCharacter: [String: [ChatFile]] = [:]

    /// All loaded group chats, keyed by group ID
    private(set) var chatsByGroup: [String: [ChatFile]] = [:]

    /// Currently active chat
    var activeChat: ChatFile?

    /// Loading state
    var isLoading = false
    var error: Error?

    private let fileManager = FileManager.default
    private let fileStore = FileStore()
    private var monitor: FolderMonitor?
    private var groupMonitor: FolderMonitor?

    // MARK: - Directory Structure

    /// Base directory for all character chats
    private var chatsDirectory: URL {
        fileStore.chatsDirectory
    }

    /// Base directory for all group chats
    private var groupChatsDirectory: URL {
        fileStore.groupChatsDirectory
    }

    /// Get the chat directory for a character (based on avatar name)
    func chatDirectory(for character: CharacterCard) -> URL {
        let avatarName = characterDirectoryName(for: character)
        return chatsDirectory.appendingPathComponent(avatarName, isDirectory: true)
    }

    /// Get the chat directory for a group (based on group ID)
    func chatDirectory(for group: CharacterGroup) -> URL {
        groupChatsDirectory.appendingPathComponent(group.id.uuidString, isDirectory: true)
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

    /// Load all chats for all characters and groups
    func loadAll() async {
        isLoading = true
        error = nil

        do {
            // Ensure chats directories exist
            try fileManager.createDirectory(at: chatsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: groupChatsDirectory, withIntermediateDirectories: true)

            // Start folder monitor for character chats if not already running
            if monitor == nil {
                let directory = chatsDirectory
                monitor = FolderMonitor(url: directory) { [weak self] in
                    Task { @MainActor in
                        await self?.loadAll()
                    }
                }
                monitor?.start()
            }

            // Start folder monitor for group chats if not already running
            if groupMonitor == nil {
                let directory = groupChatsDirectory
                groupMonitor = FolderMonitor(url: directory) { [weak self] in
                    Task { @MainActor in
                        await self?.loadAll()
                    }
                }
                groupMonitor?.start()
            }

            // Load character chats
            let characterContents = try fileManager.contentsOfDirectory(
                at: chatsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var loadedCharacterChats: [String: [ChatFile]] = [:]

            for itemURL in characterContents {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                let characterName = itemURL.lastPathComponent
                let chats = try await loadChats(in: itemURL)
                if !chats.isEmpty {
                    loadedCharacterChats[characterName] = chats
                }
            }

            chatsByCharacter = loadedCharacterChats

            // Load group chats
            let groupContents = try fileManager.contentsOfDirectory(
                at: groupChatsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var loadedGroupChats: [String: [ChatFile]] = [:]

            for itemURL in groupContents {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                let groupID = itemURL.lastPathComponent
                let chats = try await loadChats(in: itemURL)
                if !chats.isEmpty {
                    loadedGroupChats[groupID] = chats
                }
            }

            chatsByGroup = loadedGroupChats

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
        // FolderMonitor will trigger loadAll() to refresh chatsByCharacter
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
    ) async throws -> ChatFile {
        let chatName = fileName ?? "Chat \(Date().formatted(date: .abbreviated, time: .shortened))"

        let chat = ChatFile(
            fileName: chatName,
            user_name: userName,
            character_name: character.name
        )

        // Select greeting (first_mes or random from non-empty alternate_greetings)
        let validAlternates = character.alternate_greetings.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let greeting: String
        if !validAlternates.isEmpty && Bool.random() {
            greeting = validAlternates.randomElement() ?? character.first_mes
        } else {
            greeting = character.first_mes
        }

        // Add first message if character has one
        if !greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let firstMessage = substituteParams(greeting, character: character, userName: userName)
            chat.addCharacterMessage(firstMessage)
        }

        // Save immediately so FolderMonitor picks it up
        try await save(chat, for: character)

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
        // FolderMonitor will trigger loadAll() to refresh chatsByCharacter
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

    // MARK: - Group Chat Management

    /// Get all chats for a group
    func chats(for group: CharacterGroup) -> [ChatFile] {
        return chatsByGroup[group.id.uuidString] ?? []
    }

    /// Create a new chat for a group
    func createGroupChat(
        for group: CharacterGroup,
        userName: String = "User",
        fileName: String? = nil
    ) async throws -> ChatFile {
        let chatName = fileName ?? "Chat \(Date().formatted(date: .abbreviated, time: .shortened))"

        let chat = ChatFile(
            fileName: chatName,
            user_name: userName,
            character_name: group.name  // Use group name as character name
        )

        // For group chats, we don't add an initial greeting
        // The first speaker will be selected when the user sends a message

        // Save immediately so FolderMonitor picks it up
        try await save(chat, for: group)

        return chat
    }

    /// Save a chat to disk for a group
    func save(_ chat: ChatFile, for group: CharacterGroup) async throws {
        let directory = chatDirectory(for: group)

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
        // FolderMonitor will trigger loadAll() to refresh chatsByGroup
    }

    /// Auto-save the active chat for a group
    func saveActiveChat(for group: CharacterGroup) async {
        guard let chat = activeChat else { return }
        do {
            try await save(chat, for: group)
        } catch {
            print("Failed to auto-save group chat: \(error)")
        }
    }

    /// Delete a chat for a group
    func delete(_ chat: ChatFile, for group: CharacterGroup) async throws {
        guard let fileURL = chat.fileURL else { return }

        try fileManager.removeItem(at: fileURL)
        // FolderMonitor will trigger loadAll() to refresh chatsByGroup
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

