#!/usr/bin/env bash
# End-to-end test of deny-hardwrapped-gh-body.sh against synthetic
# PreToolUse(Bash) payloads.
#
# Usage: bash tests/deny-hardwrapped-gh-body-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-hardwrapped-gh-body.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

run() {  # $1 = command
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$hook" 2>&1
}

run_cwd() {  # $1 = command, $2 = payload cwd
  jq -nc --arg c "$1" --arg d "$2" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$hook" 2>&1 || true
}

# A hard-wrapped paragraph in a real gh pr create --body-file is denied.
wrapped="$work/wrapped.md"
printf 'Summary\n\nThis line wraps into the next physical line without a\nblank line between them, which GitHub renders with a <br>.\n' >"$wrapped"
out="$(run "gh pr create --title x --body-file $wrapped")" || true
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "wrapped body was not denied: $out"
printf '%s' "$out" | jq -e --arg f "$wrapped" '.hookSpecificOutput.permissionDecisionReason | contains($f)' \
  >/dev/null 2>&1 || fail "deny reason did not name the offending file: $out"
[ -n "$(printf '%s' "$out" | jq -r '.systemMessage // ""')" ] \
  || fail "deny carried no systemMessage for the human"

# The same check on gh issue comment --body-file.
out="$(run "gh issue comment 42 --body-file $wrapped")" || true
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "wrapped issue comment body was not denied: $out"

# Commands beyond pr create / issue comment that also post a body from a
# file must be caught too — pr comment is the common review-reply path.
for cmd in \
  "gh pr comment 42 --body-file $wrapped" \
  "gh pr edit 42 --body-file $wrapped" \
  "gh issue create --title x --body-file $wrapped" \
  "gh pr review 42 --approve --body-file $wrapped"
do
  out="$(run "$cmd")" || true
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || fail "[$cmd] wrapped body was not denied: $out"
done

# A nested bullet list, indented, must not be misread as prose.
nested="$work/nested.md"
printf -- '- first bullet\n  - nested detail one\n  - nested detail two\n' >"$nested"
out="$(run "gh pr create --title x --body-file $nested")"
[ -z "$out" ] || fail "nested list expected pass-through, got: $out"

# An indented fence inside a list item must still toggle fence state, so its
# contents aren't linted as prose.
indented_fence="$work/indented-fence.md"
cat >"$indented_fence" <<'EOF'
- item

  ```
  line one of a code fence
  line two of a code fence
  ```

Closing paragraph.
EOF
out="$(run "gh pr create --title x --body-file $indented_fence")"
[ -z "$out" ] || fail "indented fence expected pass-through, got: $out"

# A leading HTML tag (e.g. <details>) is structural, not prose.
details="$work/details.md"
cat >"$details" <<'EOF'
<details>
<summary>Full log</summary>

output here
</details>
EOF
out="$(run "gh pr create --title x --body-file $details")"
[ -z "$out" ] || fail "<details> block expected pass-through, got: $out"

# A --body-file flag with no argument must not crash the hook under
# set -euo pipefail — it should pass through, not error.
out="$(run 'gh pr create --title x --body-file')"
[ -z "$out" ] || fail "--body-file with no argument expected pass-through, got: $out"

# A compound command chaining two gh body-posting calls must check BOTH
# files, not just the first — a wrapped second file must still be denied.
clean_first="$work/clean-first.md"
printf 'Summary\n\nOne physical line, no wrap.\n' >"$clean_first"
out="$(run "gh issue create --title x --body-file $clean_first && gh pr create --title y --body-file $wrapped")" || true
printf '%s' "$out" | jq -e --arg f "$wrapped" '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains($f))' \
  >/dev/null 2>&1 || fail "wrapped second body-file in a chained command was not denied: $out"

# A properly blank-line-separated body, with a heading, a list, and a code
# fence containing lines that would otherwise look wrapped, is allowed.
clean="$work/clean.md"
cat >"$clean" <<'EOF'
## Summary

One physical line per paragraph, blank line separated.

This is a second paragraph, also one line.

- first bullet
- second bullet
- third bullet

```
line one of a code fence
line two of a code fence
```

Closing paragraph.
EOF
out="$(run "gh pr create --title x --body-file $clean")"
[ -z "$out" ] || fail "clean body expected pass-through, got: $out"

# --body-file= form is also recognized.
out="$(run "gh pr create --title x --body-file=$clean")"
[ -z "$out" ] || fail "clean body via --body-file= expected pass-through, got: $out"

# A --body-file path containing whitespace must still be read, in all three
# spellings a shell command can carry it. Cutting the value at the first
# space made the file unreadable, and an unreadable file is skipped silently
# — the guard was bypassed entirely, not merely degraded.
mkdir -p "$work/with space"
spaced_wrapped="$work/with space/wrapped.md"
cp "$wrapped" "$spaced_wrapped"
out="$(run "gh pr create --title x --body-file \"$spaced_wrapped\"")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "double-quoted spaced body-file was not denied: $out"
out="$(run "gh pr create --title x --body-file ${spaced_wrapped// /\\ }")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "backslash-escaped spaced body-file was not denied: $out"
out="$(run "gh pr create --title x --body-file=\"$spaced_wrapped\"")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "--body-file= with a quoted spaced path was not denied: $out"

# The paired positive: a clean body at a spaced path must still pass, so the
# three cases above prove the hook now reads the file rather than proving it
# denies whatever it cannot parse.
spaced_clean="$work/with space/clean.md"
cp "$clean" "$spaced_clean"
out="$(run "gh pr create --title x --body-file \"$spaced_clean\"")"
[ -z "$out" ] || fail "clean body at a spaced path expected pass-through, got: $out"

# A relative --body-file resolves against the payload's cwd, not the hook
# process's. The test's own cwd is the repo root, so a hook reading the
# wrong one finds no file and passes silently.
mkdir -p "$work/rel"
cp "$wrapped" "$work/rel/wrapped.md"
out="$(run_cwd 'gh pr create --title x --body-file wrapped.md' "$work/rel")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
  >/dev/null 2>&1 || fail "relative body-file under the payload cwd was not denied: $out"

# And the paired positive: a clean relative body under the same cwd passes,
# so the case above is not satisfied by denying everything unresolvable.
cp "$clean" "$work/rel/clean.md"
out="$(run_cwd 'gh pr create --title x --body-file clean.md' "$work/rel")"
[ -z "$out" ] || fail "clean relative body-file expected pass-through, got: $out"

# gh pr create without --body-file (e.g. --body inline) is out of scope and
# passes through untouched.
out="$(run 'gh pr create --title x --body "inline text"')"
[ -z "$out" ] || fail "gh pr create without --body-file expected pass-through, got: $out"

# A gh command unrelated to pr create / issue comment is real traffic.
out="$(run "gh pr view --body-file $wrapped")"
[ -z "$out" ] || fail "gh pr view expected pass-through, got: $out"

# A --body-file pointing at a file that doesn't exist yet is not this
# hook's problem to diagnose — pass through and let gh report it.
out="$(run "gh pr create --title x --body-file $work/missing.md")"
[ -z "$out" ] || fail "missing body-file expected pass-through, got: $out"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Write Edit Read AskUserQuestion; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook")"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
