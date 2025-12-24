# SillyTavern Group Chat Prompt Construction (Source-Derived)

This document reconstructs, in implementation order, how SillyTavern builds prompts for **group chats** in the original web app codebase. It is intentionally procedural: if you follow this step-by-step, you can recreate the same prompt assembly.

The description below is based on these source files:
- `public/scripts/openai.js` (prompt assembly, ordering, injection, budgeting)
- `public/scripts/PromptManager.js` (prompt configuration, default order)
- `public/scripts/group-chats.js` (group-specific card joining, depth prompts, overrides)
- `public/script.js` (chat metadata and macro substitution helpers)

All identifiers referenced below map directly to those files.

---

## Glossary (Key Concepts)

- **Prompt**: A PromptManager entry (system/user prompt) with metadata such as `identifier`, `role`, `injection_position`, `injection_depth`, and `injection_order`.
- **Absolute prompt**: `injection_position === INJECTION_POSITION.ABSOLUTE`, injected into chat history by depth.
- **Relative prompt**: Positioned relative to `main` or other prompts via PromptManager order.
- **Group chat**: `selected_group` is truthy in the frontend state.
- **Generation mode**: `group.generation_mode` (swap/append/append_disabled) controls how cards are joined.

---

## High-Level Pipeline (Group Chat)

The `openai.js` prompt flow for **group chat** can be distilled as:

1. Load prompt configuration and prompt order (`PromptManager`).
2. Compute group-specific card fields (if APPEND modes) via `group-chats.js`.
3. Build base system/user prompts (`main`, `worldInfoBefore`, `worldInfoAfter`, `personaDescription`, `charDescription`, `charPersonality`, `scenario`, `nsfw`, `jailbreak`).
4. Build absolute prompts (depth prompts, author’s note, summary, vectors, etc.).
5. Prepare chat history as a message list (includes group messages).
6. Inject absolute prompts into the chat history by depth using `populationInjectionPrompts()`.
7. Apply prompt-order logic to add “dialogue examples” and chat history in correct order.
8. Add control prompts (impersonate, group nudge, quiet prompts, continue prefill, etc.).
9. Finalize the messages list and send to the provider.

The key group-specific behavior is in steps 2, 4, 6, and 8.

### Trace Map (Entry Points → Helpers)

```
populateChatCompletion (openai.js)
  ├─ preparePromptsForChatCompletion (openai.js)
  │   ├─ getGroupCharacterCards (group-chats.js) [APPEND modes]
  │   └─ getGroupDepthPrompts (group-chats.js)
  ├─ populationInjectionPrompts (openai.js)
  ├─ populateChatHistory (openai.js)
  └─ populateDialogueExamples (openai.js)
```

---

## Step-by-Step Details

### 1) Determine Group Context

Group chat is active when `selected_group` is truthy. Group configuration is loaded from `public/scripts/group-chats.js` (persisted in `groups/` on disk). Key fields:

- `group.members`: array of avatar filenames.
- `group.disabled_members`: array of avatar filenames.
- `group.generation_mode`: swap / append / append_disabled.
- `group.generation_mode_join_prefix` / `group.generation_mode_join_suffix`.
- `group.chat_metadata`: per-chat metadata (scenario/mes_example overrides, etc.).

Reference: `public/scripts/openai.js:816`, `public/scripts/group-chats.js:442`.

### 2) Group Card Joining (APPEND / APPEND_DISABLED)

If `group.generation_mode` is **APPEND** or **APPEND_DISABLED**, SillyTavern joins all member cards into a single combined card string. This happens in `getGroupCharacterCards()` (`public/scripts/group-chats.js`).

Reference: `public/scripts/group-chats.js:442`.

**Algorithm (getGroupCharacterCards):**

- If `group.generation_mode` is not APPEND/APPEND_DISABLED or `members` is empty, return `null`.
- Iterate all members by avatar.
- Skip missing members.
- Skip disabled members **unless** generation mode is APPEND_DISABLED.
- For each member, build each field:
  - description
  - personality
  - scenario
  - mes_example

**Field join rules:**

- Each field is processed with:
  - optional prefix and suffix (`group.generation_mode_join_prefix` / `group.generation_mode_join_suffix`).
  - macro substitution (`{{char}}`, `{{user}}`, `<FIELDNAME>`).
  - `mes_example` is normalized to start with `<START>\n`.
- The joined output is newline-separated per field.

