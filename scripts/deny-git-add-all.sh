#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny whole-tree `git add` — `-A`, `--all`, `.`,
# `./`, `:/`, `*`.
#
# "Add all" stages whatever happens to be in the tree, including files
# deliberately left pending — a half-finished sibling edit, a scratch
# fixture, a brief written for another repo — and the author only finds
# out after the commit exists. Stage the paths you mean, or `git add -u`
# for already-tracked files only; `-u` stays allowed because it cannot
# introduce anything untracked. Rationale: docs/design.md, "Deny, not ask,
# for whole-tree `git add`".
#
# Mechanical, not a shell parser. Heredoc bodies and quoted regions are
# stripped first (as in deny-no-verify.sh) so prose mentioning `git add
# -A` in a commit message doesn't fire the guard — but the two quoted
# whole-tree pathspecs `'*'`/`"*"` and `':/'`/`":/"` are unwrapped ahead
# of that strip, since there they are the argument rather than prose.
# The command is then split into segments on `;`, `|` and `&` (covering
# `&&`, `||`, `|`, `;`, background `&`) plus newlines, and each segment
# is whitespace-tokenized and walked: find `git`, skip its global
# options, require the subcommand to be exactly `add` or `stage` (git's
# documented synonym), then look for a whole-tree token among the rest.
#
# Residual bound of whitespace tokenization: this is shell text with
# quotes already removed, so splitting on whitespace is what the shell
# itself would do. A backslash-escaped space in an unquoted path splits
# into fragments, but a fragment never equals a whole-tree token, so it
# can only under-deny, never false-deny.
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
stripped="$(sed -E "s/'\\*'/*/g; s/\"\\*\"/*/g; s/':\\/'/:\\//g; s/\":\\/\"/:\\//g" <<<"$stripped")"
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

  # The command word. Anything before it (env assignments, `sudo`, a
  # redirection) is skipped; a segment with no `git` is not an add.
  i=0
  while (( i < count )) && [ "${tokens[i]}" != "git" ]; do i=$((i + 1)); done
  (( i < count )) || continue
  i=$((i + 1))

  # git's own global options sit between `git` and the subcommand. Six
  # of them take a separate operand and must consume the next token too;
  # their `--opt=value` spellings are a single token and need no skip.
  while (( i < count )); do
    case "${tokens[i]}" in
      -C | -c | --git-dir | --work-tree | --namespace | --config-env) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  (( i < count )) || continue

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

agent_reason="git add $denied stages everything pending in the tree, including files deliberately left unstaged — a half-finished sibling edit, a scratch fixture, a brief for another repo. The author only finds out after the commit exists.
Stage the paths you mean (\`git add <path>...\`), or \`git add -u\` for already-tracked files only."

human_msg="blocked: whole-tree git add refused — name the paths, or git add -u for tracked files only"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
