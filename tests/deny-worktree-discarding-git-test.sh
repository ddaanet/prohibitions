#!/usr/bin/env bash
# End-to-end test of deny-worktree-discarding-git.sh against synthetic
# PreToolUse(Bash) payloads, run in a throwaway fixture repo.
#
# Usage: bash tests/deny-worktree-discarding-git-test.sh   (run from repo root)
#
# Command strings holding `$repo` are single-quoted on purpose: the hook must
# see the unexpanded text and treat the directory as unknown.
# shellcheck disable=SC2016
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-worktree-discarding-git.sh"

# Exported, so the hook's own `git rev-parse` sees the fixture config too. A
# git-hook environment would point the fixture's git (and the hook's) at the
# outer repository, so it is cleared.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fixture="$(mktemp -d "${TMPDIR:-/tmp}/wdg-fixture.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

g() { git -C "$fixture" -c user.name=tester -c user.email=tester@example.com "$@"; }

build_fixture() {
  g init -q -b main
  mkdir -p "$fixture/src" "$fixture/my dir"
  printf 'both\n' >"$fixture/both"
  printf 'one\n' >"$fixture/onlyfile.txt"
  printf 'a\n' >"$fixture/src/a.txt"
  printf 'spaced\n' >"$fixture/my file.txt"
  printf 'x\n' >"$fixture/my dir/x"
  g add -- both onlyfile.txt src/a.txt "my file.txt" "my dir/x"
  g commit -q -m first
  printf 'two\n' >>"$fixture/onlyfile.txt"
  g commit -q -a -m second
  g branch feature
  g branch both
  g tag v1
}
build_fixture

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite mid-loop under `set -e`.
run() {  # $1 = command. Verdicts are stdout JSON, exit 0.
  jq -nc --arg c "$1" --arg d "$fixture" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$hook" 2>&1 || true
}

