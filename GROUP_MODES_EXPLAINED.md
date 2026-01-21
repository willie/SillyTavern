# Group Chat Modes - Simple Explanation

The three modes control **what character information the LLM sees when generating each response**.

---

## Setup Example

Let's say you have a group with 3 characters:

**Alice:**
- Description: "Alice is a detective with keen observation skills"
- Personality: "Analytical, serious, methodical"
- Scenario: "Alice is investigating a murder case"

**Bob:**
- Description: "Bob is a bartender who knows everyone in town"
- Personality: "Friendly, talkative, gossipy"
- Scenario: "Bob is working his usual evening shift"

**Carol:**
- Description: "Carol is a journalist chasing a big story"
- Personality: "Ambitious, persistent, nosy"
- Scenario: "Carol is tracking down leads for her article"

User says: "What do you think about the mayor?"

All 3 characters are activated to respond.

---

## Mode 1: SWAP (Each Character Independent)

### What happens:

**When Alice generates her response:**
```
The LLM sees:
- Description: "Alice is a detective with keen observation skills"
- Personality: "Analytical, serious, methodical"
- Scenario: "Alice is investigating a murder case"
- Chat history...
- User: "What do you think about the mayor?"
```

**When Bob generates his response:**
```
The LLM sees:
- Description: "Bob is a bartender who knows everyone in town"
- Personality: "Friendly, talkative, gossipy"
- Scenario: "Bob is working his usual evening shift"
- Chat history...
- User: "What do you think about the mayor?"
- Alice: [her response]
```

**When Carol generates her response:**
```
The LLM sees:
- Description: "Carol is a journalist chasing a big story"
- Personality: "Ambitious, persistent, nosy"
- Scenario: "Carol is tracking down leads for her article"
- Chat history...
- User: "What do you think about the mayor?"
- Alice: [her response]
- Bob: [his response]
```

### Summary:
- Each character only knows their own backstory
- Alice generates without knowing Bob and Carol exist
- Bob generates knowing Alice exists (from chat history) but not her backstory
- Carol generates knowing Alice and Bob exist but not their backstories

---

## Mode 2: APPEND (Shared Context - Enabled Members)

### What happens:

**When Alice generates her response:**
```
The LLM sees:
- Description: "Alice is a detective with keen observation skills
              Bob is a bartender who knows everyone in town
              Carol is a journalist chasing a big story"

- Personality: "Analytical, serious, methodical
               Friendly, talkative, gossipy
               Ambitious, persistent, nosy"

- Scenario: "Alice is investigating a murder case
            Bob is working his usual evening shift
            Carol is tracking down leads for her article"

- Chat history...
- User: "What do you think about the mayor?"
```

**When Bob generates his response:**
```
The LLM sees:
- Description: [SAME COMBINED TEXT AS ALICE SAW]
- Personality: [SAME COMBINED TEXT AS ALICE SAW]
- Scenario: [SAME COMBINED TEXT AS ALICE SAW]
- Chat history...
- User: "What do you think about the mayor?"
- Alice: [her response]
```

**When Carol generates her response:**
```
The LLM sees:
- Description: [SAME COMBINED TEXT AS ALICE SAW]
- Personality: [SAME COMBINED TEXT AS ALICE SAW]
- Scenario: [SAME COMBINED TEXT AS ALICE SAW]
- Chat history...
- User: "What do you think about the mayor?"
- Alice: [her response]
- Bob: [his response]
```

### Summary:
- ALL characters see ALL backstories
- Alice knows Bob is a gossipy bartender and Carol is a nosy journalist
- Bob knows Alice is a serious detective and Carol is ambitious
- Carol knows everyone's context
- Better for natural group dynamics

---

## Mode 3: APPEND_DISABLED (Includes Disabled Members)

Let's say Carol is **disabled** (she won't speak, but she's still in the scene).

User says: "What do you think about the mayor?"

Only Alice and Bob are activated (Carol is disabled).

### What happens:

**When Alice generates her response:**
```
The LLM sees:
- Description: "Alice is a detective with keen observation skills
              Bob is a bartender who knows everyone in town
              Carol is a journalist chasing a big story"  ← CAROL INCLUDED!

- Personality: "Analytical, serious, methodical
               Friendly, talkative, gossipy
               Ambitious, persistent, nosy"  ← CAROL INCLUDED!

- Scenario: "Alice is investigating a murder case
            Bob is working his usual evening shift
            Carol is tracking down leads for her article"  ← CAROL INCLUDED!

- Chat history...
- User: "What do you think about the mayor?"
```

