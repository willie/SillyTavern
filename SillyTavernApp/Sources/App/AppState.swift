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

    /// Currently active character
    var activeCharacter: CharacterCard?

    /// Currently active chat file
    var activeChatFile: ChatFile?

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

    /// Chat store (file-based persistence)
    var chats: ChatStore

    /// Settings store
    var settings: SettingsStore

    /// World info store
    var worldInfo: WorldInfoStore

    /// Group store
    var groups: GroupStore

    // MARK: - Initialization

    init() {
        self.characters = CharacterStore()
        self.chats = ChatStore()
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
        await chats.loadAll()
        await settings.load()
        await worldInfo.load()
        await groups.load()

        // Resolve group members to characters
        for group in groups.groups {
            groups.resolveMembers(for: group, from: characters.characters)
        }
    }

    // MARK: - Chat Actions

    /// Start a new chat with a character
    func newChat(with character: CharacterCard) {
        self.activeCharacter = character

        // Create a new chat file
        let chatFile = chats.createChat(
            for: character,
            userName: settings.personaName
        )
        self.activeChatFile = chatFile
        chats.activeChat = chatFile

        // Configure chat state with the new chat
        chatState.configure(
            chatFile: chatFile,
            character: character,
            provider: settings.createProvider(),
            settings: settings.createPromptSettings(),
            worldInfo: worldInfo.allEntries,
            extensionPrompts: settings.createExtensionPrompts(),
            tokenizer: settings.createTokenizer(),
            model: settings.model,
            personaName: settings.personaName,
            personaDescription: settings.personaDescription
        )

        // Navigate to chat
        self.navigationPath.append(ChatRoute(character: character))
    }

    /// Open an existing chat
    func openChat(_ chatFile: ChatFile, for character: CharacterCard) {
        self.activeCharacter = character
        self.activeChatFile = chatFile
        chats.activeChat = chatFile

        // Configure chat state with the existing chat
        chatState.configure(
            chatFile: chatFile,
            character: character,
            provider: settings.createProvider(),
            settings: settings.createPromptSettings(),
            worldInfo: worldInfo.allEntries,
            extensionPrompts: settings.createExtensionPrompts(),
            tokenizer: settings.createTokenizer(),
            model: settings.model,
            personaName: settings.personaName,
            personaDescription: settings.personaDescription
        )

        // Navigate to chat
        self.navigationPath.append(ChatRoute(character: character))
    }

    /// Save the active chat
    func saveActiveChat() async {
        guard let chatFile = activeChatFile, let character = activeCharacter else { return }
        await chats.saveActiveChat(for: character)
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
    private let defaults = UserDefaults.standard

    // API Configuration
    var selectedProvider: String = "openai" {
        didSet { defaults.set(selectedProvider, forKey: "settings.provider") }
    }
    var apiKey: String = "" {
        didSet { defaults.set(apiKey, forKey: "settings.apiKey") }
    }
    var baseURL: String = "" {
        didSet { defaults.set(baseURL, forKey: "settings.baseURL") }
    }

    // Model Settings
    var model: String = "gpt-4o" {
        didSet { defaults.set(model, forKey: "settings.model") }
    }
    var maxContextTokens: Int = 8192 {
        didSet { defaults.set(maxContextTokens, forKey: "settings.maxContextTokens") }
    }
    var maxResponseTokens: Int = 1024 {
        didSet { defaults.set(maxResponseTokens, forKey: "settings.maxResponseTokens") }
    }

    // Generation Settings
    var temperature: Double = 0.7 {
        didSet { defaults.set(temperature, forKey: "settings.temperature") }
    }
    var topP: Double = 1.0 {
        didSet { defaults.set(topP, forKey: "settings.topP") }
    }
    var frequencyPenalty: Double = 0.0 {
        didSet { defaults.set(frequencyPenalty, forKey: "settings.frequencyPenalty") }
    }
    var presencePenalty: Double = 0.0 {
        didSet { defaults.set(presencePenalty, forKey: "settings.presencePenalty") }
    }

    // Prompt Settings
    var mainPrompt: String = "Write {{char}}'s next reply in a fictional chat between {{char}} and {{user}}." {
        didSet { defaults.set(mainPrompt, forKey: "settings.mainPrompt") }
    }
    var jailbreakPrompt: String = "" {
        didSet { defaults.set(jailbreakPrompt, forKey: "settings.jailbreakPrompt") }
    }

    // Author's Note
    var authorsNote: String = "" {
        didSet { defaults.set(authorsNote, forKey: "settings.authorsNote") }
    }
    var authorsNoteDepth: Int = 4 {
        didSet { defaults.set(authorsNoteDepth, forKey: "settings.authorsNoteDepth") }
    }
    var authorsNotePosition: String = "afterAN" {
        didSet { defaults.set(authorsNotePosition, forKey: "settings.authorsNotePosition") }
    }

    // Persona
    var personaName: String = "User" {
        didSet { defaults.set(personaName, forKey: "settings.personaName") }
    }
    var personaDescription: String = "" {
        didSet { defaults.set(personaDescription, forKey: "settings.personaDescription") }
    }

    private let fileStore = FileStore()

    func load() async {
        // Load all settings from UserDefaults
        if let provider = defaults.string(forKey: "settings.provider") {
            selectedProvider = provider
        }
        if let key = defaults.string(forKey: "settings.apiKey") {
            apiKey = key
        }
        if let url = defaults.string(forKey: "settings.baseURL") {
            baseURL = url
        }
        if let savedModel = defaults.string(forKey: "settings.model") {
            model = savedModel
        }
        if defaults.object(forKey: "settings.maxContextTokens") != nil {
            maxContextTokens = defaults.integer(forKey: "settings.maxContextTokens")
        }
        if defaults.object(forKey: "settings.maxResponseTokens") != nil {
            maxResponseTokens = defaults.integer(forKey: "settings.maxResponseTokens")
        }
        if defaults.object(forKey: "settings.temperature") != nil {
            temperature = defaults.double(forKey: "settings.temperature")
        }
        if defaults.object(forKey: "settings.topP") != nil {
            topP = defaults.double(forKey: "settings.topP")
        }
        if defaults.object(forKey: "settings.frequencyPenalty") != nil {
            frequencyPenalty = defaults.double(forKey: "settings.frequencyPenalty")
        }
        if defaults.object(forKey: "settings.presencePenalty") != nil {
            presencePenalty = defaults.double(forKey: "settings.presencePenalty")
        }
        if let prompt = defaults.string(forKey: "settings.mainPrompt") {
            mainPrompt = prompt
        }
        if let jailbreak = defaults.string(forKey: "settings.jailbreakPrompt") {
            jailbreakPrompt = jailbreak
        }
        if let note = defaults.string(forKey: "settings.authorsNote") {
            authorsNote = note
        }
        if defaults.object(forKey: "settings.authorsNoteDepth") != nil {
            authorsNoteDepth = defaults.integer(forKey: "settings.authorsNoteDepth")
        }
        if let position = defaults.string(forKey: "settings.authorsNotePosition") {
            authorsNotePosition = position
        }
        if let name = defaults.string(forKey: "settings.personaName") {
            personaName = name
        }
        if let desc = defaults.string(forKey: "settings.personaDescription") {
            personaDescription = desc
        }
    }

    func save() {
        // All settings auto-save via didSet, this is kept for manual saves if needed
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

// MARK: - Message Role (for LLM providers)

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

// MARK: - Navigation Routes

/// Route for navigating to a chat with a character
struct ChatRoute: Hashable {
    let character: CharacterCard
}
