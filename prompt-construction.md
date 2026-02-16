# SillyTavern Prompt Construction Pipeline

Exhaustive documentation of how the final LLM prompt is assembled from raw inputs to API call.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Entry Point: Generate()](#2-entry-point-generate)
3. [Character Definition](#3-character-definition)
4. [Story String Template](#4-story-string-template)
5. [System Prompt / Instruction Block](#5-system-prompt--instruction-block)
6. [User Persona](#6-user-persona)
7. [World Info / Lorebook](#7-world-info--lorebook)
8. [Author's Note / Floating Prompt](#8-authors-note--floating-prompt)
9. [Example Messages / Few-Shot](#9-example-messages--few-shot)
10. [Chat History](#10-chat-history)
11. [Extension Prompt System](#11-extension-prompt-system)
12. [Context Budget & Assembly](#12-context-budget--assembly)
13. [Macro System](#13-macro-system)
14. [Regex Post-Processing](#14-regex-post-processing)
15. [Instruct Mode Formatting](#15-instruct-mode-formatting)
16. [OpenAI Chat Completion Assembly](#16-openai-chat-completion-assembly)
17. [Server-Side Prompt Conversion](#17-server-side-prompt-conversion)
18. [Model-Specific API Calls](#18-model-specific-api-calls)
19. [Final Prompt Layout](#19-final-prompt-layout)

---

## 1. High-Level Architecture

SillyTavern constructs prompts through a two-layer pipeline:

1. **Client-side assembly** (`public/script.js`, `public/scripts/openai.js`) — decides *what* to include and in what order
2. **Server-side conversion** (`src/prompt-converters.js`, `src/endpoints/backends/chat-completions.js`) — transforms the assembled prompt into API-specific formats

The system splits into two major code paths based on the selected API:

- **Chat Completion APIs** (OpenAI, Claude, Gemini, Mistral, Cohere, etc.) — messages are structured as `{role, content}` objects and assembled via the `ChatCompletion` class
- **Text Completion APIs** (KoboldAI, NovelAI, TextGenerationWebUI) — the prompt is a single concatenated string

```
User clicks Send
    → sendTextareaMessage()           public/script.js:1597
    → Generate(type)                  public/script.js:4065
        ├─ getCharacterCardFields()   Extract character data
        ├─ getWorldInfoPrompt()       Activate lorebook entries
        ├─ renderStoryString()        Combine character fields into story block
        ├─ setFloatingPrompt()        Set up author's note
        ├─ doChatInject()             Inject depth prompts (non-OpenAI)
        ├─ Context fitting            Trim to fit token budget
        ├─ getCombinedPrompt()        Final text assembly (non-OpenAI)
        └─ prepareOpenAIMessages()    Final message assembly (OpenAI)
            ├─ preparePromptsForChatCompletion()
            ├─ populateChatCompletion()
            ├─ populateChatHistory()
            ├─ populateDialogueExamples()
            └─ populateInjectionPrompts()
    → sendGenerationRequest()         public/script.js:5844
        → fetch('/api/backends/...')
            → postProcessPrompt()     src/prompt-converters.js
            → convertClaudeMessages() / convertGooglePrompt() / etc.
            → API call
```

---

## 2. Entry Point: Generate()

**File:** `public/script.js:4065`

```javascript
export async function Generate(type, {
    automatic_trigger, force_name2, quiet_prompt, quietToLoud,
    skipWIAN, force_chid, signal, quietImage, quietName,
    jsonSchema = null, depth = 0,
} = {}, dryRun = false)
```

**Generation types:** `'normal'`, `'continue'`, `'swipe'`, `'regenerate'`, `'impersonate'`, `'quiet'`

The function orchestrates all prompt assembly in this order:

1. **Extract character fields** (line ~4235)
2. **Process macros and user input** (line ~4260)
3. **Set up extension prompts** — author's note, persona (line ~4389)
4. **Get world info** (line ~4405)
5. **Build story string** from character fields + world info (line ~4473)
6. **Format chat history** (line ~4543)
7. **Calculate context budget** — trim messages to fit (line ~4618)
8. **Assemble final prompt** (line ~4904)
9. **Branch by API type** — OpenAI path vs text completion path (line ~5021)
10. **Send request** (line ~5101)

---

## 3. Character Definition

### Data Structure

Character cards contain these fields relevant to prompt construction:

| Field | Card Key | Usage |
|-------|----------|-------|
| Description | `description` | Character's appearance, background, traits |
| Personality | `personality` | Personality summary |
| Scenario | `scenario` | Current scene/situation |
| First Message | `first_mes` | Opening message of the chat |
| Example Messages | `mes_example` | Few-shot dialogue examples |
| System Prompt | `data.system_prompt` | Character-specific system prompt override |
| Post-History Instructions | `data.post_history_instructions` | Character-specific jailbreak override |
| Creator Notes | `data.creator_notes` | Metadata notes from character creator |
| Depth Prompt | `data.extensions.depth_prompt` | Content injected at specific chat depth |
| Character Version | `data.character_version` | Version number |

### Extraction

**File:** `public/script.js:4235`

```javascript
let {
    description, personality, persona, scenario,
    mesExamples, system, jailbreak, charDepthPrompt, creatorNotes,
} = getCharacterCardFields();
```

`getCharacterCardFields()` reads from the active character object (`characters[this_chid]`) and substitutes macros via `substituteParams()` on each field.

### Character Card Parsing

**File:** `src/character-card-parser.js`

Character cards are parsed from PNG files (embedded in tEXt chunks) or JSON files. The parser extracts the `chara` field from the PNG metadata, base64-decodes it, and parses the JSON character data.

---

## 4. Story String Template

The "story string" is the primary block that combines character data into a single narrative preamble. It is rendered via Handlebars templating.

### Default Template

**File:** `public/script.js:86`

```javascript
const defaultStoryString = '{{#if system}}{{system}}\n{{/if}}'
    + '{{#if description}}{{description}}\n{{/if}}'
    + '{{#if personality}}{{char}}\'s personality: {{personality}}\n{{/if}}'
    + '{{#if scenario}}Scenario: {{scenario}}\n{{/if}}'
    + '{{#if persona}}{{persona}}\n{{/if}}';
```

Users can customize this template via the Context Settings panel. The template supports Handlebars conditionals (`{{#if}}`) and all macro variables.

### Available Template Parameters

**File:** `public/script.js:4473-4489`

```javascript
const storyStringParams = {
    description: description,
    personality: personality,
    persona: power_user.persona_description_position == persona_description_positions.IN_PROMPT
        ? persona : '',
    scenario: scenario,
    system: system,
    char: name2,
    user: name1,
    wiBefore: worldInfoBefore,
    wiAfter: worldInfoAfter,
    loreBefore: worldInfoBefore,
    loreAfter: worldInfoAfter,
    anchorBefore: beforeScenarioAnchor.trim(),
    anchorAfter: afterScenarioAnchor.trim(),
    mesExamples: mesExamplesArray.join(''),
    mesExamplesRaw: mesExamplesRawArray.join(''),
};
```

### Rendering

**File:** `public/scripts/power-user.js:2231-2266`

```javascript
export function renderStoryString(params, { customStoryString, customInstructSettings, customContextSettings } = {}) {
    const storyString = customStoryString ?? contextSettings.story_string;
    const compiledTemplate = Handlebars.compile(storyString, { noEscape: true });
    let output = compiledTemplate(params);
    output = substituteParams(output, params.user, params.char);
    output = output.replace(/^\n+/, '');
    // Add trailing newline if needed
    if (output.length > 0 && !output.endsWith('\n')) {
        output += '\n';
    }
    return output;
}
```

After rendering, if instruct mode is enabled, the story string is wrapped with instruct sequences:

**File:** `public/script.js:4492-4505`

```javascript
const storyString = renderStoryString(storyStringParams);
let combinedStoryString = isInstruct
    ? formatInstructModeStoryString(storyString)
    : storyString;
```

The story string can be positioned either in the system prompt area (`IN_PROMPT`) or injected between chat messages at a configurable depth (`IN_CHAT`).

---

## 5. System Prompt / Instruction Block

### Default Prompts

**File:** `public/scripts/openai.js:99-112`

```javascript
const default_main_prompt =
    'Write {{char}}\'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}.';
const default_nsfw_prompt = '';
const default_jailbreak_prompt = '';
const default_impersonation_prompt =
    '[Write your next reply from the point of view of {{user}}, using the chat history so far as a guideline for the writing style of {{user}}. Don\'t write as {{char}} or system. Don\'t describe actions of {{char}}.]';
const default_enhance_definitions_prompt =
    'If you have more knowledge of {{char}}, add to the character\'s lore and personality to enhance them but keep the Character Sheet\'s definitions absolute.';
const default_wi_format = '{0}';
const default_new_chat_prompt = '[Start a new Chat]';
const default_new_group_chat_prompt = '[Start a new group chat. Group members: {{group}}]';
const default_new_example_chat_prompt = '[Example Chat]';
const default_continue_nudge_prompt = '[Continue your last message without repeating its original content.]';
const default_group_nudge_prompt = '[Write the next reply only as {{char}}.]';
```

### Prompt Definitions

**File:** `public/scripts/PromptManager.js:2003-2083`

The `chatCompletionDefaultPrompts` constant defines all available prompt slots. Each prompt has an `identifier`, `name`, `role`, `content`, and optional `marker` flag. Marker prompts are position placeholders that get filled with dynamic content (character description, world info, chat history, etc.).

Key prompt identifiers:

| Identifier | Name | Role | Default Content |
|-----------|------|------|-----------------|
| `main` | Main Prompt | system | `Write {{char}}'s next reply...` |
| `nsfw` | Auxiliary Prompt | system | *(empty)* |
| `jailbreak` | Post-History Instructions | system | *(empty)* |
| `enhanceDefinitions` | Enhance Definitions | system | `If you have more knowledge of {{char}}...` |
| `charDescription` | Char Description | system | *(marker — filled with character description)* |
| `charPersonality` | Char Personality | system | *(marker)* |
| `scenario` | Scenario | system | *(marker)* |
| `personaDescription` | Persona Description | system | *(marker)* |
| `worldInfoBefore` | World Info (before) | system | *(marker)* |
| `worldInfoAfter` | World Info (after) | system | *(marker)* |
| `dialogueExamples` | Chat Examples | system | *(marker)* |
| `chatHistory` | Chat History | system | *(marker)* |

### Default Prompt Order

**File:** `public/scripts/PromptManager.js:2089-2138`

```javascript
const promptManagerDefaultPromptOrder = [
    { 'identifier': 'main', 'enabled': true },
    { 'identifier': 'worldInfoBefore', 'enabled': true },
    { 'identifier': 'personaDescription', 'enabled': true },
    { 'identifier': 'charDescription', 'enabled': true },
    { 'identifier': 'charPersonality', 'enabled': true },
    { 'identifier': 'scenario', 'enabled': true },
    { 'identifier': 'enhanceDefinitions', 'enabled': false },
    { 'identifier': 'nsfw', 'enabled': true },
    { 'identifier': 'worldInfoAfter', 'enabled': true },
    { 'identifier': 'dialogueExamples', 'enabled': true },
    { 'identifier': 'chatHistory', 'enabled': true },
    { 'identifier': 'jailbreak', 'enabled': true },
];
```

This order is user-customizable per character. Each entry can be toggled on/off.

### Character-Specific Overrides

Characters can override the `main` (system prompt) and `jailbreak` (post-history instructions) prompts. The override is applied in `preparePromptsForChatCompletion()`:

**File:** `public/scripts/openai.js:1386-1404`

```javascript
if (systemPromptOverride && systemPrompt && systemPrompt.forbid_overrides !== true) {
    systemPrompt.content = systemPromptOverride;
    prompts.override(mainReplacement, prompts.index('main'));
}
// Same pattern for jailbreak override
```

### System Prompt Presets

**File:** `public/scripts/sysprompt.js`

System prompts can be saved and loaded as presets. They support a `post_history` field for instructions placed after chat history.

---

## 6. User Persona

### Persona Description Positions

**File:** `public/scripts/power-user.js:110-120`

```javascript
export const persona_description_positions = {
    IN_PROMPT: 0,      // Included in the story string template
    AFTER_CHAR: 1,     // (deprecated, same as IN_PROMPT)
    TOP_AN: 2,         // Prepended to Author's Note
    BOTTOM_AN: 3,      // Appended to Author's Note
    AT_DEPTH: 4,       // Injected at specific chat depth
    NONE: 9,           // Not included
};
```

### How Persona Gets Injected

The injection path depends on the configured position:

**IN_PROMPT (0):** Included in `storyStringParams.persona` and rendered by the story string Handlebars template (line `public/script.js:4476`).

**TOP_AN / BOTTOM_AN (2/3):** Merged with the author's note content:

**File:** `public/script.js:3044-3050`

```javascript
const ANWithDesc = power_user.persona_description_position === persona_description_positions.TOP_AN
    ? `${power_user.persona_description}\n${originalAN}`
    : `${originalAN}\n${power_user.persona_description}`;
```

**AT_DEPTH (4):** Registered as a depth-based extension prompt:

**File:** `public/script.js:3054`

```javascript
setExtensionPrompt(INJECT_TAG, power_user.persona_description,
    extension_prompt_types.IN_CHAT, power_user.persona_description_depth,
    true, power_user.persona_description_role);
```

### Persona Loading Priority

**File:** `public/scripts/personas.js:1440-1519`

1. Chat-locked persona from `chat_metadata['persona']`
2. Character-connected persona from connection map
3. Default/user-selected persona

---

## 7. World Info / Lorebook

### Entry Data Structure

**File:** `public/scripts/world-info.js:3962-4005`

Each world info entry has these fields:

| Field | Type | Description |
|-------|------|-------------|
| `key` | `string[]` | Primary keywords that trigger activation |
| `keysecondary` | `string[]` | Secondary keywords for selective logic |
| `content` | `string` | Text injected into prompt when activated |
| `comment` | `string` | Entry title/memo |
| `constant` | `boolean` | Always active, ignores keywords |
| `selective` | `boolean` | Enables secondary key logic |
| `selectiveLogic` | `enum` | `AND_ANY(0)`, `NOT_ALL(1)`, `NOT_ANY(2)`, `AND_ALL(3)` |
| `disable` | `boolean` | Completely disabled |
| `probability` | `number` | Activation percentage (0-100) |
| `position` | `enum` | Where to place in prompt (see below) |
| `order` | `number` | Sort priority (higher = earlier insertion) |
| `depth` | `number` | Message depth when `position=atDepth` |
| `role` | `enum` | Message role when `position=atDepth` |
| `scanDepth` | `number?` | Per-entry scan depth override |
| `caseSensitive` | `boolean?` | Per-entry case sensitivity override |
| `matchWholeWords` | `boolean?` | Per-entry whole-word matching override |
| `excludeRecursion` | `boolean` | Skip during recursion scans |
| `preventRecursion` | `boolean` | Don't use content for recursion scanning |
| `delayUntilRecursion` | `number` | Delay activation until recursion level N |
| `group` | `string` | Inclusion group (comma-separated) |
| `groupOverride` | `boolean` | Priority override in group |
| `groupWeight` | `number` | Weight for group random selection |
| `sticky` | `number?` | Messages to stay active after trigger |
| `cooldown` | `number?` | Messages before re-activatable |
| `delay` | `number?` | Messages before can first activate |
| `ignoreBudget` | `boolean` | Ignore token budget limits |

### Position Types

**File:** `public/scripts/world-info.js:857-866`

```javascript
export const world_info_position = {
    before: 0,       // Before character definition
    after: 1,        // After character definition
    ANTop: 2,        // Before Author's Note
    ANBottom: 3,     // After Author's Note
    atDepth: 4,      // At specific message depth (with role)
    EMTop: 5,        // Before Example Messages
    EMBottom: 6,     // After Example Messages
    outlet: 7,       // Custom extension outlet
};
```

### Activation Pipeline

**File:** `public/scripts/world-info.js:4469-5035` (`checkWorldInfo()`)

The scanning loop runs through three states:

1. **INITIAL** — First pass, scans chat messages up to configured depth
2. **RECURSION** — Scans content of previously activated entries for more triggers
3. **MIN_ACTIVATIONS** — Increases scan depth to meet minimum activation count

For each entry, the system applies these filters in order:

1. **Disabled check** — skip if `disable === true`
2. **Generation type triggers** — must match current generation type
3. **Character filtering** — include/exclude by character name or tags
4. **Delay effects** — suppress if within delay period
5. **Cooldown** — suppress unless sticky
6. **Recursion delays** — gate by recursion level
7. **Decorators** — `@@activate` forces activation, `@@dont_activate` blocks
8. **Constant entries** — always active regardless of keywords
9. **Sticky entries** — remain active for N messages after trigger
10. **Primary keyword match** — substring, whole-word, or regex matching
11. **Secondary keyword logic** — AND_ANY, NOT_ALL, NOT_ANY, AND_ALL
12. **Probability roll** — random check against configured percentage
13. **Budget check** — skip if adding would exceed token budget

### Keyword Matching

**File:** `public/scripts/world-info.js:337-367`

```javascript
matchKeys(haystack, needle, entry) {
    // Regex patterns are detected and tested directly
    const keyRegex = parseRegexFromString(needle);
    if (keyRegex) {
        return keyRegex.test(haystack);
    }
    // Otherwise: case-transform, then substring or whole-word match
    haystack = this.#transformString(haystack, entry);
    const transformedString = this.#transformString(needle, entry);
    const matchWholeWords = entry.matchWholeWords ?? world_info_match_whole_words;
    if (matchWholeWords) {
        // Multi-word: substring match; single-word: word-boundary regex
        // ...
    } else {
        return haystack.includes(transformedString);
    }
}
```

### Scan Buffer

The `WorldInfoBuffer` class (`public/scripts/world-info.js:199-260`) manages what text is scanned:

- **Chat messages** by depth (newest first)
- **Recursion buffer** — accumulated content from activated entries
- **Inject buffer** — extension prompts marked with `scan: true`
- **Global scan data** — optionally includes character description, personality, scenario, persona, creator notes, and depth prompt content

### Budget System

**File:** `public/scripts/world-info.js:4496-4503`

```javascript
let budget = Math.round(world_info_budget * maxContext / 100) || 1;
if (world_info_budget_cap > 0 && budget > world_info_budget_cap) {
    budget = world_info_budget_cap;
}
```

Default: 25% of context. Entries with `ignoreBudget: true` bypass this limit.

### Inclusion Groups

When multiple entries share a group name, only one activates per group. Selection is by:
1. **Priority override** — entry with `groupOverride: true` and highest `order` wins
2. **Weighted random** — entries selected by `groupWeight` (default 100)

### Insertion and Sorting

**File:** `public/scripts/world-info.js:4954-5015`

Entries are sorted by `order` (descending — higher order = earlier insertion). Each entry's content is placed according to its `position` setting into separate arrays: `WIBeforeEntries`, `WIAfterEntries`, `ANTopEntries`, `ANBottomEntries`, `WIDepthEntries`, `EMEntries`, `WIOutletEntries`.

### Integration with Prompt Assembly

**File:** `public/scripts/world-info.js:894-917`

```javascript
export async function getWorldInfoPrompt(chat, maxContext, isDryRun, globalScanData) {
    const activatedWorldInfo = await checkWorldInfo(chat, maxContext, isDryRun, globalScanData);
    return {
        worldInfoString,      // Combined before + after
        worldInfoBefore,      // Entries with position: before
        worldInfoAfter,       // Entries with position: after
        worldInfoExamples,    // Entries around example messages
        worldInfoDepth,       // Entries at specific depths
        anBefore,             // Entries before author's note
        anAfter,              // Entries after author's note
        outletEntries,        // Entries for custom outlets
    };
}
```

---

## 8. Author's Note / Floating Prompt

### Data Structure

**File:** `public/scripts/authors-note.js:28-40`

```javascript
export const metadata_keys = {
    prompt: 'note_prompt',
    interval: 'note_interval',
    depth: 'note_depth',
    position: 'note_position',
    role: 'note_role',
};

const chara_note_position = {
    replace: 0,    // Replace main AN with character AN
    before: 1,     // Character AN before main AN
    after: 2,      // Character AN after main AN
};
```

Defaults: depth=4, position=IN_CHAT (1), interval=1 (every message), role=SYSTEM.

### Storage

- **Chat-level:** Stored in `chat_metadata[metadata_keys.*]`
- **Character-specific:** Stored in `extension_settings.note.chara[]` with fields: `name`, `prompt`, `useChara`, `position`
- **Global defaults:** Stored in `extension_settings.note.default*`

### Interval Logic

**File:** `public/scripts/authors-note.js:332-363`

The author's note is injected every N user messages based on `note_interval`. When interval is 1, it inserts on every generation. The check uses modulo arithmetic: `lastMessageNumber % interval === 0`.

### Injection

**File:** `public/scripts/authors-note.js:383-390`

```javascript
context.setExtensionPrompt(
    MODULE_NAME,                                 // '2_floating_prompt'
    String(prompt),                              // Note content
    chat_metadata[metadata_keys.position],       // Position type
    chat_metadata[metadata_keys.depth],          // Depth
    extension_settings.note.allowWIScan,         // Include in WI scan
    chat_metadata[metadata_keys.role],           // Role
);
```

Position types (from `extension_prompt_types`):
- `IN_PROMPT (0)` → end of system prompt section
- `IN_CHAT (1)` → between chat messages at specified depth
- `BEFORE_PROMPT (2)` → start of system prompt section

Character-specific notes combine with the main note according to `chara_note_position` (replace/before/after).

---

## 9. Example Messages / Few-Shot

### Format in Character Cards

Example messages in character cards use this format:

```
<START>
{{user}}: Hello there!
{{char}}: *waves* Hello! How can I help you today?

<START>
{{user}}: What do you like?
{{char}}: I enjoy many things! Reading, exploring, and good conversation.
```

### Parsing

**File:** `public/script.js:3317-3331`

```javascript
export function parseMesExamples(examplesStr, isInstruct) {
    if (!examplesStr || examplesStr === '<START>') {
        return [];
    }
    if (!examplesStr.startsWith('<START>')) {
        examplesStr = '<START>\n' + examplesStr.trim();
    }
    const blockHeading = (main_api === 'openai' || isInstruct)
        ? '<START>\n'
        : exampleSeparator;
    const splitExamples = examplesStr
        .split(/<START>/gi).slice(1)
        .map(block => `${blockHeading}${block.trim()}\n`);
    return splitExamples;
}
```

### OpenAI: Parsed into Individual Messages

**File:** `public/scripts/openai.js:678-736` (`parseExampleIntoIndividual()`)

Each example block is split into individual messages by detecting `name1:` (user) and `name2:` (character) prefixes. The result:

```javascript
[
    { role: 'system', content: 'Hello there!', name: 'example_user' },
    { role: 'system', content: '*waves* Hello!...', name: 'example_assistant' },
]
```

All examples use `role: 'system'` with `name` distinguishing user vs assistant examples.

### Insertion into Prompt

**File:** `public/scripts/openai.js:992-1025` (`populateDialogueExamples()`)

Each example block is preceded by a `[Example Chat]` separator message. Examples are added to the `dialogueExamples` collection. If `canAffordAll()` returns false for a block, remaining examples are dropped.

### Instruct Mode Formatting

**File:** `public/scripts/instruct-mode.js:511-575` (`formatInstructModeExamples()`)

When instruct mode is active, examples are wrapped with the model's input/output sequences instead of using role-based formatting.

### Token Budget

- When `power_user.pin_examples` is **true**: all examples are always included (pinned)
- When **false**: examples are added incrementally; when context budget is exceeded, remaining examples are dropped
- During context overflow, examples are removed **before** chat messages

---

## 10. Chat History

### Message Selection

Chat messages are processed from the active chat array. The system handles two paths:

#### OpenAI Path

**File:** `public/scripts/openai.js:834-983` (`populateChatHistory()`)

Messages are iterated **from newest to oldest** (the array is reversed). Each message is wrapped as a `Message` object and checked against the token budget via `canAfford()`. The loop breaks on the first message that doesn't fit.

```javascript
const chatPool = [...messages].reverse();
for (let index = 0; index < chatPool.length; index++) {
    const chatMessage = /* ... */;
    if (chatCompletion.canAfford(chatMessage)) {
        chatCompletion.insertAtStart(chatMessage, 'chatHistory');
    } else {
        break;
    }
}
```

Special messages inserted into chat history:
- **New Chat marker:** `[Start a new Chat]` inserted at the start
- **Group Nudge:** `[Write the next reply only as {{char}}.]` appended at the end (groups only)
- **Continue Nudge:** `[Continue your last message...]` appended at the end (continue mode)

#### Text Completion Path

**File:** `public/script.js:4644-4698`

Messages are iterated from oldest to newest. Each message's token count is accumulated and compared against `this_max_context`. Iteration stops when the budget is exceeded.

### Truncation Strategy

**File:** `public/script.js:4865-4891` (`checkPromptSize()`)

A recursive function that removes content when the prompt exceeds the context limit:

1. First, remove unpinned example messages (one at a time)
2. Then, remove the oldest chat messages (FIFO from the front)
3. Recurse until the prompt fits

### Summarization

SillyTavern has **no built-in chat summarization**. The `1_memory` extension (Tavern Extras) provides external summarization that injects a summary as an extension prompt. This is treated as a regular system prompt slot:

**File:** `public/scripts/openai.js:1279-1286`

```javascript
const summary = extensionPrompts['1_memory'];
if (summary && summary.value) systemPrompts.push({
    role: getPromptRole(summary.role),
    content: summary.value,
    identifier: 'summary',
});
```

### Regex Processing of Chat Messages

Before chat messages enter the prompt, they pass through `getRegexedString()` which applies user-defined regex scripts targeting `AI_OUTPUT` or `USER_INPUT` placements.

---

## 11. Extension Prompt System

Extensions can inject content at any position and depth in the prompt via `setExtensionPrompt()`.

### Registration

**File:** `public/script.js:8620-8628`

```javascript
export function setExtensionPrompt(key, value, position, depth, scan = false,
    role = extension_prompt_roles.SYSTEM, filter = null) {
    extension_prompts[key] = {
        value: String(value),
        position: Number(position),    // IN_PROMPT(0), IN_CHAT(1), BEFORE_PROMPT(2)
        depth: Number(depth),          // 0 = last message, up to 10000
        scan: !!scan,                  // Include in world info scanning
        role: Number(role),            // SYSTEM(0), USER(1), ASSISTANT(2)
        filter: filter,                // Optional filter function
    };
}
```

### Known Extension Keys

| Key | Source | Description |
|-----|--------|-------------|
| `1_memory` | Memory/Summarize extension | Chat summary |
| `2_floating_prompt` | Authors Note | Floating prompt injection |
| `3_vectors` | Vectors extension | Vector DB retrieved context |
| `4_vectors_data_bank` | Data Bank extension | Data bank retrieved context |
| `chromadb` | Smart Context | ChromaDB retrieved context |
| `PERSONA_DESCRIPTION` | Persona system | User persona at depth |
| `DEPTH_PROMPT` | Character card | Character depth prompt |
| `__STORY_STRING__` | Story string | Story string as in-chat injection |
| `QUIET_PROMPT` | Generate function | Quiet generation prompt |

### Retrieval

**File:** `public/script.js:3132-3160` (`getExtensionPrompt()`)

Filters `extension_prompts` by position, depth, and role. Joins matching prompts with a separator.

### Depth Injection (Non-OpenAI)

**File:** `public/script.js:5400-5448` (`doChatInject()`)

Iterates through each depth level, collects matching extension prompts, and splices them into the chat message array at the appropriate position.

### Depth Injection (OpenAI)

**File:** `public/scripts/openai.js:759-824` (`populateInjectionPrompts()`)

Collects prompts with `injection_position === ABSOLUTE`, groups by `injection_depth` and `injection_order`, and inserts them into the flattened message array at the correct positions.

---

## 12. Context Budget & Assembly

### Budget Calculation

**OpenAI Path** (`public/scripts/openai.js:1458`):

```javascript
chatCompletion.setTokenBudget(openai_max_context, openai_max_tokens);
// tokenBudget = openai_max_context - openai_max_tokens
```

**Text Completion Path** (`public/script.js:5702-5739`):

```javascript
export function getMaxContextSize(overrideResponseLength = null) {
    if (main_api == 'openai') {
        return oai_settings.openai_max_context - (overrideResponseLength || oai_settings.openai_max_tokens);
    }
    // KoboldAI, NovelAI, TextGen: max_context - amount_gen
    return max_context - (overrideResponseLength || amount_gen);
}
```

**Defaults** (`public/scripts/power-user.js:78-79`):

```javascript
export const MAX_CONTEXT_DEFAULT = 8192;
export const MAX_RESPONSE_DEFAULT = 2048;
```

### Budget Reservation System (OpenAI)

The `ChatCompletion` class uses a reservation pattern:

1. **Reserve** tokens for must-have elements (new chat message, nudges, control prompts)
2. **Fill** remaining budget with chat history and examples
3. **Free** reserved budget and insert the reserved messages

```javascript
chatCompletion.reserveBudget(3);              // Assistant priming tokens
chatCompletion.reserveBudget(newChatMessage);  // [Start a new Chat]
// ... fill chat history ...
chatCompletion.freeBudget(newChatMessage);
chatCompletion.insertAtStart(newChatMessage, 'chatHistory');
```

### Affordability Check

**File:** `public/scripts/openai.js:3736-3747`

```javascript
canAfford(message) {
    return 0 <= this.tokenBudget - message.getTokens();
}
```

### CFG Prompt Budget Reduction

When Classifier Free Guidance is enabled, the context budget is reduced by the token count of the longest CFG prompt:

**File:** `public/script.js:4363-4374`

```javascript
const decrement = Math.max(negativePromptTokenCount, positivePromptTokenCount);
this_max_context -= decrement;
```

---

## 13. Macro System

### Architecture

The macro system uses the Chevrotain parser library for robust tokenization and evaluation.

**Pipeline:** `MacroEngine.evaluate()` → `MacroParser.parseDocument()` → `MacroCstWalker.evaluateDocument()` → `MacroRegistry.executeMacro()`

**File:** `public/scripts/macros/engine/MacroEngine.js:31-71`

```javascript
evaluate(input, env) {
    const preProcessed = this.#runPreProcessors(input, env);
    const { cst } = MacroParser.parseDocument(preProcessed);
    let evaluated = MacroCstWalker.evaluateDocument({ text: preProcessed, cst, env, resolveMacro });
    const result = this.#runPostProcessors(evaluated, env);
    return result;
}
```

### Pre-Processing

Converts legacy syntax:
- `<USER>` → `{{user}}`
- `<BOT>` / `<CHAR>` → `{{char}}`
- `<GROUP>` → `{{group}}`
- `{{time_UTC+2}}` → `{{time::UTC+2}}`

### Post-Processing

- Unescapes `\{` → `{` and `\}` → `}`
- Removes `{{trim}}` macros and surrounding whitespace

### Complete Macro List

**Names/Environment** (`env-macros.js`):
`{{user}}`, `{{char}}`, `{{group}}`, `{{charIfNotGroup}}`, `{{groupNotMuted}}`, `{{notChar}}`

**Character Card** (`env-macros.js`):
`{{charPrompt}}`, `{{charInstruction}}`, `{{charDescription}}` / `{{description}}`, `{{charPersonality}}` / `{{personality}}`, `{{charScenario}}` / `{{scenario}}`, `{{persona}}`, `{{mesExamples}}`, `{{mesExamplesRaw}}`, `{{charDepthPrompt}}`, `{{charCreatorNotes}}` / `{{creatorNotes}}`, `{{charVersion}}` / `{{version}}`

**Time/Date** (`time-macros.js`):
`{{time}}`, `{{time::UTC±offset}}`, `{{date}}`, `{{weekday}}`, `{{isotime}}`, `{{isodate}}`, `{{datetimeformat::format}}`, `{{idleDuration}}`, `{{timeDiff::left::right}}`

**Chat** (`chat-macros.js`):
`{{lastMessage}}`, `{{lastMessageId}}`, `{{lastUserMessage}}`, `{{lastCharMessage}}`, `{{firstIncludedMessageId}}`, `{{firstDisplayedMessageId}}`, `{{lastSwipeId}}`, `{{currentSwipeId}}`

**Variables** (`variable-macros.js`):
`{{setvar::name::value}}`, `{{getvar::name}}`, `{{addvar::name::value}}`, `{{incvar::name}}`, `{{decvar::name}}`, `{{setglobalvar::name::value}}`, `{{getglobalvar::name}}`, `{{addglobalvar::name::value}}`, `{{incglobalvar::name}}`, `{{decglobalvar::name}}`

**Instruct** (`instruct-macros.js`):
`{{instructStoryStringPrefix}}`, `{{instructStoryStringSuffix}}`, `{{instructUserPrefix}}`, `{{instructUserSuffix}}`, `{{instructAssistantPrefix}}`, `{{instructAssistantSuffix}}`, `{{instructSystemPrefix}}`, `{{instructSystemSuffix}}`, `{{instructFirstAssistantPrefix}}`, `{{instructLastAssistantPrefix}}`, `{{instructStop}}`, `{{systemPrompt}}`, `{{defaultSystemPrompt}}`, `{{exampleSeparator}}`, `{{chatStart}}`

**Core/Utility** (`core-macros.js`):
`{{space}}`, `{{newline}}`, `{{noop}}`, `{{trim}}`, `{{input}}`, `{{maxPrompt}}`, `{{reverse::string}}`, `{{roll::NdM}}`, `{{random::a::b::c}}`, `{{pick::a::b::c}}`, `{{banned::word}}`, `{{outlet::key}}`, `{{//comment}}`

**State** (`state-macros.js`):
`{{model}}`, `{{isMobile}}`, `{{lastGenerationType}}`

### When Macros Are Applied

Macros are substituted via `substituteParams()` at multiple points:
- Story string rendering (during `renderStoryString()`)
- Prompt content (during `PromptManager.preparePrompt()`)
- Extension prompt values (during `getExtensionPrompt()`)
- Instruct mode sequences (during `formatInstructModeChat()`)
- World info entry keys and content (during scanning)

---

## 14. Regex Post-Processing

### Regex Script Types

**File:** `public/scripts/extensions/regex/engine.js:11-16`

```javascript
export const SCRIPT_TYPES = {
    GLOBAL: 0,     // Applied globally
    PRESET: 2,     // Applied per preset
    SCOPED: 1,     // Applied per character/chat
};
```

### Placement Targets

**File:** `public/scripts/extensions/regex/engine.js:281-292`

```javascript
export const regex_placement = {
    MD_DISPLAY: 0,     // (deprecated)
    USER_INPUT: 1,     // Applied to user messages
    AI_OUTPUT: 2,      // Applied to AI messages
    SLASH_COMMAND: 3,   // Applied to slash commands
    WORLD_INFO: 5,      // Applied to world info content
    REASONING: 6,       // Applied to reasoning/thinking output
};
```

### Application

**File:** `public/scripts/extensions/regex/engine.js:334-380`

`getRegexedString(rawString, placement, options)` iterates through all enabled regex scripts matching the target placement and runs each script's find/replace pattern. Scripts can target:
- Only markdown display (`markdownOnly`)
- Only prompt generation (`promptOnly`)
- Specific depth ranges (`minDepth`, `maxDepth`)

Regex scripts are applied to:
- Chat messages during prompt assembly (`public/script.js:4281`)
- World info entry content during insertion
- AI output during display

---

## 15. Instruct Mode Formatting

Instruct mode wraps all messages with model-specific instruction sequences for instruction-tuned models.

### Preset Structure

**File:** `public/scripts/instruct-mode.js:23-48`

```javascript
{
    enabled: boolean,
    wrap: boolean,                     // Add newlines around sequences
    macro: boolean,                    // Apply macro substitution
    story_string_prefix: string,       // Wraps story string start
    story_string_suffix: string,       // Wraps story string end
    input_sequence: string,            // User message prefix
    input_suffix: string,              // User message suffix
    output_sequence: string,           // Assistant message prefix
    output_suffix: string,             // Assistant message suffix
    system_sequence: string,           // System message prefix
    system_suffix: string,             // System message suffix
    first_output_sequence: string,     // First assistant message override
    last_output_sequence: string,      // Last assistant message (generation prompt)
    first_input_sequence: string,      // First user message override
    last_input_sequence: string,       // Last user message override
    last_system_sequence: string,      // Last system message override
    user_alignment_message: string,    // Filler for alignment
    stop_sequence: string,             // Stop token
    activation_regex: string,          // Auto-activate pattern
    names_behavior: string,            // 'none', 'force', 'always'
    system_same_as_user: boolean,      // Use input_sequence for system
    skip_examples: boolean,            // Skip example formatting
    sequences_as_stop_strings: boolean,// Export sequences to stop strings
}
```

### Message Wrapping

**File:** `public/scripts/instruct-mode.js:387-457` (`formatInstructModeChat()`)

Each chat message is wrapped:
1. Determine prefix based on role (user/assistant/system) and position (first/last/middle)
2. Determine suffix based on role
3. Apply macro substitution if `instruct.macro` is true
4. Assemble: `prefix + (name?: "name: ") + content + suffix`

### Story String Wrapping

**File:** `public/scripts/instruct-mode.js:478-502` (`formatInstructModeStoryString()`)

The story string is wrapped with `story_string_prefix` and `story_string_suffix`.

### Generation Prompt (Last Line)

**File:** `public/scripts/instruct-mode.js:593-651` (`formatInstructModePrompt()`)

The last line of the prompt uses `last_output_sequence` (or `output_sequence` as fallback) to prompt the model to generate as the character.

### Stop Sequences

**File:** `public/scripts/instruct-mode.js:301-367` (`getInstructStoppingSequences()`)

Exports the instruct sequences as stop strings. When `sequences_as_stop_strings` is true, all input/output/system sequences are added. Context template separators (`chat_start`, `example_separator`) can also be included.

---

## 16. OpenAI Chat Completion Assembly

This section covers the full assembly path for chat completion APIs (OpenAI, Claude, Gemini, etc.).

### Entry Point

**File:** `public/scripts/openai.js:1433-1498` (`prepareOpenAIMessages()`)

```javascript
export async function prepareOpenAIMessages({ name2, charDescription, charPersonality,
    scenario, worldInfoBefore, worldInfoAfter, bias, type, quietPrompt, quietImage,
    extensionPrompts, cyclePrompt, systemPromptOverride, jailbreakPromptOverride,
    messages, messageExamples }, dryRun)
{
    const chatCompletion = new ChatCompletion();
    chatCompletion.setTokenBudget(userSettings.openai_max_context, userSettings.openai_max_tokens);

    const prompts = await preparePromptsForChatCompletion({ ... });
    await populateChatCompletion(prompts, chatCompletion, { ... });

    if (oai_settings.squash_system_messages) {
        await chatCompletion.squashSystemMessages();
    }

    return [chatCompletion.getMessages().getChat(), true];
}
```

### Step 1: Prepare Prompts

**File:** `public/scripts/openai.js:1258-1407` (`preparePromptsForChatCompletion()`)

1. Creates array of system prompts from character data and world info
2. Adds extension prompts (memory, author's note, vectors, smart context)
3. Retrieves user-defined prompt order via `PromptManager.getPromptCollection()`
4. Merges system prompts into the prompt collection at their marker positions
5. Applies character-specific overrides for main prompt and jailbreak

### Step 2: Populate Chat Completion

**File:** `public/scripts/openai.js:1076-1238` (`populateChatCompletion()`)

Adds prompts to the `ChatCompletion` object in this order:

1. `worldInfoBefore`
2. `main` (system prompt)
3. `worldInfoAfter`
4. `charDescription`
5. `charPersonality`
6. `scenario`
7. `personaDescription`
8. Control prompts reserved (impersonate, quiet prompt)
9. `nsfw` (auxiliary prompt)
10. `jailbreak` (post-history instructions)
11. User-defined custom prompts
12. `enhanceDefinitions`
13. `bias`
14. Known extension prompts (summary, authorsNote, vectors, etc.)
15. Custom extension prompts
16. `dialogueExamples` (if pinned)
17. `chatHistory`
18. Control prompts released

### Step 3: System Message Squashing

**File:** `public/scripts/openai.js:3573-3607`

When `squash_system_messages` is enabled, consecutive system messages without names are merged into a single message to reduce API overhead.

### ChatCompletion Class

**File:** `public/scripts/openai.js:3568-3700`

The `ChatCompletion` class manages:
- Token budget tracking (`tokenBudget`, `reserveBudget()`, `freeBudget()`)
- Nested message collections (`MessageCollection`)
- Message insertion (`insertAtStart()`, `insertAtEnd()`, `insert()`)
- Affordability checks (`canAfford()`, `canAffordAll()`)
- Final flattening (`getChat()`) — recursively flattens nested collections into a flat array of `{role, content, name?}` objects

---

## 17. Server-Side Prompt Conversion

### Post-Processing

**File:** `src/prompt-converters.js:83-103`

```javascript
function postProcessPrompt(messages, type, names) {
    switch (type) {
        case PROMPT_PROCESSING_TYPE.MERGE:       // Non-strict merging
        case PROMPT_PROCESSING_TYPE.MERGE_TOOLS:  // + tool handling
        case PROMPT_PROCESSING_TYPE.SEMI:         // Strict (no empty messages)
        case PROMPT_PROCESSING_TYPE.SEMI_TOOLS:   // Strict + tools
        case PROMPT_PROCESSING_TYPE.STRICT:       // Strict + placeholders
        case PROMPT_PROCESSING_TYPE.STRICT_TOOLS: // All options
        case PROMPT_PROCESSING_TYPE.SINGLE:       // Everything into one message
        default: return messages;                  // NONE: no processing
    }
}
```

The `mergeMessages()` function handles:
- **Merging** consecutive messages with the same role
- **Strict mode**: removes empty messages
- **Placeholders**: inserts placeholder text for empty required messages
- **Single mode**: merges everything into one message
- **Tools**: preserves tool call/result message structure

### Claude (Anthropic) Conversion

**File:** `src/prompt-converters.js:196-375` (`convertClaudeMessages()`)

1. **Extract system prompt**: leading `system` role messages become the `system` parameter (separate from messages)
2. **Convert remaining system messages** to `user` role (Claude only supports `user`/`assistant`)
3. **Convert content** to Claude's array format: `[{type: 'text', text: '...'}]`
4. **Convert images** from `image_url` to base64 `{type: 'image', source: {type: 'base64', ...}}`
5. **Move assistant images** to next user message (Claude requirement)
6. **Add prefill** as final assistant message
7. **Merge consecutive same-role messages**
8. **Convert tool messages** to Claude's `tool_use`/`tool_result` format

### Google (Gemini) Conversion

**File:** `src/prompt-converters.js:431-618` (`convertGooglePrompt()`)

1. **Extract system prompt** into `system_instruction: {parts: [{text: '...'}]}`
2. **Convert roles**: `system`/`tool` → `user`, `assistant` → `model`
3. **Convert content** to `parts` array format
4. **Convert images** to `inlineData: {mimeType, data}`
5. **Convert tools** to `functionCall`/`functionResponse` format
6. **Merge consecutive same-role messages** (Google requirement)

### Other Conversions

- **Cohere** (`convertCohereMessages()`): Converts to `ChatHistory` format
- **AI21** (`convertAI21Messages()`): Merges system messages, alternates roles
- **Mistral** (`convertMistralMessages()`): Tool sanitization, prefix mode

### Claude Prompt Caching

**File:** `src/endpoints/backends/chat-completions.js:89-98`

Configurable via `claude.enableSystemPromptCache` and `claude.cachingAtDepth`. Adds `cache_control: {type: 'ephemeral'}` markers to system prompt, tools, and messages at specified depth.

---

## 18. Model-Specific API Calls

### OpenAI / Chat Completion

**File:** `public/scripts/openai.js:2808` (`sendOpenAIRequest()`)

Creates generation parameters via `createGenerationParameters()` including:
- `messages`: The assembled message array
- `model`, `temperature`, `max_tokens`, `top_p`, `frequency_penalty`, `presence_penalty`
- `stream`: Whether to use SSE streaming
- `tools`: Function calling tools (if enabled)
- `logit_bias`: Token biases
- `stop`: Custom stop sequences

Sends to `/api/backends/chat-completions/generate`.

### Claude-Specific

**File:** `src/endpoints/backends/chat-completions.js:203-382`

Additional handling:
- **Extended thinking**: Adds `thinking: {type: 'enabled', budget_tokens}` for Claude 3.7+ models
- **Web search**: Adds server-managed web search tool
- **Limited sampling**: Removes `temperature`/`top_p`/`top_k` when thinking is enabled
- **Assistant prefill**: Pre-filled assistant response start (set via `oai_settings.assistant_prefill`)
- **Beta headers**: `prompt-caching-2024-07-31`, `tools-2024-05-16`, etc.

### KoboldAI

**File:** `public/scripts/kai-settings.js:174-209`

Sends a single `prompt` string with sampler parameters (temperature, top_k, top_p, rep_pen, etc.).

### NovelAI

**File:** `public/scripts/nai-settings.js:520-612`

Sends a single `input` string with NovelAI-specific parameters. Context limits vary by model (Clio: 8192, Kayra: 8192, Erato: 8192 minus special token overhead).

### TextGenerationWebUI

**File:** `public/scripts/textgen-settings.js:1808`

Sends a single `prompt` string with extensive sampler parameters. Supports many backends (Aphrodite, TabbyAPI, KoboldCpp, Ollama, etc.).

---

## 19. Final Prompt Layout

### Chat Completion APIs (OpenAI, Claude, etc.)

The final `messages` array sent to the API, from top to bottom:

```
┌─────────────────────────────────────────────────────┐
│ [SYSTEM] Main Prompt                                │  "Write {{char}}'s next reply..."
│          (or character override)                    │
├─────────────────────────────────────────────────────┤
│ [SYSTEM] World Info (Before)                        │  Activated lorebook entries (position: before)
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Persona Description                        │  User's self-description (if IN_PROMPT)
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Character Description                      │  Character's description field
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Character Personality                      │  Character's personality field
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Scenario                                   │  Current scenario text
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Enhance Definitions (if enabled)           │  "If you have more knowledge of {{char}}..."
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Auxiliary Prompt (NSFW)                     │  User-defined auxiliary instructions
├─────────────────────────────────────────────────────┤
│ [SYSTEM] World Info (After)                         │  Activated lorebook entries (position: after)
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Extension Prompts                          │  Memory/summary, vectors, smart context
│          (at their configured positions)            │
├─────────────────────────────────────────────────────┤
│ [SYSTEM] [Example Chat]                             │  Example separator
│ [SYSTEM] example_user: "..."                        │  Few-shot examples from character card
│ [SYSTEM] example_assistant: "..."                   │
│ [SYSTEM] [Example Chat]                             │  (repeated per example block)
│ [SYSTEM] example_user: "..."                        │
│ [SYSTEM] example_assistant: "..."                   │
├─────────────────────────────────────────────────────┤
│ [SYSTEM] [Start a new Chat]                         │  Chat boundary marker
├─────────────────────────────────────────────────────┤
│ ┌─ CHAT HISTORY ──────────────────────────────────┐ │
│ │ [USER]      oldest included message             │ │
│ │ [ASSISTANT] response                            │ │
│ │ ...                                             │ │
│ │ ── depth N: Author's Note (if IN_CHAT) ──────── │ │  Injected between messages
│ │ ── depth N: WI entries (position: atDepth) ──── │ │  at their configured depths
│ │ ── depth N: Extension prompts (IN_CHAT) ─────── │ │
│ │ ── depth N: Persona (if AT_DEPTH) ────────────  │ │
│ │ ...                                             │ │
│ │ [USER]      most recent user message            │ │
│ │ [ASSISTANT] most recent response                │ │
│ └─────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Post-History Instructions (Jailbreak)      │  User-defined post-history instructions
│          (or character override)                    │
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Group Nudge (groups only)                  │  "[Write the next reply only as {{char}}.]"
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Impersonate Prompt (if impersonating)      │  "[Write your next reply from {{user}}'s POV]"
├─────────────────────────────────────────────────────┤
│ [SYSTEM] Quiet Prompt (if quiet generation)         │  Internal generation instructions
├─────────────────────────────────────────────────────┤
│ [ASSISTANT] Bias / Prefill                          │  Response priming text (Claude-specific)
└─────────────────────────────────────────────────────┘
```

**Note:** The exact order of system prompts is user-configurable via the Prompt Manager. The layout above reflects the default ordering. Individual prompts can be reordered, enabled/disabled, or given absolute injection positions.

**For Claude specifically**, the server-side converter:
1. Extracts all leading system messages into the separate `system` parameter
2. Converts remaining system messages to `user` role
3. Merges consecutive same-role messages
4. Appends assistant prefill as final message

### Text Completion APIs (KoboldAI, NovelAI, etc.)

The prompt is a single concatenated string:

```
┌─────────────────────────────────────────────────────┐
│ [Story String]                                      │
│   System prompt (if present)                        │
│   Character description                             │
│   {{char}}'s personality: ...                       │
│   Scenario: ...                                     │
│   User persona (if IN_PROMPT)                       │
│   World Info (before + after, woven in by template) │
├─────────────────────────────────────────────────────┤
│ [Example Messages] (if included)                    │
│   <START> / [Example Chat]                          │
│   {{user}}: example input                           │
│   {{char}}: example response                        │
├─────────────────────────────────────────────────────┤
│ [Chat Start Separator]                              │
├─────────────────────────────────────────────────────┤
│ [Chat History]                                      │
│   oldest included message                           │
│   ...                                               │
│   ── depth N: injected prompts ──                   │
│   ...                                               │
│   most recent message                               │
├─────────────────────────────────────────────────────┤
│ [Generation Prompt Line]                            │
│   {{char}}:  (or instruct output_sequence)          │
│   + prompt bias (if any)                            │
└─────────────────────────────────────────────────────┘
```

When instruct mode is enabled, every message is additionally wrapped with the model's instruction sequences (`input_sequence`, `output_sequence`, `system_sequence` and their suffixes).

### After Server-Side Conversion (Claude Example)

```json
{
  "model": "claude-sonnet-4-20250514",
  "system": [
    {"type": "text", "text": "Write {{char}}'s next reply...\n\nWorld Info...\n\nCharacter description...", "cache_control": {"type": "ephemeral"}}
  ],
  "messages": [
    {"role": "user", "content": [{"type": "text", "text": "example_user: Hello"}]},
    {"role": "assistant", "content": [{"type": "text", "text": "example_assistant: Hi there!"}]},
    {"role": "user", "content": [{"type": "text", "text": "[Start a new Chat]\nHello!"}]},
    {"role": "assistant", "content": [{"type": "text", "text": "Character response..."}]},
    {"role": "user", "content": [{"type": "text", "text": "User's latest message"}]},
    {"role": "assistant", "content": [{"type": "text", "text": "prefill text"}]}
  ],
  "max_tokens": 2048,
  "temperature": 0.9,
  "stream": true
}
```

---

## Appendix: Key File Reference

| File | Purpose |
|------|---------|
| `public/script.js` | Main client entry point, `Generate()` orchestrator |
| `public/scripts/openai.js` | Chat completion assembly, `prepareOpenAIMessages()`, `ChatCompletion` class |
| `public/scripts/PromptManager.js` | Prompt ordering, `Prompt` class, default prompt definitions |
| `public/scripts/world-info.js` | World info/lorebook scanning, activation, budget, insertion |
| `public/scripts/authors-note.js` | Author's note / floating prompt system |
| `public/scripts/instruct-mode.js` | Instruct mode message wrapping and formatting |
| `public/scripts/power-user.js` | Context settings, `renderStoryString()`, persona positions |
| `public/scripts/personas.js` | User persona loading and management |
| `public/scripts/tokenizers.js` | Token counting (17 supported tokenizers) |
| `public/scripts/macros/engine/MacroEngine.js` | Macro substitution engine |
| `public/scripts/macros/*.js` | Macro definitions (env, time, chat, variables, instruct, core) |
| `public/scripts/extensions/regex/engine.js` | Regex post-processing scripts |
| `public/scripts/sysprompt.js` | System prompt preset management |
| `public/scripts/char-data.js` | Character data loading |
| `src/prompt-converters.js` | Server-side format conversion (Claude, Google, Cohere, etc.) |
| `src/endpoints/backends/chat-completions.js` | Server-side API call dispatch |
| `src/character-card-parser.js` | Character card file parsing |
