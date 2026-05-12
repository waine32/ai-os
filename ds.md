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

| Layer | File | Path | Role |
|-------|------|------|------|
| 1 | `instructions.md` | `~/.ai-os/instructions.md` | Base behaviour, language, tone — replaces hardcoded defaults |
| 2 | `memory.md` | `~/.ai-os/memory.md` | Accumulated facts, user preferences, project info |
| 3 | `context.md` | `~/.ai-os/context.md` | Current active context (legacy: `context/global.md`) |
| 4 | `ds.md` | `<workspace>/ds.md` | Workspace meta-guide — instructions on how to use workspace memory files |
| 5 | `instructions.md` | `<workspace>/memory/instructions.md` | Workspace-level behaviour rules |
| 6 | `memory.md` | `<workspace>/memory/memory.md` | Workspace-level accumulated facts |
| 7 | `context.md` | `<workspace>/memory/context.md` | Workspace-level active context |
| 8 | `ds.md` | `./ds.md` (CWD walk) | Project-level instructions — discovered by walking up from CWD |

Global files (1–3) are auto-created with defaults on first run if missing. Workspace files (4–7) are created by `/workspace`. Project `ds.md` (8) is optional and project-specific. The `/memory` slash command shows all loaded context files.

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

## Model tool support

In interactive mode, models have access to these tools:

| Tool | Flash | Pro | Approval |
|------|-------|-----|----------|
| `read_file` | ✓ | ✓ | auto |
| `write_file` | ✓ | ✓ | always [y/N] |
| `grep_search` | ✓ | ✓ | auto |
| `git_info` | ✓ | ✓ | auto |
| `run_shell` | ✓ | ✓ | per `/auto` mode |
| `save_plan` | ✓ | ✓ | auto (pre-approved) |
| `delegate_to_flash` | — | ✓ | auto |

`write_file` shows a `diff -u` before the [y/N] prompt. For new files it shows the byte count. Confirmation reads from `/dev/tty` when stderr is a TTY; defaults to `n` otherwise (pipes, tests).

## Shell passthrough

Any input starting with `!` is executed directly as a shell command — the model is bypassed entirely and no tokens are consumed.

```
!pwd          → prints current directory
!ls -la       → lists files
!git status   → any shell command
```

## Interactive mode slash commands

Entered as `/command` in the interactive prompt. No API call is made; handled locally. Tab completion cycles through slash commands; `/project ` (with space) cycles through its sub-commands.

| Command | Description |
|---------|-------------|
| `!<cmd>` | Execute shell command directly — model bypassed, no tokens used |
| `/status` | Show model name, temperature, message count, estimated token count, last prompt/completion token counts, memory file size, and session delegation count |
| `/reset` | Clear conversation history (does not affect memory or session files) |
| `/compact` | Compress conversation history while preserving context |
| `/plan` | Next message outputs only a structured plan, no implementation |
| `/plan save [path]` | Save last response as active plan to disk; sets `~/.ai-os/current-plan` pointer |
| `/plan load <path>` | Load an existing plan as active context; injects path into runtime context |
| `/plan clear` | Clear the active plan pointer |
| `/plan show` | Print the active plan file contents |
| `/batch <file>` | Run prompts from file sequentially (one per line, ignores comments with `#`) |
| `/save [name]` | Save current conversation to a named session |
| `/load [name]` | Load a previously saved named session |
| `/model [flash\|pro]` | Switch between models. Pro delegates subtasks to Flash and can run shell commands via `run_shell` tool. |
| `/memory` | Display contents of loaded context files (instructions, memory, context) |
| `/memory add <text>` | Quick append to `~/.ai-os/memory.md` |
| `/memory edit [key]` | Open a context file in `$EDITOR`; keys: `instructions`, `memory`, `context`, `ws`, `ws-instructions`, `ws-memory`, `ws-context`, `proj` |
| `/workspace [path]` | Set the Workspace folder. Creates `ds.md` (meta-guide) and `memory/` with `instructions.md`, `memory.md`, `context.md`. Offers interactive editing. |
| `/project` | Show current project and workspace |
| `/project new [name]` | Create a new project in the workspace with `ds.md` and `context.md`. Sets it as active. |
| `/project list` | List all project directories in the workspace (▶ marks active project) |
| `/project set <path>` | Set active project by path (must be within `$HOME` and contain `ds.md`) |
| `/project clear` | Clear active project (requires confirmation to prevent accidental removal) |
| `/auto [on\|safe\|off]` | Shell approval loop: `on` = always auto, `safe` = read-only auto, `off` = always ask |
| `/clear` | Clear the terminal screen |
| `/help` | List all slash commands |
| `/exit` | Exit the interactive session |

Also exits on `exit`, `quit`, or empty input.

## Environment variables

- `DEEPSEEK_API_KEY` (required) — API key for DeepSeek. Crashes if not set.
- `AI_TEMPERATURE` (optional, default `0`) — temperature for model sampling.
- `AI_CONTEXT_LIMIT` (optional, default `6000`) — max estimated tokens for session history before compression.
- `NO_COLOR` (optional) — disables ANSI colors when set (standard no-color.org).

## File layout

```
ai                                      # single executable bash script (the entire router)
setup.sh                                # first-time setup script (idempotent)
ds.md                                   # project-level context (this file)
~/.ai-os/instructions.md                # user-wide behaviour instructions (auto-created on first run)
~/.ai-os/memory.md                      # accumulated memory/facts (auto-created on first run)
~/.ai-os/context.md                     # active context (optional; legacy: context/global.md)
~/.ai-os/workspace                      # path to active workspace (set by /workspace command)
~/.ai-os/current-project                # path to active project (set by /project new|set)
~/.ai-os/current-plan                   # path to active plan (set by save_plan tool or /plan save)
~/.ai-os/plans/<name>.md               # plans saved by model (save_plan) or /plan save
~/.ai-os/sessions/history.json          # session mode history (JSON array of objects)
~/.ai-os/sessions/interactive_history   # readline history for interactive mode (up-arrow recall)
~/.ai-os/sessions/named/<name>.json     # named sessions saved with /save
~/.ai-os/tmp/last_output.json           # last raw API response (for debugging; 600 perms)
~/.ai-os/tmp/last_stream.txt            # last streamed/blocking response content
<workspace>/ds.md                       # workspace meta-guide (auto-created by /workspace)
<workspace>/memory/instructions.md      # workspace behaviour rules
<workspace>/memory/memory.md            # workspace accumulated facts
<workspace>/memory/context.md           # workspace active context
<workspace>/<project>/ds.md             # project description (created by /project new)
<workspace>/<project>/context.md        # project active context (created by /project new)
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
