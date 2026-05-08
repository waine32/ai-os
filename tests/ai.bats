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
  rm -f /tmp/ai_last_output.txt
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
  [ "$output" = "test response" ]
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
