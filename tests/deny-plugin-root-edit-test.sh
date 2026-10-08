#!/usr/bin/env bash
# End-to-end test of deny-plugin-root-edit.sh against synthetic
# PreToolUse(Write|Edit|MultiEdit|NotebookEdit) payloads.
#
# Every call runs under a fixture `claude`: a symlink to bash, so a process
# exec'd through it has `comm` `claude` and a NUL-exact argv. The hook's
# ancestor walk stops at the first `claude`, so the fixture both supplies the
# argv under test and shields the verdicts from the real session running this
# suite, whose argv may hold `--plugin-dir .`. No test-only branch exists in
# the hook: this is the production code path.
#
# Verdicts: D = deny with all three channels non-empty, naming the resolved
# root and the source label; N = systemMessage only; P = no output.
#
# Usage: bash tests/deny-plugin-root-edit-test.sh   (run from repo root)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/scripts/deny-plugin-root-edit.sh"

# This repo's dogfood launcher exports the variable, and CC sets the project
# dir: both are per-case inputs here, never inherited.
unset CLAUDE_CODE_PLUGIN_DIRS CLAUDE_PROJECT_DIR

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
  return 0
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Resolved, so expected roots compare equal to the hook's resolved ones where
# the temp dir sits behind a symlink (macOS /var -> /private/var).
work="$(cd -P -- "$work" && pwd)"

mkdir -p "$work/bin"
ln -s "$(command -v bash)" "$work/bin/claude"

have_proc=0
[ -r "/proc/$$/status" ] && have_proc=1
argv_skipped=0

R="$work/R"
mkdir -p "$R" "$work/R-sibling" "$work/o" "$work/A" "$work/rel" "$work/r" \
  "$work/My Root" "$work/My" "$work/P/p" "$work/Q/p" \
  "$work/W/dist/plugin" "$work/W/scripts"
: >"$R/x.sh"
: >"$R/y"
: >"$work/o/out.txt"
ln -s "$R" "$work/L"
ln -s "$R/y" "$work/S"
ln -s "$work/o/out.txt" "$R/z"

# The fixture's own script: `; exit $?` stops bash exec'ing the child, which
# would replace the fixture's `comm`; the inner `sh -c` mirrors production,
# where CC spawns the hook command through /bin/sh.
# shellcheck disable=SC2016  # expanded by the fixture shell, not here
fixture_script='sh -c "bash \"\$1\"" sh "$1" <"$2"; exit $?'

# stderr is merged into the captured output and a non-zero exit swallowed: a
# pass case asserts the output is empty, so a hook that dies noisily fails the
# assertion rather than aborting the suite mid-loop under `set -e`.
run_under() { # run_under <cwd> <payload-json> [claude-args…]
  local cwd="$1" payload="$work/payload.json"
  printf '%s\n' "$2" >"$payload"
  shift 2
  (cd "$cwd" && "$work/bin/claude" -c "$fixture_script" claude-fixture \
    "$hook" "$payload" "$@") 2>&1 || true
}

# Two fixture `claude`s, outer then inner. The inner one's single optional
# root travels in the environment, so it never appears in the outer argv.
# shellcheck disable=SC2016  # expanded by the outer fixture shell
outer_script='"$FIXTURE_BIN" -c "$FIXTURE_SCRIPT" claude-fixture "$1" "$2" ${INNER_ROOT:+--plugin-dir "$INNER_ROOT"}; exit $?'
run_nested() { # run_nested <cwd> <payload-json> <inner-root|""> [outer-args…]
  local cwd="$1" payload="$work/payload.json" inner="$3"
  printf '%s\n' "$2" >"$payload"
  shift 3
  (cd "$cwd" && FIXTURE_BIN="$work/bin/claude" \
    FIXTURE_SCRIPT="$fixture_script" INNER_ROOT="$inner" \
    "$work/bin/claude" -c "$outer_script" claude-fixture \
    "$hook" "$payload" "$@") 2>&1 || true
}

