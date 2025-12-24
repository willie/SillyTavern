# Repository Guidelines

## Project Structure & Module Organization
- `src/`: Node/Express backend, API endpoints, configuration loaders, and shared utilities. `public/`: browser UI (scripts, styles, locales). `plugins/`: server plugins. `default/` and `data/`: seed content and user data directories.  
- `SillyTavernApp/`: Swift/iOS/macOS client that mirrors the server’s file layout (characters, chats, group chats, worlds).  
- `tests/`: separate Jest workspace (`npm install` inside) with unit and puppeteer E2E specs.  
- `webpack.config.js`: bundles client assets into `public/lib.js`; `config.yaml` governs runtime options.

## Build, Test, and Development Commands
- `npm install` (root): install server/web deps (Node ≥ 18).  
- `npm start`: run the server on the default port; `npm run debug` adds `--inspect`; `npm run start:global` for system-wide install; `npm run start:electron` bootstraps the Electron shell.  
- `npm run lint` / `npm run lint:fix`: ESLint across `src` and `public`.  
- Plugins: `npm run plugins:update` or `npm run plugins:install`.  
- Tests: `cd tests && npm install && npm test` (runs `test:unit` then `test:e2e`); E2E assumes a server at `http://localhost:8000` (set in `tests/jest.setup.js`).

## Coding Style & Naming Conventions
- JavaScript/TypeScript is ES module-based (`"type": "module"`), 4-space indentation, single quotes, and descriptive camelCase identifiers; filenames are kebab-case for scripts and snake/kebab for JSON/data when matching SillyTavern’s existing patterns.  
- Follow existing directory names literally (e.g., `group chats/`, `User Avatars/`); avoid renaming these constants.  
- Run ESLint before committing; keep JSDoc annotations in server code where present.

## Testing Guidelines
- Unit tests live under `tests/**/*.(test).js`; E2E specs use `jest-puppeteer` with `**/*.(e2e).js`.  
- Prefer fast unit coverage for helpers and endpoint utilities; reserve E2E for critical user flows (chat creation, character load, group chat persistence).  
- When adding E2E, require the server to be running locally and keep test data isolated (use temporary characters/groups and clean up).  
- Aim to leave failing tests disabled only with clear TODO and issue links.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (“Add group chat search fallback”), scoped and atomic; include rationale in the body if the diff is non-trivial.  
- PRs: describe the user-facing change, testing performed (`npm run lint`, `tests` suite), config toggles touched, and any data migration implications. Include screenshots/GIFs for UI changes and note impact on plugins or the Swift client if applicable.
