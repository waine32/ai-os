#!/usr/bin/env bats

AI_SCRIPT="${BATS_TEST_DIRNAME%/*}/ai"

setup_file() {
  export MOCK_BIN="$BATS_FILE_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"

  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  export TEST_HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$TEST_HOME/.ai-os/context"
  mkdir -p "$TEST_HOME/.ai-os/sessions"
}

setup() {
  export HOME="$TEST_HOME"
  export DEEPSEEK_API_KEY="test-key-123"
  export MOCK_CURL_RESPONSE='{"choices":[{"message":{"content":"test response"}}]}'
  rm -f "$HOME/.ai-os/sessions/history.json"
  rm -f "$HOME/.ai-os/sessions/history.txt"
  rm -f "$HOME/.ai-os/context/global.md"
  rm -f "$HOME/.ai-os/sessions/interactive_history"
  rm -f /tmp/curl_payload.json
  # Restore the original mock curl before each test
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"
}

teardown() {
  unset DEEPSEEK_API_KEY
  unset AI_TEMPERATURE
  unset AI_CONTEXT_LIMIT
  unset MOCK_CURL_RESPONSE
  unset TERM_PROGRAM
  rm -f /tmp/ai_last_output.txt
  rm -f /tmp/ai_last_stream.txt
  rm -rf "$HOME/.ai-os/tmp"
}

@test "no arguments exits with usage message" {
  run "$AI_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown model exits with usage message" {
  run "$AI_SCRIPT" unknown "test prompt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "missing DEEPSEEK_API_KEY exits with error" {
  unset DEEPSEEK_API_KEY
  run "$AI_SCRIPT" flash "test prompt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DEEPSEEK_API_KEY"* ]]
}

@test "missing prompt exits with error" {
  run "$AI_SCRIPT" flash
  [ "$status" -ne 0 ]
  [[ "$output" == *"prompt is required"* ]]
}

@test "flash model succeeds and outputs response" {
  run "$AI_SCRIPT" flash "test prompt"
  [ "$status" -eq 0 ]
  [ "$output" = "test response" ]
}

@test "pro model succeeds and outputs response" {
  run "$AI_SCRIPT" pro "test prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test response"* ]]
}

@test "session mode creates history.json file" {
  run "$AI_SCRIPT" flash --session "first prompt"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ai-os/sessions/history.json" ]
}

@test "session history is stored as valid JSON array" {
  run "$AI_SCRIPT" flash --session "test prompt"
  [ "$status" -eq 0 ]

  local hist="$HOME/.ai-os/sessions/history.json"
  [ -f "$hist" ]

  # Verify it's valid JSON
  jq empty < "$hist"

  # Verify it's an array
  [ "$(jq 'type' < "$hist")" = '"array"' ]

  # Verify it has entries with proper structure
  [ "$(jq 'length' < "$hist")" -ge 2 ]
  [ "$(jq '.[0].role' < "$hist")" = '"user"' ]
  [ "$(jq '.[0].content' < "$hist")" = '"test prompt"' ]
}

@test "session mode appends to history.json correctly" {
  run "$AI_SCRIPT" flash --session "first prompt"
  [ "$status" -eq 0 ]

  run "$AI_SCRIPT" flash --session "second prompt"
  [ "$status" -eq 0 ]

  local hist="$HOME/.ai-os/sessions/history.json"

  # Should have 4 entries total (2 pairs of user/assistant)
  [ "$(jq 'length' < "$hist")" -eq 4 ]

  # Verify first user message
  [ "$(jq '.[0].role' < "$hist")" = '"user"' ]
  [ "$(jq '.[0].content' < "$hist")" = '"first prompt"' ]

  # Verify second user message
  [ "$(jq '.[2].role' < "$hist")" = '"user"' ]
  [ "$(jq '.[2].content' < "$hist")" = '"second prompt"' ]
}

