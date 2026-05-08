# AI-OS — Claude Code inštrukcie

Minimalistický bash CLI router pre DeepSeek API. Jedno-skriptový projekt — `ai` je celý router.
Bez frameworkov, bez orchestračných vrstiev — len `curl` + `jq`.

Syntax check: `bash -n ai` | Testy: `bats tests/ai.bats`

---

## ds.md — inicializačný súbor, nie dokumentácia

`ds.md` je **projektová operačná pamäť** — číta ho model, nie človek.

- **`<projekt>/ds.md`** — načíta sa pri štarte podľa `~/.ai-os/current-project` (alebo CWD walk). Obsahuje architektúru, konvencie, aktuálne úlohy — čo model potrebuje na okamžitú prácu v kontexte.
- **`<workspace>/ds.md`** — načíta sa vždy pri štarte. Meta-pokyny o workspace súboroch.

Patrí tam: architektúra, konvencie, aktuálne rozhodnutia, čo model musí vedieť.
Nepatrí tam: docs pre používateľov (→ README), changelog, vysvetlenia pre ľudí.

Kontext vrstva (od najvšeobecnejšej): `~/.ai-os/instructions.md` → `memory.md` → `context.md` → `<ws>/ds.md` → `<ws>/memory/*` → `<projekt>/ds.md`. Implementácia: `_build_system_prompt()` v `ai`.

---

## Kód — konvencie a obmedzenia

**Bash špecifiká:**
- `set -euo pipefail` je aktívne — každá zmena musí byť odolná voči chybám
- Premenné v interaktívnej slučke (mimo funkcií) musia mať prefix `local_*` namiesto `local`
- Všetky dočasné súbory idú do `~/.ai-os/tmp/`, **nie** `/tmp` (symlink attack prevention)
- `umask 077` — nové súbory sú 600, adresáre 700

**Čo sa nesmie zmeniť:**
- Formát `history.json` — existuje migrácia z `history.txt`, spätná kompatibilita je kritická
- API key nikdy v `curl` argv — vždy cez `--config <(printf 'header = "Authorization: Bearer %s"\n' "$API_KEY")`
- Sanitizácia `/save`/`/load` názvov (`[a-zA-Z0-9_-]`) a obmedzenie `/batch` na `$HOME` — bezpečnostné mechanizmy

---

## Testovacia architektúra

- Mock `curl` je v `$MOCK_BIN/curl` (prepíše PATH v `setup_file`) — vracia `MOCK_CURL_RESPONSE` alebo default JSON
- `stream=true` → SSE (`data: {...}` riadky), `stream=false` → blocking JSON — mocky musia zodpovedať
- `bats run` zachytáva **aj stderr** do `$output` — testy na pro móde nesmú používať `[ "$output" = "..." ]` (kvôli `[pro...]` prefix), len `[[ "$output" == *"..."* ]]`
- Confirmačné `read` príkazy čítajú zo **stdin** (nie `/dev/tty`) — testy môžu pipe-ovať odpovede

---

## Rozšírenie — vzory

**Nový slash príkaz:**
1. Pridaj `case` vetvu do interaktívnej slučky (`ai`, ~riadok 660+)
2. Pridaj do `cmds=()` v `__ai_tab`
3. Pridaj riadok do `/help` bloku

**Nový model tool:**
1. Definuj JSON v `SHELL_TOOL` / nová premenná (za `FLASH_TOOLS`)
2. Pridaj handler (`elif [[ "$func_name" == "..." ]]`) do `run_agentic()` aj `run_interactive_flash()`
3. Merge do `PRO_TOOLS` ak má byť dostupný pre pro
