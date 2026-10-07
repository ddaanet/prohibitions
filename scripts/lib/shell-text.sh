# shellcheck shell=bash
# Shared shell-text helpers, sourced by the hook scripts that read a Bash
# command as text.
#
# strip_heredocs <text> prints <text> with every heredoc body and its
# terminator line removed; the line carrying the `<<DELIM` operator stays,
# since it is still command text. `<<-` strips leading tabs before matching
# the terminator, and a quoted delimiter is recognised. Output keeps a
# trailing newline per kept line.
#
# shell_split <text> splits already heredoc-stripped command text into simple
# commands and words, quote-aware. Output is a byte stream: each word ends in
# \037 and each simple command, the last included, in \036. A word's first
# byte is a flag: `L` literal, `X` when the word holds an unquoted or
# double-quoted `$`, a backtick or `$'...'`, so its value is unknown.
#   - '...' is literal; "..." honours \" \\ \$ and \`; outside quotes a
#     backslash escapes the next byte. Adjacent parts join (a"b c" is `ab c`)
#     and the quote characters go. An unbalanced quote runs to the input end.
#   - Unquoted ; & | && || |& ( ) and newline end a simple command. Inside
#     quotes, $( ... ), ${ ... } and backticks they do not: those stay in
#     their word, flagged X.
#   - An unquoted < or > (with optional digits before it at a word start;
#     also &> and >&) starts a redirection, dropped with its target, the
#     rest of the word or the next word, so `2>/dev/null` and `<<'EOF'`
#     never become pathspecs.
#   - An unquoted `#` at a word start drops the rest of the line.
# Callers read segments with `IFS= read -r -d $'\036'` and split a segment on
# \037. One awk program under LC_ALL=C using only POSIX awk features (run on
# mawk; BSD awk reviewed, not run). Linear in practice: each step scans a
# window of at most 1 KB, and a word grows through two small buffers, so it
# is recopied once per 64 KB rather than once per piece (a per-byte bash
# loop took 11 s for 20 KB).
# Residuals: a word holding \036 or \037 mis-splits; $VAR, `~`, globs and
# braces are not expanded; $( ... ), backticks, `bash -c`, `eval` and
# `xargs` are opaque; subshell scoping is not modelled.

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

