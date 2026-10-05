#!/usr/bin/env bash
# End-to-end test of deny-sandboxed-excluded-command.sh against synthetic
# PreToolUse(Bash) payloads and a controlled $HOME.
#
# The contract under test: with the harness sandbox enabled, a Bash call that
# leaves `dangerouslyDisableSandbox` unset is denied when any of its
# subcommands matches an entry of `sandbox.excludedCommands` and the harness
# would not take the call out of the sandbox itself. The harness excludes a
# call only when every part of it matches, so `git commit | tail` and
# `ls | sort` run sandboxed, where git cannot write and git/ls list phantom
# dotfiles; the hook refuses them before they run. A call whose every
# subcommand matches passes, unless it carries a shape the harness keeps
# sandboxed or might — a redirect, a `$`, a glob, a subshell, a `cd`, `git -C`
# and the rest — where the hook denies rather than guess. Quoted text and
# heredoc bodies are not subcommands, and a call carrying a command or process
# substitution is not matched at all.
#
# Usage: bash tests/deny-sandboxed-excluded-command-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-sandboxed-excluded-command.sh"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

new_home() { # new_home <label> [settings-json]; prints the home path
  local home="$tmp_root/$1"
  mkdir -p "$home/.claude"
  if [ "$#" -ge 2 ]; then
    printf '%s\n' "$2" >"$home/.claude/settings.json"
  fi
  printf '%s\n' "$home"
}

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite under `set -e`.
run() { # run <home> <command> [disable-sandbox-json]; prints hook output
  jq -nc --arg c "$2" --argjson d "${3:-null}" \
    '{tool_name: "Bash", tool_input: ({command: $c} + (if $d == null then {} else {dangerouslyDisableSandbox: $d} end)), cwd: "/x"}' \
    | HOME="$1" bash "$hook" 2>&1 || true
}

assert_denied() { # assert_denied <label> <output> <named-command>
  printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    >/dev/null 2>&1 || { fail "[$1] was not denied: $2"; return 0; }
  local reason ctx msg
  reason="$(printf '%s' "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  ctx="$(printf '%s' "$2" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  msg="$(printf '%s' "$2" | jq -r '.systemMessage // ""')"
  case "$reason" in *"$3"*) ;; *) fail "[$1] reason does not name '$3': $reason" ;; esac
  case "$ctx" in
    *dangerouslyDisableSandbox*) ;;
    *) fail "[$1] additionalContext does not carry the recovery flag: $ctx" ;;
  esac
  [ -n "$msg" ] || fail "[$1] deny carried no systemMessage for the human"
  return 0
}

assert_pass() { # assert_pass <label> <output>
  [ -z "$2" ] || fail "[$1] expected silent pass, got: $2"
  return 0
}

std='{"sandbox": {"enabled": true, "excludedCommands": ["git *", "find *", "ls *", "claude *", "just release *"]}}'
home="$(new_home standard "$std")"

# --- deny: an excluded subcommand would run sandboxed -----------------------

# Some subcommand is not excluded, so the harness sandboxes the whole call.
# Each row: command, then the command word the reason must name.
while IFS=$'\t' read -r cmd word; do
  assert_denied "$cmd" "$(run "$home" "$cmd")" "$word"
done <<'EOF'
git commit -m wip | tail	git
git log|head -5	git
ls -la | sort	ls
true&&ls	ls
cd /some/dir && git status	git
(cd sub && git log)	git
echo hi; find . -name x	find
npm test && git push	git
just release minor | tee log	just release
if true; then ls; fi	ls
echo '$(not a substitution)'; ls	ls
echo "it's"; ls	ls
EOF

# A subcommand on its own line counts as one.
out="$(run "$home" $'echo one\ngit push')"
assert_denied 'git on a second line' "$out" 'git'

# An explicit false is the same as unset.
out="$(run "$home" 'git status | head' false)"
assert_denied 'dangerouslyDisableSandbox: false' "$out" 'git'

# Every subcommand is excluded, but the call has a shape the harness keeps
# sandboxed — observed, documented, or not known to be safe.
while IFS=$'\t' read -r cmd word; do
  assert_denied "$cmd" "$(run "$home" "$cmd")" "$word"
done <<'EOF'
ls > out.txt	ls
ls -la >>log	ls
git status 2>&1	git
git apply < fix.patch	git
ls $HOME	ls
ls "$HOME/x"	ls
ls ${TMPDIR}	ls
ls *.md	ls
ls a?	ls
ls [ab]	ls
ls ~	ls
ls ~/x	ls
ls {a,b}	ls
(ls)	ls
ls a && (ls b)	ls
git fetch &	git
ls & ls	ls
ls |& ls	ls
FOO=1 git status	git
LANG=C git status	git
{ git status; }	git
! git diff --quiet	git
if ls; then ls; fi	ls
while ls; do ls; done	ls
git -C /some/dir status	git
git -c core.pager=cat log	git
git --git-dir=/x/.git status	git
git --no-pager log	git
git clone https://example.com/r.git	git
git init	git
git worktree list	git
git bundle create x.bundle HEAD	git
EOF

out="$(run "$home" $'git commit -F - <<EOF\nfix\nEOF')"
assert_denied 'heredoc into git' "$out" 'git'
out="$(run "$home" $'ls a \\\n  b')"
assert_denied 'backslash-newline continuation' "$out" 'ls'

