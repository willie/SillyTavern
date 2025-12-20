import Foundation
import Observation
import SwiftUI

// MARK: - App State

@Observable @MainActor
final class AppState {
    // MARK: - Navigation

    /// Current tab selection (iOS)
    var selectedTab: Tab = .chats

    /// Current sidebar selection (macOS)
    var sidebarSelection: SidebarItem? = .chats

    /// Navigation path for drill-down navigation
    var navigationPath = NavigationPath()

    // MARK: - Active Context

    /// Currently active character (for single-character chats)
    var activeCharacter: CharacterCard?

    /// Currently active chat
    var activeChat: Chat?

    /// Shared chat state for the active conversation
    var chatState: ChatState = ChatState()

    /// Search text for filtering
    var searchText: String = ""

    // MARK: - UI State

    /// Whether the inspector panel is visible (macOS)
    var isInspectorPresented: Bool = false

    /// Window size (tracked for responsive layouts)
    var windowSize: CGSize = .zero

    // MARK: - Stores

    /// Character store
    var characters: CharacterStore

    /// Settings store
    var settings: SettingsStore

    /// World info store
    var worldInfo: WorldInfoStore

    /// Group store
    var groups: GroupStore

    // MARK: - Initialization

    init() {
        self.characters = CharacterStore()
        self.settings = SettingsStore()
        self.worldInfo = WorldInfoStore()
        self.groups = GroupStore()

        Task {
            await loadData()
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        await characters.load()
        await settings.load()
        await worldInfo.load()
        await groups.load()

        // Resolve group members to characters
        for group in groups.groups {
            groups.resolveMembers(for: group, from: characters.characters)
        }
    }

    // MARK: - Actions

    func newChat(with character: CharacterCard) {
        self.activeCharacter = character
        self.activeChat = Chat(characterID: character.id)
        self.chatState.clearChat()
        self.navigationPath.append(character)
    }

    func openChat(_ chat: Chat) {
        self.activeChat = chat
    }
}

// MARK: - Tab Enum (iOS)

enum Tab: String, CaseIterable, Identifiable {
    case chats
    case characters
    case groups
    case worldInfo
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: return "Chats"
        case .characters: return "Characters"
        case .groups: return "Groups"
        case .worldInfo: return "World Info"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .characters: return "person.2"
        case .groups: return "person.3"
        case .worldInfo: return "book"
        case .settings: return "gear"
        }
    }
}

// MARK: - Sidebar Item (macOS)

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case chats
    case characters
    case groups
    case worldInfo
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: return "Chats"
        case .characters: return "Characters"
        case .groups: return "Groups"
        case .worldInfo: return "World Info"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .characters: return "person.2"
        case .groups: return "person.3"
        case .worldInfo: return "book"
        case .settings: return "gear"
        }
    }
}

// MARK: - Character Store

@Observable @MainActor
final class CharacterStore {
    var characters: [CharacterCard] = []
    var isLoading = false
    var error: Error?

    private let fileStore = FileStore()

    func load() async {
        isLoading = true
        error = nil

        do {
            characters = try await fileStore.loadCharacters()
        } catch {
            self.error = error
            print("Failed to load characters: \(error)")
        }

        isLoading = false
    }

    func add(_ character: CharacterCard) {
        characters.append(character)
        Task {
            try? fileStore.saveCharacter(character)
        }
    }

    func remove(_ character: CharacterCard) {
        characters.removeAll { $0.id == character.id }
        Task {
            try? fileStore.deleteCharacter(character)
        }
    }

    func importCharacter(from url: URL) async throws -> CharacterCard {
        let character = try await fileStore.importCharacter(from: url)
        characters.append(character)
        return character
    }
}

// MARK: - Settings Store

@Observable @MainActor
final class SettingsStore {
    // API Configuration
    var selectedProvider: String = "openai"
    var apiKey: String = ""
    var baseURL: String = ""

    // Model Settings
    var model: String = "gpt-4o"
    var maxContextTokens: Int = 8192
    var maxResponseTokens: Int = 1024

    // Generation Settings
    var temperature: Double = 0.7
    var topP: Double = 1.0
    var frequencyPenalty: Double = 0.0
    var presencePenalty: Double = 0.0

    // Prompt Settings
    var mainPrompt: String = "Write {{char}}'s next reply in a fictional chat between {{char}} and {{user}}."
    var jailbreakPrompt: String = ""

    // Author's Note
    var authorsNote: String = ""
    var authorsNoteDepth: Int = 4
    var authorsNotePosition: String = "afterAN"  // beforeAN, afterAN

    // Persona
    var personaName: String = "User"
    var personaDescription: String = ""

    private let fileStore = FileStore()

    func load() async {
        // Load settings from UserDefaults for now
        if let key = UserDefaults.standard.string(forKey: "apiKey") {
            apiKey = key
        }
        if let provider = UserDefaults.standard.string(forKey: "provider") {
            selectedProvider = provider
        }
        if let savedModel = UserDefaults.standard.string(forKey: "model") {
            model = savedModel
        }
    }

    func save() {
        UserDefaults.standard.set(apiKey, forKey: "apiKey")
        UserDefaults.standard.set(selectedProvider, forKey: "provider")
        UserDefaults.standard.set(model, forKey: "model")
    }

