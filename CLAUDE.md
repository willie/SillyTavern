# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Is SillyTavern

Node 18+ Express server serving a single-page chat UI for LLM interactions. Frontend is plain JS modules (no framework) with jQuery. User data lives under configurable `dataRoot` (default `./data`), separated per-user.

## Commands

```bash
npm install          # Install dependencies (runs post-install.js)
npm start            # Start server (port 8000, localhost only by default)
npm run lint         # ESLint check
npm run lint:fix     # ESLint with auto-fix

# Alternative runtimes
npm run start:deno   # Deno runtime
npm run start:bun    # Bun runtime
npm run start:electron  # Electron shell

# Plugin management
node plugins.js update              # Update git-based plugins
node plugins.js install <git-url>   # Install plugin from git
```

## Architecture

### Server Structure
- `server.js` → Entry point, parses CLI args, sets `DATA_ROOT`, imports `src/server-main.js`
- `src/server-main.js` → Express app setup, middleware pipeline, plugin loading
- `src/server-startup.js` → Mounts all API routers
- `src/endpoints/` → Individual API route handlers (characters, chats, openai, anthropic, etc.)
- `src/middleware/` → Express middleware (auth, whitelist, CORS proxy, webpack-serve)
- `src/users.js` → Multi-user account management
- `src/plugin-loader.js` → Server plugin system

### Frontend Structure
- `public/index.html` → Main SPA entry
- `public/script.js` → Main runtime, chat flow, message rendering
- `public/lib.js` → Bundled third-party deps (via webpack)
- `public/scripts/` → Feature modules:
  - `openai.js`, `textgen-settings.js`, `kai-settings.js`, `nai-settings.js` → AI backend clients
  - `PromptManager.js` → Prompt ordering, token budgeting
  - `world-info.js` → Lorebook/world info injection
  - `characters.js`, `group-chats.js` → Character/group management
  - `extensions.js` → UI extension loader
- `public/scripts/extensions/` → Built-in UI extensions
- `public/scripts/extensions/third-party/` → User-installed extensions

### Data Layout
Per-user directories under `<DATA_ROOT>/<userHandle>/`:
- `characters/`, `chats/`, `groups/`, `group chats/`, `worlds/`
- `backgrounds/`, `themes/`, `User Avatars/`, `thumbnails/`
- `OpenAI Settings/`, `KoboldAI Settings/`, `NovelAI Settings/`, `TextGen Settings/`
- `extensions/`, `QuickReplies/`, `vectors/`, `backups/`

### Plugin System
**Server plugins** (`plugins/`): Export `info` object and `init(router)` function. Routes mount at `/api/plugins/<id>`.

**UI extensions** (`public/scripts/extensions/`): Can register generation interceptors, slash commands, toolbar buttons. Managed via `extensions.js`.

## Configuration

`config.yaml` in data root. Key settings:
- `listen: false` → localhost only (default, secure)
- `listen: true` → requires whitelist, basic auth, or user accounts
- `port: 8000`
- `enableUserAccounts: false` → single-user mode
- `enableServerPlugins: false`
- `disableCsrfProtection: false` → CSRF on by default

Environment variable override: `SILLYTAVERN_<KEY>` (dots become underscores).

## Code Style

ESLint enforces:
- Single quotes, semicolons required
- 4-space indentation
- Trailing commas in multiline
- `object-curly-spacing: always`

Server code uses ESM (`type: "module"` in package.json). Frontend uses ESM with jQuery globals.

## API Patterns

All API routes under `/api/`:
- Auth: `/api/users/*`
- Content: `/api/characters`, `/api/chats`, `/api/groups`, `/api/worldinfo`, `/api/backgrounds`
- AI backends: `/api/openai`, `/api/anthropic`, `/api/google`, `/api/backends/chat-completions`
- Utilities: `/api/tokenizers`, `/api/settings`, `/api/extensions`

CSRF token required for mutations: fetch from `/csrf-token`, send as `x-csrf-token` header.

## Key Files for Common Tasks

| Task | Files |
|------|-------|
| Add API endpoint | `src/endpoints/`, register in `src/server-startup.js` |
| Modify chat flow | `public/script.js`, `public/scripts/openai.js` |
| Change prompt assembly | `public/scripts/PromptManager.js`, `public/scripts/openai.js` |
| Add AI backend | `src/endpoints/backends/`, corresponding `public/scripts/*-settings.js` |
| Modify UI | `public/index.html`, `public/style.css`, `public/scripts/` |
| Add server middleware | `src/middleware/`, register in `src/server-main.js` |

## SwiftUI Native App

The `SillyTavernApp/` directory contains a native macOS/iOS SwiftUI client. This native app is intended to be a complete port of SillyTavern to Swift and SwiftUI and should be on-disk compatible with SillyTavern's data structures.

**See [SillyTavernApp/CLAUDE.md](SillyTavernApp/CLAUDE.md) for detailed Swift/SwiftUI architecture documentation.**

```bash
cd SillyTavernApp
swift build            # Build the app
swift run              # Build and run (preferred for debugging)
```

**Important**: Always use `swift run` to run and debug SwiftUI projects that use Swift Package Manager.
