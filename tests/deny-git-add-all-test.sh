#!/usr/bin/env bash
# End-to-end test of deny-git-add-all.sh against synthetic PreToolUse(Bash)
# payloads.
#
# Usage: bash tests/deny-git-add-all-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-git-add-all.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite mid-loop under `set -e`.
run() {  # $1 = command. Deny path writes JSON to stdout, exit 0.
  jq -nc --arg c "$1" --arg d "$repo_root" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$hook" 2>&1 || true
}

assert_denied() {  # $1 = label, $2 = hook output
  printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || { fail "[$1] was not denied: $2"; return; }
  [ -n "$(printf '%s' "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "[$1] deny carried no permissionDecisionReason for the agent"
  # The remedy is mechanical, so the reason must carry it: `git add -u` for
  # tracked files only, and staging the paths you actually mean.
  printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("git add -u")' \
    >/dev/null 2>&1 || fail "[$1] reason missing the tracked-only alternative \`git add -u\`: $2"
  printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecisionReason | ascii_downcase | test("path")' \
    >/dev/null 2>&1 || fail "[$1] reason does not tell the agent to stage named paths: $2"
  printf '%s' "$2" | jq -e '.systemMessage | contains("git add -u")' \
    >/dev/null 2>&1 || fail "[$1] systemMessage missing \`git add -u\`: $2"
}

# Real must-block traffic: whole-tree staging in every form the rule names —
# the -A/--all flags and their cluster/synonym spellings, the whole-tree
# pathspecs, the `stage` synonym, git global options sitting between `git`
# and the subcommand, and the same buried in a chain.
for cmd in \
  'git add -A' \
  'git add --all' \
  'git add .' \
  'git add ./' \
  'git add :/' \
  "git add '*'" \
  'git add "*"' \
  "git add '.'" \
  'git add "."' \
  "git add './'" \
  'git add "./"' \
  "git add ':/'" \
  'git add ":/"' \
  'git add -nA' \
  'git add --no-ignore-removal' \
  'git add -A src/' \
  'git stage -A' \
  'git -C /some/dir add -A' \
  'git -c core.quotepath=off add .' \
  'git --no-pager add .' \
  'git add . && git commit -m "wip"' \
  'git add .; git commit -m "wip"' \
  'git status && git add -A && git commit -m "wip"' \
  'git add -- .'
do
  out="$(run "$cmd")"
  assert_denied "$cmd" "$out"
done

# Segments are split on newlines too: a whole-tree add on any line of a
# multi-line command is the same command.
multiline_cmd=$'git status --short\ngit add -A\ngit commit -m "wip"'
out="$(run "$multiline_cmd")"
assert_denied 'multi-line command with git add -A on line 2' "$out"

# Real must-allow traffic: targeted staging (the 77% case), the tracked-only
# `-u`, paths that merely start with or contain the whole-tree spellings, and
# other commands that share a word with the trigger but aren't the trigger.
for cmd in \
  'git add path/file' \
  'git add ./path/file' \
  'git add -u' \
  'git add .gitignore' \
  'git add ..' \
  'git add -- path/file' \
  'git add src/ tests/' \
  'git add -p src/file' \
  'git add-something -A' \
  'git status' \
  'git commit -m "run git add -A before this"' \
  "git commit -m 'git add .'" \
  "git commit -m 'done.'" \
  "git add 'path/file'" \
  'git add "src/a.b"' \
  "git add 'a'.'b'" \
  'git add "a"."b"' \
  'echo add . | cat' \
  'git log -- .' \
  'git diff .' \
  'ls -A .' \
  'git add path/file && git commit -m "wip" && git push'
do
  out="$(run "$cmd")"
  [ -z "$out" ] || fail "[$cmd] expected pass-through, got: $out"
done

# A heredoc-style commit message (this project's own convention for
# multi-line commits) that documents the refused forms in prose must not
# false-deny — heredoc bodies aren't quoted with '/" so the quote-stripping
# alone doesn't cover them; the hook must also strip heredoc bodies.
heredoc_cmd="$(cat <<'CMD'
git commit -m "$(cat <<'EOF'
Also refuse git add -A and git add .
EOF
)"
CMD
)"
out="$(run "$heredoc_cmd")"
[ -z "$out" ] || fail "heredoc commit message mentioning whole-tree adds expected pass-through, got: $out"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Write Edit Read AskUserQuestion; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook" 2>&1 || true)"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
