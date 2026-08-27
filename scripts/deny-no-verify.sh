#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny `git commit`/`git push` with `--no-verify`.
#
# Every hook must run and surface a block instead of being bypassed — the
# parent repo's pre-commit hook is the gitlore memory gate. See
# shared-claude.md "Never --no-verify". A push failing with
# `.git/gitlore-pre-push: exec: .../pre-push: not found` is a stale hook
# shim, not a reason to bypass: `(cd <repo> && claude -p ping)` lets the
# SessionStart hook rewrite it and repoint `git config gitlore.hooksDir`.
#
# Mechanical: word-bounded presence of `--no-verify` alongside a `git`
# `commit`/`push` invocation, regardless of order or adjacency in the
# command string. Quoted regions (commit messages, prompt text passed to a
# subprocess) are stripped first, so mentioning the flag in prose doesn't
# trigger a block for a command that never actually passes it; heredoc
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
# it is undefined rather than an error — the two matches below would quietly
# stop firing and the guard would go silent. Spelling the boundary as an
# explicit non-word class says the same thing everywhere.
matches_word() { # matches_word <ere-alternation> <text>
  grep -Eq "(^|[^A-Za-z0-9_])($1)([^A-Za-z0-9_]|\$)" <<<"$2"
}

grep -Eq -- '(^|[[:space:]])--no-verify([[:space:]]|$)' <<<"$stripped" || exit 0
matches_word 'git' "$stripped" || exit 0
matches_word 'commit|push' "$stripped" || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$input")"

agent_reason="git commit/push with --no-verify is refused unconditionally.
Hooks run every time; a failing push is not resolved by bypassing them."

# The recovery is printed for my human partner to paste, so it has to be
# verbatim-runnable. The path is single-quoted (an unquoted spaced path makes
# `cd` a two-argument call that fails) with any embedded single quote
# re-quoted the POSIX way as '\''. With no cwd in the payload there is no
# path to substitute, so the cd clause is dropped rather than emitted empty —
# `(cd  && claude -p ping)` is not a command anyone can run.
if [ -n "$cwd" ]; then
  esc_cwd="${cwd//\'/\'\\\'\'}"
  recovery="(cd '$esc_cwd' && claude -p ping)"
else
  recovery="claude -p ping, from the repo root"
fi

human_msg="blocked: --no-verify refused — stale push-hook symptom? fix: $recovery"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
