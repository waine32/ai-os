# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

AI-OS is a minimal deterministic bash CLI router that dispatches prompts to DeepSeek models via direct API calls. No frameworks, no orchestration layers — just `curl` + `jq`.

**Core principle:** same input → same output. Low temperature, no hidden middleware, fully transparent request pipeline.

## Running the CLI

```bash
# Stateless query
ai flash "what is the capital of France"
ai pro "solve this step by step: ..."

# Session mode (appends to history file)
ai flash --session "continue where we left off"

# Interactive mode
ai flash --interactive
ai flash -i
```

Requires `DEEPSEEK_API_KEY` in env. The binary is the file `ai` (executable, no extension) at the repo root.

## CLI modes

- **Stateless** — single query, no history. Default.
- **Session** — appends prompt and response to `~/.ai-os/sessions/history.json`, prepends history to next query. Automatically migrates from `history.txt` if present.
- **Interactive** — multi-turn conversation loop in the terminal. Persists conversation in memory until exit.

## Model aliases

| Alias | Model | Use case |
|-------|-------|----------|
| `flash` | `deepseek-v4-flash` | fast, cheap, general |
| `pro` | `deepseek-v4-pro` | slow, thorough, reasoning |

Both hit `https://api.deepseek.com/chat/completions`.

## Interactive mode slash commands

Entered as `/command` in the interactive prompt. No API call is made; handled locally.

- `/status` — show model name, temperature, message count in conversation, estimated token count, and memory file size in bytes.
- `/reset` — clear conversation history (does not clear memory or session files).
- `/memory` — display contents of `~/.ai-os/context/global.md`.
- `/help` — list all slash commands.
- `/exit` — exit interactive session.

Also exits on `exit`, `quit`, or empty input.

## Environment variables

- `DEEPSEEK_API_KEY` (required) — API key for DeepSeek. Crashes if not set.
- `AI_TEMPERATURE` (optional, default `0`) — temperature for model sampling. Accepts any numeric value.
- `AI_CONTEXT_LIMIT` (optional, default `6000`) — maximum estimated token count for session history. When exceeded, the oldest 50% of turns are compressed into a summary via API call.

## File layout

```
ai                              # single executable bash script (the entire router)
~/.ai-os/context/global.md      # persistent memory injected as system prompt prefix
~/.ai-os/sessions/history.json  # session mode history (JSON array of objects)
/tmp/ai_last_output.txt         # last raw API response (for debugging)
```

**history.json format:** Array of objects, each with:
- `"role"` — `"user"`, `"assistant"`, or `"summary"`
- `"content"` — the message text
- `"summarized_turns"` (summary objects only) — count of turns compressed into this summary

**Auto-migration:** If `~/.ai-os/sessions/history.txt` exists and `history.json` does not, the script automatically migrates the old format on the next session call.

## Session history compression

When session history exceeds `AI_CONTEXT_LIMIT` (estimated token count), the oldest 50% of turns are compressed:

1. Extract non-summary turns and take the first 50%.
2. Call `ask()` with a summarization prompt to condense the old turns into a single paragraph.
3. Replace old turns with a `{"role":"summary","content":"...","summarized_turns":N}` entry.
4. Keep the newest 50% of turns unchanged.

**Failure handling:** If compression fails (API error or no response), the full history is used silently. This degrades gracefully to avoid losing conversation context.

**Summary injection:** Summary entries are injected into `SYSTEM_PROMPT` (not into the messages array) during `load_session()`. This keeps the messages array strictly alternating user/assistant roles, which is required by the API.

Note: `compress_history()` calls `ask()` internally, which means `ask()` is called before `SYSTEM_PROMPT` is updated with summary content for the current session.

## Token estimation

Token count is estimated as `character_count / 4`. This is used internally to decide when to compress history, and also shown in `/status` output as `estim. tokens`.

## ask() function architecture

Two-step jq payload building (proper JSON escaping via `--arg` and `--argjson`):

1. Build `all_messages` array: inject system prompt + user messages.
   - System prompt is constructed from template with MEMORY file contents and any session summary.
   - User messages are passed as `--argjson msgs "$messages"` (already JSON).
   - SYSTEM_PROMPT interpolates MEMORY inline (safe, comes from file read).

2. Build final `payload` object: model name, messages array, temperature.
   - All three are passed via `--arg` (model, temp as strings) and `--argjson` (msgs as JSON).
   - Payload is passed to curl as `$payload` (safe, built by jq).

3. POST to endpoint, capture response to `/tmp/ai_last_output.txt`, extract `.choices[0].message.content`.


## Desired request pipeline

```
USER INPUT
  → safe JSON escape (jq --arg, not interpolation)
  → load ~/.ai-os/context/global.md as system prompt prefix
  → route to endpoint by alias
  → curl POST, capture raw JSON to /tmp/ai_last_output.txt
  → jq extract .choices[0].message.content (once, not twice)
  → optional structured memory write-back (explicit flag only)
  → print to stdout
```

## Memory system design intent

`~/.ai-os/context/global.md` is a human-editable markdown file. It is injected verbatim as the system prompt prefix on every call. Keep it short (< 2 KB) — it consumes context on every request.

Structured sections to maintain:
- `## User preferences` — stable facts about the user.
- `## Projects` — current work context.
- `## Rules` — hard constraints for the assistant.

Memory write-back is not currently implemented. To add: only trigger on explicit flag (e.g., `--remember "..."`), not via regex heuristics on the response.

## Constraints

- No external dependencies beyond `curl`, `jq`, and standard POSIX tools.
- No Python/Node/Go at runtime (those are acceptable for a future rewrite, not the current bash version).
- `DEEPSEEK_API_KEY` is the only required env var.
- The script must run identically on macOS and Linux.
