# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For the main SillyTavern Node.js server documentation, see [../CLAUDE.md](../CLAUDE.md).

## What Is This

Native macOS/iOS SwiftUI port of SillyTavern. Uses the same on-disk data structures for compatibility with SillyTavern.

**Platforms**: macOS 26+, iOS 26+, Swift 6.2+

## Commands

```bash
swift build            # Build the app
swift run              # Build and run (preferred for debugging)
```

## Architecture

### App Layer (`Sources/App/`)
- `SillyTavernApp.swift` - Main app entry, WindowGroup setup
- `AppState.swift` - Global observable state, stores (CharacterStore, ChatStore, SettingsStore, WorldInfoStore, GroupStore)
- `Platform/macOS/RootView_macOS.swift` - macOS NavigationSplitView layout
- `Platform/iOS/RootView_iOS.swift` - iOS TabView layout

### Core Layer (`Sources/Core/`)
- `Models/` - Data models matching SillyTavern formats
  - `CharacterCard.swift` - Character card (PNG embedded JSON, V2 spec)
  - `ChatMessage.swift`, `ChatFile.swift` - Chat in JSONL format
  - `WorldInfoBook.swift`, `WorldInfoEntry.swift` - Lorebook/world info
  - `Group.swift` - Group chat with activation strategies (natural, list, manual, pooled)
- `Services/` - Business logic
  - `FileStore.swift` - File I/O for characters, world info, groups
  - `ChatStore.swift` - Chat persistence (JSONL in `chats/<character>/`)
  - `PromptBuilder.swift` - Prompt assembly matching SillyTavern's logic
  - `LLMProvider.swift` - Provider protocol and LLMOptions/LLMMessage types
  - `TokenCounter.swift` - Token counting utilities
- `Services/Providers/` - LLM API implementations
  - `OpenAIProvider.swift`, `ClaudeProvider.swift`, `OpenRouterProvider.swift`
  - `GeminiProvider.swift`, `MistralProvider.swift`
- `Services/FolderMonitor.swift` - NSFilePresenter wrapper for disk sync

### Features Layer (`Sources/Features/`)
- `Characters/` - Character list, detail, import views
- `Chat/ChatState.swift` - Chat session state and generation logic
- `Groups/`, `WorldInfo/`, `Settings/` - Feature views

## Data Compatibility

Uses SillyTavern's data directory structure:
- `characters/` - PNG files with embedded character JSON (base64 in tEXt chunk)
- `chats/<character_avatar>/` - JSONL chat files per character
- `worlds/` - World info JSON files (entries as object keyed by uid)
- `groups/` - Group JSON files named `<id>.json` (id is timestamp string like `"1703289600000"`)
- `group chats/` - Group chat JSONL files (flat, format `2025-12-22@22h30m45s.jsonl`)

Chat JSONL format:
- Line 1: Metadata (`user_name`, `character_name`, `create_date`, `chat_metadata`)
- Lines 2+: Messages (`name`, `is_user`, `send_date`, `mes`, `swipes`, `swipe_id`, `extra`)

### Raw JSON Preservation Pattern (CRITICAL)

SillyTavern data structures have many fields. To avoid data loss on round-trip:

1. **Store raw JSON** - Models keep `private var rawJSON: [String: JSONValue]`
2. **Typed accessors** - Common fields get typed properties that read/write to rawJSON
3. **Preserve on save** - `toJSON()` starts with rawJSON and updates typed fields

```swift
struct ChatMetadata: Codable {
    private var rawJSON: [String: JSONValue]

    var note: String? {
        get { rawJSON["note"]?.string }
        set { rawJSON["note"] = newValue.map { .string($0) } }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawJSON)  // Preserves ALL fields
    }
}
```

Models using this pattern: `CharacterCard`, `CharacterGroup`, `WorldInfoBook`, `WorldInfoEntry`, `ChatMetadata`, `MessageExtra`

### Format Variants

Some fields have multiple valid formats that must be handled:

| Field | Variants |
|-------|----------|
| `send_date` | String (`"December 23, 2025 @ 10:30AM"`) or Number (`1703289600000`) |
| `group.id` | String timestamp (`"1703289600000"`), not UUID |
| `group.members` | Array of avatar filename strings, not objects |
| `character_book.entries` | Array (V2 spec) or Object keyed by uid (ST internal) |
| Character files | PNG with embedded JSON, or standalone JSON |

