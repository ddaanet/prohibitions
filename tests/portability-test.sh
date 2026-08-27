#!/usr/bin/env bash
# Repo-wide check that no hook or test reaches for a GNU-only construct.
#
# The platform contract is in docs/design.md: these hooks run wherever Claude
# Code runs, which includes macOS, so every script must hold to POSIX plus
# bash 3.2 — the bash Apple has shipped since 2007. shellcheck does not cover
# this class, and neither does the suite: a GNU-only construct is green on
# every Linux run by construction, and the failure it causes on macOS is
# either a hard `illegal option` death or, worse, a matcher that silently
# stops matching. Only a static check catches it before it ships.
#
# Behavioural coverage lives alongside this where the failure mode allows it:
# ask-write-edit-outside-project-test.sh stubs realpath and readlink out of
# PATH entirely and asserts the hook still resolves paths. `\b` has no such
# test because BSD grep does not error on it — it just stops matching, which
# no stub on a GNU box can reproduce faithfully.
#
# Usage: bash tests/portability-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# This file names every banned construct in its own check table, so it is the
# one file that cannot be scanned by them.
self="tests/portability-test.sh"

# Comment lines are skipped: the scripts explain *why* each construct is
# banned, and those explanations necessarily spell it out. A code line can
# opt out with a trailing `# portability-ok`, which the stub-building lines
# in ask-write-edit-outside-project-test.sh need — they name the GNU tools on
# purpose, to prove the hook runs without them.
code_lines() { # code_lines <file>; prints `<line-number>:<text>` for real code
  grep -nvE '^[[:space:]]*#' "$1" | grep -vF '# portability-ok' || true
}

# check <label> <ere> <remedy>
check() {
  local label="$1" pattern="$2" remedy="$3" f hit
  for f in scripts/*.sh tests/*.sh; do
    [ "$f" != "$self" ] || continue
    hit="$(code_lines "$f" | grep -E "$pattern" || true)"
    [ -z "$hit" ] || fail "$f: $label — $remedy
    $hit"
  done
  return 0
}

# `\b` is a GNU extension with no POSIX ERE equivalent. BSD/macOS grep does
# not error on it, it just stops matching, so a guard using it goes silent.
check 'GNU-only \b word boundary' \
  '\\b' \
  'spell the boundary as ([^A-Za-z0-9_]|^) / ([^A-Za-z0-9_]|$)'

# BSD realpath has no -m, and macOS before 12.3 ships no realpath at all;
# `readlink -f` is likewise GNU-only. ask-write-edit-outside-project.sh
# carries a portable abspath() built from `cd -P` and `pwd`.
check 'GNU-only path resolution' \
  '(^|[^A-Za-z0-9_-])(realpath|readlink)([^A-Za-z0-9_-]|$)' \
  'use the abspath() helper (cd -P + pwd)'

# The remaining GNU-only spellings this project has any reason to reach for.
check 'GNU-only sed -i without a backup suffix' \
  'sed +-i +[^.]' \
  'BSD sed requires an argument: sed -i.bak … && rm f.bak'
check 'GNU-only grep -P' '(^|[^A-Za-z0-9_-])grep +(-[A-Za-z]* )*-[A-Za-z]*P' \
  'PCRE is GNU-only; use -E'
check 'GNU-only date -d' '(^|[^A-Za-z0-9_-])date +(-[A-Za-z]* )*-d' \
  'BSD date uses -v/-j -f'
check 'GNU-only stat -c' '(^|[^A-Za-z0-9_-])stat +(-[A-Za-z]* )*-c' \
  'BSD stat uses -f'
check 'GNU-only find -printf' '(^|[^A-Za-z0-9_-])find .*-printf' \
  'not in BSD find; use -exec or -print0'
check 'timeout(1) is absent on macOS' '(^|[^A-Za-z0-9_-])timeout ' \
  'feature-detect, or background the job and kill it'
# shellcheck disable=SC2016  # the $ is an ERE end anchor, not an expansion
check 'paste -s with no file operand' 'paste +-s[a-z]*[^-]*$' \
  'BSD paste needs the explicit `-` operand'

# macOS ships bash 3.2. Everything below arrived in bash 4.
check 'bash 4+ construct' \
  '(declare +-A|mapfile|readarray|\$\{[A-Za-z_]+,,|\$\{[A-Za-z_]+\^\^|wait +-n|inherit_errexit)' \
  'macOS bash is 3.2; rewrite without it'

if (( failures > 0 )); then
  printf '\n%d portability failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all scripts and tests clear of GNU-only constructs\n'
