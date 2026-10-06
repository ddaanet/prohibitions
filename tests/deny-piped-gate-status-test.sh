#!/usr/bin/env bash
# The commands and outputs under test are literal shell text: `$` and
# backticks in them must reach the hook unexpanded.
# shellcheck disable=SC2016
# End-to-end test of deny-piped-gate-status.sh against synthetic
# PreToolUse(Bash) payloads.
#
# The contract under test: a gate or test runner (`just` recipes named
# precommit, prerelease, release, lint or test*, `pytest`, `bats`,
# `run-bats.sh`) piped into another command reports the pipe's exit status,
# not its own. That is denied where the status is the verdict: a call run in
# the background, whose completion notice is all the agent sees, or a
# pipeline followed by `&&` or `||`, which acts on the masked status. A
# foreground pipe with nothing chained after it passes; the PostToolUse half
# (warn-piped-gate-failure.sh) covers it.
#
# Usage: bash tests/deny-piped-gate-status-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-piped-gate-status.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite mid-loop under `set -e`.
run() {  # $1 = command, $2 = run_in_background (true|false)
  jq -nc --arg c "$1" --argjson b "${2:-false}" --arg d "$repo_root" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: ({command: $c} + (if $b then {run_in_background: true} else {} end)), cwd: $d}' \
    | bash "$hook" 2>&1 || true
}

assert_denied() {  # $1 = label, $2 = hook output
  printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || { fail "[$1] was not denied: $2"; return; }
  [ -n "$(printf '%s' "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "[$1] deny carried no permissionDecisionReason"
  # The recovery is agent-only: drop the pipe, or set pipefail first.
  printf '%s' "$2" | jq -e '.hookSpecificOutput.additionalContext // "" | contains("pipefail")' \
    >/dev/null 2>&1 || fail "[$1] additionalContext does not name the pipefail recovery: $2"
  printf '%s' "$2" | jq -e '.systemMessage == "blocked: piped gate invocation"' \
    >/dev/null 2>&1 || fail "[$1] systemMessage is not the curt blocked line: $2"
}

# Backgrounded: the completion notice reports the pipe's status, so any
# piped gate run in the background is denied, chained or not.
for cmd in \
  'just precommit 2>&1 | tail -40' \
  'just release patch 2>&1 | tail -20' \
  'pytest -q | tail -3' \
  'just test | tee "$TMPDIR/log"' \
  $'cd sub\njust precommit | tail'
do
  assert_denied "background: $cmd" "$(run "$cmd" true)"
done

# Foreground, with the masked status consumed by `&&` or `||`.
for cmd in \
  'just precommit 2>&1 | tail -40 && git commit -m wip' \
  'just precommit |& tail -40 && git commit -m wip' \
  'just test-unit 2>&1 | tail -5 || echo failed' \
  'cd sub && just lint | head && git push' \
  'pytest -q tests/ | tail -3 && git commit -m wip' \
  'uv run pytest | tail && git commit -m wip' \
  'python -m pytest -x | tail && git commit -m wip' \
  'python3 -m pytest | tail && git commit -m wip' \
  '.venv/bin/pytest | tail && git commit -m wip' \
  'scripts/run-bats.sh tests/ | tail -3 && git commit -m wip' \
  'bats tests/ | tee "$TMPDIR/log" && git commit -m wip' \
  '(just precommit) 2>&1 | tail && git commit -m wip' \
  'FOO=1 just prerelease | tail && just release patch' \
  'just -f other/justfile precommit | tail && git commit -m wip' \
  $'git status\njust precommit | grep -v ok && git commit -m wip'
do
  assert_denied "chained: $cmd" "$(run "$cmd")"
done

# `timeout` here is command text under test, never run.
assert_denied 'chained: timeout wrapper' "$(run 'timeout 900 just precommit | tail && git commit -m wip')"  # portability-ok

# Real must-allow traffic.
for cmd in \
  'just precommit 2>&1 | tail -40' \
  'pytest -q | tail -3' \
  'just precommit && git commit -m wip' \
  'just precommit 2>&1 | tail -40; git status' \
  'set -o pipefail; just precommit 2>&1 | tail -40 && git commit -m wip' \
  'just test 2>&1 | tee "$TMPDIR/log"; exit ${PIPESTATUS[0]}' \
  'pytest --collect-only -q | tail -3 && echo ok' \
  'pytest --co -q | tail -3 && echo ok' \
  'bats --version | head -1 && echo ok' \
  'just --list | head && echo ok' \
  'just build | tail && git commit -m wip' \
  'just testing-notes | tail && echo ok' \
  "grep -n '@test' tests/*.bats | head && echo ok" \
  'grep -c FAIL "$TMPDIR/gitlore-bats.abc123" | head && echo ok' \
  'echo pytest | cat && echo ok' \
  'just precommit > "$TMPDIR/log" 2>&1 && tail "$TMPDIR/log"' \
  'git commit -m "run just precommit | tail && push"' \
  'git commit -m "wip; just precommit | tail && push"' \
  "git commit -m 'pytest | tail || true'" \
  "git commit -m \$'wip\\njust precommit | tail && push'"
do
  out="$(run "$cmd")"
  [ -z "$out" ] || fail "[$cmd] expected pass-through, got: $out"
done

# Backgrounded but not piped, or with the status preserved, passes.
for cmd in \
  'just precommit' \
  'just precommit > "$TMPDIR/log" 2>&1' \
  'set -o pipefail; just precommit 2>&1 | tail -40'
do
  out="$(run "$cmd" true)"
  [ -z "$out" ] || fail "[background: $cmd] expected pass-through, got: $out"
done

# A heredoc commit message documenting the refused form is prose, even
# when a body line starts with the runner.
heredoc_cmd="$(cat <<'CMD'
git commit -F- <<'EOF' && git push
just precommit | tail && git commit is now refused
EOF
CMD
)"
out="$(run "$heredoc_cmd")"
[ -z "$out" ] || fail "heredoc commit message expected pass-through, got: $out"

# Every other tool passes through silent, even if ever mis-wired.
for t in Write Edit Read AskUserQuestion; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {command: "just precommit | tail && x"}}' | bash "$hook" 2>&1 || true)"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
