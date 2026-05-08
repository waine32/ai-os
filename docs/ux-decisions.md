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

## stdin pre confirmácie, nie `/dev/tty`

**Rozhodnutie:** Všetky `[y/N]` confirmácie (`read -r`) čítajú zo stdin, nie `</dev/tty`.

**Alternatívy:** `/dev/tty` — číta priamo z terminálu bez ohľadu na pipes

**Dôvod:** Testy používajú piped stdin (`printf '...' | ai flash --interactive`). `/dev/tty` by confirmácie nečítalo z pipe, Y/N by konzumoval hlavný loop a posielal ako prompt modelu. stdin umožňuje testy bez terminálového kontextu a v reálnom použití stdin == terminál.

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