Reference: `public/scripts/group-chats.js:457`, `public/scripts/group-chats.js:488`, `public/scripts/group-chats.js:520`.

**Overrides:**

- `chat_metadata['scenario']` overrides the joined scenario.
- `chat_metadata['mes_example']` overrides the joined examples.

Reference: `public/scripts/group-chats.js:496`.

**Result:**

`getGroupCharacterCards()` returns:

```
{ description, personality, scenario, mesExamples }
```

Those values replace the individual character card fields when assembling prompts in APPEND modes.

### 3) Group Depth Prompts (Absolute)

Group depth prompts are collected in `getGroupDepthPrompts()` (`public/scripts/group-chats.js`).

**Algorithm:**

- If not in group or mode is SWAP, return empty.
- For each member:
  - Skip missing members.
  - Skip disabled members **unless** this is the current speaker.
  - Read `character.data.extensions.depth_prompt` (prompt/depth/role).
  - Substitute macros with `baseChatReplace(characterName)`.
  - Emit prompt `{ text, depth, role }`.

These prompts are treated as **absolute prompts** (injection by depth).

Reference: `public/scripts/group-chats.js:392`.

### 4) Build Prompt Collection & Default Order

Prompt Manager provides a **default prompt order** (`promptManagerDefaultPromptOrder` in `public/scripts/PromptManager.js`). In default ordering, the relevant identifiers are:

1. `main`
2. `worldInfoBefore`
3. `personaDescription`
4. `charDescription`
5. `charPersonality`
6. `scenario`
7. `enhanceDefinitions` (disabled by default)
8. `nsfw`
9. `worldInfoAfter`
10. `dialogueExamples`
11. `chatHistory`
12. `jailbreak`

This order can be customized by the user; the actual order is whatever PromptManager resolves for the active character/group context.

Reference: `public/scripts/PromptManager.js:2097`.

### 5) Compose the Base Prompts

At build time (in `openai.js`), SillyTavern constructs a prompt list using:

- `worldInfoBefore` and `worldInfoAfter` based on world info matches.
- `main` system prompt (subject to character overrides).
- `charDescription`, `charPersonality`, `scenario` from:
  - joined group cards (APPEND/APPEND_DISABLED), or
  - current speaker’s card (SWAP).
- `personaDescription` (if provided).
- `nsfw` and `jailbreak` prompts (character overrides apply where allowed).
- `dialogueExamples` (aka `mes_example`).

All base prompts are passed through the macro engine (`substituteParams` or equivalent) to resolve `{{char}}`, `{{user}}`, etc.

Reference: `public/scripts/openai.js:1067`, `public/scripts/openai.js:1234`.

### 6) Prepare Chat History

Chat history is a list of chat messages (user/assistant). For group chats, messages are recorded with the speaking character’s name. This list is a normal LLM message list prior to injections.

Reference: `public/scripts/openai.js:803`.

### 7) Inject Absolute Prompts by Depth

Absolute prompts include:

- Group depth prompts (if APPEND/APPEND_DISABLED).
- Author’s note / summary / vectors / smart context, etc. (extension prompts).
- Any prompt with `injection_position === ABSOLUTE`.

Injection is performed in `populationInjectionPrompts()` (`public/scripts/openai.js`).

**Key rules:**

- Messages are processed **from newest to oldest** during injection, then reversed back.
- Injections occur at each depth `i = 0..maxDepth`.
- Prompts at a given depth are grouped by `injection_order` (default 100), sorted **high to low**.
- Within an order group, prompts are concatenated by role priority:
  1. system
  2. user
  3. assistant
- All prompts for the same role at the same depth/order are concatenated with `\n`.
- Each role group becomes a single injected message (`{ role, content, injected: true }`).

**Depth semantics:**

Depth is counted from the **end** of the chat (most recent message). Depth 0 injects closest to the newest message; depth 1 injects one message earlier, etc.

Reference: `public/scripts/openai.js:728`.

### 8) Dialogue Examples vs Chat History Ordering

After injection, SillyTavern decides whether dialogue examples are placed **before or after** chat history depending on the power user setting:

- If `power_user.pin_examples` is true:
  - `populateDialogueExamples()` is called **before** `populateChatHistory()`.
- Otherwise:
  - `populateChatHistory()` is called **before** `populateDialogueExamples()`.

This ordering changes token budgeting and placement in the final message list.

