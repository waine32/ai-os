# Architektúra AI-OS

## Prehľad

Jeden bash skript (`ai`) volaný priamo z terminálu. Žiadne frameworky, žiadny runtime — len `bash`, `curl`, `jq`. Cieľ: deterministický, transparentný pipeline.

```
user → ai [model] [flags] [prompt]
          │
          ├── stateless  → ask() → stdout
          ├── session    → load_session → ask() → save_session
          └── interactive → slučka: read → parse → ask/run_agentic → print
```

---

## Kontext vrstvy

`_build_system_prompt()` zostavuje system prompt z 8 vrstiev (od najvšeobecnejšej):

| # | Súbor | Načítanie |
|---|-------|-----------|
| 1 | `~/.ai-os/instructions.md` | vždy |
| 2 | `~/.ai-os/memory.md` | vždy |
| 3 | `~/.ai-os/context.md` | vždy (fallback: `context/global.md`) |
| 4 | `<workspace>/ds.md` | ak je nastavený `~/.ai-os/workspace` |
| 5 | `<workspace>/memory/instructions.md` | ak workspace |
| 6 | `<workspace>/memory/memory.md` | ak workspace |
| 7 | `<workspace>/memory/context.md` | ak workspace |
| 8 | `<projekt>/ds.md` | CWD walk nahor + fallback `~/.ai-os/current-project` |

Vrstva 8 sa nikdy nenačíta dvakrát (dedup check pri CWD walk vs current-project).

---

## Tok dát

### Stateless mód
```
PROMPT → MESSAGES=[{user, PROMPT}] → ask(stream=true) → stdout
```

### Session mód
```
load_session → MESSAGES=[history + {user, PROMPT}]
→ ask(stream=true) → stdout
→ save_session(PROMPT, OUTPUT)
```
Komprimácia: ak `estimate_tokens(history) > AI_CONTEXT_LIMIT`, `compress_history()` zhrnie starší 50% do `{role:summary}`.

### Interaktívny mód
```
while read INPUT:
  "!cmd"     → eval, no API call
  "/cmd"     → slash handler, no API call
  text       → CONV += {user, INPUT}
               flash: run_interactive_flash(CONV)
               pro:   run_agentic(CONV)
               CONV += {assistant, OUTPUT}
```

---

## Kľúčové funkcie

### `ask(messages, stream, tools?)`
- `stream=true`: SSE, tokeny idú priamo na stdout, výsledok sa uloží do `~/.ai-os/tmp/last_stream.txt`
- `stream=false`: blocking JSON, obsah cez stdout + `last_output.json`
- API key nikdy v argv — cez `--config <(printf 'header = "Authorization: Bearer %s"\n' "$KEY")`

### `run_agentic(messages)` — pro model
Tool-call loop (max 5 delegácií + 10 iterácií):
```
loop:
  ask(messages, stream=false, PRO_TOOLS)
  finish_reason == "tool_calls"?
    delegate_to_flash → ask(flash_messages, stream=true)
    run_shell         → _exec_shell_tool → Y/N → bash -c
  else:
    printf final_content; return
```

### `run_interactive_flash(messages)` — flash v interaktívnom móde
Rovnaká štruktúra ako `run_agentic`, ale:
- Používa len `SHELL_TOOL` (nie `delegate_to_flash`)
- Blocking mode (nie streaming) — trade-off za tool support

### `_exec_shell_tool(cmd, reason)`
Zobrazí príkaz, vypýta `[y/N]` zo stdin, spustí cez `bash -c`. Default = N (bezpečný default).

---

## Kedy `run_agentic` vs `run_interactive_flash`

| | `run_agentic` | `run_interactive_flash` |
|---|---|---|
| Model | pro | flash |
| Mód | stateless + interactive | interactive only |
| Tools | `delegate_to_flash` + `run_shell` | `run_shell` |
| Output | blocking, print na konci | blocking, print na konci |

Flash v stateless/session móde volá `ask(stream=true)` priamo — bez tool loopu.

---

## Bezpečnostný model

| Mechanizmus | Implementácia |
|-------------|---------------|
| Súborové práva | `umask 077` → 600/700 |
| API key | `--config <(printf ...)` — nie v `ps aux` argv |
| Dočasné súbory | `~/.ai-os/tmp/` — nie `/tmp` (symlink attack) |
| `/save`/`/load` | sanitizácia na `[a-zA-Z0-9_-]` |
| `/batch` | len súbory v `$HOME` |
| `run_shell` | potvrdenie Y/N pred každým príkazom |
| `current-project` | musí byť v `$HOME` |

---

## Štruktúra súborov `~/.ai-os/`

```
~/.ai-os/
├── instructions.md          # globálne pravidlá správania
├── memory.md                # globálna pamäť
├── context.md               # globálny aktívny kontext
├── workspace                # cesta k workspace (jeden riadok)
├── current-project          # cesta k aktívnemu projektu (jeden riadok)
├── sessions/
│   ├── history.json         # session história (JSON array)
│   ├── interactive_history  # readline história
│   └── named/<name>.json    # named sessions (/save, /load)
└── tmp/
    ├── last_output.json     # posledná raw API odpoveď
    └── last_stream.txt      # posledný zostavený obsah odpovede
```
