#!/usr/bin/env bash
# Unit test of shell_split in scripts/lib/shell-text.sh. Unpaired with any
# script, like portability-test.sh: the lib has no entry point of its own.
#
# Usage: bash tests/shell-text-lib-test.sh   (run from repo root)
#
# The inputs are command text under test: `$d` must stay unexpanded.
# shellcheck disable=SC2016
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=../scripts/lib/shell-text.sh
. "$repo_root/scripts/lib/shell-text.sh"

failures=0

# Renders the byte stream readably: word separator \037 as `~`, command
# separator \036 as `^`. No case input holds either character.
split_rendered() {  # $1 = already heredoc-stripped command text
  shell_split "$1" | tr '\037\036' '~^'
}

check() {  # $1 = label, $2 = input text, $3 = expected rendering
  local got
  got="$(split_rendered "$2")"
  if [ "$got" != "$3" ]; then
    printf 'FAIL: [%s] expected %q, got %q\n' "$1" "$3" "$got" >&2
    failures=$((failures + 1))
  fi
  return 0
}

check 'three words, one quoted' 'a "b c" d' 'La~Lb c~Ld~^'
check 'backslash-escaped space is one word' 'a\ b' 'La b~^'
check 'adjacent quoted part joins' 'x"y z"' 'Lxy z~^'
check 'single quotes are literal' "echo 'a \$b'" 'Lecho~La $b~^'
check 'quoted newline stays in its word' $'a "b\nc"' $'La~Lb\nc~^'
check 'unquoted newline ends the command' $'a\nb' 'La~^Lb~^'
check 'unquoted ; splits' 'a;b' 'La~^Lb~^'
check 'unquoted && splits' 'a && b' 'La~^Lb~^'
check 'unquoted | splits' 'a | b' 'La~^Lb~^'
check '; inside quotes does not split' 'echo "a;b"' 'Lecho~La;b~^'
check '&& inside quotes does not split' "echo 'a && b'" 'Lecho~La && b~^'
check '| inside quotes does not split' 'echo "a | b"' 'Lecho~La | b~^'
check '( inside quotes does not split' 'echo "a ( b"' 'Lecho~La ( b~^'
check '2>&1 is dropped' 'echo hi 2>&1' 'Lecho~Lhi~^'
check '> out is dropped with its target' 'echo hi > out' 'Lecho~Lhi~^'
check '2>/dev/null is dropped' 'git checkout -- f 2>/dev/null' 'Lgit~Lcheckout~L--~Lf~^'
check 'double-quoted $ is flagged X' 'echo "$d"' 'Lecho~X$d~^'
check 'unquoted $ is flagged X' 'echo $d' 'Lecho~X$d~^'
check '# note is dropped' 'echo hi # note' 'Lecho~Lhi~^'
check 'unbalanced quote runs to the end, adding no newline' 'x="a b' 'Lx=a b~^'

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all shell_split cases passed\n'
