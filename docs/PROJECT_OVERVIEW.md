# SillyTavern – Developer & Porting Guide

This document orients engineers who need to work on SillyTavern, port it to another stack, or redesign the UX. It summarizes the runtime model, code layout, data shapes, extension points, and the most important behaviors to preserve.

## What SillyTavern Is
- Node 18+ Express server that serves a single-page chat UI and exposes JSON APIs for character files, chats, themes, AI backends, translations, and image tools.
- Frontend is plain JS modules (no framework) loaded via `public/script.js` with helper libraries bundled into `lib.js` through Webpack.
- User state and assets live under a configurable `dataRoot` (default `./data`), separated per-user.

## Run / Build / Test
- Install: `npm install` (runs `post-install.js` to prep assets).
- Start: `npm start` → `server.js` → `src/server-main.js` (defaults: `listen=false`, port `8000`, CSRF on, autorun true).
- Alternatives: `npm run start:deno`, `start:bun`, or Electron shell (`npm run start:electron`).
- Webpack: middleware in `src/middleware/webpack-serve.js` compiles `public/lib.js` to `<DATA_ROOT>/_webpack/output/lib.js` (or `dist/lib.js` in Docker/forceDist) before the server finishes booting.
- Tests: `tests/sample.test.js` is a Playwright-style smoke test scaffold; add UI tests here. ESLint via `npm run lint` / `lint:fix`.

## Runtime Flow (server)
1) `server.js` parses CLI (`src/command-line.js`), sets `globalThis.DATA_ROOT` and `COMMAND_LINE_ARGS`, `chdir`s to the server directory, then imports `src/server-main.js`.
2) `server-main.js` sets up Express with security middlewares (helmet, compression, response-time, body-parser, cookie-session, optional CSRF via `csrf-sync`, optional CORS proxy). `setUserDataMiddleware` attaches per-request user context.
3) Static: `/` serves `public/index.html` (redirects to `/login` if needed); `/login` renders `public/login.html`; `webpack-serve` serves `lib.js`.
4) Public API: `/api/users` (public router). Everything else requires login/cookies unless accounts are disabled.
5) Uploads: multer targets `<DATA_ROOT>/_uploads`.
6) Routing: `src/server-startup.js` mounts all private routers (characters, chats, groups, world info, backgrounds, sprites, images, avatars, themes, presets, settings, stats, assets/files, quick replies, search, translation/classify/caption, Stable Diffusion, Horde, OpenAI/Anthropic/Google/Gemini/OpenRouter, Kobold/text-gen backends, speech/Azure, vectors, extensions, moving UI, server plugins). Deprecated endpoints redirect to new `/api/*` paths.
7) Pre-flight tasks: check/migrate user data, ensure thumbnails, verify disk cache, clean uploads, migrate access log, init settings/stats, load server plugins, run request proxy setup, compile `lib.js`.
8) Server start: `ServerStartup` binds HTTP/HTTPS on IPv4/IPv6 (auto-detection supported) and logs URLs. Post-start optionally opens browser and emits `SERVER_STARTED`.

## Configuration & CLI
- Config file: `config.yaml` (parsed in `src/config-init.js`, read via `getConfigValue`).
- Key toggles: `listen`, `listenAddress`, `protocol.ipv4/ipv6`, `port`, `ssl` cert/key paths, `whitelistMode`, `basicAuthMode`, `enableCorsProxy`, `requestProxy`, `autorun`, `enableUserAccounts`, `sessionTimeout`, `disableCsrfProtection`, `logging`, rate limiting, backups, thumbnailing, performance caches, tokenizer downloads, model defaults (OpenAI/Gemini/Claude/Mistral/Ollama/etc.), extension auto-download settings, server plugins (`enableServerPlugins`, `enableServerPluginsAutoUpdate`).
- CLI options mirror most config keys and override them (e.g., `--configPath`, `--dataRoot`, `--port`, `--listen`, `--enableIPv6/--enableIPv4 auto|true|false`, `--ssl`, `--certPath`, `--keyPath`, `--corsProxy`, `--disableCsrf`, `--requestProxyEnabled`, `--requestProxyBypass`, etc.). See `src/command-line.js` for the full list and defaults.

