# Audit AI-OS dokumentácie

Referenčný zoznam pre kontrolu konzistencie dokumentácie, kódu a testov.

---

## Čo kontrolovať

### 1. Konzistencia kód ↔ docs
- `architecture.md` kontext vrstvy = poradie v `_build_system_prompt()` (8 vrstiev)
- `roadmap.md` implementované = funkcie skutočne prítomné v `ai` skripte
- `ux-decisions.md` rozhodnutia = stav v aktuálnom kóde (napr. stdin vs /dev/tty)

### 2. Testy
- Každá nová funkcia má test v `tests/ai.bats`
- `bats tests/ai.bats` prechádza na čisto (bez skipov)
- Mock curl (`function curl()`) pokrýva nové API volania

### 3. Bezpečnostný model
- API key sa nikdy neobjaví v `ps aux` (curl cez `--config <(printf ...)`)
- Temporárne súbory v `~/.ai-os/tmp/`, nie `/tmp`
- `umask 077` aktívny pred tvorbou súborov
- Sanitizácia pri `/save`/`/load` (len `[a-zA-Z0-9_-]`)
- `/batch` len pre súbory v `$HOME`
- `current-project` musí byť v `$HOME`

### 4. Príklady v dokumentácii
- Cesty (`~/.ai-os/`, `ds.md`) zodpovedajú skutočnej štruktúre
- Slash príkazy v príkladoch fungujú (overenie v `ai flash -i`)

---

## Riziká

| Riziko | Príznaky | Kde skontrolovať |
|--------|----------|------------------|
| Drift kód↔docs | docs popisuje správanie ktoré kód nemá | porovnaj `_build_system_prompt()` s `architecture.md` |
| Zavádzajúce príklady | príkazy v docs nefungujú alebo majú iný výstup | spusti v `ai flash -i` |
| Neúplný security model | nová funkcia obchádza bezpečnostné mechanizmy | audit každého nového `eval`, `bash -c`, zápisu súborov |
| history.json regresie | zmena formátu rozbije `/save`/`/load` a kompresiiu | skontroluj `save_session`/`load_session`/`compress_history` |
| Nový `read` bez stdin fallback | confirmácia nefunguje v testoch (pipe) | všetky `read -r` musia mať `|| var="..."` fallback |

---

## Čo sa NESMIE meniť

- **Formát `history.json`**: `[{"role": "user"|"assistant"|"summary", "content": "..."}]` — zmena rozbije existujúce sessions
- **API key metóda**: vždy `--config <(printf 'header = "Authorization: Bearer %s"\n' "$KEY")` — nikdy `-H` v argv
- **`run_shell` Y/N default = N**: bezpečný default, zmeniť len na explicitnú požiadavku
- **`umask 077`**: na začiatku skriptu, nesmie sa odstraniť
- **Sanitizácia session mien**: `[a-zA-Z0-9_-]` — path traversal prevencia
- **`/batch` obmedzenie na `$HOME`**: ochrana pred načítaním citlivých súborov mimo home

---

## Postup auditu

```bash
# 1. Syntax check
bash -n ai

# 2. Testy
bats tests/ai.bats

# 3. API key bezpečnosť
grep -n 'curl' ai | grep -v 'config <(' | grep -i 'bearer\|api.key\|authorization'
# → výsledok musí byť prázdny

# 4. Temporárne súbory
grep -n '/tmp/' ai
# → výsledok musí byť prázdny (len ~/.ai-os/tmp/)

# 5. Konzistencia vrstiev
grep -c 'ws_\|proj_ds\|instructions\|memory.md\|context.md' ai
# → porovnaj s architecture.md "Kontext vrstvy" tabuľkou
```