@test "migration from history.txt to history.json" {
  # Pre-populate history.txt
  printf 'USER: foo\nASSISTANT: bar\n' > "$HOME/.ai-os/sessions/history.txt"

  run "$AI_SCRIPT" flash --session "new prompt"
  [ "$status" -eq 0 ]

  local hist="$HOME/.ai-os/sessions/history.json"
  [ -f "$hist" ]

  # Verify JSON was created with correct structure
  jq empty < "$hist"

  # Should have migrated the old entries plus new ones (4 total)
  [ "$(jq 'length' < "$hist")" -eq 4 ]

  # Verify migrated entries
  [ "$(jq '.[0].role' < "$hist")" = '"user"' ]
  [ "$(jq '.[0].content' < "$hist")" = '"foo"' ]
  [ "$(jq '.[1].role' < "$hist")" = '"assistant"' ]
  [ "$(jq '.[1].content' < "$hist")" = '"bar"' ]

  # Verify new entries were appended
  [ "$(jq '.[2].role' < "$hist")" = '"user"' ]
  [ "$(jq '.[2].content' < "$hist")" = '"new prompt"' ]
}

@test "/status shows estimated tokens in interactive mode" {
  export MOCK_CURL_RESPONSE='{"choices":[{"message":{"content":"ai response"}}]}'

  run bash -c "printf 'test\n/status\nexit\n' | '$AI_SCRIPT' flash --interactive"

  [ "$status" -eq 0 ]
  [[ "$output" == *"estim. tokens"* ]]
}

@test "compression trigger with low context limit" {
  export AI_CONTEXT_LIMIT=1
  export MOCK_CURL_RESPONSE='{"choices":[{"message":{"content":"response"}}]}'

  # Pre-populate with 6 turns (3 user + 3 assistant)
  local hist='[
    {"role":"user","content":"q1"},
    {"role":"assistant","content":"a1"},
    {"role":"user","content":"q2"},
    {"role":"assistant","content":"a2"},
    {"role":"user","content":"q3"},
    {"role":"assistant","content":"a3"}
  ]'
  echo "$hist" > "$HOME/.ai-os/sessions/history.json"

  run "$AI_SCRIPT" flash --session "new query"
  [ "$status" -eq 0 ]

  local hist_file="$HOME/.ai-os/sessions/history.json"
  [ -f "$hist_file" ]

  # Verify summary entry was created
  [ "$(jq '[.[] | select(.role=="summary")] | length' < "$hist_file")" -gt 0 ]
}

@test "summary is injected into system prompt, not messages array" {
  export MOCK_CURL_RESPONSE='{"choices":[{"message":{"content":"response"}}]}'

  # Create a capture script for curl to save the payload (-d argument)
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
found_d=0
for arg in "$@"; do
  if [[ "$found_d" == "1" ]]; then
    echo "$arg" > /tmp/curl_payload.json
    found_d=0
  fi
  [[ "$arg" == "-d" ]] && found_d=1
done
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  # Pre-populate with a summary entry
  local hist='[
    {"role":"summary","content":"previous context","summarized_turns":4},
    {"role":"user","content":"q"},
    {"role":"assistant","content":"a"}
  ]'
  echo "$hist" > "$HOME/.ai-os/sessions/history.json"

  rm -f /tmp/curl_payload.json

  run "$AI_SCRIPT" flash --session "new question"
  [ "$status" -eq 0 ]

  # Check that curl was called and payload was captured
  [ -f /tmp/curl_payload.json ]

  local payload=$(< /tmp/curl_payload.json)

  # Verify summary NOT in messages array
  [[ ! "$payload" =~ '"role":"summary"' ]] || false

  # Verify system prompt contains the summary content
  [[ "$payload" == *"previous context"* ]]
}

@test "prompt with quotes and special characters is handled safely" {
  run "$AI_SCRIPT" flash 'test "quote" and $var and \backslash'
  [ "$status" -eq 0 ]
  [ "$output" = "test response" ]
}

@test "API error response is handled" {
  export MOCK_CURL_RESPONSE='{"error":{"message":"Unauthorized"}}'
  run "$AI_SCRIPT" flash "test prompt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unauthorized"* ]]
}

@test "API response with no content exits with error" {
  export MOCK_CURL_RESPONSE='{"error":{}}'
  run "$AI_SCRIPT" flash "test prompt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no output"* ]]
}

