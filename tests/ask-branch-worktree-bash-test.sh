#!/usr/bin/env bash
# End-to-end test of ask-branch-worktree-bash.sh against synthetic
# PreToolUse(Bash) payloads.
#
# Usage: bash tests/ask-branch-worktree-bash-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/ask-branch-worktree-bash.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

run() {  # $1 = command
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$hook"
}

# Real must-ask traffic: the three creation forms named in the brief, plus
# their -B/--create variants and a flag-before-the-creation-flag ordering.
for cmd in \
  'git checkout -b feature/foo' \
  'git checkout -b feature/foo origin/main' \
  'git checkout -B main origin/main' \
  'git checkout --track -b feature/foo origin/feature/foo' \
  'git switch -c feature/foo' \
  'git switch --create feature/foo' \
  'git worktree add ../foo feature/foo' \
  'git stash branch feature/foo' \
  'git stash branch feature/foo stash@{0}'
do
  out="$(run "$cmd")"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
    >/dev/null 2>&1 || fail "[$cmd] was not asked: $out"
  [ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "[$cmd] ask carried no permissionDecisionReason for the agent"
  [ -n "$(printf '%s' "$out" | jq -r '.systemMessage // ""')" ] \
    || fail "[$cmd] ask carried no systemMessage for the human"
done

# Real must-allow traffic named explicitly in the brief as an over-match
# risk, plus other everyday git commands sharing a word with the trigger.
for cmd in \
  'git checkout CLAUDE.md' \
  'git checkout .' \
  'git checkout main' \
  'git switch main' \
  'git branch' \
  'git branch -a' \
  'git worktree list' \
  'git worktree remove ../foo' \
  'git status' \
  'git stash list' \
  'git stash pop' \
  'git stash show branch'
do
  out="$(run "$cmd")"
  [ -z "$out" ] || fail "[$cmd] expected pass-through, got: $out"
done

# Compound/unrelated commands that merely co-occur the trigger words without
# the actual adjacent creation form must not false-positive.
for cmd in \
  'git worktree list && git add -A' \
  'git commit -m "add branch/worktree ask hook for checkout -b"' \
  'git -c core.pager=cat switch main' \
  'git diff -b -- src/checkout.js' \
  'grep -rn -b needle checkout/' \
  'gh pr create --title "worktree docs" --body "how to add one"' \
  'git stash pop && git branch -a'
do
  out="$(run "$cmd")"
  [ -z "$out" ] || fail "[$cmd] expected pass-through (no adjacent creation form), got: $out"
done

# A heredoc-style commit message (this project's own convention for
# multi-line commits) that documents "checkout -b" in prose must not
# false-ask — heredoc bodies aren't quoted with '/" so the quote-stripping
# alone doesn't cover them; the hook must also strip heredoc bodies.
heredoc_cmd="$(cat <<'CMD'
git commit -m "$(cat <<'EOF'
Document why checkout -b needs confirmation before running.
EOF
)"
CMD
)"
out="$(run "$heredoc_cmd")"
[ -z "$out" ] || fail "heredoc commit message mentioning checkout -b expected pass-through, got: $out"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Write Edit Read AskUserQuestion EnterWorktree; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook")"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
