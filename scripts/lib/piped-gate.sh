# shellcheck shell=bash
# Shared detector for the piped-gate hooks, sourced by
# deny-piped-gate-status.sh (PreToolUse) and warn-piped-gate-failure.sh
# (PostToolUse). Rationale: docs/design.md, "Piped gates: deny where the
# status is the verdict, warn elsewhere".
#
# piped_gate_scan <command> prints one `<runner><TAB><after>` line per
# pipeline that starts with a gate or test runner and pipes it onward, where
# <after> names what follows that pipeline: `and` (`&&`), `or` (`||`) or
# `end` (`;`, `&`, a newline, or the end of the command). It prints nothing
# when the command sets `pipefail` or reads `PIPESTATUS` anywhere, since
# either keeps the runner's own status.
#
# A runner is a `just` recipe named precommit, prerelease, release, lint
# or test, alone or followed by `-` or `_` (`test-unit`, `lint_docs`), or `pytest`, `py.test`, `bats` or `run-bats.sh` by
# basename, after any of: `VAR=value` prefixes, a leading `(` or `{`,
# `time`, `env`, `nice`, `timeout <duration>`, `uv run`, `python[3] -m`.
# A probe that reports no verdict (`--version`, `--help`, `--collect-only`,
# `--list` and kin) is not a runner invocation.
#
# Mechanical, not a shell parser. Heredoc bodies are stripped, then quoted
# regions, so prose naming a piped gate in a commit message does not match.
# The `pipefail`/`PIPESTATUS` test runs before the quote strip, because
# `"${PIPESTATUS[0]}"` is normally quoted; a commit message that merely
# mentions either word therefore exempts its command, which under-matches,
# the safe direction. The remaining text is split on whitespace, which is
# what the shell would do once quotes are gone; a backslash-escaped space
# splits a path into fragments, and a fragment can only fail to name a
# runner. Runners inside `bash -c "…"` or behind `$( … )` are invisible.

piped_gate_scan() {
  local text
  text="$(piped_gate_strip_heredocs "$1")"
  case "$text" in *pipefail* | *PIPESTATUS*) return 0 ;; esac
  text="$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$text")"

  case "$text" in *'|'*) ;; *) return 0 ;; esac

  # `|&` pipes stderr too; `>&` and `&>` are redirects, not separators.
  # Then one line per list element, `&&` and `||` leaving a tab and the
  # word naming them on the element they follow; `;`, a lone `&` and a
  # newline end an element with nothing after it. Whole-string
  # substitutions and a line read keep this linear: a per-character or
  # per-element substring walk is quadratic on a long command, against a
  # 5 s hook timeout.
  text="${text//'|&'/|}"
  text="${text//'>&'/>}"
  text="${text//'&>'/>}"
  text="${text//'||'/$'\t'or$'\n'}"
  text="${text//'&&'/$'\t'and$'\n'}"
  text="${text//;/$'\n'}"
  text="${text//&/$'\n'}"

  local line after
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *'|'*) ;; *) continue ;; esac
    after=end
    case "$line" in
      *$'\t'and) after=and; line="${line%$'\t'and}" ;;
      *$'\t'or) after=or; line="${line%$'\t'or}" ;;
    esac
    piped_gate_element "$line" "$after"
  done <<<"$text"
  return 0
}

# piped_gate_element <pipeline> <after>: print the runner line if the
# pipeline's first stage is a runner and a pipe follows it.
piped_gate_element() {
  case "$1" in *'|'*) ;; *) return 0 ;; esac
  piped_gate_runner "${1%%|*}"
  [ -z "$piped_gate_found" ] || printf '%s\t%s\n' "$piped_gate_found" "$2"
}

# piped_gate_runner <stage>: set piped_gate_found to the runner's display
# name, or to empty. A variable rather than output, so the caller needs no
# command substitution: one fork per piped element is seconds of CPU on a
# long command.
piped_gate_runner() {
  local toks=() tok count i=0 word recipe
  piped_gate_found=""
  read -r -a toks <<<"$1" || true
  count=${#toks[@]}

  for tok in "${toks[@]+"${toks[@]}"}"; do
    case "$tok" in
      --version | --help | -h | --collect-only | --co | --list | --count | --summary | --fixtures | --markers)
        return 0 ;;
    esac
  done

  while (( i < count )); do
    tok="${toks[i]}"
    tok="${tok#"${tok%%[!({]*}"}"
    case "$tok" in
      '' | time | env | nice) i=$((i + 1)) ;;
      timeout) i=$((i + 2)) ;;
      [A-Za-z_]*=*) i=$((i + 1)) ;;
      uv)
        [ "${toks[i+1]:-}" = run ] || break
        i=$((i + 2)) ;;
      python | python3)
        [ "${toks[i+1]:-}" = -m ] || break
        i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;  # options of the wrappers above
      *) break ;;
    esac
  done
  (( i < count )) || return 0
  tok="${toks[i]}"
  word="${tok#"${tok%%[!({]*}"}"
  word="${word##*/}"

  case "$word" in
    pytest | py.test | bats | run-bats.sh)
      piped_gate_found="$word" ;;
    just)
      i=$((i + 1))
      while (( i < count )); do
        case "${toks[i]}" in
          -f | --justfile | -d | --working-directory | --set) i=$((i + 2)) ;;
          -*) i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      recipe="${toks[i]:-}"
      recipe="${recipe%)}"
      case "$recipe" in
        precommit | prerelease | release | lint | test | \
          precommit[-_]* | prerelease[-_]* | release[-_]* | lint[-_]* | test[-_]*)
          piped_gate_found="just $recipe" ;;
      esac ;;
  esac
}

piped_gate_strip_heredocs() {
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
