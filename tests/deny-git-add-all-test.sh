#!/usr/bin/env bash
# End-to-end test of deny-git-add-all.sh against synthetic PreToolUse(Bash)
# payloads.
#
# Usage: bash tests/deny-git-add-all-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-git-add-all.sh"

# Spelled in two pieces so tests/portability-test.sh does not flag the
# command word: it appears here only as hook input.
tmo=time'out'

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
  # The recovery is agent-only, so it rides additionalContext: stage the
  # paths you actually mean.
  printf '%s' "$2" | jq -e '.hookSpecificOutput.additionalContext // "" | ascii_downcase | test("path")' \
    >/dev/null 2>&1 || fail "[$1] additionalContext does not tell the agent to stage named paths: $2"
  printf '%s' "$2" | jq -e '.systemMessage // "" | startswith("blocked:")' \
    >/dev/null 2>&1 || fail "[$1] systemMessage is not a curt blocked line: $2"
  # `git add -u` stays allowed but is never offered: it stages every tracked
  # edit, a half-finished sibling included, which is what the deny prevents.
  printf '%s' "$2" | jq -e '[.hookSpecificOutput.permissionDecisionReason, .hookSpecificOutput.additionalContext, .systemMessage] | map(. // "" | contains("git add -u")) | any | not' \
    >/dev/null 2>&1 || fail "[$1] deny offers \`git add -u\` as a redirect: $2"
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
  'git add -- .' \
  '{ git add -A; }' \
  'if true; then git add -A; fi' \
  'for f in a; do git add .; done' \
  'sudo git add -A' \
  'env FOO=1 git add -A' \
  'sudo -u bob git add -A' \
  'env -i git add -A' \
  'env -u X git add -A' \
  'nice -n 5 git add -A' \
  'time -p git add -A' \
  "$tmo 5 git add -A" \
  "$tmo -s KILL 5 git add -A" \
  "$tmo -k 2 5 git add -A" \
  "$tmo --signal=KILL 5 git add -A" \
  'command -p git add -A' \
  'exec git add -A' \
  'nohup git add -A' \
  'FOO=1 BAR=2 git add -A' \
  'cd x && git add -A' \
  'true | git add -A' \
  'xargs git add -A' \
  'xargs -0 git add -A' \
  'xargs -n1 git add -A' \
  'xargs -J % git add -A' \
  'GIT_EXEC=/usr/bin/git git add -A' \
  '/usr/bin/git add -A' \
  'sudo -u bob /usr/bin/git add -A' \
  'env -i /usr/bin/git add .' \
  'git add "-A"' \
  "git add '--all'" \
  '2>/dev/null git add -A' \
  '>/dev/null 2>&1 git add .' \
  '\git add -A' \
  "git a''dd -A" \
  'g"i"t add .' \
  'git st\age -A'
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
# `"$f"` is single-quoted on purpose: the hook must see the unexpanded word.
# shellcheck disable=SC2016
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
  'echo git add -A' \
  'env echo git add -A' \
  'xargs -n1 echo git add -A' \
  'sudo -u git ls -A' \
  'legit add -A' \
  'gitk add -A' \
  '/x/git-foo add -A' \
  'git log -- .' \
  'git diff .' \
  'ls -A .' \
  'git add path/file && git commit -m "wip" && git push' \
  'echo "say \"; git add -A; \" here"' \
  'git add "my file.txt"' \
  'git add -p' \
  'git add "$f"' \
  'for f in a.sh b.sh; do git add "$f"; done'
do
  out="$(run "$cmd")"
  [ -z "$out" ] || fail "[$cmd] expected pass-through, got: $out"
done

# A heredoc-style commit message (this project's own convention for
# multi-line commits) that documents the refused forms in prose must not
# false-deny. Inside `"$( … )"` the split already keeps the body in one word.
heredoc_cmd="$(cat <<'CMD'
git commit -m "$(cat <<'EOF'
Also refuse git add -A and git add .
EOF
)"
CMD
)"
out="$(run "$heredoc_cmd")"
[ -z "$out" ] || fail "heredoc commit message mentioning whole-tree adds expected pass-through, got: $out"

# An unquoted heredoc body is not quoted with '/" at all, so the quote-aware
# split would read its lines as commands; only stripping heredoc bodies keeps
# a note that quotes the refused command from false-denying.
note_cmd=$'cat <<\'EOF\' > notes.md\ngit add -A\nEOF'
out="$(run "$note_cmd")"
[ -z "$out" ] || fail "unquoted heredoc body holding git add -A expected pass-through, got: $out"

# Real traffic this matcher's script must let through unharmed, even if ever
# mis-wired to a broader matcher: every other tool call passes through silent.
for t in Write Edit Read AskUserQuestion; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {}}' | bash "$hook" 2>&1 || true)"
  [ -z "$passthrough" ] || fail "[$t] expected pass-through, got: $passthrough"
done

# A failing awk is a hook failure, not a verdict: it must pass the call with a
# systemMessage naming the failure, never block it. The stub sits first on
# PATH, so the hook reaches it the way production reaches awk. The control
# payload is the one this hook acts on with a working awk.
awk_stub="$(mktemp -d "${TMPDIR:-/tmp}/awk-stub.XXXXXX")"
printf '#!/bin/sh\nexit 2\n' >"$awk_stub/awk"
chmod +x "$awk_stub/awk"
awk_payload="$(jq -nc '{tool_name: "Bash", tool_input: {command: "git add ."}, cwd: "'"${fixture:-/}"'"}')"
rc=0
out="$(printf '%s' "$awk_payload" | PATH="$awk_stub:$PATH" bash "$hook" 2>/dev/null)" || rc=$?
rm -rf "$awk_stub"
[ "$rc" -eq 0 ] || fail "[awk failure] exit $rc, expected 0 (a failed parse must not block)"
printf '%s' "$out" | jq -e '(.systemMessage // "") | length > 0' >/dev/null 2>&1 \
  || fail "[awk failure] no systemMessage naming the failure: $out"
printf '%s' "$out" | jq -e '(.hookSpecificOutput.permissionDecision // "") == ""' >/dev/null 2>&1 \
  || fail "[awk failure] carried a permissionDecision: $out"

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
