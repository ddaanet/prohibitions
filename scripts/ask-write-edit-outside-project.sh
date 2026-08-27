#!/usr/bin/env bash
# PreToolUse(Write|Edit) guard: ask before writing outside CLAUDE_PROJECT_DIR.
#
# ddaanet convention is that other repos stay read-only — a finding gets
# investigated, verified and proposed, never edited in place. See
# shared-claude.md "Other repos stay read-only". This can't be a deny: an
# edit my human partner explicitly asked for there must still go through,
# so the decision is ask, not deny. Dropping a note (a new .md file) is
# permitted by the same prose and passes without asking.
#
# Mechanical: the boundary is CLAUDE_PROJECT_DIR, not judgement about which
# paths are "another repo" — except scratch space (TMPDIR, /tmp), which is
# exempted since it holds no repo to protect.
set -euo pipefail

# A set CDPATH makes `cd` print the directory it lands in, which would be
# captured by the `$(cd … && pwd)` in abspath below and corrupt every path.
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

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
case "$tool_name" in
  Write | Edit) ;;
  *) exit 0 ;;
esac

file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
[ -n "$file_path" ] || exit 0

project_dir="$(abspath "${CLAUDE_PROJECT_DIR:-$PWD}")"
target="$(abspath "$file_path")"

case "$target" in
  "$project_dir" | "$project_dir"/*) exit 0 ;;
esac

# Scratch space is not "another repo" — exempt it so the harness's own
# scratchpad and temp-file conventions don't trigger a confirmation. Both
# sides of every comparison go through abspath, the literal `/tmp` included:
# on macOS `/tmp` is a symlink to `/private/tmp`, so a resolved target would
# never match an unresolved literal and the exemption would quietly lapse.
for scratch in "${TMPDIR:-}" /tmp; do
  [ -n "$scratch" ] || continue
  scratch="$(abspath "$scratch")"
  case "$target" in
    "$scratch" | "$scratch"/*) exit 0 ;;
  esac
done

# Dropping a note or brief in another repo is permitted — the prose forbids
# editing *in place*. A Write that creates a new .md file clobbers nothing
# and runs nothing, so it passes; Edit, Write over an existing file, and
# new non-.md files all remain in-place modification. CLAUDE.md and
# anything under .claude/ are the two .md locations that change behaviour,
# so they are notes only in name.
if [ "$tool_name" = Write ] && [ ! -e "$target" ]; then
  case "$target" in
    */CLAUDE.md | */.claude/*) ;;
    *.md) exit 0 ;;
  esac
fi

agent_reason="Target is outside the project directory ($project_dir). ddaanet
convention: other repos stay read-only — a finding there gets investigated,
verified and proposed, never edited in place, unless this specific write is
explicitly authorized here."

human_msg="write/edit outside project — confirm: $target"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