Reference: `public/scripts/openai.js:1203`.

### 9) Group Nudge and Control Prompts

Group-specific prompts are added in `openai.js`:

- **Group nudge** is added if `selected_group` is true and the generation type is not in the exclusion list (e.g., `impersonate`).
- **Continue prefill** may be inserted if continuing generation and the backend supports it.
- **Quiet prompt**, **impersonation prompt**, or **continue nudge** are added based on generation type.

These are generally appended **last** (control prompts), but token budget is reserved for them before assembling the final list.

Reference: `public/scripts/openai.js:816`, `public/scripts/openai.js:1079`.

### 10) Token Budgeting

SillyTavern reserves token budget for:

- New chat prompt (`new_group_chat_prompt` if group).
- Group nudge (if applicable).
- Control prompts (impersonate, quiet, continue prefill, etc.).
- Tool data (if tools are enabled).

After reserving budget, it trims or excludes chat history and injections as needed.

Reference: `public/scripts/openai.js:810`.

---

## Pseudocode Summary (Group Chat)

This is a compact pseudo-implementation of the group chat assembly logic:

```
if selected_group:
    group = current group config
    if group.generation_mode in [APPEND, APPEND_DISABLED]:
        joined = getGroupCharacterCards(group)
        charDescription = joined.description
        charPersonality = joined.personality
        scenario = joined.scenario (override from chat_metadata if set)
        mes_example = joined.mesExamples (override if set)
        depthPrompts += getGroupDepthPrompts(group)
    else:
        charDescription/personality/scenario from current speaker

prompts = PromptManager.getPromptCollection(type)
apply prompt order (default or user-custom)
apply overrides (character/system prompt, jailbreak prompt, etc.)

messages = chat history
messages = populationInjectionPrompts(absolutePrompts, messages)

if power_user.pin_examples:
    add dialogue examples then chat history
else:
    add chat history then dialogue examples

add group nudge (if group, not impersonate)
add control prompts
send messages to provider
```

---

## Notes on Matching Behavior

To match SillyTavern group chat prompt construction exactly, ensure:

- Group APPEND mode joins member cards with prefix/suffix and `<FIELDNAME>` replacement.
- Group depth prompts are collected from **all eligible members** and macro-substituted with each member’s name.
- Absolute prompt injection respects **depth**, **order**, and **role priority**.
- Dialogue examples placement respects `power_user.pin_examples`.
- Group nudge is excluded in impersonation mode.
- Token budgeting is applied before finalizing message order.

---

## References (Source Locations)

- Prompt injection by depth/order/role:
  - `public/scripts/openai.js` (`populationInjectionPrompts`)
- Group card joining / depth prompts:
  - `public/scripts/group-chats.js` (`getGroupCharacterCards`, `getGroupDepthPrompts`)
- Prompt manager order / defaults:
  - `public/scripts/PromptManager.js` (`promptManagerDefaultPromptOrder`)
- Chat history + dialogue example ordering:
  - `public/scripts/openai.js` (`populateChatHistory`, `populateDialogueExamples`)


---

## Appendix A: Prompt Identifiers and Where They Are Built

This table maps each prompt identifier to its construction site and notes any group-specific behavior.

