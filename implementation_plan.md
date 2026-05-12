# Implementation Plan

[Overview]
Implement 7 feature improvements and 3 bug fixes for the AI-OS interactive shell script (`ai`).

The AI-OS interactive shell (`ai flash --interactive`) is a bash script that provides an LLM-powered terminal assistant. It supports two models (flash and pro), maintains conversation history, provides tool-calling capabilities, and offers various slash commands. The current implementation has several bugs and UX shortcomings that need to be addressed: the `warp_seq` function causes the script to exit under `set -e` when `WARP` is empty (preventing the interactive loop from starting), the ESC interrupt mechanism conflicts with readline's SIGINT handling, multiline input is broken for pasted text, the color scheme uses hard-to-read orange, confirmation prompts use basic `[y/N]` instead of navigable options, the `[pro...]` processing indicator shows redundant lines, and plan persistence lacks robust session continuity. The approach is to fix the critical `warp_seq` crash first, then systematically address each UX issue while maintaining backward compatibility with existing tests and workflows.

[Types]
No new type definitions needed — the implementation is in bash script with JSON payloads via jq.

The following internal variables and conventions are used:
- `_AI_INTERRUPTED` (integer): 0/1 flag set by SIGUSR1 trap for ESC key detection
- `_ESC_PID` (integer): PID of the background ESC monitor process
- `_SPINNER_PID` (integer): PID of the background spinner process
- `_read_multiline()` (function): Returns multiline input via global `_MULTILINE_INPUT` variable
- `_select_option()` (function): Returns selected option index via global `_SELECTED_OPTION` variable
- `_MULTILINE_INPUT` (string): Global variable holding accumulated multiline input
- `_SELECTED_OPTION` (integer): Global variable holding the selected option index (0-based)
- `_SELECTED_LABEL` (string): Global variable holding the selected option label text
- Color constants: `C_ORANGE` → `C_LIGHTBLUE`, `C_RED` → `C_ORANGE`, new `C_DARKGRAY`, `C_DARKGREEN_BG`, `C_DARKRED_BG`, `C_WHITE`

[Files]
One file will be modified: `/Users/martinzuzic/ai-os/ai` (the main script).

No new files, no deleted files. Configuration files are unchanged.

Detailed changes to `/Users/martinzuzic/ai-os/ai`:
1. Fix `warp_seq` crash: Change `warp_seq()` function to always return 0 by adding `|| true` or restructuring to avoid `set -e` exit
2. Redesign ESC interrupt: Replace SIGINT trap with SIGUSR1 trap, update `_start_esc_monitor` to send SIGUSR1, update `_stop_esc_monitor` to clean up properly, ensure `read -er` is not interrupted by the ESC monitor
3. Implement `_read_multiline()`: New function that reads input line-by-line using `read -er` with `$'\n> '` prompt, accumulates lines until Enter on empty line (or Shift+Enter for newline, Enter to send). Handle pasted multiline text by showing all lines.
4. Implement `_select_option()`: New function that displays a list of options with arrow key navigation (up/down), highlights selected option, Enter to confirm. Returns index and label.
5. Replace all confirmation prompts: Find all `[y/N]`, `[Y/n]`, `read -r confirm` patterns and replace with `_select_option` calls. Default to first option (Áno).
6. Apply color scheme changes: Replace `C_ORANGE` with `C_LIGHTBLUE`, `C_RED` with `C_ORANGE`, add `C_DARKGRAY` for user input history background, add `C_DARKGREEN_BG`/`C_DARKRED_BG`/`C_WHITE` for diff highlighting
7. Implement `[pro...]` animation: Replace multiple `[pro...]` lines with a single animated indicator that cycles through visual states (blinking borders, progressive character graying)
8. Implement plan persistence enhancements: Improve save/load of plan state, ensure plan survives session restarts, add `/plan continue` support

[Functions]

**New functions:**
- `_read_multiline()` → `/Users/martinzuzic/ai-os/ai` (around line 490, near other helper functions)
  - Signature: `_read_multiline()`
  - Purpose: Read multiline input from user. Accumulates lines until Enter on empty line (send) or Shift+Enter (newline). Stores result in `_MULTILINE_INPUT` global.
  - Returns: 0 if input was read, 1 if interrupted (ESC/Ctrl+C)
  - Behavior: Uses `read -er` in a loop. Each iteration reads one line. If line is empty and no Shift+Enter was pressed, break and send. If Shift+Enter was pressed, append newline and continue. Shows accumulated lines above the prompt.

- `_select_option()` → `/Users/martinzuzic/ai-os/ai` (around line 490, near other helper functions)
  - Signature: `_select_option()`
  - Purpose: Display a list of selectable options with arrow key navigation. Stores selected index in `_SELECTED_OPTION` and label in `_SELECTED_LABEL`.
  - Arguments: Uses global `_OPTIONS` array (set before calling)
  - Returns: 0 if option selected, 1 if cancelled (ESC)
  - Behavior: Renders options list with highlighting. Up/down arrows move selection. Enter confirms. ESC cancels. Default selection is index 0.

