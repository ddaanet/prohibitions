#!/usr/bin/env bash
# End-to-end test of deny-volatile-memory-state.sh against synthetic
# PreToolUse(Write|Edit) payloads.
#
# The contract under test: deny when a token matches \b[0-9a-f]{5,40}\b
# (lowercase only) and is not excluded by (1) being all digits, (2) sitting
# in the closed hex-word list, (3) sitting inside the YAML frontmatter block,
# (4) being part of a UUID, or (5) sharing a line with the `<!-- hygiene-ok -->`
# suppression marker. Content is read raw — a sha's natural habitat is a code
# span, so neither backticks nor fences are stripped.
#
# The hex-word list, verbatim from gitlore's check-memory-hygiene.py HEX_WORDS
# (the complete a-f-only English set of length >= 5), so the two gates agree:
#
#   ababa abaca abaff accede acceded added adead aface afaced baaed bacaba
#   bacca baccae baffed beaded bebed bedad bedded bedead bedeaf beebe beebee
#   beefed cabda caeca caffa ceded dabba dabbed dacca daffed decad decade
#   decca deeded deedeed deface defaced ebbed efface effaced fabaceae facade
#   facaded faced faded feeded
#
# Usage: bash tests/deny-volatile-memory-state-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-volatile-memory-state.sh"
mem="$repo_root/memory/ddaanet/example.md"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# Both runners merge stderr into the captured output: a pass case asserts the
# output is empty, so a script that dies noisily is a failure rather than a
# silent pass.
run_write() { # run_write <path> <line>...
  local path="$1"
  shift
  jq -nc --arg p "$path" --arg c "$(printf '%s\n' "$@")" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' \
    | bash "$hook" 2>&1 || true
}

run_edit() { # run_edit <path> <new_string>
  jq -nc --arg p "$1" --arg n "$2" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: "before", new_string: $n}}' \
    | bash "$hook" 2>&1 || true
}

assert_denied() { # assert_denied <label> <output> [expected-token]
  local label="$1" out="$2" token="${3-}" reason
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || { fail "$label: expected deny, got: $out"; return 0; }
  reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  [ -n "$reason" ] || fail "$label: deny carried no permissionDecisionReason for the agent"
  [ -n "$(printf '%s' "$out" | jq -r '.systemMessage // ""')" ] \
    || fail "$label: deny carried no systemMessage for the human"
  if [ -n "$token" ]; then
    case "$reason" in
      *"$token"*) ;;
      *) fail "$label: deny reason did not quote the offending token '$token': $reason" ;;
    esac
  fi
  return 0
}

assert_passed() { # assert_passed <label> <output>
  [ -z "$2" ] || fail "$1: expected pass-through, got: $2"
  return 0
}

sha='4b825dc642cb6eb9a060e54bf8d69288fbee4904'  # git's empty-tree sha — a real, meaningful 40-hex sha
uuid='94e0a066-a634-4a25-a32d-b0f53b992c25'     # the originSessionId shape the harness writes

# --- denied: volatile git state reaching a memory/**.md file ----------------

# A full 40-hex sha, the case the hook shipped with.
assert_denied "full sha in a Write" \
  "$(run_write "$mem" "fixed as of $sha")" "$sha"

# An Edit introducing a full sha via new_string, even when old_string is clean.
assert_denied "full sha in an Edit new_string" \
  "$(run_edit "$mem" "tip is $sha right now")" "$sha"

# Abbreviated shas: the class the corpus actually contains. Every real hit in
# a 165-file memory store was an abbreviation, none a full sha.
assert_denied "bare 7-char sha" \
  "$(run_write "$mem" 'see commit f59674b for context')" 'f59674b'

# Read raw — a sha's habitat in prose is a code span.
# shellcheck disable=SC2016  # literal backticks in prose, not command substitution
assert_denied "7-char sha inside backticks" \
  "$(run_write "$mem" 'Fixed in commit `7c0471b`.')" '7c0471b'

# Five is git's floor for a usable abbreviation, so it is the matcher's floor.
assert_denied "5-char sha" \
  "$(run_write "$mem" 'landed as afb02 on live')" 'afb02'

# A fenced block is not stripped either.
# shellcheck disable=SC2016  # literal backticks in prose, not command substitution
assert_denied "sha inside a fenced code block" \
  "$(run_write "$mem" '```' 'fixed (`e205aa6`)' '```')" 'e205aa6'

# The brief's own provenance case: this exact string was allowed into a memory
# file by the 40-hex-only matcher.
assert_denied "abbreviated sha in an Edit new_string" \
  "$(run_edit "$mem" 'landed as afb02b9 on live')" 'afb02b9'

# The suppression marker clears the line it sits on, not the file: the
# unmarked line below it is still a violation, and it is the one reported.
# shellcheck disable=SC2016  # literal backticks in prose, not command substitution
out="$(run_write "$mem" 'Fixed in `7c0471b`. <!-- hygiene-ok -->' 'Also landed as afb02b9 on live')"
assert_denied "unmarked line beside a suppressed one" "$out" 'afb02b9'
case "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" in
  *7c0471b*) fail "suppression is per-line: the marked line's sha must not be reported: $out" ;;
