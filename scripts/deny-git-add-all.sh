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
# Mechanical, not a shell parser. Heredoc bodies and quoted regions are
# stripped first (as in deny-no-verify.sh) so prose mentioning `git add
# -A` in a commit message doesn't fire the guard — but a quoted
# whole-tree pathspec is unwrapped ahead of that strip, since there it is
# the argument rather than prose. All four are quotable and mean the same
# thing quoted: `'*'` must be quoted to reach git at all, and `'.'`,
# `'./'`, `':/'` stage the whole tree exactly as their bare spellings do.
# The command is then split into segments on `;`, `|` and `&` (covering
# `&&`, `||`, `|`, `;`, background `&`) plus newlines, and each segment
# is whitespace-tokenized and walked by `git_walk`
# (scripts/lib/git-command.sh: find `git`, skip its global options); the
# subcommand it locates must be exactly `add` or `stage` (git's documented
# synonym), then the rest is searched for a whole-tree token.
#
# Residual bound of whitespace tokenization: this is shell text with
# quotes already removed, so splitting on whitespace is what the shell
# itself would do. A backslash-escaped space in an unquoted path splits
# into fragments, but a fragment never equals a whole-tree token, so it
# can only under-deny, never false-deny.
#
# Residual bound of the unwrap: it matches a quoted pathspec as written,
# so an interpolated one — `git add "$dir"` with `dir=.` — is invisible
# here and passes. That is under-denial, the safe direction; closing it
# would need the variable's value, which a PreToolUse hook does not have.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/git-command.sh
. "$(dirname "$0")/lib/git-command.sh"

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "Bash" ] || exit 0

command="$(jq -r '.tool_input.command // ""' <<<"$input")"
stripped="$(strip_heredocs "$command")"
# Quoting the pattern keeps `*` literal rather than a glob.
for spec in '*' ':/' '.' './'; do
  stripped="${stripped//"'$spec'"/$spec}"
  stripped="${stripped//"\"$spec\""/$spec}"
done
stripped="$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$stripped")"

# One segment per line. The three separator characters all map to a
# newline; the repeated replacement char is the point, not a typo.
# shellcheck disable=SC2020
segments="$(tr ';|&' '\n\n\n' <<<"$stripped")"

denied=""
while IFS= read -r segment; do
  tokens=()
  read -r -a tokens <<<"$segment" || true
  count=${#tokens[@]}

  # git_walk finds the first `git` and skips its global options; a
  # segment with no `git` or no subcommand is not an add. Every token
  # here is literal text, so each carries the `L` flag the walk expects.
  flagged=()
  for tok in ${tokens[@]+"${tokens[@]}"}; do flagged+=("L$tok"); done
  git_walk ${flagged[@]+"${flagged[@]}"}
  (( git_sub_index >= 0 )) || continue
  i=$git_sub_index

  case "${tokens[i]}" in
    add | stage) i=$((i + 1)) ;;
    *) continue ;;  # `git add-something`, `git log -- .`, `git diff .`
  esac

  # Every remaining token, including after `--`: a whole-tree pathspec
  # is whole-tree wherever it sits. `..`, `.gitignore`, `./path/file`,
  # `-u` and `-p` are all targeted and pass.
  while (( i < count )); do
    case "${tokens[i]}" in
      --all | --no-ignore-removal | . | ./ | :/ | '*') denied="${tokens[i]}"; break 2 ;;
    esac
    if [[ "${tokens[i]}" =~ ^-[A-Za-z]*A[A-Za-z]*$ ]]; then
      denied="${tokens[i]}"
      break 2
    fi
    i=$((i + 1))
  done
done <<<"$segments"

[ -n "$denied" ] || exit 0

deny_reason="Whole-tree \`git add $denied\` is refused."

agent_context="Stage the paths you mean: \`git add <path>...\`."

human_msg='blocked: whole-tree git add'

jq -nc --arg r "$deny_reason" --arg a "$agent_context" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r, additionalContext: $a}, systemMessage: $s}'
exit 0