    /// Create an LLM provider based on current settings
    func createProvider() -> (any LLMProvider)? {
        guard !apiKey.isEmpty else { return nil }

        switch selectedProvider {
        case "openai":
            let url = baseURL.isEmpty ? URL(string: "https://api.openai.com/v1")! : URL(string: baseURL)!
            return OpenAIProvider(apiKey: apiKey, baseURL: url)

        case "claude":
            let url = baseURL.isEmpty ? URL(string: "https://api.anthropic.com")! : URL(string: baseURL)!
            return ClaudeProvider(apiKey: apiKey, baseURL: url)

        case "openrouter":
            let url = baseURL.isEmpty ? URL(string: "https://openrouter.ai/api/v1")! : URL(string: baseURL)!
            return OpenRouterProvider(apiKey: apiKey, baseURL: url)

        case "custom":
            // Custom provider uses OpenAI-compatible API format
            guard let url = URL(string: baseURL), !baseURL.isEmpty else { return nil }
            return OpenAIProvider(apiKey: apiKey, baseURL: url)

        default:
            return nil
        }
    }

    /// Create prompt settings
    func createPromptSettings() -> PromptSettings {
        PromptSettings(
            mainPrompt: mainPrompt,
            jailbreakPrompt: jailbreakPrompt,
            maxContextTokens: maxContextTokens,
            maxResponseTokens: maxResponseTokens
        )
    }

    /// Create extension prompts (author's note, etc.)
    func createExtensionPrompts() -> ExtensionPrompts {
        var prompts = ExtensionPrompts()

        if !authorsNote.isEmpty {
            prompts.authorsNote = ExtensionPrompt(
                value: authorsNote,
                role: .system,
                position: authorsNoteDepth,
                enabled: true
            )
        }

        return prompts
    }

    /// Create a tokenizer for the current model
    func createTokenizer() -> any Tokenizer {
        TokenCounter.tokenizer(for: model)
    }
}

// MARK: - World Info Store

@Observable @MainActor
final class WorldInfoStore {
    var books: [WorldInfoBook] = []
    var isLoading = false
    var error: Error?

    private let fileStore = FileStore()

    func load() async {
        isLoading = true
        error = nil

        do {
            books = try await fileStore.loadWorldInfoBooks()
        } catch {
            self.error = error
            print("Failed to load world info: \(error)")
        }

        isLoading = false
    }

    /// Get all entries from all enabled books
    var allEntries: [WorldInfoEntry] {
        books.flatMap { $0.entries.filter { $0.enabled } }
    }

    /// Add a new book
    func add(_ book: WorldInfoBook) {
        books.append(book)
        Task {
            await save(book)
        }
    }

    /// Remove a book
    func remove(_ book: WorldInfoBook) {
        books.removeAll { $0.id == book.id }
        Task {
            await delete(book)
        }
    }

    /// Save a book to disk
    func save(_ book: WorldInfoBook) async {
        do {
            try await fileStore.saveWorldInfoBook(book)
        } catch {
            print("Failed to save world info book: \(error)")
        }
    }

    /// Delete a book from disk
    private func delete(_ book: WorldInfoBook) async {
        do {
            try await fileStore.deleteWorldInfoBook(book)
        } catch {
            print("Failed to delete world info book: \(error)")
        }
    }

    /// Import a book from URL
    func importBook(from url: URL) async throws -> WorldInfoBook {
        let book = try await fileStore.importWorldInfoBook(from: url)
        books.append(book)
        return book
    }
}

// MARK: - Group Store

@Observable @MainActor
final class GroupStore {
    var groups: [CharacterGroup] = []
    var isLoading = false
    var error: Error?

    private let fileStore = FileStore()

    func load() async {
        isLoading = true
        error = nil

        do {
            groups = try await fileStore.loadGroups()
        } catch {
            self.error = error
            print("Failed to load groups: \(error)")
        }

        isLoading = false
    }

    /// Add a new group
    func add(_ group: CharacterGroup) {
        groups.append(group)
        Task {
            await save(group)
        }
    }

    /// Remove a group
    func remove(_ group: CharacterGroup) {
        groups.removeAll { $0.id == group.id }
        Task {
            await delete(group)
        }
    }

    /// Save a group to disk
    func save(_ group: CharacterGroup) async {
        do {
            try await fileStore.saveGroup(group)
        } catch {
            print("Failed to save group: \(error)")
        }
    }

    /// Delete a group from disk
    private func delete(_ group: CharacterGroup) async {
        do {
            try await fileStore.deleteGroup(group)
        } catch {
            print("Failed to delete group: \(error)")
        }
    }

    /// Resolve group members to actual characters
    func resolveMembers(for group: CharacterGroup, from characters: [CharacterCard]) {
        for i in group.members.indices {
            let memberID = group.members[i].characterID
            if let character = characters.first(where: { $0.avatar == memberID || $0.name == memberID }) {
                group.members[i].character = character
            }
        }
    }
}

// MARK: - Chat Model (Placeholder)

@Observable
final class Chat: Identifiable, Hashable {
    let id: UUID
    let characterID: UUID
    var messages: [Message] = []
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), characterID: UUID) {
        self.id = id
        self.characterID = characterID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func == (lhs: Chat, rhs: Chat) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Message Model (Placeholder)

@Observable
final class Message: Identifiable, Hashable {
    let id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = Date()
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}
