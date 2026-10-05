#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny a call that would run an excluded command
# inside the sandbox — any subcommand matching an entry of the user's
# `sandbox.excludedCommands`, with `dangerouslyDisableSandbox` unset.
#
# The harness takes a call out of the sandbox only when *every* subcommand
# matches an entry and the call has none of the shapes it refuses (a `cd`, a
# file redirect, a subshell, `git -C`, …). Any other call containing an
# excluded command runs it sandboxed, where `git commit` cannot write and
# `git status`/`ls` list phantom dotfiles — piping the result to `head` or
# `sort` does not make it correct. Re-issued with the flag, the whole call
# leaves the sandbox and goes through the full permission checks instead.
#
# A call the harness already excludes passes. The hook cannot see that
# decision — it is computed after PreToolUse, and the payload's flag is only
# the model's — so it recomputes it conservatively: every subcommand matches
# and none of the shapes below is present. A shape the harness was observed
# to sandbox, documents as sandboxed, or was never seen to exclude counts as
# refused; a miss there is a silently sandboxed run, while an extra deny
# costs one re-issued call.
# Rationale: docs/design.md, "Deny any sandboxed excluded command".
#
# Mechanical, not a shell parser. Heredoc bodies are dropped, then one
# left-to-right scan drops quoted regions — quoted text is an argument,
# never a subcommand — and notes any command substitution (`$( … )`,
# backticks) outside single quotes or process substitution (`<( … )`,
# `>( … )`) outside quotes. A call carrying one is not matched at all: what
# runs inside is out of reach of text matching. The rest is split into
# subcommands on `;`, `|`, `&`, `(`, `)` and newlines; each is
# whitespace-tokenized, leading `VAR=value` assignments and shell keywords
# are skipped, and the remainder, single-spaced, is compared to every entry.
#
# The same scan notes the shapes that rule out the harness's exclusion:
# unquoted `<` or `>` (fd duplication and heredocs included), `$` outside
# single quotes, unquoted glob characters, tilde or brace expansion, `(`,
# `)`, a lone `&`, and a backslash-newline. Per subcommand, so do a skipped
# assignment or keyword, a `cd`/`pushd`/`popd`/`sudo`/`eval`/`xargs` command
# word, an option between `git` and its subcommand, and `git clone`, `init`,
# `worktree` or `bundle`.
#
# Entries follow the harness's syntax: `cmd *` or legacy `cmd:*` is a prefix
# matching `cmd` alone or followed by a space; any other `*` is a glob over
# the whole subcommand; no `*` is an exact match.
#
# Residual bounds. Only `~/.claude/settings.json` is read, as in
# warn-sandbox-excluded-commands.sh. Wrappers the harness unwraps
# (`timeout 5 git …`, `nice git …`) and command words reached through
# `xargs`, `sudo` or `sh -c` are not matched here, so they pass — the safe
# direction for a deny, which only ever under-fires. Whitespace tokenization
# runs on text with quotes already dropped, which is what the shell itself
# would split on.
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

# Sets $unquoted to $1 with quoted regions and backslash escapes dropped,
# $substitution to 1 when $1 carries a command or process substitution
# outside single quotes, and $refused to 1 when $1 carries a `$` outside
# single quotes or a backslash-newline — refused shapes $unquoted no longer
# shows.
scan_quotes() {
  local text="$1" state=none i c next
  unquoted=""
  substitution=0
  refused=0
  for (( i = 0; i < ${#text}; i++ )); do
    c="${text:i:1}"
    next="${text:i+1:1}"
    case "$state" in
      single)
        [ "$c" = "'" ] && state=none
        ;;
      double)
        case "$c" in
          "\\")
            [ "$next" = $'\n' ] && refused=1
            i=$((i + 1))
            ;;
          '"') state=none ;;
          '`') substitution=1 ;;
          '$')
            refused=1
            [ "$next" = "(" ] && substitution=1
            ;;
        esac
        ;;
      none)
        case "$c" in
          "\\")
            [ "$next" = $'\n' ] && refused=1
            i=$((i + 1))
            ;;
          "'") state=single ;;
          '"') state=double ;;
          '`') substitution=1 ;;
          '$' | '<' | '>')
            [ "$next" = "(" ] && substitution=1
            [ "$c" = '$' ] && refused=1
            unquoted+="$c"
            ;;
          *) unquoted+="$c" ;;
        esac
        ;;
    esac
  done
}

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool_name" = "Bash" ] || exit 0
[ "$(jq -r '.tool_input.dangerouslyDisableSandbox // false' <<<"$input")" = "true" ] && exit 0

