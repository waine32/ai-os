# UX rozhodnutia

Zdokumentované rozhodnutia s alternatívami a dôvodmi. Slúži ako referencia pri refaktoroch.

---

## `!cmd` pre shell passthrough

**Rozhodnutie:** Vstup začínajúci `!` sa vykoná priamo ako shell príkaz.

**Alternatívy:** `/shell cmd`, `$cmd`, dedikovaný príkaz

**Dôvod:** `!` je zavedená bash konvencia (history expansion). Neblokuje slash namespace. Vizuálne odlíšené od `/` príkazov. Krátke na písanie.

---

## Blocking mode pre flash + tools

**Rozhodnutie:** `run_interactive_flash()` používa `ask(stream=false)` — žiadny token-by-token streaming.

**Alternatívy:** Parsovanie tool_calls z SSE streamu za behu

**Dôvod:** SSE stream pre tool_calls má inú štruktúru (`delta.tool_calls`) ako pre text (`delta.content`). Parsovanie by skomplikovalo `ask()`. Blocking mode je konzistentný s `run_agentic()` (pro tiež nestreamy pri tool calls). Trade-off: kratší wait time vs. zložitejší kód.

---

## `/dev/tty` pre tool confirmácie (s TTY guardom)

**Rozhodnutie:** Tool confirmácie (`_exec_shell_tool`, `_tool_write_file`) čítajú z `/dev/tty` keď `[[ -t 2 ]]`, inak default `n`.

**Alternatívy:** stdin — konzumovalo by promptový vstup; `/dev/tty` bez guardu — hanglo by v pipe/bats kontexte

**Dôvod:** Tool handlery sú volané z `$()` subshell kontextu — stdin je v tomto momente súbežne konzumovaný hlavnou slučkou. `/dev/tty` číta priamo z terminálu bez ohľadu na pipe stav. Guard `[[ -t 2 ]]` zachová automatické `n` v testoch a pipe kontexte kde terminál nie je dostupný.

---

## Confirmation len na `/project clear`, nie na `set`

**Rozhodnutie:** `/project clear` vyžaduje Y/N, `/project set <cesta>` nie.

**Alternatívy:** Confirmation na oboch, alebo na žiadnom

**Dôvod:** `set` je explicitná akcia s konkrétnou cestou — user vie čo robí. `clear` je jedným slovom, bez argumentu, ľahko omylom (napr. chcel `/clear`). Asymetria je zámerná.

---

## `local_*` prefix v interaktívnej slučke

**Rozhodnutie:** Premenné v case handlerov v interaktívnej slučke používajú prefix `local_*`.

**Alternatívy:** `local` keyword, žiadny prefix

**Dôvod:** `local` funguje len vo funkciách — interaktívna slučka je na top-level skriptu. Bez prefixu by sa premenné (napr. `name`, `path`) mohli kolidovať s globálnymi premennými. Prefix `local_` je vizuálna konvencia nahrádzajúca scoping.

---

## `--config <(printf ...)` pre API key

**Rozhodnutie:** API key sa posiela cez `curl --config <(process substitution)`.

**Alternatívy:** `-H "Authorization: Bearer $API_KEY"` priamo v príkaze

**Dôvod:** Argumenty `curl` sú viditeľné v `ps aux` pre každého používateľa na systéme. Process substitution (`<(printf ...)`) pošle header cez anonymný file descriptor — nikdy nie cez argv.

---

## Pro model: `max_delegations=5`, `max_iter=10`

**Rozhodnutie:** Pro tool-call loop má max 5 Flash delegácií a 10 celkových iterácií.

**Alternatívy:** Neobmedzené, iné limity

**Dôvod:** Ochrana pred nekonečnými slučkami (model sa zasekne v tool-call cykle). 5 delegácií pokryje realistické prípady (analýza → implementácia → review). Pri dosiahnutí limitu sa urobí finálne volanie bez nástrojov — graceful degradation.

---

## `/memory` zobrazuje všetky vrstvy

**Rozhodnutie:** `/memory` zobrazí global + workspace + projekt súbory, nie len globálne.

**Alternatívy:** Len globálne súbory (pôvodný stav)

**Dôvod:** Po pridaní workspace a projekt vrstiev sa `/memory` stalo neúplné — nezobrazovalo čo model skutočne dostal. Používateľ nemohol overiť či workspace/projekt kontext bol správne načítaný.

---

## Spinner (thinking indicator)

