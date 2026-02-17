# SillyTavern Prompt Construction Pipeline

Exhaustive documentation of how the final LLM prompt is assembled from raw inputs to the API call.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Entry Point: `Generate()`](#2-entry-point-generate)
3. [Two Prompt Paths: Text Completion vs Chat Completion](#3-two-prompt-paths-text-completion-vs-chat-completion)
4. [Character Definition](#4-character-definition)
5. [User Persona](#5-user-persona)
6. [System Prompt / Instruction Block](#6-system-prompt--instruction-block)
7. [World Info / Lorebook](#7-world-info--lorebook)
8. [Author's Note](#8-authors-note)
9. [Extension Prompt Injection System](#9-extension-prompt-injection-system)
10. [Example Messages / Few-Shot](#10-example-messages--few-shot)
11. [Chat History](#11-chat-history)
12. [Text Completion Prompt Assembly](#12-text-completion-prompt-assembly)
13. [Chat Completion (OpenAI) Prompt Assembly](#13-chat-completion-openai-prompt-assembly)
14. [Context Budget / Token Management](#14-context-budget--token-management)
15. [Macro / Variable Substitution](#15-macro--variable-substitution)
16. [Instruct Mode Formatting](#16-instruct-mode-formatting)
17. [Regex Post-Processing](#17-regex-post-processing)
18. [Server-Side Prompt Conversion](#18-server-side-prompt-conversion)
19. [Model-Specific Formatting](#19-model-specific-formatting)
20. [Prompt Manager (Chat Completion)](#20-prompt-manager-chat-completion)
21. [Final Prompt Layout Diagrams](#21-final-prompt-layout-diagrams)

---

## 1. High-Level Architecture

SillyTavern supports two fundamentally different prompt construction paths depending on the backend API:

| Path | Backends | Output Format |
|------|----------|---------------|
| **Text Completion** | KoboldAI, KoboldCpp, text-generation-webui, NovelAI, Horde | Single concatenated string |
| **Chat Completion** | OpenAI, Claude, Google Gemini, Mistral, Cohere, xAI, AI21, OpenRouter, etc. | Array of `{role, content}` message objects |

Both paths originate from the same `Generate()` function and share the same input data (character cards, world info, chat history, extensions), but they assemble and format the final prompt differently.

### Key Files

| File | Purpose |
|------|---------|
| `public/script.js` | Main `Generate()` entry point, text completion assembly |
| `public/scripts/openai.js` | Chat completion assembly (`prepareOpenAIMessages`), `ChatCompletion` class |
| `public/scripts/PromptManager.js` | `Prompt`, `PromptCollection`, `PromptManager` classes for chat completion ordering |
| `public/scripts/world-info.js` | World info scanning, activation, injection |
| `public/scripts/authors-note.js` | Author's note injection |
| `public/scripts/macros.js` + `public/scripts/macros/` | Macro substitution engine |
| `public/scripts/instruct-mode.js` | Instruct mode formatting (text completion) |
| `public/scripts/sysprompt.js` | System prompt management |
| `public/scripts/personas.js` | User persona management |
| `public/scripts/char-data.js` | Character card type definitions |
| `public/scripts/chat-templates.js` | Chat template detection and binding |
| `public/scripts/cfg-scale.js` | CFG / negative prompt handling |
| `public/scripts/tokenizers.js` | Client-side token counting |
| `src/prompt-converters.js` | Server-side prompt format conversion (Claude Messages API, Google, Mistral, etc.) |
| `src/endpoints/backends/chat-completions.js` | Server-side chat completion routing and API dispatch |
| `src/endpoints/backends/text-completions.js` | Server-side text completion routing |

---

## 2. Entry Point: `Generate()`

**File:** `public/script.js`
**Function:** `Generate(type, options, dryRun)` — starts around line 4065

This is the single entry point for all generation requests. The `type` parameter determines the generation mode:

| Type | Meaning |
|------|---------|
| `'normal'` | Standard user message → AI reply |
| `'swipe'` | Regenerate last AI reply (new variant) |
| `'continue'` | Continue the last AI message |
| `'impersonate'` | AI writes as the user |
| `'quiet'` | Hidden generation (used by extensions like Summarize) |
| `'regenerate'` | Regenerate the last message |

### High-Level Flow

```
Generate(type, options, dryRun)
  1. Validate state (connected, character selected, etc.)
  2. Process user input — apply regex, append file content, add reasoning
  3. Run extension interceptors (can abort generation)
  4. Extract World Info from chat context
  5. Collect extension prompts (Author's Note, Summarize, Vectors, etc.)
  6. Resolve character fields (description, personality, scenario, examples)
  7. Build prompt for selected API:
     - Text Completion: assemble story string + examples + chat → single string
     - Chat Completion: call prepareOpenAIMessages() → messages array
  8. Emit GENERATE_AFTER_DATA event
  9. If dryRun, return early
  10. Call API (streaming or non-streaming)
  11. Process response, handle tool calls, save to chat
```

---

## 3. Two Prompt Paths: Text Completion vs Chat Completion

The `main_api` variable determines which path is taken. It is set globally based on the user's API selection.

```javascript
// script.js ~line 5022
switch (main_api) {
    case 'kobold':
    case 'koboldhorde':
        generate_data = getKoboldGenerationData(finalPrompt, ...);
        break;
    case 'textgenerationwebui':
        generate_data = await getTextGenGenerationData(finalPrompt, ...);
        break;
    case 'novel':
        generate_data = getNovelGenerationData(finalPrompt, ...);
        break;
    case 'openai':
        let [prompt, counts] = await prepareOpenAIMessages({...}, dryRun);
        generate_data = { prompt: prompt };
        break;
}
```

- For `kobold`, `koboldhorde`, `textgenerationwebui`, `novel`: the text completion path produces a `finalPrompt` string.
- For `openai`: the chat completion path calls `prepareOpenAIMessages()` which returns a messages array.

---

## 4. Character Definition

### Card Formats

**Type definitions:** `public/scripts/char-data.js`

Character cards use the V2 spec (with backwards-compatible V1 wrapper). Fields:

| Field | Type | Prompt Role |
|-------|------|-------------|
| `name` | string | Character name (used as `{{char}}`) |
| `description` | string | Injected as "Character Description" |
| `personality` | string | Injected as "Character Personality" |
| `scenario` | string | Injected as "Scenario" |
| `first_mes` | string | First message in new chats |
| `mes_example` | string | Example dialogue (split on `<START>`) |
| `system_prompt` | string | Per-character system prompt override |
| `post_history_instructions` | string | Per-character jailbreak/post-history override |
| `creator_notes` | string | Available via `{{creatorNotes}}` macro |
| `character_book` | object | Embedded World Info / lorebook |
| `extensions.depth_prompt` | `{prompt, depth, role}` | Injected at specified depth in chat |
| `alternate_greetings` | string[] | Alternative first messages |

### Card Parsing

**PNG cards:** `src/character-card-parser.js`
Character data is embedded in PNG `tEXt` chunks as base64 JSON. The `ccv3` chunk (V3 spec) takes precedence over the `chara` chunk (V2).

**CharX archives:** `src/charx.js`
ZIP-based format containing `card.json` plus auxiliary assets (sprites, backgrounds).

### Field Resolution

**File:** `public/script.js`, `getCharacterFields()` ~line 3253

Fields are lazily resolved with `createLazyFields()`:

```javascript
getCharacterFields() → {
    description: baseChatReplace(character.description),
    personality: baseChatReplace(character.personality),
    scenario: chat_metadata['scenario'] || character.scenario,
    mesExamples: chat_metadata['mes_example'] || character.mes_example,
    depth_prompt: character.data?.extensions?.depth_prompt?.prompt,
}
```

The `baseChatReplace()` function applies macro substitution to character fields. The `scenario` and `mes_example` fields can be overridden per-chat via `chat_metadata`.

### Group Chats

**File:** `public/scripts/group-chats.js`

In group chats, multiple character cards are combined:

- `getGroupCharacterCards()` (line 478) — joins member descriptions into a single block
- `getGroupCharacterCardsLazy()` (line 498) — lazy version with configurable join prefix/suffix
- `collectField()` (line 548) — collects and joins a single field from all members
- `getGroupDepthPrompts()` (line 428) — extracts depth prompts from all group members

Group generation modes (`group_generation_mode`):
- `SWAP` (0): Generate one character at a time, swap context per character
- `APPEND` (1): Combine all enabled member cards
- `APPEND_DISABLED` (2): Combine all member cards including disabled

---

## 5. User Persona

**File:** `public/scripts/personas.js`

### Storage

Persona descriptions are stored in `power_user.persona_descriptions[avatarId]`:

```javascript
{
    description: string,       // The persona text
    position: number,          // Where to inject (see enum below)
    depth: number,             // Depth for AT_DEPTH mode (default 2)
    role: number,              // Role (system/user/assistant)
    lorebook: string,          // Associated world name
    title: string,             // Display title
    connections: [{type, id}], // Locks to characters/groups
}
```

### Injection Positions

**Enum:** `persona_description_positions` (in `public/scripts/power-user.js` ~line 110)

| Value | Name | Behavior |
|-------|------|----------|
| 0 | `IN_PROMPT` | Injected in the story string template via `{{persona}}` |
| 2 | `TOP_AN` | Prepended to Author's Note |
| 3 | `BOTTOM_AN` | Appended to Author's Note |
| 4 | `AT_DEPTH` | Injected as depth prompt at `persona_description_depth` |
| 9 | `NONE` | Not injected |

### Persona Locking

Personas can be locked to:
- A specific **chat** — stored in `chat_metadata['persona']`
- A specific **character or group** — stored in persona's `connections` array
- **Default** for new chats — stored in persona's `default` flag

Selection priority in `loadPersonaForCurrentChat()` (line 1440): chat lock → character connection → default → no change.

---

## 6. System Prompt / Instruction Block

**File:** `public/scripts/sysprompt.js`

### Storage

- `system_prompts[]` — array of named presets with `{name, content, post_history}`
- Active prompt: `power_user.sysprompt.{enabled, name, content, post_history}`

### Resolution for Text Completion

**File:** `public/script.js` ~line 4456

```javascript
if (main_api !== 'openai') {
    if (power_user.sysprompt.enabled) {
        system = power_user.prefer_character_prompt && characterSystemPrompt
            ? substituteParams(characterSystemPrompt, { original: power_user.sysprompt.content })
            : baseChatReplace(power_user.sysprompt.content);
    } else {
        system = '';
    }
}
```

If `prefer_character_prompt` is enabled and the character card has a `system_prompt`, the character's version is used (with the global prompt available as `{{original}}`).

### Resolution for Chat Completion

Handled by the Prompt Manager (see [Section 20](#20-prompt-manager-chat-completion)). The system prompt becomes the `main` prompt entry. Character overrides are applied via `preparePromptsForChatCompletion()`.

---

## 7. World Info / Lorebook

**File:** `public/scripts/world-info.js` (~5000+ lines)

### Entry Sources

World Info entries come from four sources, loaded in parallel by `getSortedEntries()` (line 4347):

```javascript
const [globalLore, characterLore, chatLore, personaLore] = await Promise.all([
    getGlobalLore(),       // User's selected global lorebooks
    getCharacterLore(),    // Character's embedded character_book + attached lorebooks
    getChatLore(),         // Chat-specific lorebook
    getPersonaLore(),      // Persona's attached lorebook
]);
```

### Sorting Strategy

Controlled by `world_info_character_strategy`:

| Strategy | Behavior |
|----------|----------|
| `evenly` | Merge global + character lore, sort by `order` field |
| `character_first` | Character lore sorted first, then global lore sorted |
| `global_first` | Global lore sorted first, then character lore sorted |

Chat lore always goes first, then persona lore, then the strategy result (line 4382).

### Entry Data Structure

Each entry has:
- `key[]` — primary trigger keywords
- `keysecondary[]` — secondary keywords
- `selectiveLogic` — how primary + secondary combine (AND_ANY, AND_ALL, NOT_ANY, NOT_ALL, NONE)
- `content` — the text to inject
- `position` — where to inject (see below)
- `depth` / `role` — for depth-based injection
- `order` — sorting priority (higher = earlier)
- `priority` — token budget priority
- `constant` — always active regardless of keyword matching
- `disable` — entry is disabled
- `scanDepth` — override how many messages to scan
- `caseSensitive` — keyword matching case sensitivity
- `matchWholeWords` — word boundary matching
- `useGroupScoring` — group competition mode
- `automationId` — timed effects identifier
- `outletName` — for outlet-type entries (accessed via `{{outlet::name}}`)

### Keyword Matching

**Class:** `WorldInfoBuffer` (line ~280)

The scanning algorithm:
1. Collect chat messages (reversed, up to `world_info_depth` messages)
2. Optionally include character defs, author's note, other extension prompts (`scan` flag)
3. For each entry, check if primary keys match in the scanned text
4. Apply secondary key logic per `selectiveLogic`
5. Entries with `constant: true` always activate
6. Support for regex keys (entries with `/pattern/flags` syntax)
7. **Recursive scanning** — when entries activate, their content is added to the scan buffer and scanning repeats (up to `world_info_recursive_scan` iterations)

### Decorators

Entries can have decorator prefixes (line 4410):
- Lines starting with `@@` are parsed as decorators
- `@@@` prefix = fallback decorator (only used if primary not recognized)
- Known decorators defined in `KNOWN_DECORATORS` array

### Injection Positions

**Enum:** `world_info_position`

| Position | Behavior |
|----------|----------|
| `before` | Concatenated into `worldInfoBefore` — placed before character defs in story string |
| `after` | Concatenated into `worldInfoAfter` — placed after character defs in story string |
| `EMTop` | Injected at the top of example messages |
| `EMBottom` | Injected at the bottom of example messages |
| `ANTop` | Prepended to Author's Note |
| `ANBottom` | Appended to Author's Note |
| `atDepth` | Injected at specified depth in chat history with specified role |
| `outlet` | Available to `{{outlet::name}}` macro, not directly injected |

### Token Budget

World Info has its own token budget, calculated as:
```
budget = min(maxContext * (world_info_budget / 100), world_info_budget_cap)
```

Entries are sorted by `order` and added until the budget is exhausted. Higher-priority entries (lower `priority` number) are preserved when budget is tight.

### Return Value

`checkWorldInfo()` returns (line 5034):
```javascript
{
    worldInfoBefore,    // Joined string for "before" entries
    worldInfoAfter,     // Joined string for "after" entries
    EMEntries,          // Array of {position, content} for example message injection
    WIDepthEntries,     // Array of {depth, entries[], role} for depth injection
    ANBeforeEntries,    // Array of strings for AN top
    ANAfterEntries,     // Array of strings for AN bottom
    outletEntries,      // Map of outlet name → content arrays
    allActivatedEntries // Set of all activated entries
}
```

---

## 8. Author's Note

**File:** `public/scripts/authors-note.js`

The Author's Note (AN) is an editorial injection that uses the extension prompt system.

### Storage

Stored in `chat_metadata` per-chat:
- `chat_metadata['note_prompt']` — the AN text
- `chat_metadata['note_prompt_token_counter']` — position: `extension_prompt_types` value
- `chat_metadata['note_depth']` — injection depth (default 4)
- `chat_metadata['note_role']` — injection role (system/user/assistant)
- `chat_metadata['note_interval']` — how often to inject (every N messages; 0 = disabled)

### Character-Specific AN

Characters can override the AN via `character.data.extensions.depth_prompt`:
```javascript
{
    prompt: string,  // The text
    depth: number,   // Injection depth
    role: string,    // Role name
}
```

### Injection

The AN is registered as extension prompt `'2_floating_prompt'` via:
```javascript
// authors-note.js ~line 383
context.setExtensionPrompt(
    MODULE_NAME,           // '2_floating_prompt'
    String(prompt),
    chat_metadata[metadata_keys.position],
    chat_metadata[metadata_keys.depth],
    extension_settings.note.allowWIScan,
    chat_metadata[metadata_keys.role]
);
```

World Info entries positioned at `ANTop` / `ANBottom` are merged into the AN text (line 5021-5025 of world-info.js).

---

## 9. Extension Prompt Injection System

**File:** `public/script.js` — functions around line 3060-3160

### Core Data Structure

```javascript
// script.js line 595
export let extension_prompts = {};
```

Each key maps to:
```javascript
{
    value: string,          // The prompt text
    position: number,       // extension_prompt_types enum value
    depth: number,          // For IN_CHAT: how many messages from bottom
    scan: boolean,          // Include in World Info scanning
    role: number,           // extension_prompt_roles enum value
    filter: function|null,  // Optional async filter function
}
```

### Registration

Extensions call `setExtensionPrompt()` to register their prompts:

```javascript
// script.js ~line 3060
export function setExtensionPrompt(key, value, position, depth, scan, role, filter) {
    extension_prompts[key] = { value, position, depth, scan, role, filter };
}
```

### Position Types

**Enum:** `extension_prompt_types`

| Value | Name | Behavior |
|-------|------|----------|
| 0 | `BEFORE_PROMPT` | Before the story string (text completion) or at start of prompt (chat completion) |
| 1 | `IN_PROMPT` | After the story string / end of system section |
| 2 | `IN_CHAT` | Injected at `depth` messages from the bottom of chat |
| 3 | `AFTER_PROMPT` | After everything else |
| 99 | `NONE` | Registered but not injected |

### Role Types

**Enum:** `extension_prompt_roles`

| Value | Name |
|-------|------|
| 0 | `SYSTEM` |
| 1 | `USER` |
| 2 | `ASSISTANT` |

### Retrieval

`getExtensionPrompt()` (line 3132) collects all registered prompts matching a position/depth/role, applies filters, joins with separator, runs `substituteParams()`, and returns the combined string.

### Known Extension Prompt Keys

| Key | Source | Typical Position |
|-----|--------|-----------------|
| `'1_memory'` | Summarize extension | Configurable (default IN_PROMPT) |
| `'2_floating_prompt'` | Author's Note | Configurable (default IN_CHAT depth 4) |
| `'3_vectors'` | Vectors (chat) | Configurable (default IN_PROMPT) |
| `'4_vectors_data_bank'` | Vectors (Data Bank) | Configurable (default IN_PROMPT depth 4) |
| `'chromadb'` | ChromaDB extension | IN_CHAT |
| `'PERSONA_DESCRIPTION'` | Persona (AT_DEPTH mode) | IN_CHAT at configured depth |
| `'STORY_STRING'` | Story string (when IN_CHAT mode) | IN_CHAT at configured depth |
| `'CUSTOM_WI_DEPTH_ROLE(d,r)'` | World Info depth entries | IN_CHAT at entry's depth/role |

### Injection into Text Completion

**File:** `public/script.js`, `doChatInject()` ~line 5400

For text completion, IN_CHAT extension prompts are injected directly into the chat message array:

```javascript
async function doChatInject(messages, isContinue) {
    messages.reverse();
    for (let i = 0; i <= maxDepth; i++) {
        for (const role of [SYSTEM, USER, ASSISTANT]) {
            const prompt = await getExtensionPrompt(IN_CHAT, i, '\n', role);
            if (prompt) {
                // Insert at depth position in the messages array
                messages.splice(depth + totalInserted, 0, {
                    name: roleName,
                    is_user: role === USER,
                    mes: prompt,
                });
            }
        }
    }
    messages.reverse();
}
```

### Injection into Chat Completion

**File:** `public/scripts/openai.js`, `populationInjectionPrompts()` ~line 759

For chat completion, IN_CHAT prompts are inserted as Message objects at the appropriate depth within the ChatCompletion structure.

---

## 10. Example Messages / Few-Shot

### Source

Example messages come from the character card's `mes_example` field (or `chat_metadata['mes_example']` override).

### Parsing

**File:** `public/script.js`, `parseMesExamples()` ~line 3317

```javascript
export function parseMesExamples(examplesStr, isInstruct) {
    const blockHeading = (main_api === 'openai' || isInstruct)
        ? '<START>\n'
        : exampleSeparator;   // power_user.context.example_separator
    return examplesStr.split(/<START>/gi)
        .slice(1)
        .map(block => `${blockHeading}${block.trim()}\n`);
}
```

Each `<START>` delimiter creates a new example block. The separator differs between APIs.

### World Info Example Entries

World Info entries with `EMTop` or `EMBottom` position are injected into the examples array:
- `EMTop` entries are `.unshift()`-ed (added to beginning)
- `EMBottom` entries are `.push()`-ed (added to end)

### For Text Completion

Examples are included in the prompt between the story string and the chat history. The number of examples included is budget-limited:

```javascript
// script.js ~line 4728
for (let example of mesExamplesArray) {
    tokenCount += await getTokenCountAsync(example);
    if (tokenCount < this_max_context) count_exm_add++;
    else break;
}
```

If `power_user.pin_examples` is true, all examples are always included.

### For Chat Completion

**File:** `public/scripts/openai.js`, `populateDialogueExamples()` ~line 992

Examples are converted to message objects and added to a `dialogueExamples` MessageCollection. Each example block is preceded by a `newChat` system message (e.g., "[Start a new chat]"). Addition stops when the budget is exceeded.

---

## 11. Chat History

### Message Processing

Before prompt assembly, chat messages go through several transformations:

**File:** `public/script.js` ~line 4270

1. **Regex processing** — each message is run through `getRegexedString()` with placement type `USER_INPUT` or `AI_OUTPUT` based on `is_user` flag
2. **File content appending** — `appendFileContent()` adds inline file content to messages
3. **Title appending** — media titles are appended to message text
4. **Reasoning injection** — `PromptReasoning` adds reasoning content (`extra.reasoning`) with duration tracking

### For Text Completion

**File:** `public/script.js` ~line 4543

Messages are formatted via `formatMessageHistoryItem()`:

```javascript
// script.js ~line 5600+
function formatMessageHistoryItem(chatItem, isInstruct, forceOutputSequence) {
    const isNarratorType = chatItem?.extra?.type === system_message_types.NARRATOR;
    const characterName = chatItem?.name || name2;
    const shouldPrependName = !isNarratorType;

    if (isInstruct) {
        return formatInstructModeChat(characterName, chatItem.mes,
            chatItem.is_user, isNarratorType, ...);
    }
    return shouldPrependName
        ? `${itemName}: ${chatItem.mes}\n`
        : `${chatItem.mes}\n`;
}
```

The chat history is then assembled into the `mesSend[]` array and fit to the context budget (see [Section 14](#14-context-budget--token-management)).

### For Chat Completion

**File:** `public/scripts/openai.js`, `populateChatHistory()` ~line 834

Messages are added to the ChatCompletion in reverse order (newest first) until the token budget is exhausted:

```javascript
for (let i = chatPrompts.length - 1; i >= 0; i--) {
    const chatMessage = await Message.createAsync(role, content, identifier);
    // Handle media (images, video, audio)
    // Handle tool invocations
    // Handle reasoning signatures
    if (chatCompletion.canAfford(chatMessage)) {
        chatCompletion.insertAtStart(chatMessage, 'chatHistory');
    } else {
        break;  // Budget exceeded, stop adding messages
    }
}
```

---

## 12. Text Completion Prompt Assembly

For non-OpenAI APIs, the prompt is a single concatenated string.

### Story String Template

**File:** `public/scripts/power-user.js` ~line 86

Default template (Handlebars):
```handlebars
{{#if system}}{{system}}
{{/if}}{{#if description}}{{description}}
{{/if}}{{#if personality}}{{char}}'s personality: {{personality}}
{{/if}}{{#if scenario}}Scenario: {{scenario}}
{{/if}}{{#if persona}}{{persona}}
{{/if}}
```

The template is configurable via `power_user.context.story_string` and rendered with Handlebars:

```javascript
// power-user.js ~line 2231
export function renderStoryString(params) {
    const template = power_user.context.story_string;
    const compiled = Handlebars.compile(template, { noEscape: true });
    let output = compiled(params);
    output = substituteParams(output);
    return output;
}
```

### Story String Parameters

**File:** `public/script.js` ~line 4473

```javascript
const storyStringParams = {
    description,                    // Character description
    personality,                    // Character personality
    persona,                        // User persona (if IN_PROMPT position)
    scenario,                       // Scenario text
    system,                         // System prompt (if enabled)
    char: name2,                    // Character name
    user: name1,                    // User name
    wiBefore: worldInfoBefore,      // WI "before" entries
    wiAfter: worldInfoAfter,        // WI "after" entries
    loreBefore: worldInfoBefore,    // Alias
    loreAfter: worldInfoAfter,      // Alias
    anchorBefore: beforeScenarioAnchor,  // BEFORE_PROMPT extension prompts
    anchorAfter: afterScenarioAnchor,    // IN_PROMPT extension prompts
    mesExamples: mesExamplesArray.join(''),
    mesExamplesRaw: mesExamplesRawArray.join(''),
};
```

### Story String Positioning

The story string can be placed at the top of the prompt (default) or injected at a depth within chat:

```javascript
// script.js ~line 4495
if (power_user.context.story_string_position === extension_prompt_types.IN_CHAT) {
    setExtensionPrompt('STORY_STRING', combinedStoryString,
        IN_CHAT, depth, false, role);
    combinedStoryString = '';  // Clear to prevent duplication
}
```

### Instruct Mode Wrapping

If instruct mode is enabled, the story string is wrapped:

```javascript
let combinedStoryString = isInstruct
    ? formatInstructModeStoryString(storyString, ...)
    : storyString;
```

### Depth Injection

**File:** `public/script.js`, `doChatInject()` ~line 5400

Extension prompts with `IN_CHAT` position are injected directly into the chat message array at their configured depth.

### Jailbreak Injection

```javascript
// script.js ~line 4518
if (power_user.sysprompt.enabled && power_user.sysprompt.post_history) {
    const jailbreakText = baseChatReplace(jailbreak);
    setExtensionPrompt('JAILBREAK', jailbreakText, IN_CHAT, 0, false, SYSTEM);
}
```

### Final Concatenation

**File:** `public/script.js`, inner `combine()` function ~line 4954

```javascript
const combine = () => {
    // Flatten mesSend array (each element has message + extensionPrompts)
    mesSendString = finalMesSend
        .map(e => `${e.extensionPrompts.join('')}${e.message}`)
        .join('');

    // Add chat separator and preamble
    mesSendString = addChatsSeparator(mesSendString);  // Prepends chat_start marker
    mesSendString = addChatsPreamble(mesSendString);    // NovelAI: prepends preamble

    // Final assembly
    let combinedPrompt = [
        combinedStoryString,   // Story string (character defs + system prompt + WI)
        mesExmString,          // Example messages
        mesSendString,         // Chat history with injections
        generatedPromptCache,  // Continue text (for 'continue' type)
    ].join('').replace(/\r/gm, '');

    if (power_user.collapse_newlines) {
        combinedPrompt = collapseNewlines(combinedPrompt);
    }
    return combinedPrompt;
};
```

### Post-Combination Events

```javascript
// script.js ~line 5005
await eventSource.emit(event_types.GENERATE_BEFORE_COMBINE_PROMPTS, data);
// Extensions can override data.combinedPrompt

let finalPrompt = await getCombinedPrompt(false);
await eventSource.emit(event_types.GENERATE_AFTER_COMBINE_PROMPTS, eventData);
finalPrompt = eventData.prompt;
```

---

## 13. Chat Completion (OpenAI) Prompt Assembly

For the `openai` main_api, the prompt is an array of message objects.

### Entry Point

**File:** `public/scripts/openai.js`, `prepareOpenAIMessages()` ~line 1433

```javascript
export async function prepareOpenAIMessages({
    name2, charDescription, charPersonality, scenario,
    worldInfoBefore, worldInfoAfter, extensionPrompts,
    bias, type, quietPrompt, quietImage, cyclePrompt,
    systemPromptOverride, jailbreakPromptOverride,
    messages, messageExamples
}, dryRun) {
    // 1. Create ChatCompletion instance with token budget
    const chatCompletion = new ChatCompletion();
    chatCompletion.setTokenBudget(oai_settings.openai_max_context - oai_settings.openai_max_tokens);

    // 2. Prepare system prompts collection
    const prompts = preparePromptsForChatCompletion({...});

    // 3. Populate the ChatCompletion with all content
    await populateChatCompletion(prompts, chatCompletion, {...});

    // 4. Optionally squash consecutive system messages
    if (oai_settings.squash_system_messages) {
        chatCompletion.squashSystemMessages();
    }

    // 5. Extract final messages array
    const chat = chatCompletion.getChat();

    // 6. Emit event for extensions
    await eventSource.emit(event_types.CHAT_COMPLETION_PROMPT_READY, { chat });

    return [chat, tokenHandler.counts];
}
```

### Prompt Preparation

**Function:** `preparePromptsForChatCompletion()` ~line 1258

Creates a `PromptCollection` with all system-level prompts in order. This function:

1. Reads the Prompt Manager's ordered list of prompts
2. Creates `Prompt` objects for each (world info, character fields, extension prompts, etc.)
3. Applies character-specific system prompt overrides (if `prefer_character_prompt` is enabled)
4. Applies character-specific jailbreak overrides
5. Handles extension prompts positioned at BEFORE_PROMPT or IN_PROMPT

### Population

**Function:** `populateChatCompletion()` ~line 1076

The ordered population:

1. **Reserve for response priming** — 3 tokens for `<|start|>assistant<|message|>`
2. **System prompts** — from the PromptCollection, in order:
   - World Info Before
   - Main system prompt
   - World Info After
   - Character Description
   - Character Personality
   - Scenario
   - Persona Description (if IN_PROMPT position)
3. **Control prompts** — impersonation prompt, quiet prompt
4. **User-relative prompts** — NSFW, jailbreak, enhance definitions, bias
5. **Extension prompts into main** — summarize, vectors, AN (when positioned BEFORE_PROMPT or IN_PROMPT)
6. **Tool definitions** — pre-allocated token budget for tool schemas
7. **Continue message handling** — repositions the last message for continuation
8. **In-chat injection prompts** — calls `populationInjectionPrompts()` for depth-based injections
9. **Dialogue examples** — calls `populateDialogueExamples()` with budget checking
10. **Chat history** — calls `populateChatHistory()` filling newest-first until budget exhausted
11. **Control prompts at end** — impersonation, quiet prompts

---

## 14. Context Budget / Token Management

### Token Counting

**Client-side:** `public/scripts/tokenizers.js`
**Server-side:** `src/tokenizers/` directory, `src/endpoints/tokenizers.js`

Supported tokenizers:
- OpenAI tiktoken (cl100k_base, o200k_base, gpt2)
- LLaMA (SentencePiece)
- NerdStash (NovelAI)
- MistralAI (Tekken)
- YiCoder
- Jamba (AI21)
- Claude (via API estimation)

The tokenizer selection is automatic based on the current model/API.

### Text Completion Budget

**File:** `public/script.js`, `checkPromptSize()` ~line 4865

```javascript
async function checkPromptSize() {
    const prompt = [
        combinedStoryString,
        mesExmString,
        addChatsPreamble(addChatsSeparator(jointMessages)),
        '\n',
        modifyLastPromptLine(''),
        generatedPromptCache,
    ].join('');

    let tokenCount = await getTokenCountAsync(prompt, power_user.token_padding);

    if (tokenCount > this_max_context) {
        if (count_exm_add > 0) {
            count_exm_add--;         // Remove examples first
            await checkPromptSize();
        } else if (mesSend.length > 0) {
            mesSend.shift();         // Then remove oldest messages
            await checkPromptSize();
        }
    }
}
```

Priority order for removal:
1. Example messages (removed one at a time)
2. Oldest chat messages (removed from the beginning)

### Chat Completion Budget

**File:** `public/scripts/openai.js`, `ChatCompletion` class ~line 3555

The `ChatCompletion` class tracks a token budget:

```javascript
class ChatCompletion {
    tokenBudget;  // Total available tokens
    // Methods:
    setTokenBudget(budget) { ... }
    canAfford(message) { return this.getAvailableTokens() >= message.getTokens(); }
    canAffordAll(messages) { ... }
    reserveBudget(tokens) { ... }
    freeBudget(message) { ... }
    // When adding content, tokens are automatically deducted from budget
}
```

The `TokenHandler` class (line 3081) tracks token counts by category:
```javascript
counts = {
    'start_chat': 0,
    'prompt': 0,
    'bias': 0,
    'nudge': 0,
    'jailbreak': 0,
    'impersonate': 0,
    'examples': 0,
    'conversation': 0,
}
```

### Context Size

```javascript
// script.js ~line 4329
let this_max_context = getMaxContextSize();
// Adjusted for: Horde auto-adjust, CFG prompt doubling, token_padding
```

`getMaxContextSize()` returns the configured context length minus the response length (`amount_gen`).

---

## 15. Macro / Variable Substitution

**Files:** `public/scripts/macros.js`, `public/scripts/macros/` directory

### Architecture

SillyTavern has two macro engines:
- **Legacy:** `MacrosParser` class — regex-based, always active
- **New:** `MacroEngine` + `MacroRegistry` — parser/CST-based, activated by `power_user.experimental_macro_engine`

### Main Entry Point

**File:** `public/scripts/macros.js`, `evaluateMacros()` ~line 609

Called via `substituteParams()` from `public/script.js`.

Three-phase pipeline:
1. **Pre-env macros:** dice rolls, instruct macros, variables, utilities
2. **Env substitution:** dynamic variables from the `env` object
3. **Post-env macros:** context-dependent macros (time, date, chat inspection)

### Available Macros

#### Names & Participants
| Macro | Returns |
|-------|---------|
| `{{user}}` | User persona name (name1) |
| `{{char}}` | Character name (name2) |
| `{{group}}` / `{{charIfNotGroup}}` | Group member names (comma-separated) or char name |
| `{{groupNotMuted}}` | Group members excluding muted |
| `{{notChar}}` | All participants except current speaker |

#### Character Card Fields
| Macro | Returns |
|-------|---------|
| `{{description}}` / `{{charDescription}}` | Character description |
| `{{personality}}` / `{{charPersonality}}` | Character personality |
| `{{scenario}}` / `{{charScenario}}` | Character scenario |
| `{{persona}}` | User persona description |
| `{{mesExamples}}` | Formatted dialogue examples |
| `{{mesExamplesRaw}}` | Raw dialogue examples |
| `{{charPrompt}}` | Character's system prompt override |
| `{{charInstruction}}` | Character's post-history instructions |
| `{{charDepthPrompt}}` | Character's depth prompt |
| `{{creatorNotes}}` / `{{charCreatorNotes}}` | Creator notes |
| `{{charVersion}}` / `{{version}}` | Character version |

#### Chat History
| Macro | Returns |
|-------|---------|
| `{{lastMessage}}` | Last message text |
| `{{lastMessageId}}` | Index of last message |
| `{{lastUserMessage}}` | Last user message text |
| `{{lastCharMessage}}` | Last character message text |
| `{{firstIncludedMessageId}}` | First message in context window |
| `{{firstDisplayedMessageId}}` | First displayed message |
| `{{lastSwipeId}}` | 1-based last swipe index |
| `{{currentSwipeId}}` | 1-based current swipe index |

#### Time & Date
| Macro | Returns |
|-------|---------|
| `{{time}}` / `{{time::UTC+N}}` | Current time (HH:mm) |
| `{{date}}` | Current date (locale format) |
| `{{weekday}}` | Weekday name |
| `{{isotime}}` | HH:mm format |
| `{{isodate}}` | YYYY-MM-DD format |
| `{{datetimeformat::FORMAT}}` | Custom moment.js format |
| `{{idle_duration}}` / `{{idleDuration}}` | Time since last user message |
| `{{timeDiff::time1::time2}}` | Human-readable time difference |

#### Randomization
| Macro | Returns |
|-------|---------|
| `{{roll::NdM}}` | Dice roll (e.g., `{{roll::2d6}}`) |
| `{{random::a::b::c}}` | Random choice (re-rolled each eval) |
| `{{pick::a::b::c}}` | Deterministic choice (stable per chat/position) |

#### Variables
| Macro | Effect |
|-------|--------|
| `{{getvar::name}}` | Get local (chat) variable |
| `{{setvar::name::value}}` | Set local variable |
| `{{addvar::name::value}}` | Add to local variable |
| `{{incvar::name}}` / `{{decvar::name}}` | Increment/decrement |
| `{{getglobalvar::name}}` | Get global variable |
| `{{setglobalvar::name::value}}` | Set global variable |
| `{{addglobalvar::name::value}}` | Add to global variable |
| `{{incglobalvar::name}}` / `{{decglobalvar::name}}` | Increment/decrement |

#### Instruct Mode Templates
| Macro | Returns |
|-------|---------|
| `{{instructUserPrefix}}` / `{{instructInput}}` | User input prefix sequence |
| `{{instructAssistantPrefix}}` / `{{instructOutput}}` | Assistant output prefix sequence |
| `{{instructSystemPrefix}}` | System prefix sequence |
| `{{instructStop}}` | Stop sequence |
| `{{systemPrompt}}` | Active system prompt (with character override) |
| `{{exampleSeparator}}` / `{{chatSeparator}}` | Example block separator |
| `{{chatStart}}` | Chat start marker |

#### Utility
| Macro | Returns |
|-------|---------|
| `{{maxPrompt}}` | Max context size in tokens |
| `{{model}}` | Current model name |
| `{{summary}}` | Latest chat summary |
| `{{original}}` | Original content (for overrides) |
| `{{newline}}` / `{{newline::N}}` | Newline(s) |
| `{{space::N}}` | Space(s) |
| `{{noop}}` | Empty string |
| `{{trim}}` | Trim surrounding whitespace |
| `{{reverse::text}}` | Reverse string |
| `{{// comment}}` | Comment (empty output) |
| `{{banned::word}}` | Ban word from generation |
| `{{outlet::key}}` | World Info outlet content |

### Legacy Macro Compatibility

Old-style macros are also supported:
- `<USER>`, `<BOT>`, `<CHAR>`, `<GROUP>`, `<CHARIFNOTGROUP>` — equivalent to their `{{}}` counterparts

---

## 16. Instruct Mode Formatting

**File:** `public/scripts/instruct-mode.js`

Instruct mode wraps text completion prompts with model-specific instruction formatting (e.g., Alpaca, Llama, ChatML-style).

### Settings

`power_user.instruct` contains:
```javascript
{
    enabled: boolean,
    input_sequence: string,        // e.g., "<|im_start|>user\n" or "### Instruction:\n"
    output_sequence: string,       // e.g., "<|im_start|>assistant\n"
    input_suffix: string,          // e.g., "<|im_end|>\n"
    output_suffix: string,
    system_sequence: string,       // e.g., "<|im_start|>system\n"
    system_suffix: string,
    first_input_sequence: string,  // Override for first user message
    last_input_sequence: string,   // Override for last user message
    first_output_sequence: string, // Override for first assistant message
    last_output_sequence: string,  // Override for last assistant message
    last_system_sequence: string,
    stop_sequence: string,
    story_string_prefix: string,   // Wrap before story string
    story_string_suffix: string,   // Wrap after story string
    user_alignment_message: string, // Filler if last msg isn't from user
    names_behavior: 'NONE'|'FORCE'|'ALWAYS',
    skip_examples: boolean,
    system_same_as_user: boolean,  // Use user sequences for system messages
    bind_to_context: boolean,      // Auto-select with context preset
}
```

### Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `formatInstructModeChat()` | 387 | Wraps individual chat message with sequences |
| `formatInstructModeStoryString()` | 478 | Wraps story string with prefix/suffix |
| `formatInstructModeExamples()` | 511 | Formats example messages with sequences |
| `formatInstructModePrompt()` | 593 | Formats the final generation prompt line |
| `getInstructStoppingSequences()` | 301 | Builds stop strings array |
| `autoSelectInstructPreset()` | 236 | Auto-selects preset based on model ID |

### Sequence Selection Logic (line 395+)

```
For each message:
  - Narrator (system): system_sequence (or input_sequence if system_same_as_user)
  - User: input_sequence (first_input_sequence for first, last_input_sequence for last)
  - Assistant: output_sequence (first_output_sequence for first, last_output_sequence for last)
```

---

## 17. Regex Post-Processing

**File:** `public/scripts/extensions/regex/engine.js` (referenced via `getRegexedString()`)

Messages pass through regex scripts before being included in the prompt:

```javascript
// script.js ~line 4278
let regexedMessage = getRegexedString(message, regexType, { isPrompt: true, depth });
```

Regex scripts can be:
- Global (user-defined)
- Per-character (from `character.data.extensions.regex_scripts`)

Regex placements:
- `USER_INPUT` — applied to user messages
- `AI_OUTPUT` — applied to AI messages
- `WORLD_INFO` — applied to World Info entries
- `REASONING` — applied to reasoning content

---

## 18. Server-Side Prompt Conversion

**File:** `src/prompt-converters.js`

The server receives the assembled messages array from the client and performs API-specific transformations.

### Processing Types

**Enum:** `PROMPT_PROCESSING_TYPE`

| Type | Behavior |
|------|----------|
| `NONE` | Pass through unchanged |
| `MERGE` | Merge consecutive same-role messages |
| `MERGE_TOOLS` | Merge with tool call support |
| `SEMI` | Strict user/assistant alternation + merge |
| `SEMI_TOOLS` | Semi with tool support |
| `STRICT` | Strict alternation + placeholder insertion for gaps |
| `STRICT_TOOLS` | Strict with tool support |
| `SINGLE` | Merge all messages into single user message |

### Entry Point

```javascript
// chat-completions.js line 2606
router.post('/process', async function (request, response) {
    const messages = postProcessPrompt(request.body.messages, request.body.type, names);
    return response.send({ messages });
});
```

### API-Specific Converters

| Function | Target API | Line |
|----------|-----------|------|
| `convertClaudeMessages()` | Anthropic Messages API | 196 |
| `convertClaudePrompt()` | Anthropic text completion (legacy) | 118 |
| `convertGooglePrompt()` | Google Gemini | 431 |
| `convertCohereMessages()` | Cohere | 383 |
| `convertAI21Messages()` | AI21 Labs | 626 |
| `convertMistralMessages()` | Mistral AI | 698 |
| `convertXAIMessages()` | xAI (Grok) | 780 |
| `convertTextCompletionPrompt()` | Generic text completion | 957 |

### Claude Messages API Conversion

`convertClaudeMessages()` (line 196):
1. Collects leading system messages into a separate `systemPrompt` array (if `useSysPrompt`)
2. Merges consecutive same-role messages
3. Ensures alternating user/assistant pattern
4. Adds assistant prefill to last message if applicable
5. Returns `{ messages, systemPrompt }`

### Google Gemini Conversion

`convertGooglePrompt()` (line 431):
1. Extracts system instruction from leading system messages
2. Maps roles: user→user, assistant→model, system→user
3. Prepends character names to messages
4. Handles inline media (images, video, audio) as `inlineData` parts
5. Handles tool calls as `functionCall`/`functionResponse` parts
6. Handles reasoning signatures (Gemini 2.5/3)
7. Merges consecutive same-role messages
8. Returns `{ contents, system_instruction }`

---

## 19. Model-Specific Formatting

**File:** `public/scripts/openai.js`, `createGenerationParameters()` ~line 2447

After prompt assembly, generation parameters are customized per API source:

### Common Parameters
- `messages` — the assembled messages array
- `model` — selected model name
- `temperature`, `frequency_penalty`, `presence_penalty`, `top_p`
- `max_tokens` — response budget
- `stream` — streaming flag
- `stop` — stop sequences

### Source-Specific

**Claude:**
- `top_k`, `use_sysprompt` flag, `assistant_prefill` string
- `prompt_processing_type` (merge/semi/strict)

**OpenRouter:**
- `top_k`, `min_p`, `repetition_penalty`
- `provider` settings (model routing, fallbacks, required parameters)

**Google/Vertex:**
- `safety_settings`, `thinking` configuration
- System instruction separation

**Mistral:**
- `safe_prompt` flag

### Prompt Caching

**File:** `src/prompt-converters.js`

- `cachingAtDepthForClaude()` (line 983) — adds `cache_control` to messages at specified depth
- `cachingAtDepthForOpenRouterClaude()` (line 1018) — similar for OpenRouter
- `cachingSystemPromptForOpenRouter()` (line 1065) — caches system prompts

---

## 20. Prompt Manager (Chat Completion)

**File:** `public/scripts/PromptManager.js`

The Prompt Manager controls the ordering and enabled state of all prompt components for the chat completion path.

### Prompt Class (line 182)

```javascript
class Prompt {
    identifier;            // Unique ID (e.g., 'main', 'jailbreak', 'charDescription')
    role;                  // 'system', 'user', 'assistant'
    content;               // Prompt text
    name;                  // Display name
    system_prompt;         // Is this a system prompt?
    injection_position;    // RELATIVE (0) or ABSOLUTE (1)
    injection_depth;       // For ABSOLUTE: how many messages from bottom
    injection_order;       // Sort order (default 100)
    injection_trigger;     // Generation type triggers (which types activate this)
    forbid_overrides;      // Cannot be overridden by character prompts
    extension;             // Added by extension?
    marker;                // Marker prompt (read-only content)?
}
```

### PromptCollection (line 219)

Container for ordered prompts with `add()`, `get()`, `has()`, `override()`, `index()` methods.

### Ordering Strategy

- **Global** — all characters share one prompt order (`dummyId: 100000`)
- **Character** — each character has its own prompt order

### Default Prompt Order

The system ships with a default ordering. The user can reorder, enable/disable, and add custom prompts via the Prompt Manager UI.

### Built-in Prompt Identifiers

| Identifier | Source |
|------------|--------|
| `main` | System prompt |
| `nsfw` | NSFW prompt |
| `jailbreak` | Jailbreak / post-history instructions |
| `enhanceDefinitions` | Enhance definitions prompt |
| `charDescription` | Character description (pulled from card) |
| `charPersonality` | Character personality (pulled from card) |
| `scenario` | Scenario (pulled from card) |
| `personaDescription` | User persona description |
| `worldInfoBefore` | World Info (before character) |
| `worldInfoAfter` | World Info (after character) |
| `dialogueExamples` | Example messages marker |
| `chatHistory` | Chat history marker |

### Prompt Sources (line 302)

Some prompts are "pulled" from character data rather than stored in the prompt manager:
```javascript
promptSources = {
    charDescription: 'Character Description',
    charPersonality: 'Character Personality',
    scenario: 'Scenario',
    personaDescription: 'Persona Description',
    worldInfoBefore: 'World Info (↑Char)',
    worldInfoAfter: 'World Info (↓Char)',
}
```

---

## 21. Final Prompt Layout Diagrams

### Text Completion (KoboldAI / text-generation-webui / NovelAI)

```
┌─────────────────────────────────────────────────┐
│ [NovelAI only: preamble]                        │
├─────────────────────────────────────────────────┤
│ STORY STRING (Handlebars template):             │
│   ├── System prompt (if enabled)                │
│   ├── [BEFORE_PROMPT extension prompts]         │
│   ├── World Info "before" entries                │
│   ├── Character description                     │
│   ├── Character personality                     │
│   ├── Scenario                                  │
│   ├── World Info "after" entries                 │
│   ├── [IN_PROMPT extension prompts]             │
│   └── User persona (if IN_PROMPT position)      │
│   [Instruct mode: story_string_prefix/suffix]   │
├─────────────────────────────────────────────────┤
│ EXAMPLE MESSAGES:                               │
│   ├── <START> block 1                           │
│   ├── <START> block 2                           │
│   └── ... (budget-limited)                      │
├─────────────────────────────────────────────────┤
│ [chat_start separator]                          │
├─────────────────────────────────────────────────┤
│ CHAT HISTORY (oldest to newest):                │
│   ├── User: message 1                           │
│   ├── Char: message 2                           │
│   ├── ... (budget-limited, oldest removed first)│
│   │                                             │
│   │ AT DEPTH INJECTIONS (spliced in):           │
│   │   ├── WI depth entries                      │
│   │   ├── Author's Note (depth 4 default)       │
│   │   ├── Summarize memory                      │
│   │   ├── Vector memories                       │
│   │   ├── Persona desc (if AT_DEPTH)            │
│   │   ├── Character depth prompt                │
│   │   └── Jailbreak (depth 0)                   │
│   │                                             │
│   ├── User: latest message                      │
│   └── [prompt bias / instruct prompt line]      │
├─────────────────────────────────────────────────┤
│ [generatedPromptCache — for 'continue' type]    │
└─────────────────────────────────────────────────┘
```

### Chat Completion (OpenAI / Claude / Gemini / etc.)

```
┌─────────────────────────────────────────────────┐
│ SYSTEM MESSAGES (ordered by Prompt Manager):    │
│   ├── World Info Before          [system]       │
│   ├── Main System Prompt         [system]       │
│   ├── World Info After           [system]       │
│   ├── Character Description      [system]       │
│   ├── Character Personality      [system]       │
│   ├── Scenario                   [system]       │
│   ├── Persona Description        [system]       │
│   ├── NSFW Prompt                [system]       │
│   ├── Enhance Definitions        [system]       │
│   ├── Summarize Memory           [system]       │
│   ├── Vector Memories            [system]       │
│   └── [Custom extension prompts] [system]       │
├─────────────────────────────────────────────────┤
│ DIALOGUE EXAMPLES (budget-limited):             │
│   ├── [Start a new chat]         [system]       │
│   ├── example_user: Hi           [system+name]  │
│   ├── example_assistant: Hello   [system+name]  │
│   ├── [Start a new chat]         [system]       │
│   └── ...                                       │
├─────────────────────────────────────────────────┤
│ CHAT HISTORY (budget-limited, newest-first add):│
│   ├── User message 1             [user]         │
│   ├── Assistant message 1        [assistant]    │
│   │                                             │
│   │ DEPTH INJECTIONS (inserted at depth N):     │
│   │   ├── Author's Note          [system@d4]    │
│   │   ├── WI depth entries       [varies@dN]    │
│   │   ├── Persona (AT_DEPTH)     [system@d2]    │
│   │   └── Character depth prompt [varies@dN]    │
│   │                                             │
│   ├── User message N             [user]         │
│   ├── Assistant message N        [assistant]    │
│   └── [Tool call/result messages if applicable] │
├─────────────────────────────────────────────────┤
│ CONTROL PROMPTS (at end):                       │
│   ├── Jailbreak                  [system]       │
│   ├── Impersonation prompt       [system]       │
│   ├── Quiet prompt (extensions)  [system]       │
│   ├── Group nudge                [system]       │
│   └── Prompt bias                [system]       │
├─────────────────────────────────────────────────┤
│ [Assistant prefill — for Claude/continuation]   │
└─────────────────────────────────────────────────┘
```

### Server-Side Transformation (for Claude Messages API)

```
Client sends: [{role, content, name}, ...]

Server transforms (convertClaudeMessages):
  1. Extract leading system messages → systemPrompt[]
  2. Merge consecutive same-role messages
  3. Ensure user/assistant alternation
  4. Apply prompt caching markers
  5. Add assistant prefill

API receives:
  system: [{type: "text", text: "..."}, ...]
  messages: [{role: "user", content: "..."}, {role: "assistant", content: "..."}, ...]
```

### Server-Side Transformation (for Google Gemini)

```
Client sends: [{role, content, name}, ...]

Server transforms (convertGooglePrompt):
  1. Extract system messages → system_instruction
  2. Map roles (assistant→model, system→user)
  3. Convert media to inlineData parts
  4. Convert tool calls to functionCall/functionResponse
  5. Merge consecutive same-role messages

API receives:
  system_instruction: {parts: [{text: "..."}]}
  contents: [{role: "user", parts: [{text: "..."}]}, {role: "model", parts: [{text: "..."}]}]
```