@test "AI_TEMPERATURE env var is accepted" {
  export AI_TEMPERATURE="0.5"
  run "$AI_SCRIPT" flash "test prompt"
  [ "$status" -eq 0 ]
  [ "$output" = "test response" ]
}

@test "memory context is loaded from global.md" {
  echo "## User preferences: Be concise" > "$HOME/.ai-os/context/global.md"
  run "$AI_SCRIPT" flash "test prompt"
  [ "$status" -eq 0 ]
  [ "$output" = "test response" ]
}

@test "session history is prepended to subsequent prompts" {
  # Pre-populate with initial Q&A in JSON format
  local hist='[
    {"role":"user","content":"initial question"},
    {"role":"assistant","content":"initial response"}
  ]'
  echo "$hist" > "$HOME/.ai-os/sessions/history.json"

  run "$AI_SCRIPT" flash --session "new prompt"
  [ "$status" -eq 0 ]

  local hist_file="$HOME/.ai-os/sessions/history.json"
  [ -f "$hist_file" ]

  # Verify we have 4 entries (old pair + new pair)
  [ "$(jq 'length' < "$hist_file")" -eq 4 ]

  # Verify initial entries are still there
  [ "$(jq '.[0].content' < "$hist_file")" = '"initial question"' ]
  [ "$(jq '.[1].content' < "$hist_file")" = '"initial response"' ]
}

@test "save_session appends correctly to existing history" {
  # Pre-populate with one exchange
  local hist='[
    {"role":"user","content":"first"},
    {"role":"assistant","content":"resp"}
  ]'
  echo "$hist" > "$HOME/.ai-os/sessions/history.json"

  run "$AI_SCRIPT" flash --session "second"
  [ "$status" -eq 0 ]

  local hist_file="$HOME/.ai-os/sessions/history.json"

  # Verify 4 entries total
  [ "$(jq 'length' < "$hist_file")" -eq 4 ]

  # Verify original entries preserved
  [ "$(jq '.[0].content' < "$hist_file")" = '"first"' ]
  [ "$(jq '.[1].content' < "$hist_file")" = '"resp"' ]

  # Verify new entries appended
  [ "$(jq '.[2].content' < "$hist_file")" = '"second"' ]
}

@test "history file is created after interactive session" {
  run bash -c "printf 'hello\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ai-os/sessions/interactive_history" ]
}

@test "/clear does not crash" {
  run bash -c "printf '/clear\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
}

@test "/model switches model" {
  run bash -c "printf '/model invalid\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Použitie"* ]]
}

@test "/model with no arg shows current model" {
  run bash -c "printf '/model\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"flash"* ]]
}

@test "/plan sets planning prefix on next message" {
  # Create a capture script for curl to save the payload (-d argument)
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
found_d=0
for arg in "$@"; do
  if [[ "$found_d" == "1" ]]; then
    echo "$arg" > /tmp/curl_payload.json
    found_d=0
  fi
  [[ "$arg" == "-d" ]] && found_d=1
done
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  rm -f /tmp/curl_payload.json

  run bash -c "printf '/plan\nwrite a scraper\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [ -f /tmp/curl_payload.json ]

  local payload=$(< /tmp/curl_payload.json)
  [[ "$payload" == *"step-by-step plan"* ]]
}

@test "/batch with a temp file" {
  local tmpfile=$(mktemp)
  printf 'first prompt\nsecond prompt\n' > "$tmpfile"

  run bash -c "printf '/batch $tmpfile\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first prompt"* ]]

  rm -f "$tmpfile"
}

@test "/save and /load round-trip" {
  run bash -c "printf '/save mytest\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ai-os/sessions/named/mytest.json" ]

  run bash -c "printf '/load mytest\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"načítaná"* ]]
}

@test "/compact on non-empty CONV" {
  # Create a capture script for curl to save the payload (-d argument)
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
found_d=0
for arg in "$@"; do
  if [[ "$found_d" == "1" ]]; then
    echo "$arg" > /tmp/curl_payload.json
    found_d=0
  fi
  [[ "$arg" == "-d" ]] && found_d=1
done
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  rm -f /tmp/curl_payload.json

  run bash -c "printf 'msg1\nmsg2\n/compact\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"komprimovaná"* ]]
}

