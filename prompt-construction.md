# SillyTavern Prompt Construction Pipeline

This document exhaustively traces how SillyTavern assembles the final LLM prompt — from raw user inputs, character cards, world info entries, and configuration through to the API call. Two distinct pipelines exist: one for **Text Completion APIs** (KoboldAI, NovelAI, text-generation-webui) and one for **Chat Completion APIs** (OpenAI, Claude, Gemini, etc.). Both share early stages but diverge in final assembly.

---

## Table of Contents

1. [Entry Point — `Generate()`](#1-entry-point--generate)
2. [Character Card Fields](#2-character-card-fields)
3. [World Info / Lorebook](#3-world-info--lorebook)
4. [Macro / Variable Substitution](#4-macro--variable-substitution)
5. [Regex Replacement Pipeline](#5-regex-replacement-pipeline)
6. [System Prompt Assembly (Text Completion)](#6-system-prompt-assembly-text-completion)
7. [Story String Rendering](#7-story-string-rendering)
8. [Example Messages / Few-Shot Dialogue](#8-example-messages--few-shot-dialogue)
9. [Author's Note / Floating Prompt](#9-authors-note--floating-prompt)
10. [User Persona Injection](#10-user-persona-injection)
11. [Extension Prompt System](#11-extension-prompt-system)
12. [Chat History Selection and Truncation](#12-chat-history-selection-and-truncation)
13. [Context Budget and Token Management](#13-context-budget-and-token-management)
14. [Text Completion Final Assembly](#14-text-completion-final-assembly)
15. [Chat Completion Assembly (OpenAI Path)](#15-chat-completion-assembly-openai-path)
16. [Instruct Mode Formatting](#16-instruct-mode-formatting)
17. [Backend Prompt Conversion](#17-backend-prompt-conversion)
18. [Model-Specific Formatting](#18-model-specific-formatting)
19. [Post-Processing and Stop Sequences](#19-post-processing-and-stop-sequences)
20. [Summary Prompt Layout Diagram](#20-summary-prompt-layout-diagram)

---

## 1. Entry Point — `Generate()`

**File:** `public/script.js:4065-5374`

```js
export async function Generate(type, { automatic_trigger, force_name2, quiet_prompt, quietToLoud,
    skipWIAN, force_chid, signal, quietImage, quietName, jsonSchema = null, depth = 0 } = {},
    dryRun = false)
```

Every message generation begins here. `type` is one of: `undefined`/`'normal'`, `'regenerate'`, `'swipe'`, `'continue'`, `'impersonate'`, `'quiet'`.

### High-level flow

1. **Pre-processing** — slash commands, bias extraction, user message insertion (lines 4085-4233)
2. **Character card fields** — load description, personality, scenario, system prompt, jailbreak (line 4235-4245)
3. **Depth prompts** — character-specific and group depth prompts (lines 4247-4261)
4. **Chat filtering** — collect non-system messages, apply regex, append file content, add reasoning traces (lines 4268-4326)
5. **Context size** — determine `this_max_context` from model/settings (line 4329)
6. **World info scan** — call `getWorldInfoPrompt()` with chat and scan data (lines 4391-4405)
7. **Example messages** — parse, merge WI examples, format for instruct mode (lines 4386-4432)
8. **WI depth injections** — register depth-positioned world info entries as extension prompts (lines 4434-4451)
9. **Persona description** — inject via extension prompt system (line 4454)
10. **System prompt** — resolve for text completion APIs (lines 4457-4467)
11. **Story string** — render template combining all above (lines 4469-4505)
12. **Chat history** — format, order, inject extension prompts at depth, truncate to budget (lines 4538-4741)
13. **Final assembly** — branch to text completion or chat completion path (lines 5012-5087)
14. **API call** — send to backend endpoint

---

## 2. Character Card Fields

**File:** `public/script.js:3231-3310`

Character card data is loaded lazily via `getCharacterCardFieldsLazy()` and resolved in `getCharacterCardFields()`. Called at line 4235-4245 of `Generate()`.

### Fields extracted

| Field | Source | Fallback |
|-------|--------|----------|
| `description` | `characters[chid].description` | Group card override |
| `personality` | `characters[chid].personality` | Group card override |
| `scenario` | `chat_metadata['scenario']` | `characters[chid].scenario` |
| `mesExamples` | `chat_metadata['mes_example']` | `characters[chid].mes_example` |
| `system` | `chat_metadata['system_prompt']` | `characters[chid].data.system_prompt` (only if `power_user.prefer_character_prompt`) |
| `jailbreak` | `characters[chid].data.post_history_instructions` | Only if `power_user.prefer_character_jailbreak` |
| `charDepthPrompt` | `characters[chid].data.extensions.depth_prompt.prompt` | — |
| `creatorNotes` | `characters[chid].data.creator_notes` | — |
| `persona` | `power_user.persona_description` | — |

Each field passes through `baseChatReplace()` which applies macro substitution (`substituteParams`) and newline collapsing.

```js
// public/script.js:3172-3183
export function baseChatReplace(value, name1Override, name2Override) {
    if (typeof value === 'string' && value.length > 0) {
        value = substituteParams(value, { name1Override, name2Override, replaceCharacterCard: false });
        if (power_user.collapse_newlines) value = collapseNewlines(value);
        value = value.replace(/\r/g, '');
    }
    return value;
}
```

### Character Card V2 format

Character cards are stored as PNG files with embedded JSON (TavernCard V2 spec) or standalone JSON. Parsed on the backend in `src/endpoints/characters.js:181` (`readCharacterData()`), which extracts the JSON from the PNG's tEXt chunk.

---

## 3. World Info / Lorebook

**File:** `public/scripts/world-info.js` (6,152 lines)

Called at `Generate()` line 4405:

```js
const { worldInfoString, worldInfoBefore, worldInfoAfter, worldInfoExamples,
        worldInfoDepth, outletEntries } = await getWorldInfoPrompt(chatForWI, this_max_context, dryRun, globalScanData);
```

### 3.1 Entry Structure

Each WI entry has ~40 fields (defined at `world-info.js:3962-4005`). Key fields:

| Field | Purpose |
|-------|---------|
| `key[]` | Primary activation keywords (any must match) |
| `keysecondary[]` | Secondary conditional keywords |
| `selectiveLogic` | `AND_ANY` (0), `NOT_ALL` (1), `NOT_ANY` (2), `AND_ALL` (3) |
| `content` | The text injected into the prompt |
| `position` | `before` (0), `after` (1), `ANTop` (2), `ANBottom` (3), `atDepth` (4), `EMTop` (5), `EMBottom` (6), `outlet` (7) |
| `depth` | For `atDepth` positioning — message depth (default 4) |
| `role` | `SYSTEM` (0), `USER` (1), `ASSISTANT` (2) |
| `order` | Priority for scanning (higher = first) |
| `constant` | Always activate regardless of keywords |
| `probability` | % chance of activation (1-100) |
| `group` | Inclusion group — only one entry per group activates |
| `sticky` / `cooldown` / `delay` | Timed activation effects |
| `scanDepth` | Override global scan depth per-entry |
| `ignoreBudget` | Bypass token budget limit |

### 3.2 Lore Sources (loaded in priority order)

```
Chat Lorebook → Persona Lorebook → Character Lorebook(s) → Global Lorebook(s)
```

Loaded by `getSortedEntries()` (line 4347). Insertion strategy (`world_info_character_strategy`) controls interleaving between character and global entries: `evenly`, `character_first`, or `global_first`.

### 3.3 Scanning Algorithm — `checkWorldInfo()` (line 4469-5035)

Uses a state machine with 4 states:

| State | Value | Behavior |
|-------|-------|----------|
| `INITIAL` | 1 | Scan recent chat messages up to `world_info_depth` |
| `RECURSION` | 2 | Scan content of newly activated entries |
| `MIN_ACTIVATIONS` | 3 | Expand scan depth to satisfy `world_info_min_activations` |
| `NONE` | 0 | Stop |

The `WorldInfoBuffer` class (line 199) manages what text is available to scan:

```js
// Scan buffer includes:
// 1. Chat messages up to depth (depthBuffer[])
// 2. Recursively activated entry content (recurseBuffer[])
// 3. Extension prompts flagged for scanning (injectBuffer[])
// 4. Optional global data: persona description, character description,
//    personality, depth prompt, scenario, creator notes
//    (per-entry flags: matchPersonaDescription, matchCharacterDescription, etc.)
```

**Keyword matching** (`matchKeys()`, line 337): supports regex patterns (`/pattern/flags`), case-sensitive/insensitive matching, whole-word matching.

**Budget**: `Math.round(world_info_budget * maxContext / 100)`, capped by `world_info_budget_cap`. Entries with `ignoreBudget` bypass this.

### 3.4 Output Placement

After scanning, activated entries are categorized by `position`:

| Position | Output field | Destination in prompt |
|----------|-------------|----------------------|
| `before` (0) | `worldInfoBefore` | Before character definition in story string |
| `after` (1) | `worldInfoAfter` | After character definition in story string |
| `ANTop` (2) | Merged into Author's Note | Before AN content |
| `ANBottom` (3) | Merged into Author's Note | After AN content |
| `atDepth` (4) | `worldInfoDepth[]` | Injected into chat at specified depth via extension prompts |
| `EMTop` (5) | `worldInfoExamples[]` | Prepended to example messages |
| `EMBottom` (6) | `worldInfoExamples[]` | Appended to example messages |
| `outlet` (7) | `outletEntries{}` | Custom named outlet, accessible via `{{outlet::key}}` macro |

---

## 4. Macro / Variable Substitution

**File:** `public/script.js:2823-2852` (entry), `public/scripts/macros.js` (legacy engine), `public/scripts/macros/engine/` (experimental engine)

Macros are `{{name}}` patterns substituted throughout every text field (character data, system prompts, world info content, extension prompts, user messages).

### 4.1 Entry Point

```js
// public/script.js:2823
export function substituteParams(content, options = {}) {
    if (!power_user?.experimental_macro_engine) {
        return substituteParamsLegacy(content, ...);
    }
    const env = MacroEnvBuilder.buildFromRawEnv(ctx);
    return MacroEngine.evaluate(content, env);
}
```

### 4.2 Complete Macro List

**Names:**
| Macro | Value |
|-------|-------|
| `{{user}}` | Username (`name1`) |
| `{{char}}` | Character name (`name2`) |
| `{{charIfNotGroup}}` | Character name (empty in group chats) |
| `{{group}}` | Group member list (comma-separated, including muted) |
| `{{groupNotMuted}}` | Group members excluding muted |
| `{{notChar}}` | All participants except current speaker |

**Character card fields:**
| Macro | Value |
|-------|-------|
| `{{description}}` / `{{charDescription}}` | Character description |
| `{{personality}}` / `{{charPersonality}}` | Character personality |
| `{{scenario}}` / `{{charScenario}}` | Scenario text |
| `{{persona}}` | User persona description |
| `{{mesExamples}}` / `{{mesExamplesRaw}}` | Example messages |
| `{{charPrompt}}` | Character system prompt |
| `{{charInstruction}}` / `{{charJailbreak}}` | Post-history instructions |
| `{{charVersion}}` / `{{char_version}}` | Character version |
| `{{charDepthPrompt}}` | Character depth prompt |
| `{{creatorNotes}}` | Creator notes |

**Date/time:**
| Macro | Value |
|-------|-------|
| `{{time}}` | Locale time |
| `{{date}}` | Locale date |
| `{{weekday}}` | Current weekday name |
| `{{isotime}}` | `HH:mm` format |
| `{{isodate}}` | `YYYY-MM-DD` format |
| `{{datetimeformat::FORMAT}}` | Custom moment.js format |
| `{{idle_duration}}` | Time since last message |
| `{{time_UTC±N}}` | UTC-adjusted time |
| `{{timeDiff::t1::t2}}` | Human-readable duration between times |

**Chat state:**
| Macro | Value |
|-------|-------|
| `{{lastMessage}}` | Last message text |
| `{{lastMessageId}}` | Last message index |
| `{{lastUserMessage}}` | Last user message |
| `{{lastCharMessage}}` | Last character message |
| `{{firstIncludedMessageId}}` | First message in context window |
| `{{firstDisplayedMessageId}}` | First displayed message |
| `{{lastSwipeId}}` | Total swipes (1-based) |
| `{{currentSwipeId}}` | Current swipe (1-based) |
| `{{input}}` | Current textarea content |
| `{{maxPrompt}}` | Max context tokens |
| `{{lastGenerationType}}` | Last generation type |
| `{{model}}` | Current model name |
| `{{isMobile}}` | Mobile device flag |

**Utility:**
| Macro | Value |
|-------|-------|
| `{{newline}}` | Literal `\n` |
| `{{trim}}` | Trim surrounding whitespace (post-processing) |
| `{{noop}}` | Empty string |
| `{{space}}` / `{{space::N}}` | Space(s) |
| `{{reverse::text}}` | Reversed string |
| `{{// comment}}` | Stripped (comment) |
| `{{roll FORMULA}}` | Dice roll (e.g., `{{roll 1d20+5}}`) |
| `{{random::a::b::c}}` | Random selection |
| `{{pick::a::b::c}}` | Deterministic seeded pick |
| `{{banned "word"}}` | Add word to ban list |
| `{{outlet::key}}` | WI outlet content |

**Variables:**
| Macro | Value |
|-------|-------|
| `{{setvar::name::value}}` | Set local variable |
| `{{getvar::name}}` | Get local variable |
| `{{addvar::name::value}}` | Add to variable |
| `{{incvar::name}}` | Increment variable |
| `{{decvar::name}}` | Decrement variable |
| `{{ifvar::name::true::false}}` | Conditional |

**Author's Note:**
| Macro | Value |
|-------|-------|
| `{{authorsNote}}` | Current chat's AN |
| `{{charAuthorsNote}}` | Character-specific AN |
| `{{defaultAuthorsNote}}` | Default AN |

---

## 5. Regex Replacement Pipeline

**File:** `public/scripts/extensions/regex/engine.js:334-381`

Applied to chat messages during collection in `Generate()` (line 4281):

```js
let regexedMessage = getRegexedString(message, regexType, { isPrompt: true, depth: ... });
```

Regex scripts are user-defined find/replace patterns that run at specific placements:

| Placement | Value | Applied to |
|-----------|-------|-----------|
| `USER_INPUT` | 1 | User messages |
| `AI_OUTPUT` | 2 | AI-generated messages |
| `SLASH_COMMAND` | 3 | Slash command output |
| `WORLD_INFO` | 5 | World info entries |
| `REASONING` | 6 | Reasoning/CoT content |

Each script has: `findRegex`, `replaceString`, `trimStrings[]`, `placement[]`, `minDepth`, `maxDepth`, `runOnEdit`, `markdownOnly`, `promptOnly` flags. Scripts are checked against depth constraints, then the regex is applied with capture group substitution.

---

## 6. System Prompt Assembly (Text Completion)

**File:** `public/script.js:4457-4467`

For non-OpenAI APIs, the system prompt (`system` variable) is resolved:

```js
if (main_api !== 'openai') {
    if (power_user.sysprompt.enabled) {
        system = power_user.prefer_character_prompt && system
            ? substituteParams(system, { original: power_user.sysprompt.content ?? '' })
            : baseChatReplace(power_user.sysprompt.content);
    } else {
        system = '';
    }
}
```

**Priority**: If `prefer_character_prompt` is enabled and the character card has a system prompt, the character's prompt is used (with the global prompt available via `{{original}}`). Otherwise the global `power_user.sysprompt.content` is used.

For OpenAI/Chat Completion APIs, system prompt handling is done entirely in the PromptManager (see [section 15](#15-chat-completion-assembly-openai-path)).

---

## 7. Story String Rendering

**File:** `public/scripts/power-user.js:2231-2266`

The "story string" is a Handlebars template that combines all character info, world info, and system prompt into a single preamble block.

### 7.1 Default Template

```handlebars
{{#if system}}{{system}}\n{{/if}}
{{#if description}}{{description}}\n{{/if}}
{{#if personality}}{{char}}'s personality: {{personality}}\n{{/if}}
{{#if scenario}}Scenario: {{scenario}}\n{{/if}}
{{#if persona}}{{persona}}\n{{/if}}
```

Defined at `power-user.js:86`. Users can customize this via context presets.

### 7.2 Template Variables

Passed from `Generate()` at line 4473-4489:

```js
const storyStringParams = {
    description,          // Character description
    personality,          // Character personality
    persona,              // User persona (only if position == IN_PROMPT)
    scenario,             // Scenario text
    system,               // System prompt (resolved above)
    char: name2,          // Character name
    user: name1,          // User name
    wiBefore,             // World info before character definition
    wiAfter,              // World info after character definition
    loreBefore,           // Alias for wiBefore
    loreAfter,            // Alias for wiAfter
    anchorBefore,         // Extension prompts (BEFORE_PROMPT position)
    anchorAfter,          // Extension prompts (IN_PROMPT position)
    mesExamples,          // Formatted example messages (joined)
    mesExamplesRaw,       // Raw example messages (joined)
};
```

### 7.3 Rendering Process

```js
// power-user.js:2231-2266
export function renderStoryString(params) {
    const storyString = contextSettings.story_string;          // User's template
    const compiledTemplate = Handlebars.compile(storyString, { noEscape: true });
    let output = compiledTemplate(params);                     // Render template
    output = substituteParams(output, params.user, params.char); // Apply macros
    output = output.replace(/^\n+/, '');                       // Strip leading newlines
    // Conditionally add trailing newline
    return output;
}
```

### 7.4 Context Presets

Preset files in `default/content/presets/context/` define custom story string templates. Example (ChatML preset):

```
{{#if anchorBefore}}{{anchorBefore}}\n{{/if}}
{{#if system}}{{system}}\n{{/if}}
{{#if wiBefore}}{{wiBefore}}\n{{/if}}
{{#if description}}{{description}}\n{{/if}}
{{#if personality}}{{personality}}\n{{/if}}
{{#if scenario}}{{scenario}}\n{{/if}}
{{#if wiAfter}}{{wiAfter}}\n{{/if}}
{{#if persona}}{{persona}}\n{{/if}}
{{#if anchorAfter}}{{anchorAfter}}\n{{/if}}
{{trim}}
```

### 7.5 Story String Position

The rendered story string can be placed in two positions (`power_user.context.story_string_position`):

- **`IN_PROMPT` (0)** — Default. Prepended to the full prompt as a preamble.
- **`IN_CHAT` (1)** — Injected into chat history at configurable depth/role via the extension prompt system.

```js
// script.js:4496-4505
if (applyStoryStringInject) {
    setExtensionPrompt(inject_ids.STORY_STRING, combinedStoryString,
        extension_prompt_types.IN_CHAT, depth, false, role);
    combinedStoryString = '';  // Clear to prevent duplication
}
```

---

## 8. Example Messages / Few-Shot Dialogue

**File:** `public/script.js:3317-3331, 4386-4432`

### 8.1 Parsing

Example messages are stored in the character card as a single string with `<START>` delimiters:

```
<START>
{{user}}: Hello, how are you?
{{char}}: I'm doing well, thank you for asking!
<START>
{{user}}: What's your favorite color?
{{char}}: I've always been fond of blue.
```

Parsed by `parseMesExamples()` (line 3317):

```js
export function parseMesExamples(examplesStr, isInstruct) {
    const exampleSeparator = power_user.context.example_separator
        ? `${substituteParams(power_user.context.example_separator)}\n` : '';
    const blockHeading = (main_api === 'openai' || isInstruct) ? '<START>\n' : exampleSeparator;
    return examplesStr.split(/<START>/gi).slice(1).map(block => `${blockHeading}${block.trim()}\n`);
}
```

### 8.2 World Info Example Entries

WI entries with `EMTop`/`EMBottom` position are merged into the examples array (line 4408-4425):

```js
for (const example of worldInfoExamples) {
    const cleanedExample = parseMesExamples(baseChatReplace(example.content), isInstruct);
    if (example.position === wi_anchor_position.before) {
        mesExamplesArray.unshift(...cleanedExample);
    } else {
        mesExamplesArray.push(...cleanedExample);
    }
}
```

### 8.3 Pinned vs Unpinned

- **Pinned** (`power_user.pin_examples = true`): Examples are pre-allocated in the token budget and always included.
- **Unpinned** (default): Examples are fitted into remaining budget after chat history.
- **Stripped** (`power_user.strip_examples = true`): Examples are included in the story string render but removed before final prompt assembly.

### 8.4 OpenAI Format

For chat completion APIs, examples are parsed into individual messages by `parseExampleIntoIndividual()` (`openai.js:678-736`), which splits on speaker names and assigns `role: 'system'` with `name: 'example_user'` or `name: 'example_assistant'`.

---

## 9. Author's Note / Floating Prompt

**File:** `public/scripts/authors-note.js`

Module name: `'2_floating_prompt'` (deliberately prefixed with `2_` for sort ordering among extension prompts).

### 9.1 Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `note_prompt` | `''` | The AN text (stored in `chat_metadata`) |
| `note_depth` | 4 | Injection depth in chat history |
| `note_position` | 1 (`IN_CHAT`) | Position type |
| `note_interval` | 1 | Insert every N user messages |
| `note_role` | 0 (`SYSTEM`) | Message role |

### 9.2 Per-Character Notes

Character-specific notes are stored in `extension_settings.note.chara[]`. Position options:
- `replace` (0) — Replace the global note entirely
- `before` (1) — Prepend to global note
- `after` (2) — Append to global note

### 9.3 Injection

`setFloatingPrompt()` (called at `Generate()` line 4389) registers the AN via:

```js
setExtensionPrompt('2_floating_prompt', mergedPrompt, position, depth, allowWIScan, role);
```

WI entries positioned at `ANTop`/`ANBottom` are merged around the AN content by `addPersonaDescriptionExtensionPrompt()` and the WI system.

---

## 10. User Persona Injection

**File:** `public/script.js:3034-3056`, `public/scripts/power-user.js:110-120`

The user persona (`power_user.persona_description`) can be placed at various positions:

| Position | Value | Behavior |
|----------|-------|----------|
| `IN_PROMPT` | 0 | Included as `{{persona}}` in the story string template |
| `TOP_AN` | 2 | Prepended to the Author's Note |
| `BOTTOM_AN` | 3 | Appended to the Author's Note |
| `AT_DEPTH` | 4 | Injected into chat at `persona_description_depth` with `persona_description_role` |
| `NONE` | 9 | Not included |

```js
// script.js:3034-3056
function addPersonaDescriptionExtensionPrompt() {
    if (power_user.persona_description_position === persona_description_positions.AT_DEPTH) {
        setExtensionPrompt('PERSONA_DESCRIPTION', power_user.persona_description,
            extension_prompt_types.IN_CHAT, power_user.persona_description_depth,
            true, power_user.persona_description_role);
    }
    // TOP_AN / BOTTOM_AN: merge into author's note extension prompt
}
```

When `IN_PROMPT`, the persona text is passed as the `persona` parameter to `renderStoryString()` and rendered by the Handlebars template.

---

## 11. Extension Prompt System

**File:** `public/script.js:452-466, 8620-8628, 3132-3160`

The extension prompt system is the unified injection mechanism for all dynamic content (world info depth entries, author's note, persona, memory/summary, vector RAG, etc.).

### 11.1 Data Structure

```js
extension_prompts[key] = {
    value: String,      // The prompt text
    position: Number,   // extension_prompt_types: NONE(-1), IN_PROMPT(0), IN_CHAT(1), BEFORE_PROMPT(2)
    depth: Number,      // Chat injection depth (0 = after last message)
    scan: Boolean,      // Allow world info keyword scanning
    role: Number,       // extension_prompt_roles: SYSTEM(0), USER(1), ASSISTANT(2)
    filter: Function,   // Optional async filter for conditional injection
};
```

### 11.2 Known Injection IDs

| ID | Source |
|----|--------|
| `'1_memory'` | Summarize/memory extension |
| `'2_floating_prompt'` | Author's note |
| `'3_vectors'` | Vector/embedding memory |
| `'4_vectors_data_bank'` | Data bank vectors |
| `'chromadb'` | ChromaDB smart context |
| `'PERSONA_DESCRIPTION'` | User persona (AT_DEPTH) |
| `'QUIET_PROMPT'` | Quiet generation prompt |
| `'DEPTH_PROMPT'` | Character depth prompt |
| `'DEPTH_PROMPT_N'` | Group character depth prompts |
| `'customDepthWI_D_R'` | World info at depth D with role R |
| `'customWIOutlet_KEY'` | World info outlet |
| `'__STORY_STRING__'` | Story string (when IN_CHAT position) |

### 11.3 Retrieval

```js
// script.js:3132-3160
export async function getExtensionPrompt(position, depth, separator, role, wrap) {
    return Object.keys(extension_prompts).sort()
        .map(x => extension_prompts[x])
        .filter(x => x.position == position && x.value)
        .filter(x => depth === undefined || x.depth === depth)
        .filter(x => role === undefined || x.role === role)
        // Apply async filter functions
        .map(x => x.value.trim()).join(separator);
}
```

### 11.4 Chat Injection — `doChatInject()`

**File:** `public/script.js:5400-5448`

For text completion APIs, IN_CHAT extension prompts are injected as messages at their specified depth:

```js
async function doChatInject(messages, isContinue) {
    messages.reverse();
    for (let i = 0; i <= maxDepth; i++) {
        for (const role of [SYSTEM, USER, ASSISTANT]) {
            const extensionPrompt = await getExtensionPrompt(IN_CHAT, i, '\n', role);
            if (extensionPrompt) {
                messages.splice(depth + totalInserted, 0, { name, is_user, mes: extensionPrompt, ... });
            }
        }
    }
    messages.reverse();
    return injectedIndices;
}
```

---

## 12. Chat History Selection and Truncation

**File:** `public/script.js:4268-4326, 4538-4741`

### 12.1 Message Collection

1. **Filter** — Remove system messages (keep tool invocations if tool calling supported) (line 4271)
2. **Regex** — Apply regex scripts per message based on `USER_INPUT`/`AI_OUTPUT` placement (line 4281)
3. **File attachments** — Append embedded file content (line 4282)
4. **Media titles** — Append image/file titles if flagged (lines 4284-4297)
5. **Reasoning traces** — Merge reasoning content from `extra.reasoning` with `PromptReasoning` (lines 4306-4326)

### 12.2 Message Formatting (Text Completion)

Each message is formatted via `formatMessageHistoryItem()` (line 5605):

```js
function formatMessageHistoryItem(chatItem, isInstruct, forceOutputSequence) {
    if (chatItem.extra?.[IGNORE_SYMBOL]) return '';  // Hidden messages
    let textResult = shouldPrependName ? `${itemName}: ${chatItem.mes}\n` : `${chatItem.mes}\n`;
    if (isInstruct) textResult = formatInstructModeChat(itemName, chatItem.mes, ...);
    return textResult;
}
```

### 12.3 Chat Array Construction

Messages are stored in `chat2[]` in reverse order (newest first), then re-reversed during final assembly.

For OpenAI path, raw message strings are stored; for text completion, formatted strings with names/instruct sequences.

### 12.4 User Alignment Message

If instruct mode is enabled and `power_user.instruct.user_alignment_message` is set, a synthetic user message is added when the last in-context message is not from the user (line 4589-4599).

### 12.5 Jailbreak / Post-History Instructions Injection (Text Completion)

For non-OpenAI APIs (line 4518-4536):

```js
if (main_api !== 'openai' && power_user.sysprompt.enabled) {
    jailbreak = power_user.prefer_character_jailbreak && jailbreak
        ? substituteParams(jailbreak, { original: power_user.sysprompt.post_history ?? '' })
        : baseChatReplace(power_user.sysprompt.post_history);
    if (jailbreak) {
        coreChat.push({ mes: jailbreak, is_user: true });  // Injected as user message
    }
}
```

---

## 13. Context Budget and Token Management

**File:** `public/script.js:4328-4374, 4618-4741, 4865-4891`

### 13.1 Max Context Determination

```js
let this_max_context = getMaxContextSize();  // From model/API settings
// Adjusted for: Horde limits, CFG guidance prompts
```

### 13.2 Token Counting

```js
async function getMessagesTokenCount() {
    const encodeString = [
        combinedStoryString, examplesString, userAlignmentMessage,
        chatString, modifyLastPromptLine(''), cyclePrompt
    ].join('').replace(/\r/gm, '');
    return getTokenCountAsync(encodeString, power_user.token_padding);
}
```

`power_user.token_padding` (default 64) is added as safety margin.

### 13.3 Message Filling Loop

1. **Pre-allocate injected messages** (depth prompts) — always included (line 4649-4671)
2. **Fill remaining messages** oldest-to-newest until budget exceeded (line 4673-4698)
3. **Add user alignment message** if last message isn't from user (line 4700-4707)
4. **Fit unpinned examples** into remaining budget (line 4728-4741)

### 13.4 Overflow Handling — `checkPromptSize()`

```js
async function checkPromptSize() {
    if (thisPromptContextSize > this_max_context) {
        if (count_exm_add > 0) { count_exm_add--; checkPromptSize(); }      // Remove examples first
        else if (mesSend.length > 0) { mesSend.shift(); checkPromptSize(); } // Then oldest messages
    }
}
```

---

## 14. Text Completion Final Assembly

**File:** `public/script.js:4904-5010`

For non-OpenAI APIs (`main_api !== 'openai'`), the final prompt is a single string:

```js
// getCombinedPrompt() — line 4954-4976
function combine() {
    mesSendString = finalMesSend.map(e => `${e.extensionPrompts.join('')}${e.message}`).join('');
    mesSendString = addChatsSeparator(mesSendString);   // Prepend chat_start (default: "***\n")
    mesSendString = addChatsPreamble(mesSendString);    // Prepend NAI preamble (NovelAI only)

    let combinedPrompt = [
        combinedStoryString,    // Story string (system + character + WI + persona)
        mesExmString,           // Example messages
        mesSendString,          // Chat messages with injections
        generatedPromptCache,   // Continue prompt (for continuation)
    ].join('').replace(/\r/gm, '');

    if (power_user.collapse_newlines) combinedPrompt = collapseNewlines(combinedPrompt);
    return combinedPrompt;
}
```

### Last Prompt Line Modification

`modifyLastPromptLine()` (line 4799-4863) appends to the end of the last message:

1. **Quiet prompt** at depth 0 (if provided)
2. **Instruct mode output sequence** (`formatInstructModePrompt()`) with character name
3. **Impersonation prefix** (`name1:`) for impersonate mode
4. **Character name prefix** (`name2:`) if `force_name2` is true
5. **Prompt bias** text

### Extension Events

Two events allow extensions to modify the final prompt:

```js
await eventSource.emit(event_types.GENERATE_BEFORE_COMBINE_PROMPTS, data);
// data.combinedPrompt can be set to override the combine() function

await eventSource.emit(event_types.GENERATE_AFTER_COMBINE_PROMPTS, eventData);
// eventData.prompt can be modified in-place
```

---

## 15. Chat Completion Assembly (OpenAI Path)

**File:** `public/scripts/openai.js:1433-1515`

For `main_api === 'openai'`, prompt assembly uses an entirely different system based on a `PromptManager` and `ChatCompletion` class.

### 15.1 Entry Point

Called from `Generate()` at line 5057:

```js
let [prompt, counts] = await prepareOpenAIMessages({
    name2, charDescription: description, charPersonality: personality,
    scenario, worldInfoBefore, worldInfoAfter, extensionPrompts: extension_prompts,
    bias: promptBias, type, quietPrompt: quiet_prompt, quietImage,
    cyclePrompt, systemPromptOverride: system, jailbreakPromptOverride: jailbreak,
    messages: oaiMessages, messageExamples: oaiMessageExamples,
}, dryRun);
```

### 15.2 PromptManager Prompt Order

The PromptManager (`public/scripts/PromptManager.js`) maintains an ordered list of prompt slots. Default order:

| # | Identifier | Type | Content |
|---|-----------|------|---------|
| 1 | `main` | System prompt | `"Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}."` |
| 2 | `worldInfoBefore` | Marker | World info (before char def) |
| 3 | `personaDescription` | Marker | User persona |
| 4 | `charDescription` | Marker | Character description |
| 5 | `charPersonality` | Marker | Character personality |
| 6 | `scenario` | Marker | Scenario |
| 7 | `enhanceDefinitions` | System prompt | `"If you have more knowledge of {{char}}, add to the character's lore..."` (disabled by default) |
| 8 | `nsfw` | System prompt | Auxiliary prompt (empty default) |
| 9 | `worldInfoAfter` | Marker | World info (after char def) |
| 10 | `dialogueExamples` | Marker | Example messages |
| 11 | `chatHistory` | Marker | Chat messages |
| 12 | `jailbreak` | System prompt | Post-history instructions (empty default) |

Users can reorder these via the Prompt Manager UI. Custom prompts can be added between any slots.

### 15.3 Assembly Flow — `populateChatCompletion()`

**File:** `openai.js:1076-1238`

1. **Add character info markers** — world info, description, personality, scenario, persona at their positions
2. **Add control prompts** — impersonate/quiet prompt (reserved budget, positioned last)
3. **Add system prompts** — `main`, `nsfw`, `jailbreak`, `enhanceDefinitions` in user-defined order
4. **Add extension prompts** — memory/summary (`1_memory`), author's note (`2_floating_prompt`), vectors (`3_vectors`), data bank (`4_vectors_data_bank`), ChromaDB, and any custom extension prompts with position info
5. **Add tool data** — pre-allocate tokens for function calling
6. **Add continue prefill** — assistant message start for continuation
7. **Add in-chat injection prompts** — absolute-positioned extension prompts at specific depths
8. **Add dialogue examples and chat history** — order depends on `power_user.pin_examples`
9. **Free control prompt budget** and add control messages

### 15.4 Chat History Population — `populateChatHistory()`

**File:** `openai.js:834-983`

1. Reserve budget for `newChat`/`newMainChat` system marker
2. Optionally reserve `groupNudge` prompt
3. Handle `continueNudge` for continuation
4. Add `send_if_empty` replacement if user message empty
5. Iterate messages in **reverse** (newest first), adding until budget exhausted:
   - Handle multimodal content (inline images/video/audio)
   - Handle tool invocations and results
   - Handle reasoning signatures
   - Apply name prefixing based on `names_behavior`
6. Insert control messages (new chat marker, group nudge, continue nudge)

### 15.5 `ChatCompletion` Class

**File:** `openai.js:3573+`

Manages a hierarchy of `MessageCollection` objects with token budget tracking. Key methods:
- `setTokenBudget(maxContext, maxTokens)` — Set total budget = maxContext - maxTokens
- `reserveBudget(identifier)` / `freeBudget(identifier)` — Pre-allocate/release tokens
- `add(message, position)` — Add message if budget allows
- `getChat()` — Flatten hierarchy to final message array
- `squashSystemMessages()` — Optionally combine consecutive system messages

### 15.6 Final Output Format

```js
const chat = chatCompletion.getChat();
// Returns: [{ role, content, name?, tool_calls?, tool_call_id?, signature? }, ...]
```

---

## 16. Instruct Mode Formatting

**File:** `public/scripts/instruct-mode.js`

Instruct mode wraps messages in model-specific instruction sequences. Only used for text completion APIs (`main_api !== 'openai'`).

### 16.1 Configuration

```js
// power-user.js:224-251
instruct: {
    enabled: false,
    input_sequence: '### Instruction:',      // User message prefix
    input_suffix: '',                        // User message suffix
    output_sequence: '### Response:',        // AI message prefix
    output_suffix: '',                       // AI message suffix
    system_sequence: '',                     // System message prefix
    system_suffix: '',                       // System message suffix
    first_input_sequence: '',               // First user message (override)
    first_output_sequence: '',              // First AI message (override)
    last_input_sequence: '',                // Last user message (override)
    last_output_sequence: '',               // Last AI message (override)
    story_string_prefix: '',                // Story string wrapper prefix
    story_string_suffix: '',                // Story string wrapper suffix
    stop_sequence: '',                      // Stop string
    wrap: true,                             // Add newline separators
    macro: true,                            // Substitute macros in sequences
    names_behavior: 'force',                // NONE, ALWAYS, FORCE
    user_alignment_message: '',             // Force user turn at end
}
```

### 16.2 Preset Examples

**ChatML:**
```
input_sequence:  <|im_start|>user
output_sequence: <|im_start|>assistant
system_sequence: <|im_start|>system
stop_sequence:   <|im_end|>
*_suffix:        <|im_end|>\n
story_string_prefix: <|im_start|>system
story_string_suffix: <|im_end|>\n
```

**Llama 3:**
```
input_sequence:  <|start_header_id|>user<|end_header_id|>\n\n
output_sequence: <|start_header_id|>assistant<|end_header_id|>\n\n
system_sequence: <|start_header_id|>system<|end_header_id|>\n\n
stop_sequence:   <|eot_id|>
```

### 16.3 Key Functions

| Function | File:Line | Purpose |
|----------|-----------|---------|
| `formatInstructModeStoryString()` | instruct-mode.js:478 | Wraps story string with prefix/suffix |
| `formatInstructModeExamples()` | instruct-mode.js:511 | Wraps example dialogues with sequences |
| `formatInstructModeChat()` | instruct-mode.js:387 | Wraps individual chat messages |
| `formatInstructModePrompt()` | instruct-mode.js:593 | Formats the final generation prompt line |

Each function selects the appropriate prefix/suffix based on role (user/assistant/system) and position (first/last/normal), applies macro substitution on the sequences, and handles name inclusion based on `names_behavior`.

---

## 17. Backend Prompt Conversion

**File:** `src/prompt-converters.js`, `src/endpoints/backends/chat-completions.js`

The frontend sends a normalized ChatML message array (`[{role, content, name?, ...}]`) to the backend. The backend transforms this for each API.

### 17.1 Post-Processing Types

```js
// src/prompt-converters.js:15-26
export const PROMPT_PROCESSING_TYPE = {
    NONE: '',              // Pass through unchanged
    MERGE: 'merge',        // Merge consecutive same-role messages
    MERGE_TOOLS: 'merge_tools',  // Merge with tool message support
    SEMI: 'semi',          // Strict without placeholders
    SEMI_TOOLS: 'semi_tools',
    STRICT: 'strict',      // Strict with placeholder user messages
    STRICT_TOOLS: 'strict_tools',
    SINGLE: 'single',      // All messages collapsed to user role
};
```

`postProcessPrompt()` (line 83) routes to `mergeMessages()` which:
1. Flattens multimodal content arrays to strings (preserving media tokens)
2. Prepends speaker names to content
3. Merges consecutive messages with same role
4. In strict mode, forces mid-prompt system messages to user role and adds placeholder messages
5. In single mode, collapses all messages into user role

### 17.2 API-Specific Converters

#### Claude (`convertClaudeMessages()`, line 196-375)

- Extracts leading system messages → `systemPrompt: [{ type: 'text', text }]`
- Remaining system messages → user role
- Content normalized to `[{ type: 'text', text }]` arrays
- Images extracted from base64 URLs → `{ type: 'image', source: { type: 'base64', ... } }`
- Images in assistant messages moved to next user message
- Consecutive same-role messages merged
- Tool calls → `{ type: 'tool_use', id, name, input }`
- Tool results → `{ type: 'tool_result', tool_use_id, content }`
- Optional prefill added as trailing assistant message

#### Google/Gemini (`convertGooglePrompt()`, line 431-618)

- System messages → `system_instruction: { parts: [{ text }] }`
- User messages → `role: 'user'` with parts array
- Assistant → `role: 'model'`
- Images → `inlineData: { mimeType, data: base64 }`
- Tool calls → `functionCall: { name, args }`
- Tool results → `functionResponse: { name, response }`
- Consecutive same-role merging

#### Text Completion (`convertTextCompletionPrompt()`, line 957-975)

Collapses entire message array to a single string:
```
System: [system message]
[name/role]: [content]
...
assistant:
```

#### Other converters

- **AI21** (`convertAI21Messages()`, line 626): Extracts system, merges consecutive
- **Cohere** (`convertCohereMessages()`, line 383): Converts system/tool to user
- **Mistral** (`convertMistralMessages()`, line 698): Sanitizes tool IDs, handles prefill
- **xAI** (`convertXAIMessages()`, line 780): Name prefixing

### 17.3 Routing

The `/generate` endpoint (`chat-completions.js:2010`) routes based on `chat_completion_source`:

```js
switch (request.body.chat_completion_source) {
    case 'claude':     return sendClaudeRequest(request, response);
    case 'makersuite': return sendMakerSuiteRequest(request, response);
    case 'ai21':       return sendAI21Request(request, response);
    // ... 20+ other sources
    default:           // Standard OpenAI-compatible endpoint
}
```

---

## 18. Model-Specific Formatting

### 18.1 Chat Completion vs Text Completion

The system detects text completion models (`TEXT_COMPLETION_MODELS` list in `chat-completions.js`). For these, the message array is converted to a single prompt string via `convertTextCompletionPrompt()` and sent to `/completions` instead of `/chat/completions`.

### 18.2 Claude-Specific Features

- **System prompt**: Separate `system` field (not a message) — populated from leading system messages
- **Caching**: `cache_control: { type: 'ephemeral' }` added to system prompt and at configurable message depths
- **Extended thinking**: Budget tokens calculation, prefill adjustment
- **Beta headers**: Dynamic inclusion for prompt-caching, tools, computer-use

### 18.3 Gemini-Specific Features

- **System instruction**: Separate `systemInstruction` field
- **Safety settings**: Configurable harm category thresholds
- **Thinking config**: Budget tokens per model tier
- **Image generation**: Special handling for image-capable models
- **Web search**: `google_search` tool injection

### 18.4 OpenRouter

- **Media embedding**: Special format for video/audio via `embedOpenRouterMedia()`
- **Caching**: `cachingSystemPromptForOpenRouter()` adds cache_control to first system message
- **Reasoning signatures**: `addOpenRouterSignatures()` for reasoning models
- **Fallback models**: Support for model arrays

---

## 19. Post-Processing and Stop Sequences

### 19.1 Stop Sequences

**File:** `public/script.js:2861-2910`

```js
export function getStoppingStrings(isImpersonate, isContinue) {
    const result = [];
    if (power_user.context.names_as_stop_strings) {
        result.push(`\n${name2}:`);  // Character name
        result.push(`\n${name1}:`);  // User name
        // Group member names
    }
    result.push(...getCustomStoppingStrings());  // User-defined custom stops
    if (power_user.instruct.enabled) {
        // Instruct mode stop sequences (input/output sequences)
    }
    return result.filter(onlyUnique);
}
```

### 19.2 Message Bias / Logit Bias

**File:** `public/script.js:4206`

```js
let { messageBias, promptBias, isUserPromptBias } = getBiasStrings(textareaText, type);
```

Bias strings extracted from user input via `{{bias text}}` syntax. For text completion, bias is appended to the last prompt line. For chat completion, it's passed separately.

### 19.3 CFG Guidance Scale

When `cfgGuidanceScale !== 1`, both a positive and negative prompt variant are constructed. The negative prompt is built by `getCfgPrompt()` and injected at configurable depth.

### 19.4 Newline Collapsing

If `power_user.collapse_newlines` is true, consecutive newlines (3+) are collapsed to 2.

---

## 20. Summary Prompt Layout Diagram

### Text Completion API (e.g., KoboldAI, text-generation-webui)

```
┌─────────────────────────────────────────────────────────┐
│ STORY STRING (rendered Handlebars template)              │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ [Instruct: story_string_prefix]                     │ │
│ │ System Prompt (main instruction)                    │ │
│ │ World Info (before)                                 │ │
│ │ Character Description                               │ │
│ │ Character Personality                               │ │
│ │ Scenario                                            │ │
│ │ World Info (after)                                  │ │
│ │ User Persona (if position=IN_PROMPT)                │ │
│ │ Extension anchors (BEFORE_PROMPT, IN_PROMPT)        │ │
│ │ [Instruct: story_string_suffix]                     │ │
│ └─────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ EXAMPLE MESSAGES (if not stripped)                       │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ [example_separator / <START>]                       │ │
│ │ {{user}}: example user message                      │ │
│ │ {{char}}: example char response                     │ │
│ │ [example_separator / <START>]                       │ │
│ │ ...more example blocks...                           │ │
│ └─────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ CHAT SEPARATOR (chat_start, default: "***")             │
├─────────────────────────────────────────────────────────┤
│ [NAI Preamble — NovelAI only]                           │
├─────────────────────────────────────────────────────────┤
│ CHAT HISTORY (oldest → newest, with injections)         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ [User alignment message — if last != user]          │ │
│ │ Oldest included message                             │ │
│ │ ...                                                 │ │
│ │ ── Depth N ──                                       │ │
│ │   [WI depth entries at N]                           │ │
│ │   [Author's Note at depth N]                        │ │
│ │   [Memory/Summary injection]                        │ │
│ │   [Vector RAG injection]                            │ │
│ │   [Persona at depth — if AT_DEPTH]                  │ │
│ │   [Character depth prompt]                          │ │
│ │ ── Depth N-1 ──                                     │ │
│ │ ...                                                 │ │
│ │ ── Depth 0 ──                                       │ │
│ │ Jailbreak / Post-History Instructions (as user msg) │ │
│ │ Most recent message                                 │ │
│ └─────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ LAST PROMPT LINE                                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ [Quiet prompt — if quiet generation]                │ │
│ │ [Instruct: last_output_sequence]                    │ │
│ │ [Character name: ] or [Instruct prompt format]      │ │
│ │ [Prompt bias]                                       │ │
│ └─────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ [Continue: partial message to continue from]            │
└─────────────────────────────────────────────────────────┘
```

### Chat Completion API (OpenAI, Claude, etc.)

```
┌─────────────────────────────────────────────────────────┐
│ MESSAGES ARRAY (ordered by PromptManager)                │
│                                                         │
│ 1. {role: "system"} Main Prompt                         │
│    "Write {{char}}'s next reply..."                     │
│                                                         │
│ 2. {role: "system"} World Info (before)                 │
│                                                         │
│ 3. {role: "system"} User Persona Description            │
│                                                         │
│ 4. {role: "system"} Character Description               │
│                                                         │
│ 5. {role: "system"} Character Personality               │
│                                                         │
│ 6. {role: "system"} Scenario                            │
│                                                         │
│ 7. {role: "system"} [Enhance Definitions — if enabled]  │
│                                                         │
│ 8. {role: "system"} Auxiliary/NSFW Prompt                │
│                                                         │
│ 9. {role: "system"} World Info (after)                  │
│                                                         │
│ 10. {role: "system"} [Custom user prompts — any order]  │
│                                                         │
│ 11. {role: "system"} [Extension prompts]                │
│     - Memory/Summary (1_memory)                         │
│     - Author's Note (2_floating_prompt)                 │
│     - Vectors (3_vectors)                               │
│     - Data Bank (4_vectors_data_bank)                   │
│     - ChromaDB (chromadb)                               │
│     - Other extension prompts                           │
│                                                         │
│ ─── Dialogue Examples (if pinned, before history) ───── │
│                                                         │
│ 12. {role: "system"} [Start new example chat]           │
│     {role: "system", name: "example_user"} ...          │
│     {role: "system", name: "example_assistant"} ...     │
│                                                         │
│ ─── Chat History ────────────────────────────────────── │
│                                                         │
│ 13. {role: "system"} [Start a new Chat]                 │
│                                                         │
│ 14. {role: "user/assistant"} Chat messages...           │
│     [With depth injections interspersed:]               │
│     - WI depth entries                                  │
│     - Author's Note at depth                            │
│     - Persona at depth                                  │
│     - Character depth prompt                            │
│                                                         │
│ ─── Dialogue Examples (if unpinned, after history) ──── │
│                                                         │
│ 15. {role: "system"} Post-History Instructions          │
│     (Jailbreak)                                         │
│                                                         │
│ ─── Control Messages ────────────────────────────────── │
│                                                         │
│ 16. {role: "system"} [Group nudge — group chats]        │
│ 17. {role: "system"} [Continue nudge — continuation]    │
│ 18. {role: "system"} [Quiet prompt — quiet generation]  │
│ 19. {role: "system"} [Impersonate prompt]               │
│ 20. {role: "system"} [Bias prompt]                      │
│                                                         │
│ ─── Backend Transformation ──────────────────────────── │
│                                                         │
│ For Claude:  system[] extracted, messages[] alternated   │
│ For Gemini:  system_instruction{}, contents[] with parts│
│ For OpenAI:  messages[] sent as-is                      │
│ For TextGen: collapsed to single prompt string          │
└─────────────────────────────────────────────────────────┘
```

### Key Decision Points

```
                    ┌──────────────┐
                    │  Generate()  │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ main_api?    │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼                         ▼
       ┌──────────┐             ┌──────────────┐
       │ 'openai' │             │ Other APIs   │
       └────┬─────┘             └──────┬───────┘
            │                          │
            ▼                          ▼
   ┌────────────────┐        ┌──────────────────┐
   │PromptManager + │        │ instruct.enabled?│
   │ChatCompletion  │        └────────┬─────────┘
   │ (message array)│           ┌─────┼─────┐
   └────────┬───────┘           ▼           ▼
            │              ┌────────┐ ┌──────────┐
            │              │Instruct│ │Plain text│
            ▼              │  mode  │ │ name:msg │
   ┌────────────────┐      └───┬────┘ └────┬─────┘
   │Backend convert │          └─────┬──────┘
   │per API source  │                ▼
   └────────────────┘     ┌──────────────────┐
                          │Single string     │
                          │prompt            │
                          └──────────────────┘
```