## Key Patterns

### Disk-State Synchronization (CRITICAL)

**This app must stay in sync with on-disk data at all times.** The same data directory may be accessed by:
- This SwiftUI app
- The Node.js SillyTavern server
- External file editors

Each store uses `FolderMonitor` (NSFilePresenter) to watch its directory:

```swift
@Observable @MainActor
final class CharacterStore {
    var characters: [CharacterCard] = []
    private var monitor: FolderMonitor?

    func load() async {
        // Start monitor on first load
        if monitor == nil {
            monitor = FolderMonitor(url: directory) { [weak self] in
                Task { @MainActor in await self?.load() }
            }
            monitor?.start()
        }
        // Read from disk → update @Observable property → SwiftUI refreshes
        characters = try await fileStore.loadCharacters()
    }
}
```

**Flow:**
```
Disk write (save/delete/external) → FolderMonitor fires → load() re-reads
    → @Observable property updates → SwiftUI views refresh automatically
```

**Rules:**
1. **Never manually update cached arrays** - let the monitor handle it
2. **Save to disk immediately** - don't hold unsaved state
3. **All stores watch their directories** - ChatStore, CharacterStore, WorldInfoStore, GroupStore
4. **Use NSFilePresenter** - works on both macOS and iOS, handles subdirectories

### State Management
```swift
@Observable @MainActor
final class AppState {
    var characters: CharacterStore
    var chats: ChatStore
    var chatState: ChatState
    var settings: SettingsStore
}
```

### LLM Providers
```swift
protocol LLMProvider: Sendable {
    func send(messages: [LLMMessage], model: String, options: LLMOptions) async throws -> AsyncThrowingStream<String, Error>
    func countTokens(_ text: String, model: String) -> Int
}
```

### LLM Options
Sampling parameters: `maxTokens`, `temperature`, `topP`, `topK`, `minP`, `frequencyPenalty`, `presencePenalty`, `repetitionPenalty`, `seed`, `stopSequences`

### Error Handling
Stores have `error: Error?` properties. Views display errors via alert bindings:
```swift
.alert("Error", isPresented: .init(
    get: { appState.characters.error != nil },
    set: { if !$0 { appState.characters.error = nil } }
)) {
    Button("OK") { appState.characters.error = nil }
} message: {
    Text(appState.characters.error?.localizedDescription ?? "Unknown error")
}
```

### Settings Persistence
Use `UserDefaults` via `didSet` in SettingsStore. **Never use `@AppStorage`** - it conflicts with `@Observable` and creates dual state.
```swift
var temperature: Double = 0.7 {
    didSet { defaults.set(temperature, forKey: "settings.temperature") }
}
```

### FileStore I/O
FileStore methods are `nonisolated` for background I/O. Pass primitive data, not model objects:
```swift
// Caller encodes, FileStore just writes
let data = try character.toData(prettyPrinted: true)
let savedURL = try fileStore.saveCharacter(data: data, name: character.name, existingURL: character.fileURL)
```

### FolderMonitor Debouncing
FolderMonitor debounces callbacks (200ms default) to coalesce rapid file events:
```swift
monitor = FolderMonitor(url: directory, debounceInterval: .milliseconds(200)) { ... }
```

## Key Files for Common Tasks

| Task | Files |
|------|-------|
| Add LLM provider | `Sources/Core/Services/Providers/`, implement `LLMProvider` protocol, add to `SettingsStore.createProvider()` |
| Modify chat flow | `Sources/Features/Chat/ChatState.swift` |
| Change prompt assembly | `Sources/Core/Services/PromptBuilder.swift` |
| Add character field | `Sources/Core/Models/CharacterCard.swift` |
| Modify macOS layout | `Sources/App/Platform/macOS/RootView_macOS.swift` |
| Add settings option | `Sources/App/AppState.swift` (SettingsStore), `Sources/Features/Settings/SettingsView.swift` |
| Group chat logic | `Sources/Core/Models/Group.swift` (GroupChatState) |
| Add new data store | Create store in `AppState.swift`, add `FolderMonitor` for disk sync |
| File monitoring | `Sources/Core/Services/FolderMonitor.swift` (NSFilePresenter wrapper) |
