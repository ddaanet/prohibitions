#!/usr/bin/env bash
# End-to-end test of deny-ask-user-question.sh against synthetic
# PreToolUse(AskUserQuestion) payloads.
#
# Usage: bash tests/deny-ask-user-question-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-ask-user-question.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite mid-loop under `set -e`.
run() {  # $1 = tool_name. Deny path writes JSON to stdout, exit 0.
  jq -nc --arg t "$1" '{tool_name: $t, tool_input: {}}' | bash "$hook" 2>&1 || true
}

# AskUserQuestion is always denied.
out="$(run "AskUserQuestion")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "AskUserQuestion call was not denied: $out"
[ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
  || fail "deny carried no permissionDecisionReason for the agent"
[ -n "$(printf '%s' "$out" | jq -r '.systemMessage // ""')" ] \
  || fail "deny carried no systemMessage for the human"

# The recovery rides additionalContext, not the deny reason: verified on CC
# 2.1.258 that a deny still delivers it, as a hook_additional_context
# attachment bound to the same toolUseID. Keeping the two separate is what
# stops the instructional prose rendering with the blocked call.
[ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')" ] \
  || fail "deny carried no additionalContext for the agent"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("inline") | not' \
  >/dev/null 2>&1 || fail "deny reason still carries the inline-questions recovery"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("inline")' \
  >/dev/null 2>&1 || fail "additionalContext does not carry the inline-questions recovery"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Bash Write Edit Read; do
  passthrough="$(run "$t")"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