assert_denied() {  # $1 = label, $2 = hook output
  printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || { fail "[$1] was not denied: $2"; return; }
  [ -n "$(printf '%s' "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')" ] \
    || fail "[$1] deny carried no permissionDecisionReason"
  [ -n "$(printf '%s' "$2" | jq -r '.hookSpecificOutput.additionalContext // ""')" ] \
    || fail "[$1] deny carried no additionalContext redirect for the agent"
  printf '%s' "$2" | jq -e '.systemMessage // "" | startswith("blocked:")' \
    >/dev/null 2>&1 || fail "[$1] systemMessage is not a curt blocked line: $2"
}

assert_asked() {  # $1 = label, $2 = hook output, $3... = expected paths
  local label="$1" out="$2" p
  shift 2
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
    >/dev/null 2>&1 || { fail "[$label] was not asked: $out"; return; }
  for p in "$@"; do
    printf '%s' "$out" | jq -e --arg p "$p" \
      '.hookSpecificOutput.permissionDecisionReason // "" | contains($p)' \
      >/dev/null 2>&1 || fail "[$label] ask reason does not name path '$p': $out"
  done
  printf '%s' "$out" | jq -e \
    '.hookSpecificOutput.additionalContext // "" | contains("cp") and contains("$TMPDIR")' \
    >/dev/null 2>&1 || fail "[$label] additionalContext lacks the cp-to-\$TMPDIR directive: $out"
  printf '%s' "$out" | jq -e 'has("systemMessage") | not' \
    >/dev/null 2>&1 || fail "[$label] ask carried a systemMessage: $out"
}

# Pairs with assert_asked on the same output: words that must not reach the
# ask's path list (a tree-ish, an option, a redirect target). Checked only once
# the ask exists, so a missing verdict is reported once, by assert_asked.
assert_reason_omits() {  # $1 = label, $2 = hook output, $3... = absent words
  local label="$1" out="$2" w
  shift 2
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' \
    >/dev/null 2>&1 || return 0
  for w in "$@"; do
    printf '%s' "$out" | jq -e --arg w "$w" \
      '.hookSpecificOutput.permissionDecisionReason // "" | contains($w) | not' \
      >/dev/null 2>&1 || fail "[$label] ask reason lists '$w' as a path: $out"
  done
}

assert_passed() {  # $1 = label, $2 = hook output
  [ -z "$2" ] || fail "[$1] expected pass-through, got: $2"
}

for cmd in \
  'git reset --hard' \
  'git reset --hard HEAD~1' \
  'git reset --merge' \
  'git --no-pager reset --hard' \
  'git clean -f' \
  'git clean -fd' \
  'git clean -xdf' \
  'git clean --force' \
  'git clean -f -d src' \
  'git stash drop' \
  'git stash drop stash@{1}' \
  'git stash clear' \
  'git checkout -f' \
  'git checkout --force main' \
  'git switch --discard-changes main' \
  'git switch -f main' \
  'git checkout .' \
  'git checkout -- .' \
  'git checkout HEAD -- .' \
  'git checkout :/' \
  'git checkout src' \
  'git checkout -- src/' \
  'git checkout -- "my dir"' \
  "git checkout -- '*.txt'" \
  'git checkout -- onlyfile.txt src' \
  'git restore .' \
  'git restore -W .' \
  'git restore -SW src' \
  'git restore --source=HEAD~1 -- .' \
  'git -c core.x=y checkout -- .' \
  'git -C src checkout -- .' \
  'npm test && git checkout -- .' \
  'git status; git reset --hard' \
  '{ git reset --hard; }' \
  'if true; then git reset --hard; fi' \
  '! git checkout -- .' \
  'sudo git reset --hard' \
  'git checkout -f -b x' \
  'git switch -f -c x main' \
  'git restore -sHEAD .' \
  'git clean -fd -enode' \
  'git checkout -- "$d"/'
do
  assert_denied "$cmd" "$(run "$cmd")"
done

assert_asked 'git checkout -- onlyfile.txt' "$(run 'git checkout -- onlyfile.txt')" onlyfile.txt
assert_asked 'git checkout onlyfile.txt' "$(run 'git checkout onlyfile.txt')" onlyfile.txt
# Each tree-ish or option word below would also land in the path list if the
# parser took every operand as a path; the omits check is what catches that.
cmd='git checkout HEAD -- onlyfile.txt'
out="$(run "$cmd")"
assert_asked "$cmd" "$out" onlyfile.txt
assert_reason_omits "$cmd" "$out" HEAD
cmd='git checkout main onlyfile.txt'
out="$(run "$cmd")"
assert_asked "$cmd" "$out" onlyfile.txt
assert_reason_omits "$cmd" "$out" main
assert_asked 'git checkout -- "my file.txt"' "$(run 'git checkout -- "my file.txt"')" 'my file.txt'
assert_asked 'git checkout my\ file.txt' "$(run 'git checkout my\ file.txt')" 'my file.txt'
cmd='git checkout --theirs -- onlyfile.txt'
out="$(run "$cmd")"
assert_asked "$cmd" "$out" onlyfile.txt
assert_reason_omits "$cmd" "$out" --theirs
assert_asked 'git restore onlyfile.txt' "$(run 'git restore onlyfile.txt')" onlyfile.txt
cmd='git restore --staged --worktree onlyfile.txt'
out="$(run "$cmd")"
assert_asked "$cmd" "$out" onlyfile.txt
assert_reason_omits "$cmd" "$out" --staged --worktree
cmd='git restore --source=HEAD~1 onlyfile.txt'
out="$(run "$cmd")"
assert_asked "$cmd" "$out" onlyfile.txt
assert_reason_omits "$cmd" "$out" HEAD~1
assert_asked 'cd src && git checkout a.txt' "$(run 'cd src && git checkout a.txt')" a.txt
assert_asked 'git -C src checkout a.txt' "$(run 'git -C src checkout a.txt')" a.txt
assert_asked 'git -C "$repo" checkout -- onlyfile.txt' \
  "$(run 'git -C "$repo" checkout -- onlyfile.txt')" onlyfile.txt

# The redirection and its target are not pathspecs: the path list is exactly
# onlyfile.txt.
cmd='git checkout -- onlyfile.txt 2>/dev/null'
out="$(run "$cmd")"
assert_asked "$cmd" "$out" onlyfile.txt
assert_reason_omits "$cmd" "$out" /dev/null

# Combining across segments (design §3): an ask lists every segment's per-file
# paths, and a later deny beats an earlier ask.
assert_asked 'two per-file restores in two segments' \
  "$(run 'git checkout -- onlyfile.txt && git restore src/a.txt')" onlyfile.txt src/a.txt \
  '`git checkout` and `git restore` overwrite'
assert_asked 'per-file restore inside a loop body' \
  "$(run 'for f in a; do git checkout -- onlyfile.txt; done')" onlyfile.txt
# The option text is the path shown, with no flag byte leaking into it.
cmd='git checkout --pathspec-from-file list.txt'
out="$(run "$cmd")"
assert_asked "$cmd" "$out" '--pathspec-from-file=list.txt'
assert_reason_omits "$cmd" "$out" 'L--'
assert_denied 'per-file restore then bulk restore' \
  "$(run 'git checkout -- onlyfile.txt && git checkout -- .')"

for cmd in \
  'git clean -n' \
  'git clean -fn' \
  'git clean --dry-run -f' \
  'git stash' \
  'git stash push -u' \
  'git stash pop' \
  'git stash list' \
  'git reset --keep HEAD~1' \
  'git reset' \
  'git reset HEAD onlyfile.txt' \
  'git reset --soft HEAD~1' \
  'git checkout -b x' \
  'git checkout -B x main' \
  'git checkout --orphan x' \
  'git switch main' \
  'git switch -c x' \
  'git checkout main' \
  'git checkout feature' \
  'git checkout v1' \
  'git checkout -' \
  'git checkout --' \
  'echo git checkout -- .' \
  'git checkout -p' \
  'git checkout both' \
  'git checkout nosuch' \
  'git -C "$repo" checkout main' \
  'git restore --staged onlyfile.txt' \
  'git restore -S .' \
  'git log -- .' \
  'git diff -- src' \
  'git show HEAD:onlyfile.txt' \
  'git commit -m "undo with git checkout -- . or reset --hard"' \
  'echo "git clean -f"' \
  'gh pr create --body "git stash drop"'
do
  assert_passed "$cmd" "$(run "$cmd")"
done

# Unknown effdir, bare operand: `main` passes either way, but onlyfile.txt
# exists under the payload cwd, so this passes only if the X-flagged -C really
# makes the directory unknown (design §2: then a bare operand is `switch`).
# Its `--` twin above asks.
assert_passed 'git -C "$repo" checkout onlyfile.txt' \
  "$(run 'git -C "$repo" checkout onlyfile.txt')"
# Likewise for a chdir by the env wrapper: src holds no onlyfile.txt, so only a
# stale payload-cwd lookup would ask.
assert_passed 'env -C src git checkout onlyfile.txt' \
  "$(run 'env -C src git checkout onlyfile.txt')"

# A heredoc commit message naming the refused forms must not false-deny. In
# the -F - form the body is unquoted command text, and its lines start with
# `git`, so only strip_heredocs keeps them from being read as segments.
heredoc_cmd="$(cat <<'CMD'
git commit -F - <<'EOF'
git reset --hard was the wrong fix
git clean -f would have lost the notes
EOF
CMD
)"
assert_passed 'heredoc commit body naming refused forms' "$(run "$heredoc_cmd")"
# The same message through -m "$(cat <<'EOF' …)": the body sits in quotes.
heredoc_cmd="$(cat <<'CMD'
git commit -m "$(cat <<'EOF'
Never run git reset --hard or git clean -f here
EOF
)"
CMD
)"
assert_passed 'heredoc commit message naming refused forms' "$(run "$heredoc_cmd")"

