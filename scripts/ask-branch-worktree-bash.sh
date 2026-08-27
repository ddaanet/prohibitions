#!/usr/bin/env bash
# PreToolUse(Bash) guard: ask before `git checkout -b`, `git switch -c`,
# `git worktree add`, or `git stash branch`.
#
# My human partner owns branching — never create or switch branches or
# worktrees unprompted. See shared-claude.md "My human partner owns
# branching". Scoped to the unambiguous creation forms only: a bare
# `git checkout <ref>` is indistinguishable from `git checkout <file>` (real
# traffic that must stay silent), so this does not fire on checkout/switch
# without a creation flag.
#
# Mechanical: the subcommand and its creation flag must be adjacent (allowing
# other flags between them), not merely co-occurring anywhere in the command
# string — co-occurrence alone false-positives on unrelated commands that
# just happen to mention both words (e.g. `git worktree list && git add -A`,
# or a commit message that mentions "checkout -b"). Quoted regions are
# stripped first so such prose in a message/title doesn't match; heredoc
# bodies are stripped the same way, since a heredoc-style commit message
# (this project's own convention for multi-line commits) isn't wrapped in
# `'`/`"` and would otherwise leak prose straight through. Doesn't try to
# fully shell-parse the command.
set -euo pipefail

strip_heredocs() {
  local heredoc_re="<<(-)?[[:space:]]*[\"']?([A-Za-z_][A-Za-z0-9_]*)"
  local in_here=0 strip_tabs=0 delim="" line cmp out=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_here" -eq 1 ]; then
      cmp="$line"
      if [ "$strip_tabs" -eq 1 ]; then
        while [ "${cmp:0:1}" = $'\t' ]; do cmp="${cmp:1}"; done
      fi
      [ "$cmp" = "$delim" ] && in_here=0
      continue
    fi
    if [[ "$line" =~ $heredoc_re ]]; then
      strip_tabs=0
      [ "${BASH_REMATCH[1]}" = "-" ] && strip_tabs=1
      delim="${BASH_REMATCH[2]}"
      in_here=1
    fi
    out+="$line"$'\n'
  done <<<"$1"
  printf '%s' "$out"
}

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "Bash" ] || exit 0

command="$(jq -r '.tool_input.command // ""' <<<"$input")"
stripped="$(strip_heredocs "$command")"
stripped="$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$stripped")"

# `\b` is a GNU extension with no POSIX ERE equivalent, so on BSD/macOS grep
# it is undefined rather than an error — every match below would quietly stop
# firing and the guard would go silent. `W` spells the same boundary in the
# ERE POSIX guarantees everywhere; the trailing edge is written out as
# `([^A-Za-z0-9_]|$)` where a subexpression follows it.
W='(^|[^A-Za-z0-9_])'

trigger=""
if grep -Eq -- "${W}checkout([[:space:]]+-[^[:space:]]+)*[[:space:]]+-[bB]([[:space:]]|\$)" <<<"$stripped"; then
  trigger="git checkout -b"
elif grep -Eq -- "${W}switch([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-[cC]|--create)([[:space:]]|\$)" <<<"$stripped"; then
  trigger="git switch -c"
elif grep -Eq -- "${W}worktree[[:space:]]+add([^A-Za-z0-9_]|\$)" <<<"$stripped"; then
  trigger="git worktree add"
elif grep -Eq -- "${W}stash[[:space:]]+branch([^A-Za-z0-9_]|\$)" <<<"$stripped"; then
  trigger="git stash branch"
else
  exit 0
fi

agent_reason="This command runs '$trigger', which creates or switches a
branch or worktree. My human partner owns branching — confirm before
proceeding, even when a workflow skill directs starting feature work on a
fresh branch or worktree."

human_msg="branch/worktree creation ($trigger) — confirm: $command"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
