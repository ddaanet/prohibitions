# shellcheck shell=bash
# Shared path helpers, sourced by the hook scripts that compare a tool's
# target path against a directory.

# A set CDPATH makes `cd` print the directory it lands in, which would be
# captured by the `$(cd … && pwd)` in abspath below and corrupt every path.
# Cleared here, at source time, so no caller has to remember it.
unset CDPATH

# Portable stand-in for `realpath -m`: absolute, symlinks resolved on the
# longest existing prefix, the non-existent remainder appended as written.
# `-m` is GNU-only — BSD/macOS realpath rejects it, and macOS before 12.3
# ships no realpath at all — so the hook would die under `set -e` on every
# Write there. `cd -P`/`pwd` are POSIX; CDPATH is cleared because a set
# CDPATH makes `cd` print the directory and corrupt the substitution.
#
# Residual bound: `..` inside the *non-existent* tail is not collapsed
# (`/exists/nope/../../x` stays literal), where `realpath -m` would collapse
# it. That can only fail to match the project prefix, i.e. ask where it need
# not have — the safe direction for an ask guard. `..` through existing
# directories is resolved, which is the case real traversals take.
abspath() { # abspath <path>; prints the resolved absolute path
  local p="$1" tail="" head
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  head="$p"
  while [ ! -d "$head" ]; do
    tail="${head##*/}${tail:+/$tail}"
    head="${head%/*}"
    [ -n "$head" ] || head=/
  done
  head="$(cd -P -- "$head" && pwd)" || return 1
  [ -n "$tail" ] || { printf '%s\n' "$head"; return 0; }
  case "$head" in
    /) printf '/%s\n' "$tail" ;;
    *) printf '%s/%s\n' "$head" "$tail" ;;
  esac
}