**When Bob generates his response:**
```
The LLM sees:
- Description: [SAME COMBINED TEXT INCLUDING CAROL]
- Personality: [SAME COMBINED TEXT INCLUDING CAROL]
- Scenario: [SAME COMBINED TEXT INCLUDING CAROL]
- Chat history...
- User: "What do you think about the mayor?"
- Alice: [her response]
```

### Summary:
- Carol doesn't speak (disabled)
- But Alice and Bob still know Carol exists and her context
- Useful for NPCs who are present but silent

---

## Visual Comparison

```
SWAP Mode:
┌─────────┐    ┌─────────┐    ┌─────────┐
│ Alice   │    │   Bob   │    │  Carol  │
│ sees:   │    │ sees:   │    │ sees:   │
│ - Alice │    │ - Bob   │    │ - Carol │
└─────────┘    └─────────┘    └─────────┘
Independent          Independent         Independent


APPEND Mode:
┌─────────────────────────────────────┐
│       All Characters See:           │
│ - Alice's info                      │
│ - Bob's info                        │
│ - Carol's info                      │
└─────────────────────────────────────┘
        Shared Context for All


APPEND_DISABLED (Carol disabled):
┌─────────────────────────────────────┐
│    Alice & Bob See:                 │
│ - Alice's info                      │
│ - Bob's info                        │
│ - Carol's info (but she won't talk) │
└─────────────────────────────────────┘
     Shared Context Including Silent NPCs
```

---

## When To Use Each Mode

### Use SWAP when:
- Characters shouldn't know each other's backgrounds
- Characters are from different universes/timelines
- You want maximum character independence
- Example: Time travelers from different eras who just met

### Use APPEND when:
- Characters are friends/colleagues who know each other
- Characters are in a shared universe
- You want natural group dynamics
- Example: A team of heroes who work together

### Use APPEND_DISABLED when:
- You have NPCs who are present but shouldn't speak
- You want characters to reference silent characters
- Example: Someone is unconscious/asleep/gagged but still in the scene

---

## The Critical Point

**The mode doesn't change WHO speaks** - that's determined by the activation strategy (NATURAL/LIST/POOLED/MANUAL).

**The mode changes WHAT each speaker knows** when they generate their response.

---

## Real-World Example

**Scenario:** Alice (detective), Bob (bartender), Carol (journalist) at Bob's bar.

**User:** "The mayor just walked in. What do you do?"

### With SWAP Mode:

**Alice generates knowing only:**
- She's a detective investigating a case
- Someone named Bob and Carol spoke (from chat history)
- Doesn't know Bob owns the bar
- Doesn't know Carol is a journalist

**Bob generates knowing only:**
- He's a bartender at his bar
- Someone named Alice and Carol are here (from chat history)
- Doesn't know Alice is a detective
- Doesn't know Carol is a journalist

**Carol generates knowing only:**
- She's a journalist chasing a story
- Someone named Alice and Bob spoke (from chat history)
- Doesn't know Alice is a detective
- Doesn't know Bob is the bartender

**Result:** Characters might not react naturally to each other's roles.

---

### With APPEND Mode:

**All characters generate knowing:**
- Alice is a detective investigating a case
- Bob is the bartender who owns this bar
- Carol is a journalist chasing a story

**Alice's response might be:**
"I glance at Bob, wondering if he's heard any rumors about the mayor from his patrons."

**Bob's response might be:**
"I catch Alice's eye - she's probably interested in this too. I casually wipe down the bar and move closer to the mayor's table."

**Carol's response might be:**
"Perfect timing. I signal Bob to keep the drinks flowing - a tipsy mayor might let something slip that Alice could use in her investigation."

**Result:** Characters reference each other naturally because they know each other's context.

---

## Technical Detail

The mode determines what `getGroupCharacterCards()` returns:

- **SWAP:** Returns `undefined` (no group cards, each character uses their own)
- **APPEND:** Returns merged cards (disabled members excluded)
- **APPEND_DISABLED:** Returns merged cards (disabled members included)

These merged cards override individual character cards in the prompt builder.

**Source:** `group-chats.js:440-441` for SWAP check, `group-chats.js:498-572` for merging logic