@test "pipe input succeeds and outputs response" {
  run bash -c "echo 'pipe input test' | '$AI_SCRIPT' flash"
  [ "$status" -eq 0 ]
  [ "$output" = "test response" ]
}

@test "/status shows prompt_tokens and completion_tokens" {
  export MOCK_CURL_RESPONSE='{"choices":[{"message":{"content":"resp"}}]}'
  run bash -c "printf 'hello\n/status\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prompt_tokens"* ]]
  [[ "$output" == *"completion_tokens"* ]]
}

@test "streaming SSE assembles tokens correctly" {
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
printf 'data: {"choices":[{"delta":{"content":"hello "}}]}\n'
printf 'data: {"choices":[{"delta":{"content":"world"}}]}\n'
printf 'data: [DONE]\n'
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  run "$AI_SCRIPT" flash "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "slash command is saved to interactive history" {
  rm -f "$HOME/.ai-os/sessions/interactive_history"
  run bash -c "printf '/reset\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ai-os/sessions/interactive_history" ]
  grep -q '/reset' "$HOME/.ai-os/sessions/interactive_history"
}

@test "Warp OSC 133 sequences are emitted when TERM_PROGRAM=WarpTerminal" {
  run bash -c "export TERM_PROGRAM=WarpTerminal; printf 'exit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033]133;A\007'* ]]
}

@test "interactive prompt uses > not ty:" {
  run bash -c "printf 'exit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ty:"* ]]
}

@test "ds.md loaded from CWD into system prompt" {
  # payload-capture mock
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
found_d=0
for arg in "$@"; do
  if [[ "$found_d" == "1" ]]; then
    echo "$arg" > /tmp/curl_payload.json
    found_d=0
  fi
  [[ "$arg" == "-d" ]] && found_d=1
done
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  echo "# test project context" > "$HOME/ds.md"
  rm -f /tmp/curl_payload.json

  # Run from HOME so ds.md is found
  run bash -c "cd '$HOME' && '$AI_SCRIPT' flash 'hello'"
  [ "$status" -eq 0 ]
  [ -f /tmp/curl_payload.json ]
  [[ "$(< /tmp/curl_payload.json)" == *"test project context"* ]]

  rm -f "$HOME/ds.md"
}

@test "/save strips path traversal characters" {
  run bash -c "printf '/save ../../evil\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  # The traversal chars are stripped, so it saves as "evil" not "../../evil"
  [ -f "$HOME/.ai-os/sessions/named/evil.json" ]
  [ ! -f "$HOME/../../evil.json" ]
}

@test "temp files are created in ~/.ai-os/tmp/ not /tmp" {
  run "$AI_SCRIPT" flash "test"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ai-os/tmp/last_output.json" ]
  [ -f "$HOME/.ai-os/tmp/last_stream.txt" ]
}

@test "current-project fallback loads ds.md when CWD has no ds.md" {
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
found_d=0
for arg in "$@"; do
  if [[ "$found_d" == "1" ]]; then
    echo "$arg" > /tmp/curl_payload.json
    found_d=0
  fi
  [[ "$arg" == "-d" ]] && found_d=1
done
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  local proj_dir="$HOME/fallback_proj"
  mkdir -p "$proj_dir"
  echo "PROJECTFALLBACKMARKER" > "$proj_dir/ds.md"
  printf '%s\n' "$proj_dir" > "$HOME/.ai-os/current-project"
  rm -f /tmp/curl_payload.json

  local clean_dir="$BATS_FILE_TMPDIR/clean_cwd"
  mkdir -p "$clean_dir"
  run bash -c "cd '$clean_dir' && '$AI_SCRIPT' flash 'test'"
  [ "$status" -eq 0 ]
  [ -f /tmp/curl_payload.json ]
  [[ "$(< /tmp/curl_payload.json)" == *"PROJECTFALLBACKMARKER"* ]]
}

