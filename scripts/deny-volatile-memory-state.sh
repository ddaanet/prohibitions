#!/usr/bin/env bash
# PreToolUse(Write|Edit) guard: deny volatile git state landing in a
# memory/**.md file.
#
# No commit ids, branch tips, or "uncommitted as of" notes in memory —
# identify things by durable names instead: branches, paths, issue numbers.
# A session that needs exact volatile state puts it in a handoff, not
# memory. See shared-claude.md "No volatile git state in memory files".
#
# Mechanical: scoped to full 40-hex shas only, per the rule's own carve-out
# ("upstream-main shas are stable but still discouraged"). Abbreviated hex
# would false-positive on ordinary prose. A ref name like `origin/main` is
# not itself volatile — it's the durable name the rule says to use instead
# of a sha — so it is deliberately not matched here.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
case "$tool_name" in
  Write | Edit) ;;
  *) exit 0 ;;
esac

file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
case "$file_path" in
  */memory/*.md) ;;
  *) exit 0 ;;
esac

if [ "$tool_name" = "Write" ]; then
  content="$(jq -r '.tool_input.content // ""' <<<"$input")"
else
  content="$(jq -r '.tool_input.new_string // ""' <<<"$input")"
fi

hit="$(grep -Eom1 '\b[0-9a-fA-F]{40}\b' <<<"$content" | head -n1 || true)"
[ -n "$hit" ] || exit 0

agent_reason="This write introduces volatile git state into a memory file
('$hit'). Memory identifies things by durable names — branches, paths, issue
numbers — never commit ids or branch tips, even a stable upstream-main sha.
Rewrite the reference by durable name, or if the exact volatile state is what
needs preserving, put it in a handoff instead of memory."

human_msg="blocked: volatile git state in memory file — $file_path"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
