#!/usr/bin/env bash
# End-to-end test of warn-sandbox-excluded-commands.sh against synthetic
# SessionStart payloads and a controlled $HOME.
#
# The contract under test: when the harness sandbox is enabled,
# ~/.claude/settings.json must exclude the five sandbox-sensitive command
# patterns — git:*, find:*, ls:*, claude:*, just release:* — from sandboxing.
# Sandboxed, the first four see phantom dotfiles or silently drop SessionStart
# hooks, and `just release` runs git push and gh inside a recipe body the
# harness cannot see, so a missing entry has to reach both channels:
# additionalContext for the agent (which must then pass
# dangerouslyDisableSandbox until it is fixed) and systemMessage for the human
# who owns the settings file.
#
# The release pattern carries its space and is exact: `just release:*`, never
# `just:*` and never a bare `just release`. Membership is string equality, so
# the literal here has to match the literal in settings.json character for
# character — the bare-entry cases below are what pins that.
#
# Silence is the pass signal, so the failure paths must be loud: no sandbox
# means nothing to exclude and the hook stays quiet, but an unparseable
# settings.json warns rather than passing — a check that cannot run must not
# look like one that ran clean.
#
# $HOME is the only lever the hook offers, so every case builds a throwaway
# home under $TMPDIR and runs the hook against it.
#
# Usage: bash tests/warn-sandbox-excluded-commands-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/warn-sandbox-excluded-commands.sh"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

# --- harness ----------------------------------------------------------------

new_home() { # new_home <label> [settings-json]; prints the home path
  local home="$tmp_root/$1"
  mkdir -p "$home/.claude"
  if [ "$#" -ge 2 ]; then
    printf '%s\n' "$2" >"$home/.claude/settings.json"
  fi
  printf '%s\n' "$home"
}

# The hook needs nothing from the payload but must still consume it.
payload() {
  jq -nc '{hook_event_name: "SessionStart", session_id: "t", cwd: "/x", source: "startup"}'
}

out=''
status=0
ctx=''
msg=''

# stderr is merged into the captured output: a pass case asserts the output is
# empty, so a script that dies noisily fails rather than passing silently.
run() { # run <home>; sets $out and $status
  out="$(payload | HOME="$1" bash "$hook" 2>&1)" && status=0 || status=$?
}

assert_pass() { # assert_pass <label>
  [ "$status" -eq 0 ] || fail "$1: expected exit 0, got $status: $out"
  [ -z "$out" ] || fail "$1: expected silent pass, got: $out"
  return 0
}

# Quoting the needle inside the pattern keeps it literal: every pattern under
# test contains a `*` that would otherwise glob against anything.
asserts() { # asserts <label> <field> <haystack> <needle>
  case "$3" in
    *"$4"*) ;;
    *) fail "$1: $2 does not name '$4': $3" ;;
  esac
  return 0
}

refutes() { # refutes <label> <field> <haystack> <needle>
  case "$3" in
    *"$4"*) fail "$1: $2 names '$4', which is not missing: $3" ;;
  esac
  return 0
}

# Shape shared by every warn case, parse failure included: a SessionStart
# hookSpecificOutput on stdout with exit 0, both channels populated, and an
# agent-facing text naming the workaround and the file to fix. Sets $ctx/$msg
# for the per-case assertions that follow.
assert_warn_shape() { # assert_warn_shape <label> <settings-path>
  local label="$1" path="$2"
  ctx=''
  msg=''
  [ "$status" -eq 0 ] || fail "$label: expected exit 0, got $status: $out"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' \
    >/dev/null 2>&1 || { fail "$label: no SessionStart hookSpecificOutput: $out"; return 0; }
  ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  msg="$(printf '%s' "$out" | jq -r '.systemMessage // ""')"
  [ -n "$ctx" ] || fail "$label: warning carried no additionalContext for the agent"
  [ -n "$msg" ] || fail "$label: warning carried no systemMessage for the human"
  asserts "$label" additionalContext "$ctx" 'dangerouslyDisableSandbox'
  asserts "$label" additionalContext "$ctx" "$path"
  return 0
}

all_five=('git:*' 'find:*' 'ls:*' 'claude:*' 'just release:*')

# --- pass: nothing to warn about --------------------------------------------

# No settings file at all, in a home that has a .claude directory and in one
# that does not: absence is not a sandbox.
home="$(new_home no-settings-file)"
run "$home"
assert_pass 'no ~/.claude/settings.json'

home="$tmp_root/no-claude-dir"
mkdir -p "$home"
run "$home"
assert_pass 'no ~/.claude directory at all'

# Sandbox off: the excludedCommands list is inert, empty or not.
home="$(new_home sandbox-disabled '{"sandbox": {"enabled": false, "excludedCommands": []}}')"
run "$home"
assert_pass 'sandbox disabled'

# A settings file with no sandbox key is the same situation.
home="$(new_home no-sandbox-key '{}')"
run "$home"
assert_pass 'settings.json with no sandbox key'

# The configuration this hook exists to reach: all five present.
home="$(new_home all-present \
  '{"sandbox": {"enabled": true, "excludedCommands": ["git:*","find:*","ls:*","claude:*","just release:*"]}}')"
run "$home"
assert_pass 'all five patterns excluded'

# Membership, not equality: extra entries and a different order are still
# compliant — a real settings.json accretes exclusions.
home="$(new_home all-present-plus-extras \
  '{"sandbox": {"enabled": true, "excludedCommands": ["claude:*","npm:*","just release:*","ls:*","git:*","find:*"]}}')"
run "$home"
assert_pass 'all five present among extras, unordered'

