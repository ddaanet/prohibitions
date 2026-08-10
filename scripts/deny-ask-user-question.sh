#!/usr/bin/env bash
# PreToolUse(AskUserQuestion) guard: unconditional deny.
#
# ddaanet convention is to ask inline in numbered plain prose instead, each
# question carrying a stated default, so the thread proceeds without a
# round-trip through the tool's UI. See shared-claude.md "Never call
# AskUserQuestion".
#
# Mechanical: agent is not involved.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "AskUserQuestion" ] || exit 0

agent_reason='AskUserQuestion is refused unconditionally.

Ask inline in numbered plain prose instead, each question carrying a stated
default, so the thread proceeds without a round-trip.'

human_msg="AskUserQuestion blocked: ask inline instead"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}' >&2
exit 2
