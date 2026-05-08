# AI-OS

A minimal bash CLI that routes prompts to DeepSeek AI models via direct API calls. No frameworks, no dependencies beyond curl and jq. Single executable `ai` at repo root.

## Requirements

- `curl`
- `jq`
- `git`
- `DEEPSEEK_API_KEY` environment variable

## Installation

Clone the repository:

```bash
git clone <repo-url>
cd ai-os
```

Run the setup script:

```bash
./setup.sh
```

Or manually add the repo to your PATH:

```bash
export PATH="$PATH:/path/to/ai-os"
```

## Usage

### Stateless

Execute a prompt without saving history:

```bash
ai flash "What is the capital of France?"
ai pro "Explain quantum computing in detail"
```

### Session mode

Append prompts and responses to a persistent history file:

```bash
ai flash --session "First question"
ai flash --session "Follow-up question"
```

Responses are stored in `~/.ai-os/sessions/history.json`.

### Interactive mode

Start an interactive conversation:

```bash
ai flash -i
ai flash --interactive
```

- Up/down arrow keys recall previous prompts
- ESC interrupts the current streaming response without exiting
- History is persisted to `~/.ai-os/sessions/interactive_history`

### Pipe input

Pass text via stdin:

```bash
echo "text to analyze" | ai flash
cat file.txt | ai flash "summarize:"
```

## Models

- **flash** = deepseek-v4-flash (fast, cost-effective)
- **pro** = deepseek-v4-pro (thorough, extended reasoning)

Pro is recommended for analysis; Flash for implementation. Efficient workflow: analysis (Pro) → implementation (Flash) → final review (Pro).

Pro automatically delegates suitable subtasks to Flash via tool calls. Status markers in output:

```
[pro...]      — Pro thinking
[→ flash: reason]  — Delegating to Flash
[← pro]       — Returning to Pro
```

## Slash commands

Available in interactive mode:

| Command | Description |
|---------|-------------|
| `/status` | Show current model, temperature, message count, token estimates, active delegations |
| `/reset` | Clear conversation history |
| `/compact` | Compress conversation history |
| `/plan` | Output only a structured plan for the next message |
| `/batch <file>` | Run prompts from file (one per line; lines starting with # are ignored) |
| `/save [name]` | Save conversation to a named session |
| `/load [name]` | Load a named session |
| `/model [flash\|pro]` | Switch models mid-conversation |
| `/memory` | Show loaded context files |
| `/project [set <path>\|clear]` | Show, set, or clear the active project for ds.md loading |
| `/clear` | Clear terminal screen |
| `/help` | List all commands |
| `/exit` | Exit interactive mode |

## Context files

A layered system assembles context into the system prompt (loaded in order):

1. `~/.ai-os/instructions.md` — Base behavior, language, and tone (auto-created on first run)
2. `~/.ai-os/memory.md` — Accumulated facts and preferences (auto-created on first run)
3. `~/.ai-os/context.md` — Active context (optional)
4. `./ds.md` — Project-level instructions (discovered by walking up from CWD)

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DEEPSEEK_API_KEY` | API key for DeepSeek (required) | — |
| `AI_TEMPERATURE` | Model temperature (0–1) | 0 |
| `AI_CONTEXT_LIMIT` | Max tokens before auto-compressing session history | 6000 |

## Shell hook

The setup script offers to install a zsh hook that tracks your current project. When you `cd` into a git repository containing a `ds.md` file, the hook writes the project path to `~/.ai-os/current-project`. This ensures `ds.md` is always loaded even when `ai` is invoked from outside the project directory.

## File layout

```
~/.ai-os/
  instructions.md
  memory.md
  context.md
  sessions/
    history.json
    interactive_history
    named/
      <name>.json
  tmp/
    last_output.json
    last_stream.txt
  current-project
```
