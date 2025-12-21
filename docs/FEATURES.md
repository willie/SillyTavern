# SillyTavern Feature Guide

This guide documents powerful features that most users never discover. SillyTavern has sophisticated systems for prompt assembly, character interaction, and context management that go far beyond basic chat.

## Table of Contents
1. [Prompt Assembly Pipeline](#prompt-assembly-pipeline)
2. [Character System](#character-system)
3. [World Info / Lorebook](#world-info--lorebook)
4. [Group Chats](#group-chats)
5. [Memory Systems](#memory-systems)
6. [Expression & Sprite System](#expression--sprite-system)
7. [Slash Commands](#slash-commands)
8. [Power User Features](#power-user-features)

---

## Prompt Assembly Pipeline

SillyTavern uses a sophisticated layered system to assemble prompts. Understanding this gives you precise control over what the AI sees.

### Token Budget System

Every prompt component competes for your model's context window:

```
Available tokens = context_size - max_response_tokens
```

The system uses a **reserve/free** mechanism:
- Components can **reserve** tokens without consuming them (for conditional sections)
- When actually added, they **free** the reservation and consume the budget
- This allows optional sections that only use tokens if included

**How to access**: Settings > AI Response Formatting > Context Size / Response Length

### Injection Positions

Prompts can be positioned two ways:

**RELATIVE (position 0)**: Positioned around the main system prompt
- Before main prompt
- After main prompt
- Before/after character description, personality, scenario

**ABSOLUTE (position 1)**: Injected at a specific message depth in chat
- Depth 0 = right after system prompts, before chat
- Depth 4 = 4 messages back from the latest
- Higher depth = further back in conversation

**How to access**: Open Prompt Manager (AI Response Formatting > Prompts > Advanced) to see and reorder all prompt components.

### Injection Order/Priority

When multiple prompts target the same depth:
- Higher `order` value = processes first (appears earlier)
- Lower `order` value = processes last (appears later)
- Default order is 100

**Example**: An author's note at depth 4 with order 100 will appear before a world info entry at depth 4 with order 50.

### Generation Triggers

Prompts can be set to only activate during specific generation types:
- `normal`: Standard message generation
- `continue`: Continuing the AI's last message
- `impersonate`: Having the AI speak as your character
- `quiet`: Background generation (summaries, etc.)

**How to access**: Prompt Manager > Edit a prompt > Injection Trigger dropdown

### Character Card Overrides

Character cards can override your default prompts:
- `system_prompt` field replaces your main system prompt
- `post_history_instructions` replaces your jailbreak/NSFW prompt

Unless a prompt has `forbid_overrides: true`, character cards take precedence.

**How to see what's overridden**: Look for badges in Prompt Manager showing which prompts are character-overridden.

### Prompt Construction Flow

```
Character/Settings Inputs
│
├─ Character card + overrides
├─ User prompt presets (main/nsfw/jailbreak)
├─ World Info matches
├─ Vector memory results
├─ Authors note
├─ Extension prompts
└─ Chat history + dialogue examples
          ▼
   Merge & Order Prompts
   (respect depth, order, position)
          ▼
   Token Budget Trimming
   (oldest chat messages first)
          ▼
   Final API Payload
```

---

## Character System

### Character Card Versions

**V2 (Standard)**: Current format with these fields:
- `name`, `description`, `personality`, `scenario`, `first_mes`, `mes_example`
- `creator_notes`, `system_prompt`, `post_history_instructions`
- `tags`, `creator`, `character_version`
- `alternate_greetings[]`, `character_book` (embedded lorebook)

**V3 (Enhanced)**: Adds asset references and extended metadata.

**CharX**: ZIP format containing `card.json` plus images/assets.

### Depth Prompts (Hidden Feature)

Each character can have a **depth prompt**: a system message injected at a specific depth in the conversation.

**How to access**: Character Editor > Advanced Definitions > Depth Prompt

Configure:
- **Prompt text**: What to inject
- **Depth**: How many messages back (0 = top, 4 = default)
- **Role**: system, user, or assistant

**Use case**: Inject character-specific instructions mid-conversation, like "Remember to stay in character" at depth 4.

### Alternate Greetings

Characters can have multiple opening messages:
- **Alternate greetings**: Shown when starting any chat
- **Group-only greetings**: Only shown when character joins a group chat

**How to access**: Character Editor > First Message > click arrows to add/switch greetings

### Embedded Lorebooks

Characters can carry their own World Info:
- Stored in `character_book` field
- Automatically activates when chatting with that character
- Entries can reference other entries (recursive activation)

**How to access**: Character Editor > World/Lorebook > Character Lorebook

### Regex Scripts (Per-Character)

Characters can transform text with regex patterns:
- Apply to AI output, user input, or both
- Can be limited to specific message depths
- Supports markdown-only or prompt-only modes

**How to access**: Character Editor > Advanced Definitions > Regex Scripts

---

## World Info / Lorebook

World Info injects context when keywords match. The system is more powerful than most realize.

### Matching Options

| Option | Description |
|--------|-------------|
| **Keywords** | Comma-separated list of trigger words |
| **Regex** | Regular expression pattern matching |
| **Case Sensitive** | Respect capitalization |
| **Match Whole Words** | Prevent partial matches ("cat" won't match "category") |
| **Probability** | % chance to activate even when matched (0-100) |

**How to access**: World Info > Edit entry > Keys / Logic

### Selective Logic

Control how primary and secondary keys interact:

| Logic | Behavior |
|-------|----------|
| **AND ANY** | Primary keys match AND any secondary key matches |
| **AND ALL** | Primary keys match AND all secondary keys match |
| **NOT ANY** | Primary keys match AND no secondary keys match |
| **NOT ALL** | Primary keys match AND not all secondary keys match |

**Use case**: Entry for "dragon" that only activates if "fire" is also mentioned (AND ANY), or an entry about a secret that doesn't activate if "revealed" is mentioned (NOT ANY).

### Timed Effects

**Sticky** (stays active for N messages):
- Once triggered, remains active for the specified number of chat messages
- Useful for ongoing situations: "The storm continues for 5 messages"

**Cooldown** (wait N messages before re-triggering):
- After activation ends, entry cannot activate again for N messages
- Prevents repetitive information

**Delay** (wait N turns before first activation):
- Entry won't activate until N chat turns after conditions are met
- Build-up effect: "The tension builds..."

**How to access**: World Info > Edit entry > Timing section

### Recursive Activation

Entries can trigger other entries:
- Entry A's content contains keywords that match Entry B
- Entry B then also gets included

**How to access**: Settings > World Info > Recursive Scan (enable globally)

Set `max_recursion_steps` to limit depth (prevent infinite loops).

### Insertion Strategies

| Strategy | Behavior |
|----------|----------|
| **Evenly** | Distribute entries throughout the prompt |
| **Character First** | Character-attached entries before global |
| **Global First** | Global entries before character-attached |

**How to access**: Settings > World Info > Insertion Strategy

### Scanning Sources

Entries can match against:
- Chat messages (configurable depth)
- Character description/personality
- Scenario
- User persona description
- Creator notes

**How to access**: World Info > Edit entry > Scan options (checkboxes)

---

## Group Chats

Group chats allow multiple characters to interact. The system is highly configurable.

### Activation Strategies

| Strategy | How Characters Respond |
|----------|----------------------|
| **Natural** | AI decides who speaks based on context |
| **List** | Characters respond in defined order |
| **Manual** | You pick who responds each time |
| **Pooled** | Random selection from enabled members |

**How to access**: Group > Settings > Activation Strategy

### Generation Modes

| Mode | Behavior |
|------|----------|
| **Swap** | One character responds at a time (default) |
| **Append** | All character cards combined into one prompt |
| **Append (include disabled)** | Same as Append but includes muted members |

**Append mode** is powerful for ensemble responses where you want the AI to consider all characters at once.

**How to access**: Group > Settings > Generation Mode

### Per-Member Settings

- **Disable members**: Muted characters won't respond but remain in the group
- **Depth prompts**: Each character can have their own depth injection
- **Sprites hidden**: Disabled members' sprites don't show in visual novel mode

**How to access**: Group > Member list > Click character > Options

### Group-Only Greetings

Characters can have greetings that only trigger when they join a group:

**How to access**: Character Editor > First Message > Group-only greetings tab

---

## Memory Systems

SillyTavern has multiple ways to provide context beyond the immediate chat history.

### Chat History Trimming

When the context window fills up:
1. Oldest messages are removed first
2. Pinned messages (dialogue examples) can be preserved
3. Mandatory prompts (system, author's note) are never trimmed
4. If mandatory prompts exceed context, generation aborts with error

### Vector Memory

Semantic search for relevant past context:
- Embeds messages into vector space
- Retrieves messages similar to current context
- Injected before chat history

**How to access**: Extensions > Vector Storage

Requires an embedding model (local or API).

### Data Bank

Upload reference documents:
- PDFs, text files, markdown
- Chunked and embedded for retrieval
- Search returns relevant chunks to include in prompt

**How to access**: Extensions > Vector Storage > Data Bank tab

### Author's Note

A floating prompt that stays in context:

| Setting | Description |
|---------|-------------|
| **Depth** | How many messages back to inject (0 = top) |
| **Position** | Before scenario, before chat, or after |
| **Frequency** | Inject every N messages (0 = always) |
| **Role** | system, user, or assistant |

**Global vs Per-Chat**: You can have a global author's note and override it per-chat.

**How to access**: Extensions > Author's Note (or the "A" button in chat)

### Smart Context (ChromaDB)

Vector-enhanced context management:
- Automatically embeds and retrieves relevant history
- Works alongside regular chat history
- Configurable retrieval count

**How to access**: Extensions > Smart Context

---

## Expression & Sprite System

Characters can display dynamic expressions and sprites.

### 28 Default Expressions

admiration, amusement, anger, annoyance, approval, caring, confusion, curiosity, desire, disappointment, disapproval, disgust, embarrassment, excitement, fear, gratitude, grief, joy, love, nervousness, optimism, pride, realization, relief, remorse, sadness, surprise, neutral

### Sprite System

Characters can have multiple sprite images:
- Store in `characters/[character_name]/[expression].png`
- Filename becomes the expression label (e.g., `joy.png` → "joy")
- Variants supported: `joy-1.png`, `joy.expressive.png`

**How to add sprites**: Create a folder matching your character's name in the characters directory, add PNG files named by expression.

### Expression Detection

| Method | Description |
|--------|-------------|
| **Local** | Uses built-in classifier model |
| **LLM** | Asks the AI to classify emotion |
| **Extras** | External classification service |
| **None** | Disabled |

**How to access**: Extensions > Expression Images > Expression Detection

### Visual Novel Mode

Displays character sprites in a visual novel layout:
- Shows active character(s) on screen
- Sprites update based on detected expressions
- Disabled members hidden (if configured)

**How to access**: User Settings > Visual Novel Mode (checkbox)

---

## Slash Commands

Type `/` in the chat input to access commands. Here are the most useful:

### Chat Management
| Command | Description |
|---------|-------------|
| `/continue` | Continue the AI's last message |
| `/impersonate` | Generate as your character |
| `/sys [text]` | Send a system message |
| `/comment [text]` | Add a comment (not sent to AI) |
| `/send [text]` | Send as user |
| `/sendas name=[char] [text]` | Send as a specific character |
| `/trigger` | Trigger AI response |
| `/delswipe` | Delete current swipe |

### Navigation
| Command | Description |
|---------|-------------|
| `/go [name]` | Switch to a character/group |
| `/bg [name]` | Change background |
| `/closechat` | Close current chat |
| `/tempchat` | Start a temporary chat |
| `/chat-manager` | Open chat manager |

### Group Management
| Command | Description |
|---------|-------------|
| `/member-add [name]` | Add character to group |
| `/member-remove [name]` | Remove from group |
| `/member-enable [name]` | Enable a muted member |
| `/member-disable [name]` | Mute a member |
| `/member-up [name]` | Move member up in list |
| `/member-down [name]` | Move member down |

### Settings
| Command | Description |
|---------|-------------|
| `/api [name]` | Switch API provider |
| `/instruct [preset]` | Switch instruct preset |
| `/context [preset]` | Switch context preset |
| `/instruct-on` / `/instruct-off` | Toggle instruct mode |

### Utility
| Command | Description |
|---------|-------------|
| `/?` or `/help` | Show all commands |
| `/dupe` | Duplicate current character |
| `/rename-char [name]` | Rename character |
| `/ask [question]` | Get AI response without adding to chat |
| `/sysgen [prompt]` | Generate system content (summaries, etc.) |
| `/char-find [name]` | Find character by name |

### World Info Commands
| Command | Description |
|---------|-------------|
| `/wi-list` | List all world info books |
| `/wi-list-entries [book]` | List entries in a book |
| `/wi-activate [book] [entry]` | Force-activate an entry |
| `/wi-deactivate [book] [entry]` | Deactivate an entry |

---

## Power User Features

### Prompt Manager

Full control over prompt ordering and content:
- Drag to reorder prompt components
- Toggle components on/off per character
- See token counts for each component
- View what's being overridden by character cards

**How to access**: AI Response Formatting > Prompts > Prompt Manager (or click "Advanced")

### Instruct Mode

Format prompts for instruction-tuned models:
- Wraps system/user/assistant messages with model-specific tags
- Presets for common models (Llama, Mistral, etc.)
- Custom format support

**How to access**: AI Response Formatting > Instruct Mode

### CFG Scale (Classifier-Free Guidance)

Increases prompt adherence:
- Higher values = more literal following of instructions
- Can help with character consistency
- Not all backends support it

**How to access**: AI Response Formatting > CFG Scale

### Logprobs Display

See token probabilities:
- Shows which tokens the model considered
- Useful for debugging prompt issues
- Helps understand model behavior

**How to access**: AI Response Formatting > Logprobs (requires API support)

### Token Counter

Real-time token counting:
- Shows current context usage
- Per-component breakdown in Prompt Manager
- Supports multiple tokenizer models

**How to access**: The token count display in the chat input area shows current usage.

### Quick Replies

Create reusable message buttons:
- Set up common prompts, commands, or responses
- Organize into sets
- Trigger with keyboard shortcuts or buttons

**How to access**: Extensions > Quick Reply

### Regex Scripts (Global)

Transform AI output with regex:
- Clean up unwanted patterns
- Format responses
- Apply to specific backends only

**How to access**: Extensions > Regex

---

## Tips for Discovery

1. **Right-click everything**: Many UI elements have context menus with additional options
2. **Check Advanced/More buttons**: Collapsed sections hide power features
3. **Read tooltips**: Hover over settings for explanations
4. **Use `/help`**: The slash command help shows all available commands
5. **Check Extensions**: Many features are extensions that need enabling
6. **Explore Prompt Manager**: Understanding prompt order is key to good results