## Data Model & Storage
- Per-user directories are created from `USER_DIRECTORY_TEMPLATE` (`src/constants.js`) under `<DATA_ROOT>/<userHandle>/`:
  - `characters/`, `chats/`, `group chats/`, `groups/`, `worlds/` (world info), `backgrounds/`, `themes/`, `QuickReplies/`, `extensions/`, `NovelAI Settings/`, `KoboldAI Settings/`, `OpenAI Settings/`, `TextGen Settings/`, `user/images`, `User Avatars`, `user/files`, `user/workflows` (ComfyUI), `assets/`, `vectors/`, `thumbnails/` (with `bg` and `avatar`), `backups/`, `sysprompt/`, `reasoning/`, `movingUI/`, `instruct/`, `context/`.
  - Public directories (shared, not per-user): `public/img`, `public/sounds`, `public/scripts/extensions`, `public/scripts/extensions/third-party`, `backups/`.
- User accounts: when `enableUserAccounts=true`, login/auth uses cookie-session; passwords are scrypt-hashed. `users.js` exposes admin/private/public routers; `recover.js` helps reset credentials.
- CSRF: `/csrf-token` provides tokens unless disabled; all modifying routes expect `x-csrf-token` header.
- Uploads: temporary uploads in `<DATA_ROOT>/_uploads`; cleaned on startup.

## API Surface (conceptual)
- Auth/session: `/api/users/*` handles login/logout/session info and admin user management.
- Content CRUD: `/api/characters`, `/api/chats`, `/api/groups`, `/api/worldinfo`, `/api/backgrounds`, `/api/sprites`, `/api/themes`, `/api/quick-replies`, `/api/assets`, `/api/files`, `/api/images`, `/api/moving-ui`, `/api/extensions`, `/api/presets`, `/api/settings`, `/api/stats`, `/api/content`.
- AI backends: `/api/openai`, `/api/anthropic`, `/api/google`, `/api/gemini`, `/api/openrouter`, `/api/backends/chat-completions`, `/api/backends/text-completions`, `/api/backends/kobold`, `/api/novelai`, `/api/horde`, `/api/sd`, `/api/speech`, `/api/azure`, `/api/translate`, `/api/extra/classify`, `/api/extra/caption`, `/api/tokenizers`, `/api/vector`.
- Utilities: `/api/search/*` (SerpAPI/reader), `/thumbnail/*`, `/api/secrets`, `/api/serpapi` redirects are shimmed for backward compat.
- Events: `src/server-events.js` exposes an EventEmitter with `SERVER_STARTED` and others for internal hooks.

## Frontend Architecture
- Entry point: `public/index.html` + `public/style.css`; main runtime script is `public/script.js` (ESM).
- Libraries: `public/lib.js` gathers third-party deps (lodash, Fuse, DOMPurify, highlight.js, localforage, Handlebars, showdown, moment, Popper, etc.) and provides `initLibraryShims()` for legacy globals.
- UI modules (selected examples from `public/scripts`):
  - Core chat flow: `RossAscends-mods.js`, `power-user.js`, `PromptManager.js`, `filters.js`, `instruct-mode.js`, `authors-note.js`, `logprobs.js`.
  - Backend clients: `openai.js`, `textgen-settings.js`, `kai-settings.js` (Kobold), `nai-settings.js` (NovelAI), `horde.js`, `openrouter.js`, `cfg-scale.js`, `tokenizers.js`.
  - Content management: `world-info.js`, `group-chats.js`, `tags.js`, `bookmarks.js`, `extensions.js`, `secrets.js`, `themes.js`, `sprites.js`, `backgrounds.js`, `assets.js`, `files.js`.
  - UX helpers: `utils.js`, `i18n.js`, `moving-ui.js`, `slash-commands.js`, `search.js`, `stats.js`, `quick-replies.js`.
