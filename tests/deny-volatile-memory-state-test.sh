#!/usr/bin/env bash
# End-to-end test of deny-volatile-memory-state.sh against synthetic
# PreToolUse(Write|Edit) payloads.
#
# Usage: bash tests/deny-volatile-memory-state-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-volatile-memory-state.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

sha='4b825dc642cb6eb9a060e54bf8d69288fbee4904'  # git's empty-tree sha — a real, meaningful 40-hex sha

# Write with volatile content in a memory/**.md path is denied.
out="$(jq -nc --arg s "$sha" \
  '{tool_name: "Write", tool_input: {file_path: "'"$repo_root"'/memory/ddaanet/example.md", content: ("fixed as of " + $s)}}' \
  | bash "$hook" 2>&1)" || true
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "Write with sha in memory/ was not denied: $out"
[ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
  || fail "deny carried no permissionDecisionReason for the agent"
[ -n "$(printf '%s' "$out" | jq -r '.systemMessage // ""')" ] \
  || fail "deny carried no systemMessage for the human"

# Edit introducing a full sha via new_string in a memory/**.md path is
# denied, even when old_string is clean.
out="$(jq -nc --arg s "$sha" \
  '{tool_name: "Edit", tool_input: {file_path: "'"$repo_root"'/memory/ddaanet/example.md", old_string: "before", new_string: ("tip is " + $s + " right now")}}' \
  | bash "$hook" 2>&1)" || true
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "Edit with a full sha in memory/ was not denied: $out"

# origin/<ref> is a durable name, exactly what the rule says to use instead
# of a sha — it must NOT be treated as volatile state.
out="$(jq -nc \
  '{tool_name: "Write", tool_input: {file_path: "'"$repo_root"'/memory/ddaanet/example.md", content: "the release reads from origin/main"}}' \
  | bash "$hook")"
[ -z "$out" ] || fail "origin/<ref> as a durable name expected pass-through, got: $out"

# The same volatile content outside memory/**.md is allowed — this repo's
# own task handoff file is real traffic that legitimately isn't memory.
out="$(jq -nc --arg s "$sha" \
  '{tool_name: "Write", tool_input: {file_path: "'"$repo_root"'/.claude/handoff-task.md", content: ("fixed as of " + $s)}}' \
  | bash "$hook")"
[ -z "$out" ] || fail "volatile content outside memory/ expected pass-through, got: $out"

# Ordinary durable-name content in a real memory file is allowed — this
# repo's own shared-claude.md tier file, unmodified.
out="$(jq -nc --arg c "$(head -c 4000 "$repo_root/memory/ddaanet/shared-claude.md")" \
  '{tool_name: "Write", tool_input: {file_path: "'"$repo_root"'/memory/ddaanet/shared-claude.md", content: $c}}' \
  | bash "$hook")"
[ -z "$out" ] || fail "durable-name memory content expected pass-through, got: $out"

# An abbreviated hex sequence must not false-positive — the rule is scoped
# to full 40-hex shas.
out="$(jq -nc \
  '{tool_name: "Write", tool_input: {file_path: "'"$repo_root"'/memory/ddaanet/example.md", content: "see commit f59674b for context"}}' \
  | bash "$hook")"
[ -z "$out" ] || fail "abbreviated sha expected pass-through, got: $out"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Bash Read AskUserQuestion; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook")"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
