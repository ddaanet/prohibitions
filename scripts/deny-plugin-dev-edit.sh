#!/usr/bin/env bash
# PreToolUse(Write|Edit) guard: deny edits inside any plugin-dev/ subtree.
#
# plugin-dev/ is vendored via `git subtree` from claude-plugin-dev, pinned to
# a tag. It is generated, read-only content: changes go to the source repo,
# get tagged, then land here via `just update-plugin-dev vX.Y.Z`. See
# shared-claude.md "Never hand-edit a vendored subtree".
#
# Mechanical: any absolute path with a `plugin-dev` path component.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
case "$tool_name" in
  Write | Edit) ;;
  *) exit 0 ;;
esac

file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
[ -n "$file_path" ] || exit 0

case "$file_path" in
  */plugin-dev/*) ;;
  *) exit 0 ;;
esac

agent_reason="This path is inside a vendored plugin-dev/ subtree — generated,
read-only content pulled from claude-plugin-dev via git subtree. Edits belong
in the claude-plugin-dev source repo, released as a tag, and reach this copy
through the update-plugin-dev release step — not made directly here."

human_msg="blocked: plugin-dev/ is vendored, read-only — edit claude-plugin-dev instead"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