- State is largely kept in module-level variables (no state manager). Network I/O uses `fetch` directly against the Express API.
- Internationalization: `public/locales/*` with `i18n.js` loader.
- Extensions: client-side extensions in `public/scripts/extensions` (and `public/scripts/extensions/third-party`). Enabled via `config.yaml` → `extensions.enabled`. They can register generation interceptors, slash commands, toolbar buttons, etc. Auto-update/download logic is in `public/scripts/extensions.js`.

## Plugin Systems
- **Server plugins** (`src/plugin-loader.js`): place modules in `plugins/`; each must export `info { id, name, description }` and `init(router)`. `init` can attach Express routes under `/api/plugins/<id>`. Optional `exit` runs on shutdown. Auto-update pulls git-based plugins when `enableServerPluginsAutoUpdate=true`.
- **UI extensions**: live in `public/scripts/extensions` (and `public/scripts/extensions/third-party`). Enabled via `config.yaml` → `extensions.enabled`. They can register generation interceptors, slash commands, toolbar buttons, etc. Auto-update/download logic is in `public/scripts/extensions.js`.

## Security Posture
- Defaults are secure-by-default when `listen=false` (localhost only). Turning on `listen=true` requires either whitelist mode, basic auth, or user accounts; `verifySecuritySettings()` enforces warnings/fail-fast.
- CSRF protection is on unless `--disableCsrf`. Cookie sessions use secrets per-`DATA_ROOT`.
- CORS proxy is opt-in; request proxy can force outbound HTTP/SOCKS for model providers.

## Key UX Surfaces (for redesign work)
- Chat pane composition/layout, message rendering, and markdown handling are in `public/script.js` + `public/scripts/utils.js` + `public/style.css`.
- Character/card management UI is built from `public/scripts/characters.js`, `public/scripts/world-info.js`, `public/scripts/group-chats.js`, and associated templates under `public/`.
- Moving/dragging/resizable panes handled by `public/scripts/moving-ui.js` and helpers in `power-user.js`.
- Settings & presets: modules `openai.js`, `textgen-settings.js`, `kai-settings.js`, `nai-settings.js`, `horde.js`, `cfg-scale.js`, `preset-manager.js`, and `instruct-mode.js`; corresponding UI panels are defined in `index.html`.
- i18n text keys live in `public/locales`; `t()` helper centralizes translations.
- Any new UX should preserve CSRF headers, session cookie expectations, and the request shapes defined by the `/api/*` routes above.

## Porting Guidelines
- Keep the contract of `/api/*` routes (paths, payload fields, authentication via cookie-session + CSRF token) or provide a compatibility shim; the frontend makes direct `fetch` calls assuming these endpoints.
- Data directory layout is assumed by both client and server (e.g., character thumbnails in `<DATA_ROOT>/<user>/thumbnails/avatar`). Preserve folder names or update `USER_DIRECTORY_TEMPLATE` and client-side paths together.
- Preserve preprocessing steps that run before listen: migrations (`migrateUserData`, `migrateSystemPrompts`), thumbnail cache creation, and disk cache verification for character cards.
- Respect feature flags: CSRF, whitelist/basic auth, extensions enabled, tokenizer downloads, server plugins, request proxy, performance caches. Ported stacks should surface equivalents.
- Webpack-only dependency is the `lib.js` bundle; everything else is vanilla ESM and static assets. In another stack, you can prebuild `lib.js` and serve it from a CDN/path but keep import paths (`./lib.js`) stable.

## Where to Start Hacking
- Express entry/middleware: `src/server-main.js`.
- Routing surface: `src/server-startup.js` and individual routers under `src/endpoints/`.
- User/data management: `src/users.js`, `src/constants.js`, `src/util.js`.
- Frontend runtime: `public/script.js` plus modules in `public/scripts/`.
- Styling: `public/style.css` and component-specific CSS under `public/css/`.
- Extensibility: server plugins (`plugins/`), UI extensions (`public/scripts/extensions/`).