| Identifier | Source / Construction | Group-Specific Notes |
|---|---|---|
| `main` | `public/scripts/PromptManager.js:2011`, `public/scripts/PromptManager.js:2097` | Can be overridden by character `system_prompt` |
| `worldInfoBefore` | `public/scripts/openai.js:1067`, `public/scripts/openai.js:1243`, `public/scripts/PromptManager.js:2053` | Uses matches from group chat context |
| `worldInfoAfter` | `public/scripts/openai.js:1069`, `public/scripts/openai.js:1244`, `public/scripts/PromptManager.js:2047` | Uses matches from group chat context |
| `personaDescription` | `public/scripts/openai.js:1073`, `public/scripts/openai.js:1301`, `public/scripts/PromptManager.js:2085` | Uses persona for current session |
| `charDescription` | `public/scripts/openai.js:1070`, `public/scripts/openai.js:1245`, `public/scripts/PromptManager.js:2067`, `public/scripts/group-chats.js:442` | Joined across members in APPEND/APPEND_DISABLED |
| `charPersonality` | `public/scripts/openai.js:1071`, `public/scripts/openai.js:1246`, `public/scripts/PromptManager.js:2073`, `public/scripts/group-chats.js:442` | Joined across members in APPEND/APPEND_DISABLED |
| `scenario` | `public/scripts/openai.js:1072`, `public/scripts/openai.js:1247`, `public/scripts/PromptManager.js:2079`, `public/scripts/group-chats.js:442` | Joined across members; can be overridden via `chat_metadata['scenario']` |
| `nsfw` | `public/scripts/openai.js:1096`, `public/scripts/PromptManager.js:2021`, `public/scripts/PromptManager.js:2127` | Standard prompt, order controlled by prompt manager |
| `dialogueExamples` | `public/scripts/openai.js:957`, `public/scripts/openai.js:983`, `public/scripts/PromptManager.js:2028` | Uses joined `mes_example` in APPEND modes; overrides via `chat_metadata['mes_example']` |
| `jailbreak` | `public/scripts/openai.js:1372`, `public/scripts/PromptManager.js:2034`, `public/scripts/PromptManager.js:2143` | Can be overridden by character `post_history_instructions` |
| `chatHistory` | `public/scripts/openai.js:803`, `public/scripts/PromptManager.js:2041`, `public/scripts/PromptManager.js:2139` | Uses group messages; combined with absolute injections |
| `groupNudge` | `public/scripts/openai.js:816`, `public/scripts/openai.js:1251` | Added for groups unless generation type is impersonate |
| `summary` | `public/scripts/openai.js:1121`, `public/scripts/openai.js:1256`, `public/scripts/openai.js:728` | Absolute injection (depth/order/role) |
| `authorsNote` | `public/scripts/openai.js:1131`, `public/scripts/openai.js:1265`, `public/scripts/openai.js:728` | Absolute injection (depth/order/role) |
| `vectorsMemory` | `public/scripts/openai.js:1141`, `public/scripts/openai.js:1274`, `public/scripts/openai.js:728` | Absolute injection (depth/order/role) |
| `smartContext` | `public/scripts/openai.js:1161`, `public/scripts/openai.js:1291` | Relative insert near `main` (positioned) |
| `characterDepthPrompt` | `public/scripts/group-chats.js:392` | One per eligible member; absolute injection |
| `continueNudge` | `public/scripts/openai.js:827`, `public/scripts/openai.js:842` | Control prompt appended last |
| `impersonate` | `public/scripts/openai.js:1079` | Control prompt appended last |
| `quietPrompt` | `public/scripts/openai.js:1084`, `public/scripts/openai.js:1250` | Control prompt appended last |

---

## Appendix B: Condensed Checklist (Group Chat Prompt Assembly)

1) **Detect group chat** via `selected_group` and load group config (members, disabled members, generation_mode). See `public/scripts/openai.js:816` and `public/scripts/group-chats.js:442`.
2) **If APPEND/APPEND_DISABLED**:
   - Join member card fields with `generation_mode_join_prefix/suffix`. See `public/scripts/group-chats.js:488`.
   - Replace `<FIELDNAME>`, `{{char}}`, `{{user}}`. See `public/scripts/group-chats.js:457`.
   - Normalize `mes_example` with `<START>\n`. See `public/scripts/group-chats.js:520`.
   - Override `scenario`/`mes_example` if `chat_metadata` contains overrides. See `public/scripts/group-chats.js:496`.
3) **Collect group depth prompts** from all eligible members (skip disabled unless current speaker). See `public/scripts/group-chats.js:392`.
4) **Build base prompts** (`main`, world info before/after, persona, card fields, nsfw, jailbreak). See `public/scripts/openai.js:1067` and `public/scripts/openai.js:1096`.
5) **Assemble prompt order** using PromptManager’s current ordering (default list if none). See `public/scripts/PromptManager.js:2097`.
6) **Prepare chat history** messages in chronological order. See `public/scripts/openai.js:803`.
7) **Inject absolute prompts** by depth using:
   - group by depth
   - group by `injection_order` (high→low)
   - concatenate by role priority (system→user→assistant)
   See `public/scripts/openai.js:728`.
8) **Insert dialogue examples** before or after chat history depending on `power_user.pin_examples`. See `public/scripts/openai.js:1203`.
9) **Add group nudge** unless in impersonate mode; add control prompts last. See `public/scripts/openai.js:816` and `public/scripts/openai.js:1079`.
10) **Budget tokens** before finalizing; trim chat history/injections as needed. See `public/scripts/openai.js:810`.
