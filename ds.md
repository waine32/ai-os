# AI-OS

Bash CLI router for DeepSeek API. No frameworks, just `curl` + `jq`.
Key files: `ai` (main script), `tests/ai.bats`, `ds.md`.
Run tests: `bats tests/ai.bats`
Syntax check: `bash -n ai`

---

## Project overview

AI-OS is a minimal deterministic bash CLI router that dispatches prompts to DeepSeek models via direct API calls. No frameworks, no orchestration layers — just `curl` + `jq`.

**Core principle:** same input → same output. Low temperature, no hidden middleware, fully transparent request pipeline.

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
| `ds.md` | `./ds.md` (CWD walk) | Project-level instructions — discovered by walking up from CWD |

`instructions.md` and `memory.md` are auto-created with defaults on first run if missing. `ds.md` is optional and project-specific. The `/memory` slash command shows all loaded context files.

## Output streaming

Responses stream token-by-token via SSE (`"stream": true`). Output starts printing immediately.

- User-facing calls (stateless, session, interactive) always stream.
- Internal calls (`compress_history` summarization) use blocking mode to avoid terminal noise.
- Assembled response is saved to `~/.ai-os/tmp/last_stream.txt` after each streaming call.

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
| `/status` | Show model name, temperature, message count, estimated token count, last prompt/completion token counts, memory file size, and session delegation count |
| `/reset` | Clear conversation history (does not affect memory or session files) |
| `/compact` | Compress conversation history while preserving context |
| `/plan` | Next message outputs only a structured plan, no implementation |
| `/batch <file>` | Run prompts from file sequentially (one per line, ignores comments with `#`) |
| `/save [name]` | Save current conversation to a named session |
| `/load [name]` | Load a previously saved named session |
| `/model [flash\|pro]` | Switch between models (flash for speed, pro for thoroughness). Pro automatically delegates subtasks to Flash via tool calls. |
| `/memory` | Display contents of loaded context files (instructions, memory, context) |
| `/project [set <path>\|clear]` | Show, set, or clear the active project for `ds.md` fallback loading |
| `/clear` | Clear the terminal screen |
| `/help` | List all slash commands |
| `/exit` | Exit the interactive session |

Also exits on `exit`, `quit`, or empty input.

## Environment variables

- `DEEPSEEK_API_KEY` (required) — API key for DeepSeek. Crashes if not set.
- `AI_TEMPERATURE` (optional, default `0`) — temperature for model sampling.
- `AI_CONTEXT_LIMIT` (optional, default `6000`) — max estimated tokens for session history before compression.

## File layout

```
ai                                      # single executable bash script (the entire router)
setup.sh                                # first-time setup script (idempotent)
ds.md                                   # project-level context (this file)
~/.ai-os/instructions.md                # user-wide behaviour instructions (auto-created on first run)
~/.ai-os/memory.md                      # accumulated memory/facts (auto-created on first run)
~/.ai-os/context.md                     # active context (optional; legacy: context/global.md)
~/.ai-os/sessions/history.json          # session mode history (JSON array of objects)
~/.ai-os/sessions/interactive_history   # readline history for interactive mode (up-arrow recall)
~/.ai-os/sessions/named/<name>.json     # named sessions saved with /save
~/.ai-os/tmp/last_output.json           # last raw API response (for debugging; 600 perms)
~/.ai-os/tmp/last_stream.txt            # last streamed response content (assembled tokens)
~/.ai-os/current-project                # last known git project root (written by chpwd hook)
```

## Session history compression

When session history exceeds `AI_CONTEXT_LIMIT`, the oldest 50% of turns are summarized into a `{"role":"summary"}` entry and the messages array is trimmed. Failure degrades gracefully (full history used).

## Pro→Flash delegation

When running with `ai pro`, a `delegate_to_flash` tool is exposed to the model. Pro offloads straightforward subtasks (lookups, formatting, drafting) to Flash. Flash streams its response; Pro synthesizes the final answer (blocking). Max 5 delegations per turn; Flash prompt capped at 10 000 chars.

Status markers on stderr: `[pro...]` → `[→ flash: <reason>]` → `[← pro]`.

### Project tracking (shell hook)

A `chpwd` zsh hook writes the git root to `~/.ai-os/current-project` on every `cd` into a project with `ds.md`. `_build_system_prompt()` reads this as a fallback so `ds.md` loads correctly even when `ai` is run outside the project directory.

## Security model

- **`umask 077`** — all created files 600, directories 700.
- **Temp files** in `~/.ai-os/tmp/` — not `/tmp` (symlink attack prevention).
- **API key** via `--config <(printf ...)` — never in `curl` argv / `ps aux`.
- **`/save`/`/load` names** sanitized to `[a-zA-Z0-9_-]`.
- **`/batch` paths** restricted to `$HOME`.
- **ESC / Ctrl+C during streaming** — interrupts turn, rolls back unanswered message from CONV, stays in session.

## Constraints

- No external dependencies beyond `curl`, `jq`, and standard POSIX tools.
- `DEEPSEEK_API_KEY` is the only required env var.
- Must run identically on macOS and Linux.
