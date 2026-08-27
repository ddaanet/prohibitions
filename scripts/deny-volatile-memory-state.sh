#!/usr/bin/env bash
# PreToolUse(Write|Edit) guard: deny volatile git state landing in a
# memory/**.md file.
#
# No commit ids, branch tips, or "uncommitted as of" notes in memory —
# identify things by durable names instead: branches, paths, issue numbers.
# A session that needs exact volatile state puts it in a handoff, not
# memory. See shared-claude.md "No volatile git state in memory files".
#
# Mechanical: a lowercase `\b[0-9a-f]{5,40}\b` run denies, five being git's
# floor for a usable abbreviation. Abbreviations are the entire observed
# population: a real 165-file store held four commit ids and not one full
# sha, so the 40-hex scope this hook shipped with had zero true positives
# available to it. The old header justified that scope with "abbreviated hex
# would false-positive on ordinary prose"; measured, it does not. Four
# exclusions keep the widened matcher precise — an all-digit run is a number
# (file modes, byte budgets, token counts), the a-f-only English words of
# length >= 5 are a closed 47-entry list, the YAML frontmatter block is
# skipped whole, and UUIDs are blanked. A line carrying `<!-- hygiene-ok` is
# exempt, the same marker gitlore's gate honours.
#
# Content is read raw: a sha's habitat in prose is a code span, so a
# code-stripped scan would find none of the real hits. Uppercase is not
# matched — git never emits an uppercase sha, while `FDA` and `EBCDIC` are
# ordinary acronyms. A ref name like `origin/main` is not itself volatile —
# it's the durable name the rule says to use instead of a sha — so it is
# deliberately not matched here.
#
# This mirrors gitlore's `check-memory-hygiene.py` `volatile-state` check, so
# the write-time and commit-time gates agree on what a violation is. One
# deliberate divergence: this hook also blanks UUIDs inside the body, which
# gitlore's whole-file check does not need — an `Edit.new_string` fragment
# carrying `originSessionId:` arrives with no frontmatter boundary to detect.
#
# Residual bound, stated rather than implied: a sha split across a line break,
# or abbreviated below five characters, passes; so does the ~4% of seven-char
# shas that are all digits ((10/16)**7). Whitespace safety is not at stake —
# no filename is ever split here. This is a cheap high-precision filter, not a
# proof of absence. Rationale: docs/design.md.
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"
case "$tool_name" in
  Write | Edit) ;;
  *) exit 0 ;;
esac

file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
case "$file_path" in
  */memory/*.md) ;;
  *) exit 0 ;;
esac

# A Write carries the whole file, so its frontmatter block is detectable and
# gets blanked; an Edit carries a fragment, which has none.
if [ "$tool_name" = "Write" ]; then
  content="$(jq -r '.tool_input.content // ""' <<<"$input")"
  frontmatter_scope=1
else
  content="$(jq -r '.tool_input.new_string // ""' <<<"$input")"
  frontmatter_scope=0
fi

# Blank the suppressed lines and the frontmatter block, then the UUIDs. The
# UUID pass is `sed -E` rather than more awk because interval expressions are
# not portable in awk; a space, not the empty string, so blanking cannot weld
# two neighbouring runs into one.
scanned="$(
  awk -v fm_scope="$frontmatter_scope" -v marker='<!-- hygiene-ok' '
    NR == 1 && fm_scope && $0 == "---" { fm = 1; print ""; next }
    fm { if ($0 == "---") fm = 0; print ""; next }
    index($0, marker) { print ""; next }
    { print }
  ' <<<"$content" \
    | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ /g'
)"

# First surviving candidate wins: it is the one the deny reason quotes.
hit=""
while IFS= read -r candidate; do
  # All digits is a number, not a sha.
  case "$candidate" in
    *[!0-9]*) ;;
    *) continue ;;
  esac
  # The complete a-f-only English set of length >= 5, verbatim from gitlore's
  # HEX_WORDS so the two gates agree. Closed: no later word can surprise it.
  case "$candidate" in
    ababa | abaca | abaff | accede | acceded | added | adead | aface | afaced \
      | baaed | bacaba | bacca | baccae | baffed | beaded | bebed | bedad \
      | bedded | bedead | bedeaf | beebe | beebee | beefed | cabda | caeca \
      | caffa | ceded | dabba | dabbed | dacca | daffed | decad | decade \
      | decca | deeded | deedeed | deface | defaced | ebbed | efface \
      | effaced | fabaceae | facade | facaded | faced | faded | feeded)
      continue
      ;;
  esac
  hit="$candidate"
  break
done < <(grep -oE '\b[0-9a-f]{5,40}\b' <<<"$scanned" || true)

[ -n "$hit" ] || exit 0

agent_reason="This write introduces volatile git state into a memory file
('$hit'). Memory identifies things by durable names — branches, paths, issue
numbers — never commit ids or branch tips, even a stable upstream-main sha.
Rewrite the reference by durable name, or if the exact volatile state is what
needs preserving, put it in a handoff instead of memory."

human_msg="blocked: volatile git state in memory file — $file_path"

jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
