# SillyTavern Group Chat System Documentation

## Overview

SillyTavern's group chat system allows multiple AI characters to participate in conversations. The system uses **rule-based activation logic** (not LLM-based) to determine which characters respond, and generates responses **sequentially** (one at a time, not in parallel).

## Architecture

### Core Components

- **Activation Strategies**: Determine *which* characters respond
- **Generation Modes**: Determine *how* character cards are combined in prompts
- **Response Generation**: Sequential execution of individual character generations

---

## Generation Modes

SillyTavern supports **three distinct generation modes** that fundamentally change how character information is presented to the LLM.

### Mode 1: SWAP (Individual Character Responses)

**How it works:**
- Each character generates responses using **only their own character card**
- No character card combination occurs
- Most similar to standard single-character chat

**Prompt construction:**
```
User message
---
Character A's turn:
- Uses Character A's description
- Uses Character A's personality
- Uses Character A's scenario
- Uses Character A's example messages

Character B's turn:
- Uses Character B's description
- Uses Character B's personality
- Uses Character B's scenario
- Uses Character B's example messages
```

**When to use:**
- Characters have distinct, separate contexts
- You want maximum character independence
- Characters shouldn't know about each other's backstories

**Implementation detail:**
- `getGroupDepthPrompts()` returns empty array (no combined depth prompts)
- Source: `group-chats.js:440-441`

---

### Mode 2: APPEND (Merged Context - Enabled Members Only)

**How it works:**
- Combines character cards from all **enabled** group members
- Creates unified description, personality, scenario, and example messages
- Disabled members are excluded from the merged context
- All characters receive the same combined prompt

**Prompt construction:**
```
User message
---
Combined Description:
Character A's description
Character B's description
Character C's description

Combined Personality:
Character A's personality
Character B's personality
Character C's personality

Combined Scenario:
Character A's scenario
Character B's scenario
Character C's scenario

Combined Example Messages:
<START>
Character A's examples
<START>
Character B's examples
<START>
Character C's examples
```

**When to use:**
- Characters should be aware of each other
- Shared universe/context
- Characters need to reference each other's traits
- Better for coherent group dynamics

**Key feature:**
- Disabled members are **excluded** from combined card
- Source: `group-chats.js:554`

---

### Mode 3: APPEND_DISABLED (Merged Context - All Members)

**How it works:**
- Identical to APPEND mode
- **Includes disabled members** in the combined character card
- Even if a character can't respond, their context influences active characters

**When to use:**
- Disabled characters should still influence the scene
- NPCs that provide context but don't speak
- Background characters that inform active characters' behavior

**Example use case:**
```
Active Characters: Alice, Bob
Disabled Characters: Carol (unconscious/silent NPC)

Carol's description/personality still appears in the combined prompt,
so Alice and Bob can reference her presence/state in their responses.
```

---

## Character Card Combination Logic

### Fields That Get Combined

Four character card fields are merged in APPEND modes:

1. **Description** - Physical appearance, background, etc.
2. **Personality** - Traits, behaviors, speaking style
3. **Scenario** - Current situation context
4. **Example Messages** - Sample dialogue

### Combination Process

**Source: `group-chats.js:548-560`**

```javascript
function collectField(fieldName, getter, preprocess = null) {
    const values = [];
    for (const member of group.members) {
        // Find character data
        const index = characters.findIndex(x => x.avatar === member);
        const character = characters[index];

        // Skip disabled members (unless APPEND_DISABLED mode)
        if (group.disabled_members.includes(member) &&
            characterId !== index &&
            group.generation_mode !== group_generation_mode.APPEND_DISABLED) {
            continue;
        }

        // Collect and format field value
        values.push(replaceAndPrepareForJoin(
            getter(character),
            character.name,
            fieldName,
            preprocess
        ));
    }

    // Join with newlines
    return values.filter(x => x.length).join('\n');
}
```

### Custom Prefix/Suffix Wrapping

Each member's field can be wrapped with custom prefixes and suffixes:

**Source: `group-chats.js:529-539`**

```javascript
function replaceAndPrepareForJoin(value, characterName, fieldName, preprocess) {
    const prefix = customTransform(
        group.generation_mode_join_prefix,
        fieldName,
        characterName,
        false
    );
    const suffix = customTransform(
        group.generation_mode_join_suffix,
        fieldName,
        characterName,
        false
    );

    return `${prefix}${value}${suffix}`;
}
```

**Available placeholders:**
- `<FIELDNAME>` - Replaced with field name (Description, Personality, etc.)
- Character name is available for custom templates
- Configured in group settings: `generation_mode_join_prefix` and `generation_mode_join_suffix`

**Example usage:**
```
Prefix: "--- <FIELDNAME> for {{char}} ---\n"
Suffix: "\n---\n"

Result:
--- Description for Alice ---
Alice is a curious scientist...
---
--- Description for Bob ---
Bob is a pragmatic engineer...
---
```

---

## Prompt Integration

### How Group Cards Override Individual Cards