# The hook must consume stdin even though it needs nothing from it. A payload
# larger than the pipe buffer makes a non-consuming hook kill the writer:
# under `set -o pipefail` that surfaces as a non-zero status or as jq's error
# text on the merged stderr, so this pass case is what catches it.
home="$(new_home oversized-payload \
  '{"sandbox": {"enabled": true, "excludedCommands": ["git:*","find:*","ls:*","claude:*","just release:*"]}}')"
pad="$tmp_root/pad.txt"   # via a file: 256KB through --arg overruns ARG_MAX
head -c 262144 /dev/zero | tr '\0' 'x' >"$pad"
out="$(jq -nc --rawfile p "$pad" \
  '{hook_event_name: "SessionStart", session_id: "t", cwd: "/x", source: "startup", pad: $p}' \
  | HOME="$home" bash "$hook" 2>&1)" && status=0 || status=$?
assert_pass 'oversized payload is consumed, not left in the pipe'

# --- warn: the sandbox is on and the exclusions are not there ---------------

# No excludedCommands key at all: every one of the five is missing.
home="$(new_home no-excluded-commands '{"sandbox": {"enabled": true}}')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape 'excludedCommands absent' "$settings"
asserts 'excludedCommands absent' systemMessage "$msg" 'excludedCommands'
for p in "${all_five[@]}"; do
  asserts 'excludedCommands absent' additionalContext "$ctx" "$p"
  asserts 'excludedCommands absent' systemMessage "$msg" "$p"
done

# A partial list: only the absent patterns get named, and the ones that are
# present must not be reported as missing — a warning that relists satisfied
# entries costs the human the diff they came for.
home="$(new_home partial-list \
  '{"sandbox": {"enabled": true, "excludedCommands": ["git:*","ls:*"]}}')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape 'partial excludedCommands' "$settings"
asserts 'partial excludedCommands' systemMessage "$msg" 'excludedCommands'
for p in 'find:*' 'claude:*' 'just release:*'; do
  asserts 'partial excludedCommands' additionalContext "$ctx" "$p"
  asserts 'partial excludedCommands' systemMessage "$msg" "$p"
done
refutes 'partial excludedCommands' systemMessage "$msg" 'git:*'
refutes 'partial excludedCommands' systemMessage "$msg" 'ls:*'

# Exact-string membership: a bare `git` entry is a different exclusion from
# `git:*` and does not satisfy it, so `git:*` alone is missing.
home="$(new_home bare-prefix \
  '{"sandbox": {"enabled": true, "excludedCommands": ["git", "find:*", "ls:*", "claude:*", "just release:*"]}}')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape 'bare git entry' "$settings"
asserts 'bare git entry' systemMessage "$msg" 'excludedCommands'
asserts 'bare git entry' additionalContext "$ctx" 'git:*'
asserts 'bare git entry' systemMessage "$msg" 'git:*'
for p in 'find:*' 'ls:*' 'claude:*' 'just release:*'; do
  refutes 'bare git entry' systemMessage "$msg" "$p"
done

# Same exactness for the two-word pattern, which is the one most likely to be
# written loosely: a bare `just release` is not `just release:*`, and `just:*`
# is a different, broader exclusion that does not satisfy it either.
home="$(new_home bare-release \
  '{"sandbox": {"enabled": true, "excludedCommands": ["git:*", "find:*", "ls:*", "claude:*", "just release", "just:*"]}}')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape 'bare just release entry' "$settings"
asserts 'bare just release entry' systemMessage "$msg" 'excludedCommands'
asserts 'bare just release entry' additionalContext "$ctx" 'just release:*'
asserts 'bare just release entry' systemMessage "$msg" 'just release:*'
for p in 'git:*' 'find:*' 'ls:*' 'claude:*'; do
  refutes 'bare just release entry' systemMessage "$msg" "$p"
done

# Unparseable settings: fail loud. A silent check here is indistinguishable
# from one that never ran, and the sandbox may well be on.
home="$(new_home broken-json '{not json')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape 'unparseable settings.json' "$settings"
for needle in 'settings.json' 'parse'; do
  asserts 'unparseable settings.json' additionalContext "$ctx" "$needle"
  asserts 'unparseable settings.json' systemMessage "$msg" "$needle"
done

# Parseable but the wrong shape, which is the harder case: the JSON is valid,
# so it clears the parse gate and only fails when the keys are read. Warning
# is the only honest answer — the sandbox may be on and the check did not run.
# `off` and `bad` must stay distinguishable, or the check's silence stops
# meaning anything.
home="$(new_home sandbox-not-an-object '{"sandbox": "enabled"}')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape '.sandbox is a string' "$settings"
asserts '.sandbox is a string' additionalContext "$ctx" 'sandbox is not an object'
asserts '.sandbox is a string' systemMessage "$msg" 'sandbox is not an object'

home="$(new_home settings-not-an-object '[1, 2]')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape 'settings.json is an array, not an object' "$settings"
asserts 'settings.json is an array' additionalContext "$ctx" 'not a JSON object'

home="$(new_home excluded-not-a-list \
  '{"sandbox": {"enabled": true, "excludedCommands": "git:*"}}')"
settings="$home/.claude/settings.json"
run "$home"
assert_warn_shape 'excludedCommands is a string' "$settings"
asserts 'excludedCommands is a string' additionalContext "$ctx" 'excludedCommands is not a list'
asserts 'excludedCommands is a string' systemMessage "$msg" 'excludedCommands is not a list'

# `"sandbox": false` is a legitimate way to turn it off, not a shape error.
home="$(new_home sandbox-false '{"sandbox": false}')"
run "$home"
assert_pass '"sandbox": false is off, not malformed'

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all hook scenarios passed\n'
