#!/usr/bin/env bash
# PreToolUse(AskUserQuestion) guard: unconditional deny.
#
# ddaanet convention is to ask inline in numbered plain prose instead, each
# question carrying a stated default, so the thread proceeds without a
# round-trip through the tool's UI. See shared-claude.md "Never call
# AskUserQuestion".
#
# Three channels, split by audience: the deny reason is the tool_result the
# call fails with, additionalContext carries the recovery silently, and
# systemMessage is the human's one line.
#
# Mechanical: agent is not involved.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "AskUserQuestion" ] || exit 0

deny_reason='AskUserQuestion is refused unconditionally.'

agent_context='Ask inline in numbered plain prose instead, each question carrying a stated
default, so the thread proceeds without a round-trip.'

human_msg='askuserquestion blocked — convention is inline numbered questions'

jq -nc --arg r "$deny_reason" --arg a "$agent_context" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r, additionalContext: $a}, systemMessage: $s}'
exit 0