# Every other tool call passes through silent. The payload carries a command a
# Bash call would be denied for, so the pass is the tool_name gate's doing.
for t in Write Edit Read AskUserQuestion; do
  passthrough="$(jq -nc --arg t "$t" '{tool_name: $t, tool_input: {command: "git reset --hard"}}' \
    | bash "$hook" 2>&1 || true)"
  assert_passed "tool $t" "$passthrough"
done

# Bound: tokenizing is linear, so a ~100 KB command whose bulk is one quoted
# -m message still reaches its trailing deny in a few seconds.
message="$(head -c 100000 /dev/zero | tr '\0' 'x')"
bound_cmd="git commit -m \"$message\" && git checkout -- ."
SECONDS=0
out="$(run "$bound_cmd")"
elapsed=$SECONDS
assert_denied '100 KB command ending in git checkout -- .' "$out"
(( elapsed < 4 )) || fail "[100 KB command] took ${elapsed}s, expected under 4s"

# The same bound when the word is built from many small pieces: 40000
# backquoted spans in one double-quoted message, 120 KB. Appending each piece
# onto the whole word made this quadratic (about 6 s for shell_split alone).
message="$(head -c 40000 /dev/zero | tr '\0' 'x' | sed 's/x/`a`/g')"
bound_cmd="git commit -m \"$message\" && git checkout -- ."
SECONDS=0
out="$(run "$bound_cmd")"
elapsed=$SECONDS
assert_denied '120 KB of backquoted pieces ending in git checkout -- .' "$out"
(( elapsed < 4 )) || fail "[120 KB of pieces] took ${elapsed}s, expected under 4s"

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
