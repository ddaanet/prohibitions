#!/usr/bin/env bash
# End-to-end test of ask-write-edit-outside-project.sh against synthetic
# PreToolUse(Write|Edit) payloads.
#
# Usage: bash tests/ask-write-edit-outside-project-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/ask-write-edit-outside-project.sh"
export CLAUDE_PROJECT_DIR="$repo_root"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

run() {  # $1 = tool_name, $2 = file_path
  jq -nc --arg t "$1" --arg f "$2" '{tool_name: $t, tool_input: {file_path: $f}}' | bash "$hook"
}

# A real in-project path (the file this test itself lives in) is allowed
# through silently, for both matched tools.
for t in Write Edit; do
  out="$(run "$t" "$repo_root/tests/ask-write-edit-outside-project-test.sh")"
  [ -z "$out" ] || fail "[$t] in-project path expected pass-through, got: $out"
done

# The project root itself (no trailing path) is in-project.
out="$(run "Write" "$repo_root")"
[ -z "$out" ] || fail "project root itself expected pass-through, got: $out"

# A real out-of-repo path — another of my human partner's repos — asks.
outside="$HOME/code/gitlore/README.md"
for t in Write Edit; do
  out="$(run "$t" "$outside")"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
    >/dev/null 2>&1 || fail "[$t] out-of-project path was not asked: $out"
  [ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "[$t] ask carried no permissionDecisionReason for the agent"
  [ -n "$(printf '%s' "$out" | jq -r '.systemMessage // ""')" ] \
    || fail "[$t] ask carried no systemMessage for the human"
done

# A sibling directory sharing the repo's name as a prefix must still ask —
# guards against a naive substring-prefix check on CLAUDE_PROJECT_DIR.
sibling="${repo_root}-sibling/file.txt"
out="$(run "Write" "$sibling")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
  >/dev/null 2>&1 || fail "prefix-sharing sibling path was not asked: $out"

# A relative traversal that resolves back inside the project is allowed.
out="$(run "Write" "$repo_root/tests/../CLAUDE.md")"
[ -z "$out" ] || fail "traversal resolving in-project expected pass-through, got: $out"

# A traversal that escapes the project asks.
out="$(run "Write" "$repo_root/../outside.txt")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
  >/dev/null 2>&1 || fail "traversal resolving out-of-project was not asked: $out"

# Scratch space is exempt: it holds no repo to protect, and this harness's
# own conventions route all temp files through TMPDIR/scratchpad.
export TMPDIR="${TMPDIR:-/tmp}"
out="$(run "Write" "$TMPDIR/prohibitions-test-scratch.txt")"
[ -z "$out" ] || fail "TMPDIR path expected pass-through, got: $out"

out="$(run "Write" "/tmp/prohibitions-test-scratch.txt")"
[ -z "$out" ] || fail "bare /tmp path expected pass-through, got: $out"

# Dropping a note in another repo is permitted — the prose forbids editing
# *in place*. A Write creating a not-yet-existing .md file outside the
# project passes through; everything else out-of-project still asks.
new_md="${repo_root}-sibling/brief-probe.md"
[ ! -e "$new_md" ] || fail "test precondition: $new_md unexpectedly exists"
out="$(run "Write" "$new_md")"
[ -z "$out" ] || fail "new out-of-project .md via Write expected pass-through, got: $out"

# Edit on the same path is an in-place modification by definition.
out="$(run "Edit" "$new_md")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
  >/dev/null 2>&1 || fail "Edit on out-of-project .md was not asked: $out"

# Write over an existing out-of-project .md clobbers it: ask.
[ -f "$outside" ] || fail "test precondition: $outside must exist"
out="$(run "Write" "$outside")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
  >/dev/null 2>&1 || fail "Write over existing out-of-project .md was not asked: $out"

# A new non-.md file can be code: ask.
out="$(run "Write" "${repo_root}-sibling/hook.sh")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
  >/dev/null 2>&1 || fail "new out-of-project non-.md was not asked: $out"

# The two .md locations that change behaviour are not notes: ask.
for p in "${repo_root}-sibling/CLAUDE.md" "${repo_root}-sibling/.claude/commands/x.md"; do
  out="$(run "Write" "$p")"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
    >/dev/null 2>&1 || fail "new behaviour-changing .md ($p) was not asked: $out"
done

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
