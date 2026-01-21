# SillyTavern Group Chat Handling: Messaging & Responses

This document outlines the technical implementation of group chats in SillyTavern, specifically focusing on how the system determines speakers and manages the message generation flow.

## 1. Core Architecture
Group chats in SillyTavern are not a separate engine, but a **Context Switching Orchestrator** built on top of the standard 1-on-1 chat logic. 

*   **Shared History:** All characters in a group share a single chat JSON file.
*   **Contextual Identity:** Messages in the history include an `original_avatar` field. This allows the UI and the prompt builder to identify which character sent which message.
*   **Dynamic Swapping:** The system "swaps" the active character identity (Name, Personality, Scenario) right before sending a prompt to the LLM.

---

## 2. Response Orchestration (`generateGroupWrapper`)
The `generateGroupWrapper` function in `public/scripts/group-chats.js` acts as the conductor for every turn.

### The Selection Process
When a response is triggered, the system calculates an **Activated Members** list based on the chosen **Activation Strategy**:

1.  **Natural Strategy (Default):**
    *   **Mentions:** Scans the last message for character names. If found, those characters are queued.
    *   **Talkativeness:** For all other members, a random roll is performed. If `Random(0,1) <= Character_Talkativeness` (default 0.5), they are queued.
    *   **Failsafe:** If no one is activated, the system selects one random character to speak.
2.  **List Strategy:** Every member of the group is added to the queue in a fixed order.
3.  **Pooled Strategy:** One character is chosen randomly from the pool of members who haven't spoken since the last user message.

### The Execution Loop
Once the queue is built, the system iterates through it:
*   It sets the global character context to the next member in the queue.
*   It calls the standard `Generate()` function.
*   It waits for the LLM to finish before moving to the next character in the queue.
*   **Yielding:** The "Send" button is only re-enabled after the entire queue is exhausted.

---

## 3. Prompt Construction & LLM Expectations
The system ensures the LLM generates the correct response through specific prompt engineering techniques:

### Prompt Priming (Prefixing)
SillyTavern appends the name of the active character followed by a colon (e.g., `Alice:`) to the very end of the prompt. This forces the LLM to begin its response at that point, ensuring it speaks as the correct character.

### Stop Sequences
To prevent the LLM from writing for multiple characters at once (hallucinating a script), the system sends **Stop Sequences** to the API:
*   `
User:`
    *   `
[Other Character Name]:`
    *   Common delimiters like `###` or `</s>`.

### Multi-Character Visibility
The LLM receives the history as a transcript. Because SillyTavern formats history messages with the sender's name (e.g., `Bob: Hello`), the LLM can understand the group dynamic and refer to other participants by name.

---

## 4. Modern Model Handling (Reasoning)
For models that support "Thinking" or "Reasoning" (e.g., DeepSeek R1, Gemini), SillyTavern:
*   Extracts the reasoning block from the API response.
*   Stores it in a separate metadata field (`extra.reasoning`).
*   Hides it from the main chat flow in the UI, keeping the character's "in-character" response clean while preserving the AI's "thoughts" for the user to review.
