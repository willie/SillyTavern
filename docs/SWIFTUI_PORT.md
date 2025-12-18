# SillyTavern SwiftUI Port Plan

Goal: Ship a native SwiftUI app that preserves core SillyTavern behavior (prompt assembly, character/world info/memory) while dramatically simplifying UX and deployment. Single codebase for iOS/iPadOS/macOS.

## Core Simplifications
- One state layer: `ObservableObject` stores (`AppState`, `ChatState`, `CharacterStore`, `SettingsStore`, `WorldInfoStore`, `MemoryStore`) using async/await. No Redux/complex plumbing.
- One prompt builder: pure Swift module that merges character card, presets, world info hits, memory, authors note, dialogue examples, and chat history; then token-trims. No scattered injections.
- One provider interface: `LLMProvider` protocol (`send(messages: [LLMMessage])`, `models()`, `pricing`, `supportsTools`). Implementations: `OpenAIProvider`, `ClaudeProvider`, `LocalLlamaProvider` (Metal-backed), etc. Swap providers without UI changes.
- One navigation model: Home dashboard → Characters → Chats → World Info → Settings. Everything reachable in 2 taps/clicks.
- One “Advanced” pattern: expert flags live behind disclosure groups/sheets; presets surface common toggles (style, safety, temperature/top_p/max tokens).
- One storage shape: mirror current JSON per user (characters, chats, world info, settings) in app group container. Thumbnails cached separately. Optional export/import bundle for backup or interop with the Node version.

## High-Level Architecture
```
[SwiftUI Views]
    |
[Observable State Objects]
    |        \
[Prompt Builder]   [Provider Router]
    |                   |
[Token Counter]     [LLMProvider protocol]
    |                   |
[Files (JSON) + Thumb Cache]   [OpenAI | Claude | Local Metal]
```

## Navigation / Screens
```
Home Dashboard
├─ Continue Chat
├─ New Chat
├─ Characters
├─ World Info
├─ Settings
└─ Learn/Help

Characters
├─ List (search/tags)
├─ Detail/Edit
└─ Import/Export

Chats
├─ Thread view (messages, inline media)
├─ Context drawer (world info hits, memory, authors note)
└─ Input bar (preset selector + “Advanced” sheet)

World Info
├─ Entry list (filters)
├─ Entry edit
└─ Test input (see matches)

Settings (grouped)
├─ Model & Safety
├─ Memory & Prompts
├─ UI & Layout
├─ Extensions (if supported)
└─ Data & Export
```

## Swift Types (Sketch)
- `AppState`: holds current user, active chat/character, router enum for navigation.
- `CharacterStore`: `[CharacterCard]`, thumbnails, import/export.
- `ChatState`: current thread messages, metadata, streaming status, token counts.
- `WorldInfoStore`: entries with triggers, match tester, enable/disable flags.
- `MemoryStore`: vector recall results (if using embeddings), summaries, authors note.
- `SettingsStore`: provider config, UI/theme, advanced generation settings, data/export.
- `PromptBuilder`: functions to assemble `PromptBlock`s and `LLMMessage`s, apply order/depth, and trim via `Tokenizer`.
- `Tokenizer`: Swift binding to tiktoken/gpt-tokenizer; fallback to a small C/Metal tokenizer if needed.
- `LLMProvider` protocol + concrete providers (OpenAI, Claude, Local Metal/llama.cpp).
- `FileStore`: read/write JSON per user; cache thumbnails; export/import bundles.

## Prompt Pipeline Parity (Simplified)
1) Inputs: character card (and overrides), user presets (main/nsfw/jailbreak/impersonation/new chat), world info matches, vector recall (optional), authors note, dialogue examples, chat history.
2) Builder: merge prompts with identifiers/roles/positions/depth/order; include extension prompts if supported; keep mandatory prompts first.
3) Token budgeting: count with `Tokenizer`, trim oldest chat messages; abort if mandatory prompts exceed model context.
4) Output: `[LLMMessage]` ready for `LLMProvider.send()`.

## UX Overhaul Notes
- Onboarding: pick provider (or Local), add key, import a character, start chat. No wall of settings.
- Chat screen: main pane + right drawer for context (world info hits, vector recall, authors note). Advanced generation in a sheet; presets for “Concise”, “Creative”, “Stay in Character”. Inline status for streaming/errors.
- Characters: grid/list with tags, quick “Set Active”. Edit in a modal sheet with live preview of card content.
- World Info: searchable list, quick enable/disable, “Test input” to preview matches.
- Settings: grouped by intent; advanced toggles behind disclosure. Inline helper text/tooltips instead of large forms.
- Accessibility: large touch targets, dynamic type, focus states, reduced motion toggle.
- Theming: light/dark + accent; optional high-contrast.

## Data & Interop
- Storage: JSON per user in app group folder matching current folders (characters, chats, world info, settings). Cache thumbnails separately.
- Import/export: zip bundle with metadata to stay compatible with the Node version.
- Secrets: Keychain for provider keys. No CSRF needed locally; if adding a LAN bridge, gate with auth and CSRF.

## Deployment
- Ship as universal iOS/iPadOS/macOS app. No external server required unless using LAN/local LLM; in that case, add a minimal embedded HTTP bridge that proxies to `LLMProvider` implementations.
- For local LLM: wrap a Metal-optimized llama.cpp library as `LocalLlamaProvider`.

## Next Steps (if building)
1) Define data models and FileStore layout matching current JSON shapes.
2) Implement `LLMProvider` protocol for OpenAI first; add Claude/local after.
3) Build `Tokenizer` binding and `PromptBuilder` with unit tests for ordering/trim.
4) Stand up SwiftUI views: Home, Chat (with drawer), Characters, World Info, Settings.
5) Add import/export bundle; verify round-trip with sample data from the Node app.

## JSON-First Storage Layer (no SwiftData)
- Keep per-user folder layout in App Group container: `characters/`, `chats/`, `worlds/`, `settings/`, `thumbnails/`, `assets/`, `backups/`.
- Define `Codable` structs that mirror existing JSON (CharacterCard, ChatThread, WorldInfoEntry, Settings) with a `schemaVersion` for migrations.
- `FileStore` API (plain Codable + FileManager, atomic writes):
  - `loadCharacters() -> [CharacterCard]`, `save(character:)`
  - `loadChats(for id)`, `appendMessage(...)`, `replaceChat(...)`
  - `loadWorldInfo()`, `save(worldInfo:)`
  - `loadSettings()`, `save(settings:)`
  - `exportBundle()` / `importBundle()` (zip JSON + media)
- Concurrency: do I/O on a background queue; debounce writes; use `.atomic` write. For chat appends, allow append-only journal then compact periodically.
- Indexing: build in-memory indexes after load for search/tags/world-info matching; optionally cache a small `index.json`, regenerate if missing.
- Validation/migration: check `schemaVersion`, add in-memory migrations before save; log/repair corrupted files; keep rolling backups in `backups/`.
- Media: store images/thumbs as files; JSON stores paths, not blobs. Generate thumbs lazily into `thumbnails/`.
- Error handling: surface load/save issues to a “Data Health” screen with retry/repair controls.
- Tests: unit tests for load/save round-trip, migration, and corruption recovery.