shell_split() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    BEGIN {
      sq = "\047"; mode = 0; inword = 0; w = ""; u = ""; t = ""; xf = 0
      drop = 0; skip = 0; nwords = 0; cont = 0; csq = 0; pendnl = 0
      plain0 = "^[^ \t;&|()<>\047\"\\\\$`#]+"
      sp_dq = "[\"\\\\$`]"
      sp_cs = "[\047\"\\\\(){}]"
    }
    # Appends to the current word, which is w u t: pieces land in t, t
    # spills into u past 1 KB and u into w past 64 KB, so a word built from
    # many small pieces is not recopied whole on every append.
    function ap(s) {
      t = t s
      if (length(t) > 1024) {
        u = u t; t = ""
        if (length(u) > 65536) { w = w u; u = "" }
      }
    }
    function endword() {
      if (!inword) return
      if (drop) drop = 0
      else if (skip) skip = 0
      else { printf "%s%s%s%s\037", (xf ? "X" : "L"), w, u, t; nwords++ }
      w = ""; u = ""; t = ""; xf = 0; inword = 0
    }
    function endcmd() {
      skip = 0
      if (nwords > 0) { printf "\036"; nwords = 0 }
    }
    function cs_enter(opener, closer, ret) {
      cso = opener; csc = closer; csd = 1; csret = ret; csq = 0; mode = 3
    }
    # Consumes a redirection operator starting at i (digits, <>, an optional
    # & | - suffix) and arms drop (target in the same word) or skip (target is
    # the next word).
    function redir(   c) {
      while (substr(line, i, 1) ~ /[0-9]/) i++
      if (substr(line, i, 1) == "&") i++
      while (substr(line, i, 1) ~ /[<>]/) i++
      if (substr(line, i, 1) ~ /[&|-]/) i++
      c = substr(line, i, 1)
      if (i > n || c == " " || c == "\t") skip = 1
      else {
        drop = 1; inword = 1
        if (c == "(") { ap("("); cs_enter("(", ")", 0); i++ }
      }
    }
    {
      line = $0; n = length(line); i = 1
      if (pendnl) { ap("\n"); pendnl = 0 }
      while (i <= n) {
        if (mode == 1) {
          rest = substr(line, i, 1024); p = index(rest, sq)
          if (p == 0) { ap(rest); i += length(rest) }
          else { ap(substr(rest, 1, p - 1)); i += p; mode = 0 }
        } else if (mode == 2) {
          rest = substr(line, i, 1024)
          if (!match(rest, sp_dq)) { ap(rest); i += length(rest); continue }
          ap(substr(rest, 1, RSTART - 1)); i += RSTART - 1
          c = substr(line, i, 1); nx = substr(line, i + 1, 1)
          if (c == "\"") { mode = 0; i++ }
          else if (c == "\\") {
            if (i == n) { cont = 1; i++ }
            else if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { ap(nx); i += 2 }
            else { ap("\\"); i++ }
          } else if (c == "$" && (nx == "(" || nx == "{")) {
            xf = 1; ap("$" nx); cs_enter(nx, (nx == "(" ? ")" : "}"), 2); i += 2
          } else if (c == "$") { xf = 1; ap("$"); i++ }
          else { xf = 1; ap("`"); mode = 4; csret = 2; i++ }
        } else if (mode == 3) {
          rest = substr(line, i, 1024)
          if (csq == 1) {
            p = index(rest, sq)
            if (p == 0) { ap(rest); i += length(rest) }
            else { ap(substr(rest, 1, p)); i += p; csq = 0 }
            continue
          }
          if (!match(rest, sp_cs)) { ap(rest); i += length(rest); continue }
          ap(substr(rest, 1, RSTART - 1)); i += RSTART - 1
          c = substr(line, i, 1)
          if (csq == 2) {
            if (c == "\"") csq = 0
            if (c == "\\" && i < n) { ap(c); i++; c = substr(line, i, 1) }
            ap(c); i++
            continue
          }
          if (c == sq) csq = 1
          else if (c == "\"") csq = 2
          else if (c == "\\" && i < n) { ap(c); i++; c = substr(line, i, 1) }
          else if (c == cso) csd++
          else if (c == csc) { csd--; if (csd == 0) mode = csret }
          ap(c); i++
        } else if (mode == 4) {
          rest = substr(line, i, 1024)
          if (!match(rest, "[`\\\\]")) { ap(rest); i += length(rest); continue }
          ap(substr(rest, 1, RSTART - 1)); i += RSTART - 1
          c = substr(line, i, 1)
          if (c == "\\" && i < n) { ap(c substr(line, i + 1, 1)); i += 2 }
          else { ap(c); i++; if (c == "`") mode = csret }
        } else if (mode == 5) {
          rest = substr(line, i, 1024)
          if (!match(rest, "[\047\\\\]")) { ap(rest); i += length(rest); continue }
          ap(substr(rest, 1, RSTART - 1)); i += RSTART - 1
          c = substr(line, i, 1)
          if (c == "\\" && i < n) { ap(c substr(line, i + 1, 1)); i += 2 }
          else { ap(c); i++; if (c == sq) mode = 0 }
        } else {
          rest = substr(line, i, 1024); c = substr(rest, 1, 1); nx = substr(line, i + 1, 1)
          if (!inword && match(rest, "^[0-9]+[<>]")) redir()
          else if (match(rest, plain0)) { inword = 1; ap(substr(rest, 1, RLENGTH)); i += RLENGTH }
          else if (c == " " || c == "\t") { endword(); i++ }
          else if (c == ";" || c == "|" || c == "(" || c == ")") { endword(); endcmd(); i++ }
          else if (c == "&") {
            endword()
            if (nx == ">") redir()
            else { endcmd(); i++ }
          }
          else if (c == "<" || c == ">") { endword(); redir() }
          else if (c == sq) { inword = 1; mode = 1; i++ }
          else if (c == "\"") { inword = 1; mode = 2; i++ }
          else if (c == "\\") {
            if (i == n) { cont = 1; i++ }
            else { inword = 1; ap(nx); i += 2 }
          } else if (c == "$") {
            inword = 1; xf = 1
            if (nx == "(" || nx == "{") { ap("$" nx); cs_enter(nx, (nx == "(" ? ")" : "}"), 0); i += 2 }
            else if (nx == sq) { ap("$" sq); mode = 5; i += 2 }
            else { ap("$"); i++ }
          } else if (c == "`") { inword = 1; xf = 1; ap("`"); mode = 4; csret = 0; i++ }
          else if (inword) { ap("#"); i++ }
          else i = n + 1
        }
      }
      if (cont) cont = 0
      else if (mode == 0) { endword(); endcmd() }
      else pendnl = 1
    }
    END { endword(); endcmd() }
  '
}