# <k> plain bash layers between the fixture `claude` and the hook's `sh`, so
# the fixture sits k+2 hops above the hook: hook -> sh -> k bash -> claude.
# The `sh` here carries its own `; exit $?`: where /bin/sh is bash it would
# otherwise exec the hook and shift every hop count by one.
# shellcheck disable=SC2016  # expanded by each layer's shell
layer_script='n="$1"; shift; if [ "$n" -gt 0 ]; then bash -c "$LAYER_SCRIPT" layer "$((n - 1))" "$@"; exit $?; fi; sh -c "bash \"\$1\"; exit \$?" sh "$1" <"$2"; exit $?'
run_layers() { # run_layers <cwd> <payload-json> <k> [claude-args…]
  local cwd="$1" payload="$work/payload.json" k="$3"
  printf '%s\n' "$2" >"$payload"
  shift 3
  (cd "$cwd" && LAYER_SCRIPT="$layer_script" \
    "$work/bin/claude" -c "$layer_script" claude-fixture \
    "$k" "$hook" "$payload" "$@") 2>&1 || true
}

# The hook's `sh` moves to <hook-cwd> before starting it, so the hook's own
# cwd differs from the fixture `claude`'s.
# shellcheck disable=SC2016  # expanded by the fixture shell
split_cwd_script='sh -c "cd \"\$2\" && bash \"\$1\"; exit \$?" sh "$1" "$3" <"$2"; exit $?'
run_split_cwd() { # run_split_cwd <claude-cwd> <hook-cwd> <payload-json> [claude-args…]
  local cwd="$1" hook_cwd="$2" payload="$work/payload.json"
  printf '%s\n' "$3" >"$payload"
  shift 3
  (cd "$cwd" && "$work/bin/claude" -c "$split_cwd_script" claude-fixture \
    "$hook" "$payload" "$hook_cwd" "$@") 2>&1 || true
}

pl() { # pl <tool> <mode|-> <path>; mode `-` omits permission_mode
  jq -nc --arg t "$1" --arg m "$2" --arg f "$3" \
    '{tool_name: $t, tool_input: {file_path: $f}}
     + (if $m == "-" then {} else {permission_mode: $m} end)'
}

expect_deny() { # expect_deny <label> <out> <root> <source-label>
  jq -e --arg r "$3" --arg s "($4)" '
    .hookSpecificOutput.permissionDecision == "deny"
    and (.hookSpecificOutput.permissionDecisionReason // "" | contains($r))
    and (.hookSpecificOutput.permissionDecisionReason // "" | contains($s))
    and (.hookSpecificOutput.additionalContext // "") != ""
    and (.systemMessage // "") != ""' >/dev/null 2>&1 <<<"$2" \
    || fail "$1: expected deny naming $3 $4, got: $2"
}

expect_note() { # expect_note <label> <out>
  jq -e '(.systemMessage // "") != ""
    and .hookSpecificOutput.permissionDecision == null
    and .hookSpecificOutput.additionalContext == null' \
    >/dev/null 2>&1 <<<"$2" \
    || fail "$1: expected a systemMessage-only note, got: $2"
}

expect_pass() { # expect_pass <label> <out>
  [ -z "$2" ] || fail "$1: expected no output, got: $2"
}

env_src=CLAUDE_CODE_PLUGIN_DIRS

# --- env source ------------------------------------------------------------

for t in Edit Write; do
  out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl "$t" auto "$R/x.sh")")"
  expect_deny "1 [$t] env root" "$out" "$R" "$env_src"
done

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit auto "$R")")"
expect_deny "2 the root itself" "$out" "$R" "$env_src"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit auto "$work/R-sibling/x")")"
expect_pass "3 R-sibling is not under R" "$out"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit auto "$work/o/x")")"
expect_pass "4 outside every root" "$out"

for dirs in "$work/A:$R" "::$R:"; do
  out="$(CLAUDE_CODE_PLUGIN_DIRS="$dirs" run_under "$work" "$(pl Edit auto "$R/x")")"
  expect_deny "5 env list '$dirs'" "$out" "$R" "$env_src"
done