## Quick Checks Before Shipping Changes
- Run `npm test` (extend Playwright tests as needed) and `npm run lint`.
- Confirm `lib.js` rebuilds (`npm start` does it automatically); for production/docker use `webpack.config.js` with `forceDist`.
- Verify CSRF flow by hitting `/csrf-token` then a POST endpoint while logged in.
- If altering data schemas, add migration logic to `users.js` or relevant endpoint handlers and test with existing `data/` samples.

## Prompt & Context Pipeline (Frontend)
- Core files: `public/scripts/openai.js` (OpenAI/chat-completion pipeline), `public/scripts/PromptManager.js` (ordering, overrides, token budgeting), `public/script.js` (message flow), `public/scripts/instruct-mode.js` (instruction formatting), `public/scripts/world-info.js` (lorebook), `public/scripts/authors-note.js` (floating prompts), `public/scripts/extensions.js` (extension injections), `public/scripts/tokenizers.js` (token counts), `public/scripts/vectors/*` (vector memory/data bank), `public/scripts/logprobs.js` (postprocessing).
- Prompt construction flow (OpenAI/chat-completion path):
  1) `promptManager.preparePromptsForChatCompletion()` merges system prompts with user-defined prompts (main/nsfw/jailbreak/impersonation/new-chat), prompt-order preferences, and any character overrides; can mark prompts as absolute or relative positions and injection depth/order.
  2) Extension prompts (`extension_prompts`) are injected by position/role via `prepareExtensionPrompts()`; slash commands and moving UI can add more.
  3) `populateChatCompletion()` assembles the final message list: control prompts (quiet/system), mandatory prompts (authors note, vectors memory/data bank, smart context), ordered system/user prompts, dialogue examples, and chat history. It respects per-prompt enable/disable flags per character.
  4) `TokenHandler` (in `openai.js`) trims/aborts when mandatory prompts exceed `openai_max_context`; it logs overruns to the UI. Chat history is pruned from oldest first; summaries/anchors (authors note, world info) are kept where possible.
- Memory / knowledge sources:
  - **Chat history**: pruned by token budget inside `TokenHandler`.
  - **World Info / lorebooks**: `world-info.js` injects matched entries into prompts; depth/injection order configurable.
  - **Authors note / floating prompt**: `authors-note.js` injects a late system/user prompt at a chosen depth.
  - **Vector memory / data bank**: `public/scripts/vectors/*` runs similarity search over stored embeddings and injects results as prompts (`vectorsMemory`, `vectorsDataBank`) before chat history.
  - **Summaries/continuations**: `continue_nudge_prompt`, group nudge, impersonation prompts, and enhance definitions prompts are available and ordered through PromptManager.
- Location/time context:
  - Message timestamps come from saved chat metadata (`chat_metadata` in `public/script.js`) and are formatted via `utils.timestampToMoment`; no automatic timezone/geo adjustments are injected into prompts unless an extension adds them.
- Other backends (Kobold/TextGen/NovelAI) follow similar assembly paths in their respective modules (`public/scripts/kai-settings.js`, `textgen-settings.js`, `nai-settings.js`) but the OpenAI/chat-completion stack is the most feature-complete and illustrates how prompts are layered. Porting should preserve marker prompts, ordering, and token-budget trimming semantics to avoid regressions.