@test "ds.md not loaded twice when CWD walk and current-project both point to same file" {
  cat > "$MOCK_BIN/curl" << 'MOCKCURL'
#!/bin/bash
found_d=0
for arg in "$@"; do
  if [[ "$found_d" == "1" ]]; then
    echo "$arg" > /tmp/curl_payload.json
    found_d=0
  fi
  [[ "$arg" == "-d" ]] && found_d=1
done
if [[ -n "${MOCK_CURL_RESPONSE:-}" ]]; then
  echo "$MOCK_CURL_RESPONSE"
else
  echo '{"choices":[{"message":{"content":"test response"}}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  local proj_dir="$HOME/dedup_proj"
  mkdir -p "$proj_dir"
  echo "DEDUPLICATION_MARKER" > "$proj_dir/ds.md"
  printf '%s\n' "$proj_dir" > "$HOME/.ai-os/current-project"
  rm -f /tmp/curl_payload.json

  run bash -c "cd '$proj_dir' && '$AI_SCRIPT' flash 'test'"
  [ "$status" -eq 0 ]
  [ -f /tmp/curl_payload.json ]
  local count
  count=$(grep -o "DEDUPLICATION_MARKER" < /tmp/curl_payload.json | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "/project shows current project path" {
  printf '%s\n' "$HOME/myproject" > "$HOME/.ai-os/current-project"
  run bash -c "printf '/project\n/exit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Projekt:"* ]]
}

@test "/project clear removes current-project file" {
  printf '%s\n' "$HOME/myproject" > "$HOME/.ai-os/current-project"
  run bash -c "printf '/project clear\ny\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Projekt vymazaný"* ]]
  [ ! -f "$HOME/.ai-os/current-project" ]
}

@test "/project set rejects path outside HOME" {
  run bash -c "printf '/project set /etc\n/exit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Chyba"* ]]
}

@test "/project set writes path to current-project when valid" {
  local proj_dir="$HOME/settest_proj"
  mkdir -p "$proj_dir"
  echo "# set test" > "$proj_dir/ds.md"
  run bash -c "printf '/project set $proj_dir\n/exit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Projekt nastavený"* ]]
  [ -f "$HOME/.ai-os/current-project" ]
  [[ "$(< "$HOME/.ai-os/current-project")" == "$proj_dir" ]]
}

# ── Pro→Flash delegation ──────────────────────────────────────────────────────

@test "flash payload has no tools field" {
  local payload_file="$BATS_FILE_TMPDIR/flash_payload.json"
  cat > "$MOCK_BIN/curl" << MOCKCURL
#!/bin/bash
found_d=0
for arg in "\$@"; do
  if [[ "\$found_d" == "1" ]]; then
    printf '%s' "\$arg" > "${payload_file}"
    found_d=0
  fi
  [[ "\$arg" == "-d" ]] && found_d=1
done
echo '{"choices":[{"message":{"content":"flash answer"}}]}'
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  run "$AI_SCRIPT" flash "test"
  [ "$status" -eq 0 ]
  [ -f "$payload_file" ]
  run grep -c '"tools"' "$payload_file"
  [ "$output" -eq 0 ]
}

@test "pro payload includes delegate_to_flash tool" {
  local payload_file="$BATS_FILE_TMPDIR/pro_payload.json"
  cat > "$MOCK_BIN/curl" << MOCKCURL
#!/bin/bash
found_d=0
for arg in "\$@"; do
  if [[ "\$found_d" == "1" ]]; then
    printf '%s' "\$arg" > "${payload_file}"
    found_d=0
  fi
  [[ "\$arg" == "-d" ]] && found_d=1
done
echo '{"choices":[{"message":{"content":"pro answer"},"finish_reason":"stop"}]}'
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  run "$AI_SCRIPT" pro "test"
  [ "$status" -eq 0 ]
  [ -f "$payload_file" ]
  [[ "$(< "$payload_file")" == *"delegate_to_flash"* ]]
  [[ "$(< "$payload_file")" == *'"tools"'* ]]
}

