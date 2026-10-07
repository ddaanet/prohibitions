#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny whole-tree `git add` — `-A`, `--all`, `.`,
# `./`, `:/`, `*`.
#
# "Add all" stages whatever happens to be in the tree, including files
# deliberately left pending — a half-finished sibling edit, a scratch
# fixture, a brief written for another repo — and the author only finds
# out after the commit exists. The redirect is to stage the paths you
# mean. `-u` stays allowed because it cannot introduce anything untracked,
# but the deny never offers it: it stages every tracked edit, a
# half-finished sibling included. The deny splits by audience: the reason
# only refuses, additionalContext carries the recovery to the agent, and
# systemMessage is the human's curt line. Rationale: docs/design.md,
# "Deny, not ask, for whole-tree `git add`".
#
# Mechanism: the command text is heredoc-stripped, split quote-aware into
# simple commands and words by `shell_split`, and each segment is walked by
# `git_walk` (scripts/lib/git-command.sh). `git` must be the command word,
# behind `VAR=value` words and the reserved words and wrappers `git_walk`
# lists, and global options such as `-C d` are skipped; `/usr/bin/git` and
# `\git` count. So `echo git add -A`, or prose in a commit message or a
# quoted string, never matches. The subcommand must be exactly `add` or
# `stage` (git's documented synonym); every word after it, `--` included,
# is searched for a whole-tree token, because a quoted spelling is the same
# word once split: `"-A"`, `'.'` and `'*'` deny like their bare forms.
# `..`, `.gitignore`, `./path/file`, `-u` and `-p` are targeted and pass.
#
# A word of unknown value (`"$f"`, or `-A"$x"`, a whole-tree token joined
# to an expansion) is never matched, so `git add "$dir"` with `dir=.`
# passes. That is under-denial, the safe direction; closing it would need
# the variable's value, which a PreToolUse hook does not have.
#
# Residuals: `$( ... )`, backticks, `bash -c` and `eval` are opaque, as are
# a `git` behind a wrapper `git_walk` does not list and the arguments
# `xargs` feeds a `git`; a word holding \036 or \037 mis-splits.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/git-command.sh
. "$(dirname "$0")/lib/git-command.sh"

main() {
  local input command stripped split seg
  input="$(cat)"
  [ "$(jq -r '.tool_name // ""' <<<"$input")" = "Bash" ] || exit 0

  command="$(jq -r '.tool_input.command // ""' <<<"$input")"
  stripped="$(strip_heredocs "$command")"
  [[ "$stripped" == *git* ]] || exit 0
  [[ "$stripped" =~ (add|stage) ]] || exit 0

  # Captured rather than read from a process substitution, whose exit status
  # is lost: a failing awk then ends the hook instead of passing the command.
  split="$(shell_split "$stripped")"
  while IFS= read -r -d $'\036' seg; do
    judge_segment "$seg"
  done <<<"$split"
  exit 0
}

# Denies when the segment is `git add`/`stage` with a whole-tree word.
judge_segment() {  # $1 = segment
  local -a words=()
  local i w
  IFS=$'\037' read -r -d '' -a words < <(printf '%s' "$1") || true

  git_walk "${words[@]}"
  (( git_sub_index >= 0 )) || return 0

  case "${words[git_sub_index]}" in
    Ladd | Lstage) ;;
    *) return 0 ;;  # `git add-something`, `git log -- .`, `git diff .`
  esac

  for (( i = git_sub_index + 1; i < ${#words[@]}; i++ )); do
    [ "${words[i]:0:1}" = "L" ] || continue
    w="${words[i]:1}"
    case "$w" in
      --all | --no-ignore-removal | . | ./ | :/ | '*') emit_deny "$w" ;;
    esac
    if [[ "$w" =~ ^-[A-Za-z]*A[A-Za-z]*$ ]]; then
      emit_deny "$w"
    fi
  done
  return 0
}

emit_deny() {  # $1 = offending token
  local deny_reason agent_context human_msg
  deny_reason="Whole-tree \`git add $1\` is refused."
  agent_context="Stage the paths you mean: \`git add <path>...\`."
  human_msg='blocked: whole-tree git add'

  jq -nc --arg r "$deny_reason" --arg a "$agent_context" --arg s "$human_msg" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r, additionalContext: $a}, systemMessage: $s}'
  exit 0
}

main
