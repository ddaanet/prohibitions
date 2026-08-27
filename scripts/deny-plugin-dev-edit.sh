#!/usr/bin/env bash
# PreToolUse(Write|Edit) guard: deny edits inside any plugin-dev/ subtree.
#
# plugin-dev/ is vendored via `git subtree` from claude-plugin-dev, pinned to
# a tag. It is generated, read-only content: changes go to the source repo,
# get tagged, then land here via `just update-plugin-dev vX.Y.Z`. See
# shared-claude.md "Never hand-edit a vendored subtree".
#
# Mechanical: a `plugin-dev` path component sitting at a git tree root.
# Relative paths are live traffic, so the match is not anchored on an
# absolute path; a nested vendor/thing/plugin-dev/ is somebody else's
# directory of that name and passes.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
case "$tool_name" in
  Write | Edit) ;;
  *) exit 0 ;;
esac

file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
[ -n "$file_path" ] || exit 0

# The segment counts only at a git tree root, tested by `.git` adjacency —
# no subprocess and no path resolution. `%%` takes the outermost occurrence,
# which is the tree root by construction. `-e` and not `-d`: a linked
# worktree carries .git as a gitlink *file*. The relative branch resolves
# `.` against the hook process's cwd, which CC sets to the live session cwd —
# the best available answer for a path the model emitted relative to it.
# Rationale, including why not CLAUDE_PROJECT_DIR: docs/design.md,
# "Tree-root anchoring by `.git` adjacency".
case "$file_path" in
  plugin-dev/*) parent="." ;;
  */plugin-dev/*) parent="${file_path%%/plugin-dev/*}"; [ -n "$parent" ] || parent=/ ;;
  *) exit 0 ;;
esac
[ -e "$parent/.git" ] || exit 0

agent_reason="This path is inside a vendored plugin-dev/ subtree — generated,
read-only content pulled from claude-plugin-dev via git subtree. Edits belong
in the claude-plugin-dev source repo, released as a tag, and reach this copy
through the update-plugin-dev release step — not made directly here."

human_msg="blocked: plugin-dev/ is vendored, read-only — edit claude-plugin-dev instead"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
