#!/usr/bin/env bash
# End-to-end test of deny-no-verify.sh against synthetic PreToolUse(Bash)
# payloads.
#
# Usage: bash tests/deny-no-verify-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-no-verify.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite mid-loop under `set -e`.
run() {  # $1 = command. Deny path writes JSON to stdout, exit 0.
  jq -nc --arg c "$1" --arg d "$repo_root" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$hook" 2>&1 || true
}

# Real must-block traffic: --no-verify on commit and on push, in either
# argument order, alone or chained after other commands.
for cmd in \
  'git commit --no-verify -m "wip"' \
  'git commit -m "wip" --no-verify' \
  'git push --no-verify' \
  'git add -A && git commit -m "wip" && git push --no-verify'
do
  out="$(run "$cmd")"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || fail "[$cmd] was not denied: $out"
  printf '%s' "$out" | jq -e '.systemMessage | contains("claude -p ping")' \
    >/dev/null 2>&1 || fail "[$cmd] systemMessage missing the stale-shim recovery: $out"
  [ -n "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "[$cmd] deny carried no permissionDecisionReason for the agent"
done

# The recovery command is printed for a human to paste, so it must be
# verbatim-runnable: the substituted repo path is quoted, or a spaced path
# turns `cd /Users/x/my repo` into a two-argument cd that fails.
out="$(jq -nc '{tool_name: "Bash", tool_input: {command: "git push --no-verify"}, cwd: "/tmp/my repo"}' \
  | bash "$hook" 2>&1 || true)"
printf '%s' "$out" | jq -e '.systemMessage | contains("(cd '\''/tmp/my repo'\'' && claude -p ping)")' \
  >/dev/null 2>&1 || fail "spaced repo path was not quoted in the recovery command: $out"

# A single quote inside the path has to be re-quoted the POSIX way, or the
# quoting added above is itself what breaks the command. Both the path and
# the expectation are assembled from named characters: spelling them inline
# needs four levels of escaping and stops being readable or checkable.
sq="'"
bs="\\"
quoted_repo="/tmp/o${sq}brien/repo"
expected="(cd ${sq}/tmp/o${sq}${bs}${sq}${sq}brien/repo${sq} && claude -p ping)"
out="$(jq -nc --arg d "$quoted_repo" \
  '{tool_name: "Bash", tool_input: {command: "git push --no-verify"}, cwd: $d}' \
  | bash "$hook" 2>&1 || true)"
printf '%s' "$out" | jq -e --arg e "$expected" '.systemMessage | contains($e)' \
  >/dev/null 2>&1 || fail "single quote in the repo path was not re-quoted: $out"

# With no cwd in the payload there is no path to substitute, so the cd clause
# is dropped rather than emitted empty — `(cd  && claude -p ping)` is not a
# command anyone can run.
out="$(jq -nc '{tool_name: "Bash", tool_input: {command: "git push --no-verify"}}' \
  | bash "$hook" 2>&1 || true)"
printf '%s' "$out" | jq -e '.systemMessage | contains("claude -p ping")' \
  >/dev/null 2>&1 || fail "cwd-less payload lost the stale-shim recovery: $out"
printf '%s' "$out" | jq -e '.systemMessage | contains("cd") | not' \
  >/dev/null 2>&1 || fail "cwd-less payload emitted a cd clause with no path: $out"

# Real must-allow traffic: this repo's own commit workflow, and other real
# commands that share a word with the trigger but aren't the trigger.
for cmd in \
  'git commit -m "add hook 4"' \
  'git push' \
  'git status' \
  'git branch' \
  'git checkout CLAUDE.md' \
  'npm run build -- --no-verify-jwt && git commit -m "add commit"' \
  'git commit -m "document that --no-verify is refused"'
do
  out="$(run "$cmd")"
  [ -z "$out" ] || fail "[$cmd] expected pass-through, got: $out"
done

# A heredoc-style commit message (this project's own convention for
# multi-line commits) that documents "--no-verify" in prose must not
# false-deny — heredoc bodies aren't quoted with '/" so the quote-stripping
# alone doesn't cover them; the hook must also strip heredoc bodies.
heredoc_cmd="$(cat <<'CMD'
git commit -m "$(cat <<'EOF'
Document that --no-verify is refused by the new hook.
EOF
)"
CMD
)"
out="$(run "$heredoc_cmd")"
[ -z "$out" ] || fail "heredoc commit message mentioning --no-verify expected pass-through, got: $out"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Write Edit Read AskUserQuestion; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook" 2>&1 || true)"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