@test "run_agentic writes final content to last_stream.txt" {
  export MOCK_CURL_RESPONSE='{"choices":[{"message":{"content":"pro answer"},"finish_reason":"stop"}]}'
  run "$AI_SCRIPT" pro "test question"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ai-os/tmp/last_stream.txt" ]
  [[ "$(< "$HOME/.ai-os/tmp/last_stream.txt")" == "pro answer" ]]
  [[ "$output" == *"pro answer"* ]]
}

@test "ai flash does not invoke run_agentic" {
  run "$AI_SCRIPT" flash "test"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[pro...]"* ]]
}

@test "run_agentic delegates to flash and returns pro final answer" {
  local counter_file="$BATS_FILE_TMPDIR/deleg_count"
  local toolcall_file="$BATS_FILE_TMPDIR/toolcall_resp.json"
  rm -f "$counter_file"

  printf '%s\n' '{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"delegate_to_flash","arguments":"{\"prompt\":\"flash task\",\"reason\":\"simple\"}"}}]},"finish_reason":"tool_calls"}]}' > "$toolcall_file"

  cat > "$MOCK_BIN/curl" << MOCKCURL
#!/bin/bash
cf="${counter_file}"
rf="${toolcall_file}"
count=0
[ -f "\$cf" ] && count=\$(< "\$cf")
count=\$((count + 1))
printf '%s' "\$count" > "\$cf"
if [ "\$count" -eq 1 ]; then
  cat "\$rf"
elif [ "\$count" -eq 2 ]; then
  echo '{"choices":[{"message":{"content":"flash result"}}]}'
else
  echo '{"choices":[{"message":{"content":"pro final answer"},"finish_reason":"stop"}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  run "$AI_SCRIPT" pro "delegate test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pro final answer"* ]]
}

@test "run_agentic rejects oversized flash prompt" {
  local counter_file="$BATS_FILE_TMPDIR/big_count"
  local toolcall_file="$BATS_FILE_TMPDIR/big_toolcall.json"
  rm -f "$counter_file"

  # Build a tool_call with a 10001-char prompt
  local big_prompt
  big_prompt=$(printf '%10001s' '' | tr ' ' 'x')
  local args_str
  args_str=$(jq -rn --arg p "$big_prompt" '{"prompt":$p}')
  jq -n --arg args "$args_str" '{
    "choices":[{
      "message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_big","type":"function","function":{"name":"delegate_to_flash","arguments":$args}}]},
      "finish_reason":"tool_calls"
    }]
  }' > "$toolcall_file"

  cat > "$MOCK_BIN/curl" << MOCKCURL
#!/bin/bash
cf="${counter_file}"
rf="${toolcall_file}"
count=0
[ -f "\$cf" ] && count=\$(< "\$cf")
count=\$((count + 1))
printf '%s' "\$count" > "\$cf"
if [ "\$count" -eq 1 ]; then
  cat "\$rf"
else
  echo '{"choices":[{"message":{"content":"concluded"},"finish_reason":"stop"}]}'
fi
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  run "$AI_SCRIPT" pro "oversized test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"concluded"* ]]
}

# ── setup.sh ──────────────────────────────────────────────────────────────────

@test "setup.sh creates ~/.ai-os directory structure" {
  local setup_script
  setup_script="$(dirname "$AI_SCRIPT")/setup.sh"
  rm -rf "$HOME/.ai-os/sessions/named" "$HOME/.ai-os/tmp" "$HOME/.ai-os/context"

  run bash "$setup_script" <<< $'n\nn\n'
  [ "$status" -eq 0 ]
  [ -d "$HOME/.ai-os/sessions/named" ]
  [ -d "$HOME/.ai-os/tmp" ]
}

@test "setup.sh creates instructions.md and memory.md if missing" {
  local setup_script
  setup_script="$(dirname "$AI_SCRIPT")/setup.sh"
  rm -f "$HOME/.ai-os/instructions.md" "$HOME/.ai-os/memory.md"

  run bash "$setup_script" <<< $'n\nn\n'
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ai-os/instructions.md" ]
  [ -f "$HOME/.ai-os/memory.md" ]
}

@test "setup.sh is idempotent on re-run" {
  local setup_script
  setup_script="$(dirname "$AI_SCRIPT")/setup.sh"

  run bash "$setup_script" <<< $'n\nn\n'
  [ "$status" -eq 0 ]
  run bash "$setup_script" <<< $'n\nn\n'
  [ "$status" -eq 0 ]
}

