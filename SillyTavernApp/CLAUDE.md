# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For the main SillyTavern Node.js server documentation, see [../CLAUDE.md](../CLAUDE.md).

## What Is This

Native macOS/iOS SwiftUI port of SillyTavern. Uses the same on-disk data structures for compatibility as SillyTavern for maximum compatibility.

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
  - `CharacterGroup.swift` - Group chat support
- `Services/` - Business logic
  - `FileStore.swift` - File I/O for characters, world info, groups
  - `ChatStore.swift` - Chat persistence (JSONL in `chats/<character>/`)
  - `PromptBuilder.swift` - Prompt assembly matching SillyTavern's logic
  - `TokenCounter.swift` - Token counting utilities
- `Providers/` - LLM API integrations implementing `LLMProvider` protocol
  - `OpenAIProvider.swift`, `ClaudeProvider.swift`, `OpenRouterProvider.swift`

### Features Layer (`Sources/Features/`)
- `Characters/` - Character list, detail, import views
- `Chat/ChatState.swift` - Chat session state and generation logic
- `Groups/`, `WorldInfo/`, `Settings/` - Feature views

## Data Compatibility

Uses SillyTavern's data directory structure:
- `characters/` - PNG files with embedded character JSON
- `chats/<character_avatar>/` - JSONL chat files per character
- `worlds/` - World info JSON files
- `groups/` - Group configuration JSON files

Chat JSONL format:
- Line 1: Metadata (`user_name`, `character_name`, `create_date`, `chat_metadata`)
- Lines 2+: Messages (`name`, `is_user`, `send_date`, `mes`, `swipes`, `swipe_id`, `extra`)

## Key Patterns

### State Management
```swift
@Observable @MainActor
final class AppState {
    var characters: CharacterStore
    var chats: ChatStore
    var chatState: ChatState
}
```

### LLM Providers
```swift
protocol LLMProvider: Sendable {
    func send(messages: [LLMMessage], model: String, options: LLMOptions) async throws -> AsyncThrowingStream<String, Error>
    func countTokens(_ text: String, model: String) -> Int
}
```

## Key Files for Common Tasks

| Task | Files |
|------|-------|
| Add LLM provider | `Sources/Core/Providers/`, implement `LLMProvider` protocol |
| Modify chat flow | `Sources/Features/Chat/ChatState.swift` |
| Change prompt assembly | `Sources/Core/Services/PromptBuilder.swift` |
| Add character field | `Sources/Core/Models/CharacterCard.swift` |
| Modify macOS layout | `Sources/App/Platform/macOS/RootView_macOS.swift` |
| Add settings option | `Sources/App/AppState.swift` (SettingsStore), `Sources/Features/Settings/SettingsView.swift` |
