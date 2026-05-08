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
ai flash -i
ai flash --interactive

# Pipe input
echo "summarize this" | ai flash
cat file.txt | ai flash "summarize:"
```

Requires `DEEPSEEK_API_KEY` in env. The binary is the file `ai` (executable, no extension) at the repo root.

## CLI modes

- **Stateless** — single query, no history. Default. Supports pipe input — if stdin is not a TTY and no prompt is given as an argument, reads stdin.
- **Session** — appends prompt and response to `~/.ai-os/sessions/history.json`, prepends history to next query. Automatically migrates from `history.txt` if present.
- **Interactive** — multi-turn conversation loop in the terminal. Persists conversation in memory until exit.

## Context files

AI-OS uses a Claude Code–style layered context system. Files are loaded at startup and assembled into the system prompt in this order:

| File | Path | Role |
|------|------|------|
| `instructions.md` | `~/.ai-os/instructions.md` | Base behaviour, language, tone — replaces hardcoded defaults |
| `memory.md` | `~/.ai-os/memory.md` | Accumulated facts, user preferences, project info |
| `context.md` | `~/.ai-os/context.md` | Current active context (legacy: `context/global.md`) |
| `ds.md` | `./ds.md` (CWD walk) | Project-level instructions, like CLAUDE.md — discovered by walking up from CWD |

`instructions.md` and `memory.md` are auto-created with defaults on first run if missing. `ds.md` is optional and project-specific. The `/memory` slash command shows all loaded context files.

## Output streaming

Responses stream token-by-token via SSE (`"stream": true`). Output starts printing immediately.

- User-facing calls (stateless, session, interactive) always stream.
- Internal calls (`compress_history` summarization) use blocking mode to avoid terminal noise.
- Assembled response is saved to `/tmp/ai_last_stream.txt` after each streaming call.

## Warp terminal integration

When `TERM_PROGRAM=WarpTerminal` is detected, the interactive loop emits OSC 133 sequences:

- `\033]133;A\007` — prompt start (before `read`)
- `\033]133;C\007` — command executing (after Enter)
- `\033]133;D;0\007` / `\033]133;D;1\007` — command done (0=ok, 1=error)

Lets Warp draw block boundaries and enables click-to-copy on AI responses. No-op on all other terminals.

## Model aliases

| Alias | Model | Use case |
|-------|-------|----------|
| `flash` | `deepseek-v4-flash` | fast, cheap, general |
| `pro` | `deepseek-v4-pro` | slow, thorough, reasoning |

Both hit `https://api.deepseek.com/chat/completions`.

## Interactive mode slash commands

Entered as `/command` in the interactive prompt. No API call is made; handled locally.

| Command | Description |
|---------|-------------|
| `/status` | Show model name, temperature, message count, estimated token count, last prompt/completion token counts, and memory file size |
| `/reset` | Clear conversation history (does not affect memory or session files) |
| `/compact` | Compress conversation history while preserving context |
| `/plan` | Next message outputs only a structured plan, no implementation |
| `/batch <file>` | Run prompts from file sequentially (one per line, ignores comments with `#`) |
| `/save [name]` | Save current conversation to a named session |
| `/load [name]` | Load a previously saved named session |
| `/model [flash\|pro]` | Switch between models (flash for speed, pro for thoroughness) |
| `/memory` | Display all loaded context files (instructions.md, memory.md, context.md) |
| `/clear` | Clear the terminal screen |
| `/help` | List all slash commands |
| `/exit` | Exit the interactive session |

Also exits on `exit`, `quit`, or empty input.

### Command history

Up-arrow / down-arrow recalls previous prompts using GNU readline (via `read -er`). History is automatically persisted to `~/.ai-os/sessions/interactive_history` across sessions, allowing you to recall prompts even after exiting the program. This readline history is isolated and does not pollute your main shell history. Slash commands are also saved to history. Tab-completion for slash commands is available: type `/` and press Tab to complete or list matching commands.

## Environment variables

- `DEEPSEEK_API_KEY` (required) — API key for DeepSeek. Crashes if not set.
- `AI_TEMPERATURE` (optional, default `0`) — temperature for model sampling. Accepts any numeric value.
- `AI_CONTEXT_LIMIT` (optional, default `6000`) — maximum estimated token count for session history. When exceeded, the oldest 50% of turns are compressed into a summary via API call.

## File layout

```
ai                                      # single executable bash script (the entire router)
ds.md                                   # project-level context (auto-loaded if present in CWD or parents)
~/.ai-os/instructions.md                # user-wide behaviour instructions (auto-created on first run)
~/.ai-os/memory.md                      # accumulated memory/facts (auto-created on first run)
~/.ai-os/context.md                     # active context (optional; legacy: context/global.md)
~/.ai-os/sessions/history.json          # session mode history (JSON array of objects)
~/.ai-os/sessions/interactive_history   # readline history for interactive mode (up-arrow recall)
~/.ai-os/sessions/named/<name>.json     # named sessions saved with /save
~/.ai-os/tmp/last_output.json           # last raw API response (for debugging; 600 perms)
~/.ai-os/tmp/last_stream.txt            # last streamed response content (assembled tokens)
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

Real token counts (`prompt_tokens`, `completion_tokens`) are read from `.usage` in blocking API responses and shown in `/status`. In streaming mode these are set to 0 since DeepSeek does not reliably include usage in SSE chunks.

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
  → stream tokens to stdout (SSE) or print assembled response
```

## Memory system design intent

`~/.ai-os/context/global.md` is a human-editable markdown file. It is injected verbatim as the system prompt prefix on every call. Keep it short (< 2 KB) — it consumes context on every request.

Structured sections to maintain:
- `## User preferences` — stable facts about the user.
- `## Projects` — current work context.
- `## Rules` — hard constraints for the assistant.

Memory write-back is not currently implemented. To add: only trigger on explicit flag (e.g., `--remember "..."`), not via regex heuristics on the response.

## Security model

- **`umask 077`** set at startup — all created files get 600, directories get 700.
- **Temp files** written to `~/.ai-os/tmp/` (not `/tmp`) to prevent symlink attacks in world-writable `/tmp`.
- **API key** passed to curl via `--config <(printf ...)` (process substitution) so it never appears in `curl`'s argv / `ps aux` output.
- **`/save` and `/load` names** sanitized to `[a-zA-Z0-9_-]` only — path traversal characters stripped.
- **`/batch` file paths** restricted to within `$HOME` — prevents reading system files as prompts.

## Constraints

- No external dependencies beyond `curl`, `jq`, and standard POSIX tools.
- No Python/Node/Go at runtime (those are acceptable for a future rewrite, not the current bash version).
- `DEEPSEEK_API_KEY` is the only required env var.
- The script must run identically on macOS and Linux.
