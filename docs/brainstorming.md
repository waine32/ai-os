# Brainstorming

Voľné nápady. Nič tu nie je záväzné.

---

## UX vylepšenia

- **Syntax highlighting** — výstup modelu cez `bat` alebo `highlight` ak je nainštalovaný (auto-detect, fallback na plain)
- **`fzf` história** — Ctrl+R v interaktívnom móde otvára `fzf` nad `interactive_history` namiesto readline reverse-search
- **Progress indikátor** — pri blocking mode (flash+tools, pro) zobraziť elapsed time alebo spinner
- **Diff výstup** — ak model vráti code block, ponúknuť `diff` voči aktuálnemu súboru
- **Token counter v reálnom čase** — live update tokeny počas streamovania

---

## Nové príkazy

- **`/memory add <text>`** — rýchly append do `memory.md` bez editora (už v roadmape)
- **`/alias <skratka> <príkaz>`** — `/alias gp "!git push"` — vlastné príkazy uložené v `~/.ai-os/aliases`
- **`/share`** — exportuje aktuálnu session ako Markdown do clipboardu alebo súboru
- **`/pin <číslo>`** — pripne správu natrvalo do kontextu (nevymaže sa pri `/compact`)
- **`/undo`** — vráti posledný turn (user + assistant) z CONV
- **`/retry`** — opakuje posledný prompt s novou odpoveďou (vymaže poslednú assistant odpoveď)
- **`/template <meno>`** — načíta predpripravený prompt template

---

## Modely a provideri

- **Podpora viacerých providerov** — konfigurovateľný endpoint + API key cez env; `PROVIDER=claude ai flash --interactive`
- **Automatický fallback** — ak DeepSeek vráti 429/503, skúsiť záložný model/provider
- **Lokálne modely** — Ollama integrácia; rovnaké OpenAI-compatible API
- **Model per-task** — v batch móde špecifikovať model na riadok: `model=pro: Refaktoruj tento kód`

---

## Nástroje pre model

- **`read_file`** — model si prečíta súbor (s potvrdením, obmedzenie na `$HOME`)
- **`write_file`** — model zapíše do súboru (povinný diff preview pred zápisom)
- **`http_get`** — model fetchne URL (whitelist domén)
- **`run_test`** — spustí `bats tests/` a vráti výsledok modelu

---

## Integrácie

- **tmux** — výstup modelu do vedľajšieho pane; `!tmux send-keys ...`
- **Warp AI blocks** — OSC 133 sekvencie sú implementované; rozšíriť o metadata bloky
- **VS Code terminal** — detekcia `$TERM_PROGRAM=vscode`, prispôsobenie formátovania
- **`direnv`** — automatické nastavenie `DEEPSEEK_API_KEY` z `.envrc` per-projekt

---

## Multi-agent

- **Paralelné volania** — `/batch --parallel` spustí prompty súbežne (background jobs + wait)
- **Model-to-model pipeline** — výstup flash → vstup pro: `ai flash "zoznam krokov" | ai pro "implementuj"`
- **Agentic task runner** — YAML task file, model si plánuje a vykonáva kroky sám (s potvrdeniami)
