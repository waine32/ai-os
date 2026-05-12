#!/usr/bin/env bash
set -euo pipefail

AI_OS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "AI-OS setup"
echo "────────────────────────────────────────────────────────────────"

# 1. Dependency check
ok=1
for cmd in curl jq git; do
  if command -v "$cmd" &>/dev/null; then
    printf '  ✓ %s\n' "$cmd"
  else
    printf '  ✗ %s  (chýba — nainštaluj ho a spusti setup znova)\n' "$cmd"
    ok=0
  fi
done
[[ "$ok" -eq 0 ]] && exit 1

# 2. API key
if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  echo "  ! DEEPSEEK_API_KEY nie je nastavený — pridaj ho do ~/.zshrc:"
  echo '    export DEEPSEEK_API_KEY="sk-..."'
else
  echo "  ✓ DEEPSEEK_API_KEY nastavený"
fi

# 3. Directory structure
mkdir -p "$HOME/.ai-os/sessions/named" "$HOME/.ai-os/tmp" "$HOME/.ai-os/context"
echo "  ✓ ~/.ai-os/ adresárová štruktúra"

# 4. Context files (defaults)
if [[ ! -f ~/.ai-os/instructions.md ]]; then
  cat > ~/.ai-os/instructions.md <<'EOF'
## Identity
You are a deterministic CLI assistant.

## Language
Always respond in Slovak language.

## Behavior
Be concise and direct. Prefer structured output for complex answers.

## Model selection

🟣 Pro — use for:
- debugging
- architecture decisions
- flaky tests
- async race conditions
- large refactors

🔵 Flash — use for:
- CRUD tests
- boilerplate generation
- rename/refactor
- generating mocks
- formatting
- repetitive edits

Efficient pattern: analysis (Pro) → implementation (Flash) → final review (Pro)
EOF
  echo "  ✓ ~/.ai-os/instructions.md vytvorený"
else
  echo "  · ~/.ai-os/instructions.md existuje"
fi

if [[ ! -f ~/.ai-os/memory.md ]]; then
  echo "# Memory" > ~/.ai-os/memory.md
  echo "  ✓ ~/.ai-os/memory.md vytvorený"
else
  echo "  · ~/.ai-os/memory.md existuje"
fi

# 5. PATH check
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
if echo "$PATH" | grep -q "$AI_OS_DIR"; then
  echo "  · PATH obsahuje $AI_OS_DIR"
else
  printf '\nPridať %s do PATH v %s? [y/N] ' "$AI_OS_DIR" "$ZSHRC"
  read -r ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    printf '\nexport PATH="%s:$PATH"\n' "$AI_OS_DIR" >> "$ZSHRC"
    echo "  ✓ PATH pridaný do $ZSHRC"
    echo "    Spusti:  source $ZSHRC"
  fi
fi

# 6. chpwd hook check
if grep -q '_ai_project_hook' "$ZSHRC" 2>/dev/null; then
  echo "  · chpwd hook existuje v $ZSHRC"
else
  printf '\nPridať ai-os chpwd hook do %s? [y/N] ' "$ZSHRC"
  read -r ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    cat >> "$ZSHRC" <<'HOOK'

# ai-os: track current project for ds.md fallback
_ai_project_hook() {
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null) || git_root=""
  if [[ -n "$git_root" && "$git_root" = "$HOME"* && -f "$git_root/ds.md" ]]; then
    printf '%s\n' "$git_root" > ~/.ai-os/current-project
  else
    rm -f ~/.ai-os/current-project
  fi
}
add-zsh-hook chpwd _ai_project_hook
HOOK
    echo "  ✓ Hook pridaný do $ZSHRC"
    echo "    Spusti:  source $ZSHRC"
  fi
fi

echo ""
echo "Setup dokončený."