**Source: `script.js:3260-3282`**

When `groupCardsLazy` is available (APPEND modes), it overrides individual character fields:

```javascript
description: () => {
    if (groupCardsLazy) return groupCardsLazy.description;
    return baseChatReplace(character.description?.trim());
},

personality: () => {
    if (groupCardsLazy) return groupCardsLazy.personality;
    return baseChatReplace(character.personality?.trim());
},

scenario: () => {
    if (groupCardsLazy) return groupCardsLazy.scenario;
    const scenarioText = chat_metadata['scenario'] || character.scenario || '';
    return baseChatReplace(scenarioText.trim());
},

mesExamples: () => {
    if (groupCardsLazy) return groupCardsLazy.mesExamples;
    const exampleDialog = chat_metadata['mes_example'] || character.mes_example || '';
    return baseChatReplace(exampleDialog.trim());
},
```

### Lazy Evaluation

Character cards are combined **lazily** - fields are only processed when accessed by the prompt builder.

**Benefits:**
- Avoids unnecessary string concatenation
- Allows dynamic field selection based on prompt template
- Reduces memory overhead for large groups

**Source: `group-chats.js:498-572`**

---

## Chat Metadata Overrides

### Priority Order

1. **Chat metadata** (highest priority)
2. **Group combined cards** (APPEND modes only)
3. **Individual character cards** (fallback)

**Source: `group-chats.js:562-570`**

```javascript
const scenarioOverride = String(chat_metadata['scenario'] || '');
const mesExamplesOverride = String(chat_metadata['mes_example'] || '');

// Scenario uses override first, then combined fields
scenario: () => baseChatReplace(scenarioOverride?.trim()) ||
    collectField('Scenario', c => c.scenario)

// Example messages use override first, then combined fields
mesExamples: () => baseChatReplace(mesExamplesOverride?.trim()) ||
    collectField('Example Messages', c => c.mes_example,
        x => !x.startsWith('<START>') ? `<START>\n${x}` : x)
```

**Use case:**
- Override group scenario for specific chat session
- Provide custom example messages for the entire group
- Does not modify underlying character cards

---

## Depth Prompts

**Source: `group-chats.js:428-470`**

### SWAP Mode
- Returns **empty array** - no group depth prompts
- Each character uses only their own depth prompts

### APPEND/APPEND_DISABLED Modes
- Collects depth prompts from all members
- Respects `disabled_members` based on generation mode
- Extracted from `character.data?.extensions?.depth_prompt`

**Format:**
```javascript
{
    depth: number,          // Insertion depth
    role: string,          // System/assistant/user
    content: string        // Prompt text
}
```

---

## Activation Strategies

Group chat uses **4 activation strategies** to determine which characters respond:

### 1. NATURAL (Default - Smart Activation)

**Logic:**
1. **Mention detection** - Characters whose names appear in user input
2. **Talkativeness roll** - Each character rolls against their talkativeness stat (0.0-1.0)
3. **Fallback** - If no one activated, picks 1 random character

**Optional:** Can prevent same character from responding twice (`allow_self_responses: false`)

**Source: `group-chats.js:1249-1323`**

### 2. LIST (All Members)

- All enabled members respond in order
- Every single character speaks each turn

**Source: `group-chats.js:1187-1195`**

### 3. POOLED (Round-Robin)

- Tracks which members have spoken since last user message
- Prioritizes members who haven't spoken yet
- Ensures fair turn-taking

**Source: `group-chats.js:1204-1238`**

### 4. MANUAL (Random Selection)

- Randomly selects one character
- Used for non-user-input scenarios

---

## Response Generation Flow

**Main function: `generateGroupWrapper()`**
**Source: `group-chats.js:945-1098`**

### Execution Steps

```
1. Precondition Checks
   ├─ Verify online status
   ├─ Check if generation already in progress (is_group_generating)
   └─ Load and validate group data

2. Determine Activation
   ├─ Get user input or last message text
   ├─ Determine if this is user input or continuation
   ├─ Get activation strategy from group settings
   ├─ Filter to enabled members only
   └─ Call activation function → returns character ID array

3. Queue Setup (if enabled)
   └─ Populate groupChatQueueOrder Map for UI display

4. Generate Each Activated Character (SEQUENTIAL)
   FOR each character ID:
   ├─ Set character context (setCharacterId, setCharacterName)
   ├─ Emit GROUP_MEMBER_DRAFTED event
   ├─ Call Generate() with type: 'normal'/'swipe'/'impersonate'/'quiet'/'continue'
   ├─ Check shouldAutoContinue() for automatic continuation
   └─ Update queue display

5. Cleanup
   ├─ Reset is_group_generating flag
   ├─ Clear character context
   ├─ Show swipe buttons
   └─ Emit GROUP_WRAPPER_FINISHED event
```

### Important: Sequential Execution