out="$(CLAUDE_CODE_PLUGIN_DIRS=rel run_under "$work" "$(pl Edit auto "$work/rel/x")")"
expect_pass "6 a relative env entry is dropped" "$out"

# A literal ~ on purpose: expanding it is the hook's job, as it is CC's.
# shellcheck disable=SC2088
out="$(CLAUDE_CODE_PLUGIN_DIRS="~/r" HOME="$work" run_under "$work" "$(pl Edit auto "$work/r/x")")"
expect_deny "7 env ~/r against HOME" "$out" "$work/r" "$env_src"

# shellcheck disable=SC2088
out="$(CLAUDE_CODE_PLUGIN_DIRS="~" HOME="$R" run_under "$work" "$(pl Edit auto "$R/x")")"
expect_deny "7 env lone ~ against HOME" "$out" "$R" "$env_src"

# --- argv source -----------------------------------------------------------

if (( have_proc )); then
  out="$(run_under "$work" "$(pl Edit auto "$R/x")" --plugin-dir "$R")"
  expect_deny "8 --plugin-dir R" "$out" "$R" --plugin-dir

  out="$(run_under "$work" "$(pl Edit auto "$R/x")" "--plugin-dir=$R")"
  expect_deny "9 --plugin-dir=R" "$out" "$R" --plugin-dir

  out="$(run_under "$work" "$(pl Edit auto "$R/x")" --plugin-dir-no-mcp "$R")"
  expect_deny "10 --plugin-dir-no-mcp R" "$out" "$R" --plugin-dir-no-mcp
  out="$(run_under "$work" "$(pl Edit auto "$R/x")" "--plugin-dir-no-mcp=$R")"
  expect_deny "10 --plugin-dir-no-mcp=R" "$out" "$R" --plugin-dir-no-mcp

  out="$(run_under "$work" "$(pl Edit auto "$work/My Root/x")" --plugin-dir "$work/My Root")"
  expect_deny "11 spaced root" "$out" "$work/My Root" --plugin-dir
  out="$(run_under "$work" "$(pl Edit auto "$work/My/x")" --plugin-dir "$work/My Root")"
  expect_pass "11 spaced root does not split into My" "$out"

  out="$(CLAUDE_PROJECT_DIR="$work/P" run_under "$work/Q" "$(pl Edit auto "$work/P/p/x")" --plugin-dir p)"
  expect_deny "12 relative root anchors on CLAUDE_PROJECT_DIR" "$out" "$work/P/p" --plugin-dir
  out="$(CLAUDE_PROJECT_DIR="$work/P" run_under "$work/Q" "$(pl Edit auto "$work/Q/p/x")" --plugin-dir p)"
  expect_pass "12 relative root ignores cwd when the project dir is set" "$out"

  out="$(run_under "$work/Q" "$(pl Edit auto "$work/Q/p/x")" --plugin-dir p)"
  expect_deny "13 relative root falls back to the claude cwd" "$out" "$work/Q/p" --plugin-dir
  out="$(run_split_cwd "$work/Q" "$work" "$(pl Edit auto "$work/Q/p/x")" --plugin-dir p)"
  expect_deny "13 the claude cwd, not the hook's own" "$out" "$work/Q/p" --plugin-dir

  out="$(run_nested "$work" "$(pl Edit auto "$R/x")" "" --plugin-dir "$R")"
  expect_pass "14 the nearest claude's argv wins over an outer one" "$out"

  out="$(run_nested "$work" "$(pl Edit auto "$R/x")" "$R")"
  expect_deny "15 the inner claude's argv is read" "$out" "$R" --plugin-dir

  out="$(run_under "$work" "$(pl Edit auto "$R/x")" -- --plugin-dir "$R")"
  expect_pass "16 nothing after -- is an option" "$out"

  # Taken as a root, an empty value would resolve to the claude cwd, $work.
  out="$(run_under "$work" "$(pl Edit auto "$work/o/x")" --plugin-dir= --plugin-dir "")"
  expect_pass "32 empty --plugin-dir values are skipped" "$out"

  out="$(run_layers "$work" "$(pl Edit auto "$R/x")" 6 --plugin-dir "$R")"
  expect_deny "17 claude at the 8th ancestor is found" "$out" "$R" --plugin-dir
  out="$(run_layers "$work" "$(pl Edit auto "$R/x")" 7 --plugin-dir "$R")"
  expect_pass "17 claude at the 9th ancestor is past the cap" "$out"