# The command words the harness refuses wherever they sit, even when the user
# has excluded them.
home_words="$(new_home words \
  '{"sandbox": {"enabled": true, "excludedCommands": ["ls *", "cd *", "pushd *", "popd *", "sudo *", "eval *", "xargs *"]}}')"
while IFS=$'\t' read -r cmd word; do
  assert_denied "$cmd" "$(run "$home_words" "$cmd")" "$word"
done <<'EOF'
cd /x && ls	cd
cd /x	cd
pushd /x; ls; popd	pushd
sudo ls	sudo
eval ls	eval
ls | xargs ls	xargs
EOF

# The legacy `cmd:*` spelling is the same prefix.
home_legacy="$(new_home legacy \
  '{"sandbox": {"enabled": true, "excludedCommands": ["git:*", "just release:*"]}}')"
assert_denied 'legacy git:*' "$(run "$home_legacy" 'git status | head')" 'git'
assert_denied 'legacy just release:*' "$(run "$home_legacy" 'just release patch | tail')" 'just release'
assert_pass 'legacy git:*, harness-excluded' "$(run "$home_legacy" 'git status')"
assert_pass 'legacy just release:*, harness-excluded' "$(run "$home_legacy" 'just release patch')"

# A pattern with no wildcard is exact: `docker` matches only a bare `docker`.
# Any other `*` is a glob over the whole subcommand.
home_exact="$(new_home exact \
  '{"sandbox": {"enabled": true, "excludedCommands": ["docker", "npm run *:watch"]}}')"
assert_denied 'exact entry, bare' "$(run "$home_exact" 'docker | cat')" 'docker'
assert_pass 'exact entry, alone' "$(run "$home_exact" 'docker')"
assert_pass 'exact entry, with arguments' "$(run "$home_exact" 'docker ps')"
assert_denied 'mid-pattern glob' "$(run "$home_exact" 'npm run build:watch | cat')" 'npm'
assert_pass 'mid-pattern glob, alone' "$(run "$home_exact" 'npm run build:watch')"
assert_pass 'mid-pattern glob, no match' "$(run "$home_exact" 'npm run build')"

# --- pass: nothing excluded would run sandboxed ------------------------------

# Every subcommand is excluded and no refused shape is present: the harness
# already runs the call unsandboxed. The first rows are the shapes observed
# running unsandboxed.
while IFS= read -r cmd; do
  assert_pass "$cmd" "$(run "$home" "$cmd")"
done <<'EOF'
ls a && ls b
ls a | ls b
ls a; ls b
git commit -m "fix: a > b, *? & (y) ~ {a,b}"
ls foo\.bar
ls a  # comment
git status --porcelain
git status
git
ls
just release minor
just release
claude -p ping
git log --format='%H $x' -- 'a*b'
git show HEAD~1
git log @{u}..
EOF

# The flag already takes the call out of the sandbox.
assert_pass 'flag set, bare' "$(run "$home" 'git status' true)"
assert_pass 'flag set, piped' "$(run "$home" 'git commit -m x | tail' true)"

# Not an excluded subcommand: a different command word, a prefix that is not
# a word boundary, an excluded word appearing only as an argument, a recipe
# other than release.
while IFS= read -r cmd; do
  assert_pass "$cmd" "$(run "$home" "$cmd")"
done <<'EOF'
echo git status
gitk
lsof -i
grep -rn git .
just precommit
just releases
justfoo release
npm test | tail
cat README.md
EOF

# Quoted text is an argument, never a subcommand.
assert_pass 'double-quoted prose' "$(run "$home" 'echo "git status | ls"')"
assert_pass 'single-quoted prose' "$(run "$home" "echo 'ls; git push'")"
assert_pass 'commit message body' "$(run "$home" 'gh pr comment 1 --body "run git status; ls"')"

# A heredoc body is data.
out="$(run "$home" $'cat <<EOF >notes.txt\ngit push\nls -la\nEOF')"
assert_pass 'heredoc body' "$out"

# A command or process substitution anywhere outside single quotes turns
# matching off for the whole call.
while IFS= read -r cmd; do
  assert_pass "$cmd" "$(run "$home" "$cmd")"
done <<'EOF'
echo $(git rev-parse HEAD)
ls $(pwd)
echo "$(git log -1)"; ls
echo `git rev-parse HEAD`
diff <(ls a) <(ls b)
git log >(cat)
EOF

# No sandbox, no list, or a list the hook cannot read: nothing to enforce
# here. The SessionStart check is what reports a settings file it cannot read.
assert_pass 'sandbox disabled' \
  "$(run "$(new_home off '{"sandbox": {"enabled": false, "excludedCommands": ["git *"]}}')" 'git status')"
assert_pass 'no settings file' "$(run "$(new_home none)" 'git status')"
assert_pass 'unparseable settings' "$(run "$(new_home broken '{not json')" 'git status')"
assert_pass 'excludedCommands not a list' \
  "$(run "$(new_home not-list '{"sandbox": {"enabled": true, "excludedCommands": "git *"}}')" 'git status')"
assert_pass 'sandbox not an object' "$(run "$(new_home bad-sandbox '{"sandbox": "on"}')" 'git status')"
assert_pass 'no excludedCommands' "$(run "$(new_home no-list '{"sandbox": {"enabled": true}}')" 'git status')"

# Other tools are not this hook's business.
out="$(jq -nc '{tool_name: "Read", tool_input: {file_path: "/x"}}' | HOME="$home" bash "$hook" 2>&1 || true)"
assert_pass 'non-Bash tool' "$out"

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
