#!/usr/bin/env bash
# End-to-end test of ask-enter-worktree.sh against synthetic
# PreToolUse(EnterWorktree) payloads.
#
# Usage: bash tests/ask-enter-worktree-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/ask-enter-worktree.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

check_ask() {  # $1 = description, $2 = hook JSON output
  printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
    >/dev/null 2>&1 || fail "$1 was not asked: $2"
  [ -n "$(printf '%s' "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "$1 ask carried no permissionDecisionReason for the agent"
  [ -n "$(printf '%s' "$2" | jq -r '.systemMessage // ""')" ] \
    || fail "$1 ask carried no systemMessage for the human"
}

# EnterWorktree creating a new worktree by name asks.
out="$(jq -nc '{tool_name: "EnterWorktree", tool_input: {name: "feature-foo"}}' | bash "$hook" 2>&1 || true)"
check_ask "create by name" "$out"

# EnterWorktree switching into an existing worktree by path also asks — the
# rule covers switching, not only creation.
out="$(jq -nc '{tool_name: "EnterWorktree", tool_input: {path: "/repo/.claude/worktrees/x"}}' | bash "$hook" 2>&1 || true)"
check_ask "switch by path" "$out"

# Neither name nor path (random name generated) still asks.
out="$(jq -nc '{tool_name: "EnterWorktree", tool_input: {}}' | bash "$hook" 2>&1 || true)"
check_ask "no args" "$out"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Bash Write Edit Read AskUserQuestion ExitWorktree; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook" 2>&1 || true)"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
