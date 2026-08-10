#!/usr/bin/env bash
# PreToolUse(Write|Edit) guard: ask before writing outside CLAUDE_PROJECT_DIR.
#
# ddaanet convention is that other repos stay read-only — a finding gets
# investigated, verified and proposed, never edited in place. See
# shared-claude.md "Other repos stay read-only". This can't be a deny: a
# legitimately targeted path outside the project (e.g. a note dropped in
# another repo, an edit my human partner explicitly asked for there) must
# still go through, so the decision is ask, not deny.
#
# Mechanical: the boundary is CLAUDE_PROJECT_DIR, not judgement about which
# paths are "another repo" — except scratch space (TMPDIR, /tmp), which is
# exempted since it holds no repo to protect.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
case "$tool_name" in
  Write | Edit) ;;
  *) exit 0 ;;
esac

file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
[ -n "$file_path" ] || exit 0

project_dir="$(realpath -m "${CLAUDE_PROJECT_DIR:-$PWD}")"
target="$(realpath -m "$file_path")"

case "$target" in
  "$project_dir" | "$project_dir"/*) exit 0 ;;
esac

# Scratch space is not "another repo" — exempt it so the harness's own
# scratchpad and temp-file conventions don't trigger a confirmation.
if [ -n "${TMPDIR:-}" ]; then
  tmp_dir="$(realpath -m "$TMPDIR")"
  case "$target" in
    "$tmp_dir" | "$tmp_dir"/*) exit 0 ;;
  esac
fi
case "$target" in
  /tmp | /tmp/*) exit 0 ;;
esac

agent_reason="Target is outside the project directory ($project_dir). ddaanet
convention: other repos stay read-only — a finding there gets investigated,
verified and proposed, never edited in place, unless this specific write is
explicitly authorized here."

human_msg="write/edit outside project — confirm: $target"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