# ── ! passthrough ──────────────────────────────────────────────────────────────

@test "! passthrough executes command and bypasses model" {
  run bash -c "printf '!echo shellok\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shellok"* ]]
}

@test "! with no command does not crash" {
  run bash -c "printf '!\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
}

@test "! passthrough does not make API call" {
  local payload_file="$BATS_FILE_TMPDIR/pass_payload.json"
  cat > "$MOCK_BIN/curl" << MOCKCURL
#!/bin/bash
found_d=0
for arg in "\$@"; do
  if [[ "\$found_d" == "1" ]]; then
    printf '%s' "\$arg" > "${payload_file}"
    found_d=0
  fi
  [[ "\$arg" == "-d" ]] && found_d=1
done
echo '{"choices":[{"message":{"content":"should not appear"}}]}'
MOCKCURL
  chmod +x "$MOCK_BIN/curl"
  rm -f "$payload_file"

  run bash -c "printf '!echo hi\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  # curl was not called for the passthrough — payload file should not exist
  [ ! -f "$payload_file" ]
}

# ── /workspace ────────────────────────────────────────────────────────────────

@test "/workspace creates directory structure and saves path" {
  local ws_dir="$HOME/test_workspace_$$"

  run bash -c "printf '/workspace $ws_dir\nn\nn\nn\nn\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]

  [ -d "$ws_dir/memory" ]
  [ -f "$ws_dir/ds.md" ]
  [ -f "$ws_dir/memory/instructions.md" ]
  [ -f "$ws_dir/memory/memory.md" ]
  [ -f "$ws_dir/memory/context.md" ]
  [ -f "$HOME/.ai-os/workspace" ]
  [[ "$(< "$HOME/.ai-os/workspace")" == "$ws_dir" ]]

  rm -rf "$ws_dir"
  rm -f "$HOME/.ai-os/workspace"
}

@test "/workspace ds.md is in workspace root not memory/" {
  local ws_dir="$HOME/test_ws_root_$$"

  run bash -c "printf '/workspace $ws_dir\nn\nn\nn\nn\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]

  [ -f "$ws_dir/ds.md" ]
  [ ! -f "$ws_dir/memory/ds.md" ]

  rm -rf "$ws_dir"
  rm -f "$HOME/.ai-os/workspace"
}

# ── /project new / list / clear ───────────────────────────────────────────────

@test "/project new creates project in workspace" {
  local ws_dir="$HOME/ws_newproj_$$"
  mkdir -p "$ws_dir"
  printf '%s\n' "$ws_dir" > "$HOME/.ai-os/workspace"

  run bash -c "printf '/project new myapp\nn\nn\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]

  [ -d "$ws_dir/myapp" ]
  [ -f "$ws_dir/myapp/ds.md" ]
  [ -f "$ws_dir/myapp/context.md" ]
  [[ "$(< "$HOME/.ai-os/current-project")" == "$ws_dir/myapp" ]]

  rm -rf "$ws_dir"
  rm -f "$HOME/.ai-os/workspace"
}

@test "/project new without workspace shows error" {
  rm -f "$HOME/.ai-os/workspace"
  run bash -c "printf '/project new myapp\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workspace"* ]]
}

@test "/project list shows projects in workspace" {
  local ws_dir="$HOME/ws_list_$$"
  mkdir -p "$ws_dir/alpha" "$ws_dir/beta"
  printf '%s\n' "$ws_dir" > "$HOME/.ai-os/workspace"

  run bash -c "printf '/project list\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]

  rm -rf "$ws_dir"
  rm -f "$HOME/.ai-os/workspace"
}

@test "/project clear requires y confirmation, cancels on n" {
  printf '%s\n' "$HOME/somepath" > "$HOME/.ai-os/current-project"

  run bash -c "printf '/project clear\nn\nexit\n' | '$AI_SCRIPT' flash --interactive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Zrušené"* ]]
  # file should still exist (not cleared)
  [ -f "$HOME/.ai-os/current-project" ]
}