else
  argv_skipped=1
fi

# --- matching --------------------------------------------------------------

out="$(CLAUDE_CODE_PLUGIN_DIRS="$work/L" run_under "$work" "$(pl Edit auto "$R/x")")"
expect_deny "18 symlinked root resolves to its target" "$out" "$R" "$env_src"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit auto "$work/L/x")")"
expect_deny "19 target through a symlinked dir" "$out" "$R" "$env_src"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit auto "$work/S")")"
expect_deny "20 outside symlink to a file under R (t2)" "$out" "$R" "$env_src"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit auto "$R/z")")"
expect_deny "21 link under R to an outside file (t1)" "$out" "$R" "$env_src"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Write auto "$R/new/dir/f")")"
expect_deny "22 Write creating new dirs under R" "$out" "$R" "$env_src"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$R" "$(pl Edit auto x.sh)")"
expect_deny "23 relative target against the hook cwd" "$out" "$R" "$env_src"

# A root `cd -P` cannot enter is dropped, silently: stderr is merged into the
# capture, so a leaked `Permission denied` breaks the deny's JSON. Root can
# enter a 0600 directory, so the case says nothing there.
if [ "$(id -u)" -ne 0 ]; then
  mkdir "$work/locked"
  chmod 0600 "$work/locked"
  out="$(CLAUDE_CODE_PLUGIN_DIRS="$work/locked:$R" run_under "$work" "$(pl Edit auto "$R/x")")"
  chmod 0700 "$work/locked"
  expect_deny "31 an unenterable root is dropped without stderr" "$out" "$R" "$env_src"
fi

# --- modes -----------------------------------------------------------------

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit dontAsk "$R/x")")"
expect_deny "24 dontAsk" "$out" "$R" "$env_src"

for m in default acceptEdits -; do
  out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit "$m" "$R/x")")"
  expect_note "25 mode '$m'" "$out"
done

for m in plan bypassPermissions someFutureMode; do
  out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl Edit "$m" "$R/x")")"
  expect_pass "26 mode '$m'" "$out"
done

# --- tools -----------------------------------------------------------------

nb="$(jq -nc --arg f "$R/n.ipynb" \
  '{tool_name: "NotebookEdit", permission_mode: "auto", tool_input: {notebook_path: $f}}')"
out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$nb")"
expect_deny "27 NotebookEdit notebook_path" "$out" "$R" "$env_src"

out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl MultiEdit auto "$R/x")")"
expect_deny "27 MultiEdit" "$out" "$R" "$env_src"

for t in Read Bash; do
  out="$(CLAUDE_CODE_PLUGIN_DIRS="$R" run_under "$work" "$(pl "$t" auto "$R/x")")"
  expect_pass "28 [$t] is not an edit tool" "$out"
done

# --- the dogfood copy ------------------------------------------------------

W="$work/W"
out="$(CLAUDE_CODE_PLUGIN_DIRS="$W/dist/plugin" run_under "$W" "$(pl Edit auto "$W/scripts/x.sh")")"
expect_pass "29 the source tree beside a loaded dist copy" "$out"
out="$(CLAUDE_CODE_PLUGIN_DIRS="$W/dist/plugin" run_under "$W" "$(pl Edit auto "$W/dist/plugin/x")")"
expect_deny "29 the loaded dist copy" "$out" "$W/dist/plugin" "$env_src"

# --- no roots at all -------------------------------------------------------

out="$(run_under "$work" "$(pl Edit auto "$R/x")")"
expect_pass "30 bare fixture, no env" "$out"

if (( failures > 0 )); then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
if (( argv_skipped )); then
  printf 'all hook scenarios passed (argv cases 8-17 skipped: no /proc)\n'
else
  printf 'all hook scenarios passed\n'
fi
