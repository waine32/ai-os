# AI-OS

Minimalistický bash CLI router pre DeepSeek API. Interaktívny agent s tool layer-om, context hierarchiou a approval loop-om — v jedinom bash skripte bez frameworkov.

```bash
ai flash "Vysvetli git rebase"
ai flash -i          # interaktívny mód
ai pro "Refaktoruj:  $(cat main.py)"
```

---

## Požiadavky

- **bash 5+** (macOS: `brew install bash`)
- **jq** (`brew install jq`)
- **curl**
- **DeepSeek API kľúč** — [platform.deepseek.com](https://platform.deepseek.com)

---

## Inštalácia

```bash
git clone https://github.com/waine32/clipboard-intelligence ai-os
cd ai-os
chmod +x ai
./setup.sh                         # vytvorí ~/.ai-os/ štruktúru
export DEEPSEEK_API_KEY="sk-..."   # pridaj do ~/.zshrc
```

Voliteľne pridaj do `PATH`:
```bash
export PATH="$PATH:/path/to/ai-os"
```

---

## Použitie

```bash
ai flash "prompt"           # jednorazový prompt (streaming)
ai pro   "prompt"           # pro model (agentic, deleguje na flash)
ai flash -i                 # interaktívny mód
ai flash -s "prompt"        # session mód (história sa ukladá)
echo "text" | ai flash      # pipe input
cat file.txt | ai flash "zhrň:"
```

---

## Modely

| Model | Príkaz | Popis |
|-------|--------|-------|
| **Flash** | `ai flash` | Rýchly, cost-effective. Streaming výstup. |
| **Pro** | `ai pro` | Agentic loop — deleguje subtasky na Flash, volá shell nástroje. |

Pro označuje svoju prácu v stderr:
```
[pro...]            — Pro rozmýšľa
[→ flash: dôvod]   — Deleguje na Flash
[← pro]            — Vrátil sa z Flash
[pro: concluding…] — Finálna odpoveď
```

---

## Interaktívny mód — príkazy

```bash
ai flash -i
```

| Príkaz | Popis |
|--------|-------|
| `!<príkaz>` | Shell passthrough — model obídený, tokeny ušetrené |
| `/status` | Model, teplota, správy, tokeny, pamäť |
| `/model [flash\|pro]` | Prepne model |
| `/auto [on\|safe\|off]` | Approval loop pre shell príkazy |
| `/plan` | Ďalšia správa → výstup ako štruktúrovaný plán |
| `/plan <súbor>` | Načíta súbor ako vstup pre plán |
| `/plan save [cesta]` | Uloží posledný plán do súboru, nastaví ho ako aktívny |
| `/plan load <cesta>` | Načíta existujúci plán ako aktívny kontext |
| `/plan clear` | Zruší aktívny plán |
| `/plan show` | Zobrazí obsah aktívneho plánu |
| `/compact` | Komprimuje históriu konverzácie |
| `/reset` | Vymaže históriu session |
| `/save [meno]` | Uloží konverzáciu |
| `/load [meno]` | Načíta uloženú konverzáciu |
| `/batch <súbor>` | Spustí prompty zo súboru sekvenčne |
| `/memory` | Zobrazí všetky kontext vrstvy |
| `/memory add <text>` | Rýchly zápis do `~/.ai-os/memory.md` |
| `/memory edit [kľúč]` | Otvorí kontext súbor v editore |
| `/workspace <cesta>` | Nastaví workspace |
| `/project [sub]` | Správa projektov (`new`, `list`, `set`, `clear`) |
| `/clear` | Vymaže obrazovku |
| `/help` | Zoznam všetkých príkazov |
| `/exit` | Ukončí session |

Klávesy: **↑↓** história · **ESC** preruší odpoveď · **Tab** dopĺňa slash príkazy

---

## Tool layer

V interaktívnom móde môže model volať tieto nástroje:

| Nástroj | Popis | Approval |
|---------|-------|----------|
| `read_file(path, offset?, limit?)` | Číta súbor | Automatické |
| `write_file(path, content)` | Zapíše súbor — zobrazí diff pred potvrdením | Vždy pýta [y/N] |
| `grep_search(pattern, path?, options?)` | Hľadá vzor v súboroch | Automatické |
| `git_info(type)` | Git status / diff / log / branch | Automatické |
| `run_shell(command)` | Ľubovoľný shell príkaz | Podľa `/auto` módu |
| `save_plan(content, name)` | Uloží plán do `~/.ai-os/plans/<name>.md` a nastaví ho ako aktívny | Automatické (pre-approved) |
| `delegate_to_flash(prompt)` | Pro → Flash delegácia | Automatické (len Pro) |

Flash interactive dostane: `run_shell + read_file + write_file + grep_search + git_info + save_plan`  
Pro dostane všetko vrátane `delegate_to_flash`.

---

## Approval loop — `/auto`

```bash
/auto off    # default: každý run_shell pýta potvrdenie [y/N]
/auto safe   # read-only príkazy (cat, ls, git diff...) sú auto; ostatné pýtajú
/auto on     # všetky run_shell príkazy sú auto (bez potvrdenia)
```

`write_file` **vždy** pýta potvrdenie bez ohľadu na `/auto` mód.

Bezpečné príkazy (pre `safe` mód): `cat`, `ls`, `find`, `grep`, `head`, `tail`, `git status`, `git log`, `git diff`, `git branch`, `git show`, `wc`, `du`, `df`, `which`, `file`, `stat`, `date`, `pwd`.

---

## Context hierarchia

Systémový prompt sa zostavuje z týchto vrstiev (od najvšeobecnejšej):

```
~/.ai-os/instructions.md           # Globálne pokyny (jazyk, rola, správanie)
~/.ai-os/memory.md                 # Globálna pamäť
~/.ai-os/context.md                # Globálny kontext (stack, prostredie)
<workspace>/ds.md                  # Workspace meta-info
<workspace>/memory/instructions.md # Workspace pokyny
<workspace>/memory/memory.md       # Workspace pamäť
<workspace>/memory/context.md      # Workspace kontext
<projekt>/ds.md                    # Projektové pokyny (CWD walk nahor)
```

**Runtime kontext** — pri každej správe sa automaticky injektuje:
```
[Runtime Context]
CWD: /Users/martinzuzic/myproject
Git: branch=main, 3 zmenených
```

Model vždy vie kde sa nachádza a aký je stav repozitára.

---

## UX

**Thinking indicator** — kým model pracuje, rotuje spinner (`|/-\`) na stderr. V Pro móde sa spinner reštartuje pri každom API volání aj po odmietnutí [y/N].

**Diff viewer** — pred `write_file` potvrdením sa zobrazí `diff -u` (zelené pridané, červené odobrané riadky). Pre nový súbor sa zobrazí veľkosť v bajtoch.

**Farby** — UI výstupy sú farebne odlíšené: cyan = cesty, žltá = príkazy, zelená = úspech, červená = chyby, dim = meta-prefixe. Farby sa automaticky vypnú keď stderr nie je TTY alebo je nastavená `NO_COLOR`.

**□ prefix** — každý riadok odpovede modelu začína `□` (biely štvorček). Prvý stĺpec slúži ako vizuálna lišta pre odlíšenie výstupu od UI elementov. V neinteraktívnom móde (piping) `□` chýba.

**Aktívny plán** — model (aj používateľ cez `/plan save`) môže uložiť plán do `~/.ai-os/plans/`. Cesta sa automaticky injektuje do runtime kontextu každej správy, takže model vie kde plán nájsť aj po reštarte session.

---

## Konfiguračné súbory

```
~/.ai-os/
├── instructions.md       # Rola, jazyk, správanie (auto-vytvorené)
├── memory.md             # Pamäť naprieč session (auto-vytvorené)
├── context.md            # Kontext (stack, prostredie)
├── workspace             # Pointer na aktívny workspace
├── current-project       # Pointer na aktívny projekt (z shell hooku)
├── current-plan          # Pointer na aktívny plán (nastavuje save_plan / /plan save)
├── plans/
│   └── <name>.md         # Plány uložené modelom cez save_plan alebo /plan save
├── sessions/
│   ├── history.json      # Session história
│   ├── interactive_history  # Readline história
│   └── named/            # Named sessions (/save)
└── tmp/
    ├── last_output.json  # Posledná raw API odpoveď
    └── last_stream.txt   # Posledný výstup modelu
```

Nastavenie: `ai flash -i` → `/memory edit instructions`

---

## Environment variables

| Premenná | Popis | Default |
|----------|-------|---------|
| `DEEPSEEK_API_KEY` | API kľúč (povinný) | — |
| `AI_TEMPERATURE` | Teplota modelu (0–1) | `0` |
| `AI_CONTEXT_LIMIT` | Max tokeny pred auto-kompresiou | `6000` |
| `NO_COLOR` | Vypne ANSI farby (štandard no-color.org) | — |

---

## Testy

```bash
bats tests/ai.bats    # 97+ testov
bash -n ai            # syntax check
```
