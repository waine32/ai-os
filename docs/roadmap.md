# Roadmap

## Implementované

| Funkcia | Popis |
|---------|-------|
| Session history JSON | História uložená ako JSON array, migrácia z legacy `.txt` |
| Automatická komprimácia | Keď história presiahne `AI_CONTEXT_LIMIT`, starší 50% sa zhrnie do `summary` |
| CWD kontext walk | `ds.md` sa hľadá rekurzívne nahor od CWD |
| Workspace system | `/workspace` — globálne pamäťové súbory v jednom adresári |
| `/project new/list/set/clear` | Správa projektov v workspace, tab cycling, confirmation na clear |
| `!` shell passthrough | `!cmd` — model obídený, žiadne tokeny |
| `run_shell` tool | Model navrhne príkaz, user potvrdí Y/N, spustí sa |
| `run_interactive_flash()` | Flash tool-call loop (blocking) |
| Pro→Flash delegácia | `delegate_to_flash` tool — pro offloaduje subtasky na flash |
| `/compact` | Manuálna komprimácia konverzácie |
| ESC interrupt | ESC počas streamovania preruší a rollback-ne posledný user turn |
| Warp OSC 133 | Shell integration pre Warp terminal |
| Named sessions | `/save [name]` / `/load [name]` |
| `/batch` | Sekvenčné spúšťanie promptov zo súboru |

---

## Plánované

### Krátkodobé
- **`/memory add <text>`** — rýchly append do `~/.ai-os/memory.md` bez otvárania editora
- **`/memory edit [kľúč]`** — otvoriť konkrétny súbor v `$EDITOR`; kľúče: `instructions`, `memory`, `context`, `ws`, `proj`
- **`/memory` rozšírenie** — zobraziť všetky vrstvy (global + workspace + projekt), nie len globálne

### Strednodobé
- **`/history`** — prezeranie a vyhľadávanie v session histórii (`~/.ai-os/sessions/history.json`)
- **Perzistentná história pre pro** — interaktívny pro mód momentálne neukladá históriu medzi sessionmi
- **Multi-model fallback** — ak primárny provider zlyhá, automaticky skúsiť záložný

### Dlhodobé / nápady
- **MCP-like tool registry** — konfigurovateľné externé nástroje (nie hardkódované v skripte)
- **`/alias`** — vlastné skrátené príkazy
- **`fzf` integrácia** — fuzzy search v interaktívnej histórii
- **Web UI wrapper** — tenký HTTP wrapper okolo `ai` pre browserové použitie

---

## Zámer projektu

AI-OS zostáva **single-file bash**. Každé rozšírenie musí:
- Fungovať bez nových závislostí (len `curl`, `jq`, bash)
- Bežať identicky na macOS aj Linux
- Mať testy v `tests/ai.bats`