# Every way of not having a list is a pass: with the sandbox off there is
# nothing to escape, and a settings file this hook cannot read is
# warn-sandbox-excluded-commands.sh's to report at session start.
settings="$HOME/.claude/settings.json"
[ -f "$settings" ] || exit 0
patterns=()
while IFS= read -r -d '' entry; do
  patterns+=("$entry")
done < <(jq -j '
  if type == "object" and (.sandbox | type) == "object" and .sandbox.enabled == true
     and (.sandbox.excludedCommands | type) == "array"
  then .sandbox.excludedCommands[] | strings | . + "\u0000"
  else empty end' "$settings" 2>/dev/null || true)
(( ${#patterns[@]} > 0 )) || exit 0

command="$(jq -r '.tool_input.command // ""' <<<"$input")"
scan_quotes "$(strip_heredocs "$command")"
(( substitution == 0 )) || exit 0

# Call-wide refused shapes, on the text with quoted regions dropped. A lone
# `&` is one left after removing every `&&`.
case "$unquoted" in *['<>()*?[']*) refused=1 ;; esac
case "${unquoted//&&/}" in *'&'*) refused=1 ;; esac
[[ "$unquoted" =~ (^|[[:space:]=:])~ ]] && refused=1
[[ "$unquoted" =~ \{[^}]*(,|\.\.)[^}]*\} ]] && refused=1

matches() { # matches <subcommand> <entry>
  local sub="$1" entry="$2" prefix
  case "$entry" in
    *' *' | *':*')
      if [[ "$entry" == *' *' ]]; then prefix="${entry% \*}"; else prefix="${entry%:\*}"; fi
      [ "$sub" = "$prefix" ] || [ "${sub#"$prefix "}" != "$sub" ]
      ;;
    *'*'*)
      # The entry is the glob: left unquoted on purpose.
      # shellcheck disable=SC2053
      [[ "$sub" == $entry ]]
      ;;
    *) [ "$sub" = "$entry" ] ;;
  esac
}

# One subcommand per line; the repeated replacement char is the point.
# shellcheck disable=SC2020
segments="$(tr ';|&()' '\n\n\n\n\n' <<<"$unquoted")"

denied=()
all_matched=1
while IFS= read -r segment; do
  tokens=()
  read -r -a tokens <<<"$segment" || true
  i=0
  while (( i < ${#tokens[@]} )); do
    case "${tokens[i]}" in
      '{' | '}' | '!' | if | then | elif | else | fi | do | done | while | until) i=$((i + 1)) ;;
      [A-Za-z_]*=*)
        if [[ "${tokens[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then i=$((i + 1)); else break; fi
        ;;
      *) break ;;
    esac
  done
  (( i == 0 )) || refused=1
  (( i < ${#tokens[@]} )) || continue
  case "${tokens[i]}" in cd | pushd | popd | sudo | eval | xargs) refused=1 ;; esac
  if [ "${tokens[i]}" = git ]; then
    case "${tokens[i+1]-}" in -* | clone | init | worktree | bundle) refused=1 ;; esac
  fi
  sub="${tokens[*]:i}"
  matched=0
  for entry in "${patterns[@]}"; do
    if matches "$sub" "$entry"; then
      matched=1
      # Name it by the entry's literal words, so `just release *` reads as
      # `just release`, not `just`.
      name="${entry% \*}"; name="${name%:\*}"; name="${name%%\**}"; name="${name% }"
      [ -n "$name" ] || name="${tokens[i]}"
      case " ${denied[*]-} " in *" $name "*) ;; *) denied+=("$name") ;; esac
      break
    fi
  done
  (( matched == 1 )) || all_matched=0
done <<<"$segments"

(( ${#denied[@]} > 0 )) || exit 0
# The harness runs this call unsandboxed itself.
(( all_matched == 1 && refused == 0 )) && exit 0

list="$(printf '%s, ' "${denied[@]}")"
list="${list%, }"

deny_reason="Refused: $list would run sandboxed — it is in sandbox.excludedCommands and this call does not set dangerouslyDisableSandbox."

agent_context="Re-issue the same command with dangerouslyDisableSandbox: true."

human_msg="blocked: $list would run sandboxed"

jq -nc --arg r "$deny_reason" --arg a "$agent_context" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r, additionalContext: $a}, systemMessage: $s}'
exit 0
