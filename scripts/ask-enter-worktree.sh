#!/usr/bin/env bash
# PreToolUse(EnterWorktree) guard: ask before creating or switching into a
# worktree.
#
# My human partner owns branching — never create or switch branches or
# worktrees unprompted, even when a workflow skill says to start feature work
# on a fresh one. See shared-claude.md "My human partner owns branching".
#
# Mechanical: the tool call itself is the trigger, unconditionally — no path
# or argument distinguishes a wanted call from an unwanted one, that
# judgement belongs to the human being asked.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "EnterWorktree" ] || exit 0

name="$(jq -r '.tool_input.name // ""' <<<"$input")"
path="$(jq -r '.tool_input.path // ""' <<<"$input")"
target="${path:-${name:-<generated name>}}"

agent_reason="EnterWorktree creates or switches into a worktree. My human
partner owns branching — confirm before proceeding, even when a workflow
skill directs starting feature work on a fresh worktree."

human_msg="enter worktree — confirm: $target"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
