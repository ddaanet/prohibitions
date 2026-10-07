# shellcheck shell=bash
# Shared shell-text helpers, sourced by the hook scripts that read a Bash
# command as text.
#
# strip_heredocs <text> prints <text> with every heredoc body and its
# terminator line removed; the line carrying the `<<DELIM` operator stays,
# since it is still command text. `<<-` strips leading tabs before matching
# the terminator, and a quoted delimiter is recognised. Output keeps a
# trailing newline per kept line.

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