### Prompt Construction Diagram (OpenAI / Chat Completion Path)
```
Character/Settings Inputs
│
├─ Character card + overrides
├─ User prompt presets (main/nsfw/jailbreak/impersonation/new-chat)
├─ Authors note / floating prompts
├─ World Info (lorebook matches)
├─ Vector memory + data bank search results
├─ Extension prompts (registered by extensions)
├─ System controls (quiet prompt, summaries, safety toggles)
└─ Chat history + dialogue examples

           ▼
   preparePromptsForChatCompletion()
   - Merge system + user prompts
   - Apply character overrides
   - Respect prompt order, depth, role, absolute/relative markers
   - Insert extension prompts by position/role

           ▼
   populateChatCompletion()
   - Build message collections in order:
       control prompts (quiet/system)
       mandatory prompts (authors note, vectors, smart context)
       ordered system/user prompts
       dialogue examples
       chat history (newest last)

           ▼
   TokenHandler.trim()
   - Count tokens (model-aware)
   - Trim oldest chat messages first
   - Abort if mandatory prompts exceed max context

           ▼
 Final ChatCompletion payload
 (role/content/name list sent to backend)
```

## UI Model & Screens (Conceptual)
- Landing/Login: `public/index.html` with login gating; `public/login.html` for auth. Session via cookies; CSRF header on mutating calls.
- Sidebar: Character list, groups, tags, bookmarks, presets, and extensions entries assembled in `public/script.js` with `group-chats.js`, `tags.js`, `bookmarks.js`, `extensions.js`.
- Chat Pane: Message stream (markdown+media), input box, swipe/regen controls, status indicators. Rendering in `public/script.js`; markdown sanitized via DOMPurify; media handled in `images.js`/`assets.js`.
- Character Management: Card import/export, attributes, avatars, thumbnails via `public/scripts/characters.js` plus endpoints `/api/characters`, `/api/avatars`, `/thumbnail`. Group characters via `group-chats.js`.
- World Info / Lorebook: Editor and matcher in `world-info.js`; prompts injected by match rules (keys, case/regex options). Backed by `/api/worldinfo`.
- Presets & Settings: Model/backend settings panels (`openai.js`, `kai-settings.js`, `textgen-settings.js`, `nai-settings.js`, `horde.js`, `cfg-scale.js`, `preset-manager.js`). Settings persist per-user in `<DATA_ROOT>/<user>/... Settings`.
- Extensions UI: Managed in `extensions.js`; extension fields can render templates and add toolbar items. Third-party extensions live under `public/scripts/extensions/third-party`.
- Moving UI / Layout: Drag/drop/resizable panels handled by `moving-ui.js` and helpers in `power-user.js`; state saved in `<DATA_ROOT>/<user>/movingUI`.
- Search / Browse: SERP/reader integrations in `search.js` and `st-context.js`; uses `/api/search/*`.
- Stats/Logs: User stats in `stats.js`; logprobs display in `logprobs.js`; access log is server-side under `<DATA_ROOT>/access.log`.
- Themes/Backgrounds/Sprites: Managed by `themes.js`, `backgrounds.js`, `sprites.js`; assets stored per-user in corresponding folders and served by matching `/api/*` routes.

## Core Conceptual Models
- User: Handle, name, password hash, admin flag, enabled flag. Drives per-user directories and session scope.
- Character Card: Lore/personality plus avatar and definitions; stored as JSON/card files under `characters/`; thumbnails cached in `thumbnails/avatar`.
- Chat: Ordered messages with metadata (`chat_metadata`); persisted under `chats/` per user/character or group.
- Group: Collection of characters with shared chat (`group chats/`), avatars, and depth prompts; see `group-chats.js`.
- World Info Entry: Trigger keys + content; injected when keys match recent messages; stored under `worlds/`.
- Prompt: Structured object (`PromptManager`) with identifier, role, content, position, depth, order, system/user flag, extension flag. Collections are ordered and trimmed per token budget.
- Memory Blocks: Chat history, vector memory/data bank hits, world info, authors note, summaries—all become prompts at defined depths/orders.
- Extension Prompt: An extension-provided prompt with position (before/in prompt), role, optional filter; injected alongside core prompts.
- Assets: Images/files/backgrounds/themes/sprites stored per-user; served via `/api/assets`, `/api/files`, `/api/images`, `/api/backgrounds`, `/api/sprites`.
- Tokenizer/Model: Token counting and model metadata handled by `tokenizers.js`; informs prompt trimming and pricing displays.
