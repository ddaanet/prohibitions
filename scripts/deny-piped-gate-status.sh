#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny a gate or test runner piped into another
# command where the pipe's exit status becomes the verdict.
#
# Without `pipefail`, `just precommit | tail` exits with `tail`'s status, so
# a failing gate reports success. Two shapes act on that status before
# anyone reads the output: a call run in the background, whose completion
# notice ("exit code 0") is all the agent sees, and a pipeline followed by
# `&&` or `||`, which commits or pushes on the masked status. Those are
# denied. A foreground pipe with nothing chained after it passes, and
# warn-piped-gate-failure.sh flags its failure text afterwards. Rationale:
# docs/design.md, "Piped gates: deny where the status is the verdict, warn
# elsewhere". Detection lives in lib/piped-gate.sh.
#
# The deny splits by audience: the reason refuses, additionalContext carries
# the recovery to the agent, systemMessage is the human's curt line.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/piped-gate.sh
. "$(dirname "$0")/lib/piped-gate.sh"

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "Bash" ] || exit 0

command="$(jq -r '.tool_input.command // ""' <<<"$input")"
background="$(jq -r '.tool_input.run_in_background // false' <<<"$input")"

runner=""
while IFS=$'\t' read -r name after; do
  [ -n "$name" ] || continue
  if [ "$background" = "true" ] || [ "$after" != "end" ]; then
    runner="$name"
    break
  fi
done <<<"$(piped_gate_scan "$command")"

[ -n "$runner" ] || exit 0

if [ "$background" = "true" ]; then
  deny_reason="Backgrounded \`$runner\` behind a pipe is refused: its completion notice would carry the pipe's exit status, not the gate's."
else
  deny_reason="\`$runner\` behind a pipe, chained with \`&&\` or \`||\`, is refused: the chain would act on the pipe's exit status, not the gate's."
fi

agent_context="Run the gate so its own exit status is the call's: drop the pipe, or start the command with \`set -o pipefail;\`."

human_msg='blocked: piped gate invocation'

jq -nc --arg r "$deny_reason" --arg a "$agent_context" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r, additionalContext: $a}, systemMessage: $s}'
exit 0
