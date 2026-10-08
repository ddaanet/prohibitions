#!/usr/bin/env bash
# PreToolUse(Bash) guard: ask before `git checkout -b`, `git switch -c`,
# `git worktree add`, or `git stash branch`.
#
# My human partner owns branching — never create or switch branches or
# worktrees unprompted. See shared-claude.md "My human partner owns
# branching". Scoped to the creation forms: a plain `git checkout <ref>` or
# `git switch <ref>` does not ask. Branch versus path is decidable now
# (`git_checkout_parse` makes that call for the deny hook), so asking on a
# plain switch is possible, but it is a separate decision this hook has not
# taken.
#
# Mechanism: the command text is heredoc-stripped, split quote-aware into
# simple commands and words by `shell_split`, and each segment is walked by
# `git_walk` (scripts/lib/git-command.sh). `git` must be the command word,
# global options such as `-C d` and `-c a=b` skipped, so `echo checkout -b x`,
# a commit message or a `-- checkout -b` pathspec never matches. A
# `checkout`/`switch` goes to `git_checkout_parse`, and mode `create` asks
# (`-b`, `-B`, `-c`, `-C`, `--orphan`, `--create` in any order or cluster);
# `worktree add` and `stash branch` are the first argument after the
# subcommand. The mode for `create` does not depend on the directory, so
# the directory is passed as unknown: no `cd` tracking, no lookup on disk,
# and no `git` subprocess. A forced create (`checkout -f -b x`) is
# `discard_switch`, not `create`: deny-worktree-discarding-git.sh refuses
# it, and a deny would beat this hook's ask, so this hook does not ask.
#
# Residuals: `$( ... )`, backticks, `bash -c` and `eval` are opaque, and so
# is a `git` behind a wrapper `git_walk` does not list; a word holding \036
# or \037 mis-splits.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/git-command.sh
. "$(dirname "$0")/lib/git-command.sh"

main() {
  local input command stripped pre split seg
  input="$(cat)"
  [ "$(jq -r '.tool_name // ""' <<<"$input")" = "Bash" ] || exit 0

  command="$(jq -r '.tool_input.command // ""' <<<"$input")"
  stripped="$(strip_heredocs "$command")"
  # Prefilter on the text with quote and backslash characters dropped, so a
  # word bash de-quotes to `git` (`g''it`, `g\it`) still enters.
  pre="${stripped//[\'\"\\]/}"
  [[ "$pre" == *git* ]] || exit 0

  # Captured rather than read from a process substitution, whose exit status
  # is lost. A failing awk passes the call with a systemMessage, never blocks.
  split="$(shell_split "$stripped")" || shell_split_failed ask-branch-worktree-bash
  while IFS= read -r -d $'\036' seg; do
    judge_segment "$seg"
  done <<<"$split"
  exit 0
}

# Asks when the segment is one of the four creation forms.
judge_segment() {  # $1 = segment
  local -a words=() args=()
  local sub
  IFS=$'\037' read -r -d '' -a words < <(printf '%s' "$1") || true

  git_walk "${words[@]}"
  (( git_sub_index >= 0 )) || return 0

  sub="${words[git_sub_index]:1}"
  if (( ${#words[@]} > git_sub_index + 1 )); then
    args=("${words[@]:git_sub_index+1}")
  fi

  case "$sub" in
    checkout | switch)
      git_checkout_parse "" "$sub" "${args[@]+"${args[@]}"}"
      [ "$gc_mode" = "create" ] || return 0
      if [ "$sub" = "checkout" ]; then emit_ask "git checkout -b"; else emit_ask "git switch -c"; fi ;;
    worktree)
      [ "${args[0]+${args[0]:1}}" = "add" ] && emit_ask "git worktree add" ;;
    stash)
      [ "${args[0]+${args[0]:1}}" = "branch" ] && emit_ask "git stash branch" ;;
  esac
  return 0
}

emit_ask() {  # $1 = trigger
  local agent_reason human_msg
  agent_reason="This command runs '$1', which creates or switches a
branch or worktree. My human partner owns branching — confirm before
proceeding, even when a workflow skill directs starting feature work on a
fresh branch or worktree."
  human_msg="branch/worktree creation ($1) — confirm: $command"

  jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}, systemMessage: $s}'
  exit 0
}

main
