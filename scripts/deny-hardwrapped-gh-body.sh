#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny `gh pr|issue create|comment|edit|review
# --body-file` when the referenced file hard-wraps a paragraph.
#
# GitHub bodies are not hard-wrapped: one physical line per paragraph,
# because every newline renders as <br>. Blank lines between paragraphs,
# list items and headings are still correct — the rule is about
# mid-paragraph newlines. See shared-claude.md "GitHub bodies are not
# hard-wrapped".
#
# Mechanical: scoped to --body-file (a real path to lint), not --body
# (inline text isn't reliably extractable from a shell command string, and
# ddaanet's own convention already routes drafts to a file). Doesn't detect
# a hand-written files-changed list — that is judgement, not mechanical.
#
# Covers pr/issue create, comment, edit and review (the commands that post a
# body from a file); not release --notes-file, a different flag and a
# different audience (changelog notes), out of scope for this rule.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "Bash" ] || exit 0

# `\b` is a GNU extension with no POSIX ERE equivalent, so on BSD/macOS grep
# it is undefined rather than an error — every match below would quietly stop
# firing and the guard would go silent. Spelling the boundary as an explicit
# non-word class says the same thing everywhere.
matches_word() { # matches_word <ere-alternation> <text>
  grep -Eq "(^|[^A-Za-z0-9_])($1)([^A-Za-z0-9_]|\$)" <<<"$2"
}

command="$(jq -r '.tool_input.command // ""' <<<"$input")"
matches_word 'gh' "$command" || exit 0
matches_word 'pr|issue' "$command" || exit 0
matches_word 'create|comment|edit|review' "$command" || exit 0
grep -Eq -- '--body-file([^A-Za-z0-9_]|$)' <<<"$command" || exit 0

# Emits the violating line number for $1, or 0 if it's clean.
find_violation_line() {
  local file="$1" in_fence=0 prev_nonblank="" prev_structural=0 line_no=0
  local line structural
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))

    if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
      in_fence=$((1 - in_fence))
      prev_nonblank=""
      continue
    fi
    [ "$in_fence" -eq 1 ] && continue

    if [ -z "$line" ]; then
      prev_nonblank=""
      continue
    fi

    structural=0
    if [[ "$line" =~ ^[[:space:]]*(\#{1,6}[[:space:]]|[-*+][[:space:]]|[0-9]+\.[[:space:]]|\>|\||\<) ]] \
      || [[ "$line" =~ ^[[:space:]]*(---|\*\*\*|___)[[:space:]]*$ ]]; then
      structural=1
    fi

    if [ -n "$prev_nonblank" ] && [ "$structural" -eq 0 ] && [ "$prev_structural" -eq 0 ]; then
      echo "$line_no"
      return
    fi
    prev_nonblank="$line"
    prev_structural=$structural
  done <"$file"
  echo 0
}

# A compound command can chain more than one gh body-posting call (e.g.
# creating a linked issue then PR) — check every --body-file, not just the
# first, so a wrapped second file isn't silently missed.
body_files="$(grep -Eo -- '--body-file[= ][^[:space:]]+' <<<"$command" || true)"
[ -n "$body_files" ] || exit 0

violation_file=""
violation_line=0
while IFS= read -r match; do
  [ -n "$match" ] || continue
  body_file="${match#--body-file}"
  body_file="${body_file#=}"
  body_file="${body_file# }"
  body_file="${body_file%\"}"
  body_file="${body_file#\"}"
  body_file="${body_file%\'}"
  body_file="${body_file#\'}"
  if [ -z "$body_file" ] || [ "$body_file" = "-" ] || [ ! -f "$body_file" ]; then
    continue
  fi

  line="$(find_violation_line "$body_file")"
  if [ "$line" -gt 0 ]; then
    violation_file="$body_file"
    violation_line="$line"
    break
  fi
done <<<"$body_files"

[ -n "$violation_file" ] || exit 0

agent_reason="$violation_file hard-wraps a paragraph — line $violation_line follows
a non-blank line with no blank line between them. Every newline in a GitHub
body renders as <br>; use one physical line per paragraph, with blank lines
between paragraphs, list items and headings. Rewrite $violation_file, then retry."

human_msg="blocked: hard-wrapped GitHub body — $violation_file:$violation_line"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
