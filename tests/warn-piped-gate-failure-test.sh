#!/usr/bin/env bash
# The commands and outputs under test are literal shell text: `$` and
# backticks in them must reach the hook unexpanded.
# shellcheck disable=SC2016
# End-to-end test of warn-piped-gate-failure.sh against synthetic
# PostToolUse(Bash) payloads.
#
# The contract under test: a foreground call that pipes a gate or test runner
# exits with the pipe's status, so a failing gate arrives on PostToolUse
# looking green. When its output carries a failure line, the hook tells the
# agent the run failed. Green output, an unpiped runner, a backgrounded call
# (whose PostToolUse carries no output yet) and any non-runner command pass
# silent.
#
# Usage: bash tests/warn-piped-gate-failure-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/warn-piped-gate-failure.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

run() {  # $1 = command, $2 = stdout, $3 = run_in_background (true|false)
  jq -nc --arg c "$1" --arg o "$2" --argjson b "${3:-false}" \
    '{hook_event_name: "PostToolUse", tool_name: "Bash",
      tool_input: ({command: $c} + (if $b then {run_in_background: true} else {} end)),
      tool_response: {stdout: $o, stderr: "", interrupted: false}}' \
    | bash "$hook" 2>&1 || true
}

assert_warned() {  # $1 = label, $2 = hook output, $3 = expected quoted line
  printf '%s' "$2" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' \
    >/dev/null 2>&1 || { fail "[$1] did not warn: $2"; return; }
  printf '%s' "$2" | jq -e --arg l "$3" '.hookSpecificOutput.additionalContext | contains($l)' \
    >/dev/null 2>&1 || fail "[$1] additionalContext does not quote the failure line '$3': $2"
  printf '%s' "$2" | jq -e '.hookSpecificOutput.additionalContext | test("failed")' \
    >/dev/null 2>&1 || fail "[$1] additionalContext does not say the run failed: $2"
  printf '%s' "$2" | jq -e '.systemMessage | length > 0' \
    >/dev/null 2>&1 || fail "[$1] no systemMessage for the human: $2"
}

piped='just precommit 2>&1 | tail -40'

# Failure lines, one per runner's output format.
check_warn() {  # $1 = label, $2 = command, $3 = stdout, $4 = expected line
  assert_warned "$1" "$(run "$2" "$3")" "$4"
}
check_warn 'just recipe failure' "$piped" \
  $'ok 41 x\nerror: Recipe `test-unit` failed with exit code 1' \
  'error: Recipe `test-unit` failed with exit code 1'
check_warn 'TAP not ok' 'bats tests/ | tail -20' \
  $'ok 1 a\nnot ok 2 b\nok 3 c' 'not ok 2 b'
check_warn 'run-bats.sh count' 'scripts/run-bats.sh tests/ | tail -3' \
  'bats: 1032 passed, 1 failed — full log: /tmp/gitlore-bats.abc' \
  'bats: 1032 passed, 1 failed'
check_warn 'pytest summary' 'pytest -q | tail -3' \
  $'..F.\n2 failed, 5 passed in 1.20s' '2 failed, 5 passed in 1.20s'
check_warn 'pytest FAILED line' 'uv run pytest | tail -20' \
  $'FAILED tests/test_x.py::test_y - assert 1 == 2\n===== 1 failed in 0.1s =====' \
  'FAILED tests/test_x.py::test_y'
check_warn 'shell suite count' "$piped" \
  $'FAIL: [x] was not denied\n\n3 failure(s)' 'FAIL: [x] was not denied'

# Green or unrelated output passes silent.
for case in \
  "$piped"$'\t'$'ok 1 a\nall hook scenarios passed' \
  'scripts/run-bats.sh tests/ | tail -3'$'\t''bats: 1033 passed, 0 failed — full log: /tmp/x' \
  'pytest -q | tail -3'$'\t''5 passed in 0.30s' \
  'cat "$TMPDIR/log" | tail'$'\t''error: Recipe `test` failed with exit code 1' \
  'just precommit'$'\t''ok' \
  'set -o pipefail; just precommit | tail'$'\t''error: Recipe `x` failed'
do
  cmd="${case%%$'\t'*}"
  out_text="${case#*$'\t'}"
  out="$(run "$cmd" "$out_text")"
  [ -z "$out" ] || fail "[$cmd] expected silence, got: $out"
done

# A backgrounded call's PostToolUse carries the launch notice, never the
# gate's output; the PreToolUse half owns that case.
out="$(run "$piped" 'error: Recipe `x` failed' true)"
[ -z "$out" ] || fail "[background] expected silence, got: $out"

# Any other event or tool passes through silent.
other="$(jq -nc '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "just precommit | tail"}}' | bash "$hook" 2>&1 || true)"
[ -z "$other" ] || fail "[PreToolUse event] expected silence, got: $other"
for t in Write Edit Read; do
  passthrough="$(jq -nc --arg t "$t" '{hook_event_name: "PostToolUse", tool_name: $t, tool_input: {}, tool_response: {}}' | bash "$hook" 2>&1 || true)"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
