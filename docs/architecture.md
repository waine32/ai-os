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
  _start_spinner
  ask(messages, stream=false, PRO_TOOLS)
  _stop_spinner
  finish_reason == "tool_calls"?
    delegate_to_flash → ask(flash_messages, stream=true)
    run_shell         → _exec_shell_tool → Y/N → bash -c
    save_plan         → _tool_save_plan → zápis + current-plan pointer
  else:
    _print_response final_content; return
```

### `run_interactive_flash(messages)` — flash v interaktívnom móde
Rovnaká štruktúra ako `run_agentic`, ale:
- Používa len `FLASH_INTERACTIVE_TOOLS` (nie `delegate_to_flash`)
- Blocking mode (nie streaming) — trade-off za tool support
- Výstup cez `_print_response` (pridáva `□` prefix v interactive mode)

### `_exec_shell_tool(cmd, reason)`
Zobrazí príkaz farebne, vypýta potvrdenie cez `_select_option` (arrow keys), spustí cez `bash -c`. Default = Áno (prvá možnosť). Podporuje "Vždy Áno (táto session)" — nastaví `SHELL_AUTO_APPROVE="on"`.

### `_tool_write_file(args)` — s diff viewerom
Pred `_select_option` promptom zobrazí:
- existujúci súbor: `diff -u` (max 80 riadkov) sfarbený cez `_colorize_diff()`
- nový súbor: `(nový súbor — N B)`
Potvrdenie cez `_select_option` s možnosťou "Áno a nezobrazovať diff nabudúce".

### `_tool_save_plan(args)` — pre-approved
Zapíše `content` do `~/.ai-os/plans/<name>.md`, aktualizuje `~/.ai-os/current-plan` pointer. Automaticky načítaný do `_runtime_context()` pri ďalšej správe.

### `_print_response(content)`
Stub (passthrough) v stateless/session móde. V interactive móde: `printf '%s\n' "$content" | sed "s/^/□ /"`. Prefixuje každý riadok bielym štvorčekom.

### `_colorize_diff()`
Pipeline filter: riadky `+` → zelené pozadie, `-` → červené pozadie, `@@` → cyan, `+++`/`---` → dim. Stub mimo interactive módu (no-op).

### Spinner helpers
`_start_spinner()` / `_stop_spinner()` — animovaný `|/-\` na stderr počas `ask()`. Stubs mimo interactive módu. `disown` po štarte zabraňuje "Terminated: 15" notifikáciám pri kill.

---

## Kedy `run_agentic` vs `run_interactive_flash`

| | `run_agentic` | `run_interactive_flash` |
|---|---|---|
| Model | pro | flash |
| Mód | stateless + interactive | interactive only |
| Tools | `delegate_to_flash` + všetky | všetky okrem `delegate_to_flash` |
| Output | `_print_response` (□ v interactive) | `_print_response` (□ vždy) |
| Spinner | `_start_spinner` okolo každého `ask()` | `_start_spinner` okolo každého `ask()` |

Flash v stateless/session móde volá `ask(stream=true)` priamo — bez tool loopu, bez `□` prefixu.

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
| `save_plan` meno | sanitizácia na `[a-zA-Z0-9_-]`, max 50 znakov |
| confirmácie v tooloch | `/dev/tty` s `[[ -t 2 ]]` guardom — default `n` v pipe/test kontexte |

---

## Štruktúra súborov `~/.ai-os/`

```
~/.ai-os/
├── instructions.md          # globálne pravidlá správania
├── memory.md                # globálna pamäť
├── context.md               # globálny aktívny kontext
├── workspace                # cesta k workspace (jeden riadok)
├── current-project          # cesta k aktívnemu projektu (jeden riadok)
├── current-plan             # cesta k aktívnemu plánu (jeden riadok)
├── plans/
│   └── <name>.md            # plány uložené modelom (save_plan) alebo /plan save
├── sessions/
│   ├── history.json         # session história (JSON array)
│   ├── interactive_history  # readline história
│   └── named/<name>.json    # named sessions (/save, /load)
└── tmp/
    ├── last_output.json     # posledná raw API odpoveď
    └── last_stream.txt      # posledný zostavený obsah odpovede
```
