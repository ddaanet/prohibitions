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
  return 0
}

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite mid-loop under `set -e`.
run() {  # $1 = command
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$hook" 2>&1 || true
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
  'git stash branch feature/foo stash@{0}' \
  'git -C d checkout -b x' \
  'git -c a=b switch -c x' \
  "g''it checkout -b x" \
  'g\it switch -c x'
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

# The trigger words only count when `git` is the command word and the walk
# lands on the subcommand: prose after echo, or a non-creating git command whose
# arguments happen to spell a creation form, must not ask.
for cmd in \
  'echo checkout -b x' \
  'echo git checkout -b x' \
  'echo git worktree add ../x' \
  'git log --oneline -- checkout -b' \
  'gh pr create --body "start with git switch -c x"'
do
  out="$(run "$cmd")"
  [ -z "$out" ] || fail "[$cmd] expected pass-through (git is not the command word, or the subcommand is not a creation form), got: $out"
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

# Only `create` asks, and it never depends on the directory, so the hook
# spawns no git, even for an operand that exists in the payload cwd, where
# the shared parser would otherwise run its rev-parse commit test. A logging
# git shim on PATH records every call; the trusted root is the payload cwd.
real_git="$(command -v git)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/abw-shim.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nexec "%s" "$@"\n' "$scratch/calls.log" "$real_git" >"$scratch/bin/git"
chmod +x "$scratch/bin/git"
: >"$scratch/f"
for cmd in 'git checkout f' 'git checkout main f' 'git checkout -b x'; do
  : >"$scratch/calls.log"
  jq -nc --arg c "$cmd" --arg d "$scratch" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' \
    | env -u CLAUDE_PROJECT_DIR PATH="$scratch/bin:$PATH" bash "$hook" >/dev/null 2>&1 || true
  [ ! -s "$scratch/calls.log" ] || fail "[$cmd] hook spawned git: $(tr '\n' '|' <"$scratch/calls.log")"
done
# Control: the discard hook, sharing the parser, does reach the shim on the
# same payload, so the empty logs above are not an unreachable shim.
: >"$scratch/calls.log"
jq -nc --arg d "$scratch" '{tool_name: "Bash", tool_input: {command: "git checkout f"}, cwd: $d}' \
  | env -u CLAUDE_PROJECT_DIR PATH="$scratch/bin:$PATH" bash "$repo_root/scripts/deny-worktree-discarding-git.sh" >/dev/null 2>&1 || true
grep -q 'rev-parse' "$scratch/calls.log" || fail "[control] the discard hook did not reach the git shim"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Write Edit Read AskUserQuestion EnterWorktree; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook" 2>&1 || true)"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