esac

# --- allowed: everything the widened matcher must not claim -----------------

# An all-digit run is a number — file modes, byte budgets, token counts.
assert_passed "all-digit runs are numbers" \
  "$(run_write "$mem" 'Mode 100644 and a 160000 gitlink; the budget is 25600 bytes, seen at 197354.')"

# The hex-word list is closed, so no later English word can surprise it.
assert_passed "hex words are words" \
  "$(run_write "$mem" 'The next line added a facade; the entry acceded and was defaced, then faded.')"

# The hex run must be word-boundary-delimited: `defaced` inside `codefaced`
# is not a token of its own. This is the case `\b` used to carry, and it is
# where a GNU-only `grep -oE '\b…\b'` fails silently on BSD/macOS rather
# than erroring, so it is asserted behaviourally instead of by platform.
assert_passed "hex run embedded in a longer word" \
  "$(run_write "$mem" 'the codefaced stagedeadbeefly xdeadbeef deadbeefx cases')"

# Git never emits an uppercase sha; uppercase hex is an acronym.
assert_passed "uppercase hex is an acronym" \
  "$(run_write "$mem" 'The FDA and the CDC once used EBCDIC; DEADBEEF is a sentinel.')"

# Below git's five-character floor.
assert_passed "four-char hex is too short" \
  "$(run_write "$mem" 'beef and f59b are too short')"

# originSessionId is a UUID the harness writes into every fact's frontmatter,
# and its dash-separated groups are 8 and 12 hex characters.
assert_passed "frontmatter originSessionId" \
  "$(run_write "$mem" '---' 'name: example' 'description: an example fact' \
    'metadata:' '  type: reference' "  originSessionId: $uuid" '---' '' 'A body naming no sha.')"

# An Edit fragment carries no frontmatter boundary to detect, so the UUID
# shape itself has to be excluded.
assert_passed "originSessionId in an Edit new_string" \
  "$(run_edit "$mem" "  originSessionId: $uuid")"

# The same UUID in the body, where no frontmatter block is in scope.
assert_passed "UUID in the body" \
  "$(run_write "$mem" "session $uuid did it")"

# The suppression marker clears the line it sits on — same marker as gitlore's
# gate, so a suppressed line is suppressed at write time too.
# shellcheck disable=SC2016  # literal backticks in prose, not command substitution
assert_passed "hygiene-ok clears its line" \
  "$(run_write "$mem" 'Fixed in `7c0471b`. <!-- hygiene-ok -->')"

# origin/<ref> is a durable name, exactly what the rule says to use instead
# of a sha — it must NOT be treated as volatile state.
assert_passed "origin/<ref> is a durable name" \
  "$(run_write "$mem" 'the release reads from origin/main')"


# --- tree-root anchoring ---------------------------------------------------
#
# memory/ counts only at a git tree root, tested by `.git` adjacency.
# Rationale: docs/design.md, "Tree-root anchoring by `.git` adjacency".

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run_write_in() { # run_write_in <cwd> <path> <content>
  jq -nc --arg p "$2" --arg c "$3" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' \
    | (cd "$1" && bash "$hook") 2>&1 || true
}

# A bare relative file_path is live traffic — the model emits one constantly —
# and must deny when the hook's cwd is the repo root.
assert_denied "relative memory/ path" \
  "$(run_write_in "$repo_root" "memory/ddaanet/x.md" "fixed as of $sha")" "$sha"

# A memory/ nested below a tree root is some other directory of that name,
# not this repo's gitlore store.
assert_passed "memory/ nested below the tree root" \
  "$(run_write_in "$repo_root" "plugin-dev/memory/x.md" "fixed as of $sha")"

# A memory/ under a directory that is no git tree at all.
mkdir -p "$work/loose/memory"
assert_passed "memory/ outside any git tree" \
  "$(run_write "$work/loose/memory/x.md" "fixed as of $sha")"
# The same volatile content outside memory/**.md is allowed — this repo's
# own task handoff file is real traffic that legitimately isn't memory.
assert_passed "volatile content outside memory/" \
  "$(run_write "$repo_root/.claude/handoff-task.md" "fixed as of $sha")"

# Ordinary durable-name content in a real memory file is allowed — this
# repo's own shared-claude.md tier file, unmodified. Cut by lines, not by
# bytes: `head -c` on a file this full of em-dashes splits a UTF-8 sequence
# the moment an edit upstream shifts the boundary, and jq would then be fed
# a fragment no assertion here is about.
assert_passed "real shared-claude.md content" \
  "$(jq -nc --arg p "$repo_root/memory/ddaanet/shared-claude.md" \
    --arg c "$(head -n 60 "$repo_root/memory/ddaanet/shared-claude.md")" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' | bash "$hook" 2>&1 || true)"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Bash Read AskUserQuestion; do
  assert_passed "[$t] other tools" \
    "$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook" 2>&1 || true)"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
