# Repository Guidelines (SillyTavernApp)

## Project Structure & Module Organization
- `Sources/App/`: SwiftUI entrypoints per platform (`Platform/macOS`, `Platform/iOS`) and shared UI composition.  
- `Sources/Features/`: Chat UI/logic (e.g., `ChatState`, view models).  
- `Sources/Core/Services/`: Persistence and file I/O (`FileStore`, `ChatStore`, `CharacterStore`), matching SillyTavern’s on-disk layout.  
- `Resources/`: Assets and localized strings.  
- `Package.swift`: SwiftPM manifest; builds iOS/macOS app targets.

## Build, Test, and Development Commands
- Open `Package.swift` in Xcode to run and debug iOS/macOS targets; select the desired scheme (e.g., macOS app).  
- CLI: `swift build` to compile; `swift test` if tests are added.  
- Data location: app group `~/Library/Group Containers/group.sillytavern/` when available, otherwise `~/Documents/SillyTavern/`. Chat data lives in `characters/`, `chats/<avatar>/`, `group chats/` (flat JSONL files), `groups/`, `worlds/`, mirroring the server.

## Coding Style & Naming Conventions
- SwiftUI-first; favor value types and `@Observable`/`@MainActor` where stateful.  
- CamelCase for properties/methods, PascalCase for types.  
- Keep filenames aligned with primary type (e.g., `ChatStore.swift`).  
- Preserve canonical folder names (e.g., `group chats`, `User Avatars`) to maintain cross-app compatibility.

## Testing Guidelines
- No dedicated Swift tests are present yet; add new ones under `Tests/` using XCTest and mirror key flows (character load, chat save/load, group chat listings).  
- Prefer deterministic fixtures using the shared data layout; avoid mutating real user data during tests.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subjects (e.g., “Add macOS chat folder monitor”), grouped by feature.  
- PRs: state platform impact (iOS/macOS), data compatibility considerations, and verification steps (build target, manual flows like loading existing chats). Include screenshots/screen recordings for UI changes.