**Rozhodnutie:** `_start_spinner` / `_stop_spinner` okolo každého `ask()` volania v `run_agentic` aj `run_interactive_flash`.

**Alternatívy:** Statický `[pro...]` text, bez indikátora

**Dôvod:** Po odmietnutí [y/N] nebolo vidieť že model znovu pracuje. Spinner na stderr je súbežný s streamovaným výstupom na stdout — nezasahujú si. Stubs mimo interactive módu — bezpečné volať všade. `disown` po štarte zabraňuje "Terminated: 15" notifikáciám pri `kill`.

---

## Diff viewer pre `write_file`

**Rozhodnutie:** Pred [y/N] potvrdením `write_file` sa zobrazí `diff -u` (existujúci súbor) alebo byte count (nový súbor).

**Alternatívy:** Zobraziť celý nový obsah, žiadny preview

**Dôvod:** Celý nový obsah je zbytočný hluk pre veľké súbory. `diff -u` ukazuje presne čo sa mení — rovnaký UX ako v Claude Code. `head -80` obmedzuje výstup. `mktemp` namiesto `<(...)` — macOS bash 3.2 má problémy s process substitution v niektorých kontextoch.

---

## Farby + `NO_COLOR`

**Rozhodnutie:** ANSI farby sú zapnuté keď `[[ -t 2 && -z "${NO_COLOR:-}" ]]`, inak prázdne konštanty.

**Alternatívy:** Vždy farby, externá konfigurácia

**Dôvod:** Testy bežia cez pipe — `_C_*` sú prázdne, assertions prechádzajú bez ANSI šumu. `NO_COLOR` je priemyselný štandard (no-color.org). Pozadie namiesto textu pre diff riadky — zachová pôvodnú farbu textu v tmavých aj svetlých termináloch.

---

## `□` prefix na výstupe modelu

**Rozhodnutie:** Každý riadok odpovede modelu v interactive móde začína `□ ` (U+25A1 biely štvorček).

**Alternatívy:** `ai:` prefix, farebné ohraničenie, žiadny marker

**Dôvod:** Vytvorí konzistentný vizuálny stĺpec odlišujúci model output od UI elementov (spinners, tool výstupy, prompty). Prázdny štvorček = "nevyplnené" → slúži ako checkbox stĺpec pre budúce použitie. Implementovaný cez `sed "s/^/□ /"` v `_print_response()` — no-op stub v neinteraktívnom móde zachová čistý stdout pre piping.

---

## `save_plan` ako pre-approved tool

**Rozhodnutie:** `save_plan` je v toolsete bez Y/N potvrdenia — model ho môže volať okamžite po vytvorení plánu.

**Alternatívy:** Vyžadovať potvrdenie, manuálne `/plan save`

**Dôvod:** Plán je textový výstup bez side-effectov na kód alebo systém — rizikovosť je nízka. Potvrdenie by prerušilo flow (model práve dokončil plánovanie). Cesta sa sanitizuje na `[a-zA-Z0-9_-]` a injektuje sa do runtime kontextu pri ďalšej správe — model vie kde plán nájsť aj po reštarte session.

---

## `_select_option` — interaktívny výber s arrow keys

**Rozhodnutie:** Všetky confirmation prompty používajú `_select_option` namiesto `read [y/N]`. Možnosti sa prepínajú šípkami (←/→/↑/↓), Enter potvrdí. Vybraná možnosť je zvýraznená inverzným textom.

**Alternatívy:** `read [y/N]`, `fzf`, `select` builtin

**Dôvod:** `_select_option` poskytuje konzistentné UX naprieč všetkými promptmi. Arrow key navigácia je intuitívnejšia ako písanie Y/N. Podporuje viac ako 2 možnosti (napr. "Áno", "Nie", "Vždy Áno (táto session)"). Predvolená možnosť je vždy prvá (Áno). Fallback na prvú možnosť keď `/dev/tty` nie je k dispozícii.

---

## ESC interrupt redesign: SIGINT → SIGUSR1

**Rozhodnutie:** ESC monitor posiela `SIGUSR1` namiesto `SIGINT` na prerušenie API volania.

**Alternatívy:** `SIGINT` (pôvodný stav), `SIGTERM`, pipe-based interrupt