```javascript
// Source: group-chats.js:1057-1082
for (const chId of activatedMembers) {
    setCharacterId(chId);
    setCharacterName(characters[chId].name);

    // AWAIT = blocks until this character finishes
    textResult = await Generate(generateType, {
        automatic_trigger: byAutoMode,
        ...params
    });

    // Next character only starts after previous finishes
}
```

**No parallel generation** - characters must wait their turn.

---

## Parameter Substitution

**Source: `PromptManager.js:1278-1291`**

Group members are available as `{{groupOverride}}` macro:

```javascript
preparePrompt(prompt, original = null) {
    const groupMembers = this.getActiveGroupCharacters();
    const preparedPrompt = new Prompt(prompt);

    if (typeof original === 'string') {
        if (0 < groupMembers.length) {
            preparedPrompt.content = substituteParams(
                prompt.content ?? '',
                {
                    original,
                    groupOverride: groupMembers.join(', ')
                }
            );
        }
    }
}
```

**Usage in prompts:**
```
The following characters are present: {{groupOverride}}
```

**Output:**
```
The following characters are present: Alice, Bob, Carol
```

---

## Storage Format

### Group Metadata

**Source: `src/endpoints/groups.js:164-179`**

```javascript
{
    id: string,                              // Unique group ID
    name: string,                            // Display name
    members: string[],                       // Character avatar IDs
    avatar_url: string,                      // Group avatar URL

    // Behavior settings
    allow_self_responses: boolean,           // Same char can respond twice
    activation_strategy: number,             // 0-3 (NATURAL/LIST/MANUAL/POOLED)
    generation_mode: number,                 // 0-2 (SWAP/APPEND/APPEND_DISABLED)
    disabled_members: string[],              // Disabled member avatar IDs

    // Context customization
    generation_mode_join_prefix: string,     // Prefix for APPEND mode
    generation_mode_join_suffix: string,     // Suffix for APPEND mode

    // Chat management
    chat_id: string,                         // Current active chat ID
    chats: string[],                         // Array of all chat IDs

    // Auto-mode
    auto_mode_delay: number,                 // Seconds between auto generations
}
```

### Chat Messages

**Format:** JSONL (JSON Lines)
- First line: Header with metadata
- Subsequent lines: Individual messages

**Message structure:**
```javascript
{
    name: string,                // Speaker name
    is_user: boolean,            // Is this user or character
    is_system: boolean,          // Is this a system message
    mes: string,                 // Message text
    original_avatar: string,     // Character avatar ID
    force_avatar: string,        // Avatar thumbnail URL
    extra: {
        gen_id: number           // Unique generation ID (timestamp-based)
    }
}
```

**Source: `group-chats.js:600-609`**

---

## Mode Comparison Table

| Feature | SWAP | APPEND | APPEND_DISABLED |
|---------|------|--------|-----------------|
| **Combined character cards** | ❌ No | ✅ Yes | ✅ Yes |
| **Disabled members in prompt** | N/A | ❌ No | ✅ Yes |
| **Depth prompts combined** | ❌ No | ✅ Yes | ✅ Yes |
| **Each character receives** | Own card only | Combined group card | Combined group card |
| **Character independence** | Maximum | Shared context | Shared context |
| **Use case** | Separate contexts | Collaborative/aware | Background characters |

---

## Events

The system emits events at key points:

```javascript
GROUP_WRAPPER_STARTED           // Generation begins
GROUP_MEMBER_DRAFTED            // Character selected to speak
GROUP_WRAPPER_FINISHED          // All generations complete
GROUP_CHAT_DELETED              // Chat deleted
GROUP_CHAT_CREATED              // New group chat created
GROUP_UPDATED                   // Group settings changed
CHARACTER_RENAMED_IN_PAST_CHAT  // Character renamed
```

---

## Key Files Reference

| File | Lines | Purpose |
|------|-------|---------|
| `public/scripts/group-chats.js` | 122-127 | Activation strategy constants |
| `public/scripts/group-chats.js` | 129-133 | Generation mode constants |
| `public/scripts/group-chats.js` | 428-470 | `getGroupDepthPrompts()` |
| `public/scripts/group-chats.js` | 478-489 | `getGroupCharacterCards()` |
| `public/scripts/group-chats.js` | 498-572 | `getGroupCharacterCardsLazy()` |
| `public/scripts/group-chats.js` | 945-1098 | `generateGroupWrapper()` |
| `public/scripts/group-chats.js` | 1249-1323 | `activateNaturalOrder()` |
| `public/script.js` | 3231-3286 | `getCharacterCardFieldsLazy()` |
| `public/scripts/PromptManager.js` | 1278-1291 | Group parameter substitution |
| `src/endpoints/groups.js` | 164-179 | Group metadata structure |

---

## Design Philosophy

SillyTavern's group chat system prioritizes:

1. **User control** over emergent AI behavior
2. **Predictability** over surprises
3. **Sequential coherence** over parallel chaos
4. **Flexible context sharing** via generation modes

This makes it excellent for **collaborative storytelling** where users want to orchestrate character interactions, rather than autonomous multi-agent task completion.