**Modified functions:**
- `warp_seq()` → `/Users/martinzuzic/ai-os/ai` (line 880)
  - Change: Add `|| true` to prevent `set -e` from exiting when `WARP` is empty
  - New body: `warp_seq() { [[ -n "$WARP" ]] && printf '\033]133;%s\007' "$1" || true; }`

- `_start_esc_monitor()` → `/Users/martinzuzic/ai-os/ai` (line 884)
  - Change: Send SIGUSR1 instead of SIGINT to parent process
  - Line 892: `[[ "$_k" == $'\033' ]] && kill -USR1 "$_ppid" 2>/dev/null && break`

- `_stop_esc_monitor()` → `/Users/martinzuzic/ai-os/ai` (line 898)
  - Change: Ensure cleanup is robust, kill background process group

- Main interactive loop (around line 1025-1040)
  - Change: Replace `IFS= read -er -p $'\n> ' INPUT` with call to `_read_multiline`
  - Change: Update trap handlers — use SIGUSR1 for ESC, keep SIGINT for Ctrl+C but restore before `read -er`
  - Change: Update `_AI_INTERRUPTED` handling to check for SIGUSR1

- `_ask` function (around line 1670)
  - Change: Update trap to use SIGUSR1 instead of SIGINT
  - Line 1671: `trap '_AI_INTERRUPTED=1' USR1`
  - Line 1672: Remove `trap '_AI_INTERRUPTED=1' INT` (keep only USR1)
  - Line 1684: `trap '' USR1` (restore after API call)

- All confirmation prompt locations (search for `[y/N]`, `[Y/n]`, `read -r confirm`, `read -r yn`)
  - Change: Replace with `_select_option` calls
  - Locations include: `/project clear`, `write_file` tool confirmation, `/auto` mode prompts, and any other interactive confirmations

- Color constant definitions (around line 80-100)
  - Change: `C_ORANGE` → `C_LIGHTBLUE` (change value from orange ANSI to light blue ANSI)
  - Change: `C_RED` → `C_ORANGE` (change value from red ANSI to orange ANSI)
  - Add: `C_DARKGRAY='\033[100m'` (dark gray background for user history)
  - Add: `C_DARKGREEN_BG='\033[42m'` (dark green background for added lines in diff)
  - Add: `C_DARKRED_BG='\033[41m'` (dark red background for removed lines in diff)
  - Add: `C_WHITE='\033[97m'` (bright white text for diff)

- `_print_response()` or history display function
  - Change: Apply `C_DARKGRAY` background to user input lines in history

- `[pro...]` processing indicator (around line 777-810)
  - Change: Replace multiple `[pro...]` lines with single animated indicator
  - Implementation: Use a single line with `\r` (carriage return) to update in place
  - Animation: Cycle through `[pro    ]` → `[pro   ]` → `[pro  ]` → `[pro ]` → `[pro]` (progressive shortening) or use a spinner-like animation

**Removed functions:**
- None

[Classes]
No classes — the implementation is in bash script with no object-oriented code.

[Dependencies]
No new dependencies. The implementation relies on existing tools: bash 3.2+, jq, curl, standard Unix utilities (stty, kill, printf, read). The `_select_option` function uses ANSI escape sequences for cursor movement and highlighting, which are supported by all modern terminals.

[Testing]
Update `/Users/martinzuzic/ai-os/tests/ai.bats` to cover new functionality and verify bug fixes.

Test modifications:
1. Add test for `warp_seq` not crashing under `set -e` when `WARP` is empty
2. Add test for multiline input via `_read_multiline` (piped input with multiple lines)
3. Add test for `_select_option` with default selection
4. Update existing confirmation prompt tests to use new `_select_option` flow
5. Add test for color scheme changes (verify `C_LIGHTBLUE` is used instead of `C_ORANGE`)
6. Add test for `[pro...]` animation (verify single line output)
7. Update ESC interrupt tests to use SIGUSR1 instead of SIGINT
8. Add test for plan persistence across session restarts

[Implementation Order]
Implement changes in dependency order to minimize conflicts and ensure testability.

1. **Fix `warp_seq` crash** — Add `|| true` to `warp_seq()` function. This is the most critical bug fix as it prevents the interactive loop from starting. Test immediately.

2. **Redesign ESC interrupt** — Replace SIGINT with SIGUSR1 in `_start_esc_monitor`, `_stop_esc_monitor`, and all trap handlers. This must be done before multiline input changes since both affect the input loop.

3. **Implement `_read_multiline`** — Create the multiline input function. Replace the single `read -er` in the main loop. Handle Shift+Enter detection and pasted multiline text display.

4. **Implement `_select_option`** — Create the option selection helper function with arrow key navigation.

5. **Replace confirmation prompts** — Find and replace all `[y/N]` and similar patterns with `_select_option` calls.

6. **Apply color scheme changes** — Update color constants and apply new colors to history display and diff output.

7. **Implement `[pro...]` animation** — Replace multiple processing indicator lines with single animated indicator.

8. **Implement plan persistence enhancements** — Improve save/load of plan state for session continuity.

9. **Update tests** — Add and update tests in `tests/ai.bats` for all changes.

10. **Update documentation** — Update `docs/` files and `README.md` if needed.
