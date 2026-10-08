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

# abspath(), the portable `realpath -m`; sourcing it also clears CDPATH.
# shellcheck source-path=SCRIPTDIR source=lib/path.sh
. "${BASH_SOURCE[0]%/*}/lib/path.sh"

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
