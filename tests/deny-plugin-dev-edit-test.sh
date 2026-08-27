#!/usr/bin/env bash
# End-to-end test of deny-plugin-dev-edit.sh against synthetic
# PreToolUse(Write|Edit) payloads.
#
# Usage: bash tests/deny-plugin-dev-edit-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-plugin-dev-edit.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

run() {  # $1 = tool_name, $2 = file_path. Deny path writes JSON to stdout, exit 0.
  jq -nc --arg t "$1" --arg f "$2" '{tool_name: $t, tool_input: {file_path: $f}}' | bash "$hook" 2>&1
}

# A real file inside this repo's own vendored subtree is denied.
target="$repo_root/plugin-dev/release.just"
for t in Write Edit; do
  out="$(run "$t" "$target")" || true
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || fail "[$t] plugin-dev/ path was not denied: $out"
  [ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "[$t] deny carried no permissionDecisionReason for the agent"
  [ -n "$(printf '%s' "$out" | jq -r '.systemMessage // ""')" ] \
    || fail "[$t] deny carried no systemMessage for the human"
done

# A real file this repo's own source tree, sharing no plugin-dev path
# component, is allowed through unharmed.
out="$(run "Write" "$repo_root/justfile")"
[ -z "$out" ] || fail "non-plugin-dev path expected pass-through, got: $out"

# A directory name that merely starts with plugin-dev but isn't the segment
# must not false-positive.
out="$(run "Write" "$repo_root/plugin-dev-notes/file.txt")"
[ -z "$out" ] || fail "plugin-dev-notes/ (not the exact segment) expected pass-through, got: $out"

# --- tree-root anchoring ---------------------------------------------------
#
# The segment counts only at a git tree root, tested by `.git` adjacency.
# Rationale: docs/design.md, "Tree-root anchoring by `.git` adjacency".

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run_in() {  # $1 = cwd, $2 = tool_name, $3 = file_path
  jq -nc --arg t "$2" --arg f "$3" '{tool_name: $t, tool_input: {file_path: $f}}' \
    | (cd "$1" && bash "$hook") 2>&1 || true
}

# A bare relative file_path is live traffic — the model emits one constantly —
# and must deny when the hook's cwd is the repo root.
out="$(run_in "$repo_root" Write "plugin-dev/release.just")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "relative plugin-dev/ path was not denied: $out"

# A linked worktree carries .git as a gitlink *file*, so the anchor tests -e
# and not -d. CC's own worktrees live at .claude/worktrees/<name> inside the
# launch repo, which is why the anchor is .git adjacency and not
# CLAUDE_PROJECT_DIR.
mkdir -p "$work/wt/plugin-dev"
printf 'gitdir: %s/.git/worktrees/probe\n' "$repo_root" >"$work/wt/.git"
out="$(run Write "$work/wt/plugin-dev/release.just")" || true
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "worktree gitlink-file root was not denied: $out"

# A plugin-dev/ nested below a tree root is some other directory of that name,
# not this repo's vendored subtree.
out="$(run Write "$repo_root/vendor/nested/plugin-dev/x.sh")"
[ -z "$out" ] || fail "nested plugin-dev/ expected pass-through, got: $out"

# A plugin-dev/ under a directory that is no git tree at all.
mkdir -p "$work/loose/plugin-dev"
out="$(run Write "$work/loose/plugin-dev/x.sh")"
[ -z "$out" ] || fail "plugin-dev/ outside any git tree expected pass-through, got: $out"

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