**Dôvod:** `SIGINT` spôsoboval kolízie s readline — keď ESC prišlo počas `read -er`, readline interpretovalo SIGINT ako Ctrl+C a ukončilo prompt. `SIGUSR1` je user-defined signál, ktorý readline ignoruje. Skript ho zachytáva len počas API volania (`trap '_AI_INTERRUPTED=1' USR1`), po skončení sa trap resetuje na `''`.

---

## Plan persistence: `/plan progress`, `/plan history`, `/plan continue`

**Rozhodnutie:** Plány majú timestampované názvy (`plan-20260512_234835.md`), progress tracking cez `.meta.json` súbory, a `/plan continue` vloží celý plán do promptu.

**Alternatívy:** Jeden súbor bez verzovania, progress v názve súboru

**Dôvod:** Timestampy umožňujú `/plan history` zobraziť všetky verzie. `.meta.json` je oddelený od obsahu plánu — nemení git diff. `/plan continue` je robustnejší ako spoliehať sa na modelovu pamäť — plán je explicitne v prompte.

---

## Farebná schéma: light blue, orange, dark bg pre diff

**Rozhodnutie:** `_C_CMD` = light blue (117), `_C_ERR` = orange (208), `_C_BG_ADD` = dark green bg + white text, `_C_BG_DEL` = wine-red bg, `_C_BG_USER` = dark gray bg.

**Alternatívy:** Pôvodné farby (yellow, red, green/red bg)

**Dôvod:** Oranžová na príkazoch bola ťažko čitateľná — light blue je lepší kontrast. Červená na chybách bola príliš agresívna — orange je menej rušivá. Dark green/wine-red pozadie pre diff riadky je konzistentné s GitHub diff stylingom. Dark gray pozadie pre user input v histórii vizuálne oddeľuje otázky od odpovedí.

---

## `[pro...]` animácia — single line s vymazaním

**Rozhodnutie:** `[pro...]` sa zobrazí na jednom riadku a po dokončení sa vymaže `\r\033[K`.

**Alternatívy:** Viacero riadkov `[pro...]`, žiadny indikátor

**Dôvod:** Viacero riadkov `[pro...]` (jeden pre každú delegáciu) vytváralo zbytočný vizuálny šum. Single line s vymazaním je čistejšie — používateľ vidí len spinner a tool výstupy.

---

## `_select_option` fallback vracia poslednú možnosť (Nie) v non-TTY

**Rozhodnutie:** Keď `_select_option` nie je TTY, vracia `"${_so_options[-1]}"` (poslednú možnosť) namiesto prvej.

**Alternatívy:** Prvá možnosť (Áno), pýtať sa cez `/dev/tty`, vrátiť prázdny string

**Dôvod:** V testoch a pipe kontexte nie je terminál. Prvá možnosť je typicky "Áno" — vracanie "Áno" by automaticky potvrdzovalo všetky operácie, čo je nebezpečné. Posledná možnosť je typicky "Nie" alebo najbezpečnejšia alternatíva. Toto je konzervatívny default: radšej zlyhať ako nechtiac povoliť.

---

## `grep_search` options sanitizácia

**Rozhodnutie:** `_tool_grep_search` povoľuje len bezpečnú podmnožinu grep flagov: `-i -l -w -r -n -I --exclude-dir= --include=`.

**Alternatívy:** Povoliť všetky flagy, nepovoliť žiadne

**Dôvod:** `grep_search` je pre-approved tool (model ho volá bez potvrdenia). Bez sanitizácie by model mohol vložiť `--include=` alebo `--exclude-dir=` flagy na manipuláciu výsledkov. Úplný zákaz flagov by obmedzoval legitímne použitie (case-insensitive search, file type filtering). Sanitizácia je kompromis: model má flexibilitu, ale nemôže injectovať nebezpečné flagy.

---

## `realpath` (bez `-m`) pre `/batch` path check

**Rozhodnutie:** `/batch` používa `realpath` (bez `-m`) namiesto `realpath -m`.

**Alternatívy:** `realpath -m`, `readlink -f`, žiadna normalizácia

**Dôvod:** `realpath -m` nerieši symbolické linky — ak má user `~/link -> /etc`, `realpath -m ~/link/shadow` vráti `~/link/shadow`, čo prejde `$HOME` checkom, ale shell pri čítaní nasleduje symlink do `/etc/shadow`. `realpath` (bez `-m`) resolvuje symlinky, takže `realpath ~/link/shadow` vráti `/etc/shadow`, čo je mimo `$HOME` a bude odmietnuté.
