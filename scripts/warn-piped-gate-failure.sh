#!/usr/bin/env bash
# PostToolUse(Bash) check: a foreground call that piped a gate or test
# runner exited 0, but the output carries a failure line.
#
# The pipe's last command sets the call's status, so a failing gate arrives
# here (PostToolUse fires only on exit 0) looking green. The failure is in
# the output the agent already has, but nothing marks it. This hook quotes
# the first failure line back as agent-only context and tells the human in
# one line. It never blocks: the call has already run. Backgrounded calls
# are skipped, since their PostToolUse carries only the launch notice;
# deny-piped-gate-status.sh refuses those. Rationale: docs/design.md, "Piped
# gates: deny where the status is the verdict, warn elsewhere".
#
# Failure lines recognised, one per runner output format: just's
# `error: Recipe … failed`, TAP `not ok`, a count of one or more `failed`
# (run-bats.sh, pytest's summary), pytest's `FAILED ` lines, and a
# `FAIL:` line or `N failure(s)` count from plain shell suites. A runner
# with another format goes unflagged, which is silence, not a false alarm.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/piped-gate.sh
. "$(dirname "$0")/lib/piped-gate.sh"

input="$(cat)"
[ "$(jq -r '.hook_event_name // ""' <<<"$input")" = "PostToolUse" ] || exit 0
[ "$(jq -r '.tool_name // ""' <<<"$input")" = "Bash" ] || exit 0
[ "$(jq -r '.tool_input.run_in_background // false' <<<"$input")" != "true" ] || exit 0

command="$(jq -r '.tool_input.command // ""' <<<"$input")"
runner="$(piped_gate_scan "$command" | cut -f1 | head -n 1)"
[ -n "$runner" ] || exit 0

stdout="$(jq -r '.tool_response.stdout // ""' <<<"$input")"
failure_re='^error: Recipe .* failed|^not ok |(^|[^0-9])[1-9][0-9]* failed([^A-Za-z]|$)|^FAILED |^FAIL:|(^|[^0-9])[1-9][0-9]* failures?([^A-Za-z]|$)'
line="$(grep -E "$failure_re" <<<"$stdout" | head -n 1 || true)"
[ -n "$line" ] || exit 0
line="${line:0:200}"

agent_context="Treat this \`$runner\` run as failed: its output contains \`$line\`. The call exited 0 because the pipe's last command set the status."

human_msg="$runner failed behind a pipe that reported exit 0"

jq -nc --arg a "$agent_context" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $a}, systemMessage: $s}'
exit 0
