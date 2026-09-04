#!/usr/bin/env bash
# SessionStart check: warn when the harness sandbox is on but
# `~/.claude/settings.json` does not exclude `git`, `find`, `ls`, `claude` and
# `just release` from it.
#
# Sandboxed, `git`/`find`/`ls` see phantom dotfiles — user-home dotfiles are
# bind-mounted to `/dev/null` and show up as untracked character devices — and
# a sandboxed `claude -p` silently drops every SessionStart hook. `just
# release` is a different failure: a recipe body is invisible to the harness,
# which matches `excludedCommands` statically against the segments of the Bash
# call, so the `git:*` entry never reaches the `git push` and `gh` calls
# `release.sh` makes *inside* the recipe. The harness's own
# `sandbox.excludedCommands` runs those commands unsandboxed while the
# auto-mode classifier still vets them, so the plugin only has to check the
# setting is present: once, at session start, naming what is missing.
#
# Mechanical: exact-string membership of the five patterns in
# `.sandbox.excludedCommands` — no globbing, the patterns are compared as
# literals. Silence is the pass signal, so every way of not knowing warns
# rather than passing — unparseable JSON, a `.sandbox` that is not an object,
# an `excludedCommands` that is not a list: a check that could not run must
# not look like one that ran clean. Residual: only the user-level
# `~/.claude/settings.json` is read;
# a project or managed settings file setting the same key is not consulted, so
# this can warn about an exclusion that is in fact in force.
set -euo pipefail

warn() { # warn <agent-context> <human-line>; emits the hook JSON and exits 0
  jq -nc --arg c "$1" --arg s "$2" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c},
      systemMessage: $s}'
  exit 0
}

# The SessionStart payload carries nothing this hook needs, but it must still
# be drained: an oversized payload left in the pipe kills the writer.
cat >/dev/null

settings="$HOME/.claude/settings.json"
[ -f "$settings" ] || exit 0

if ! jq empty "$settings" >/dev/null 2>&1; then
  warn "Could not parse $settings, so the sandbox exclusion check could not run.
If the sandbox is enabled, run git, find, ls, claude -p and just release with dangerouslyDisableSandbox: true until that file parses again — sandboxed, git/find/ls see phantom dotfiles (user-home dotfiles bind-mounted to /dev/null show up as untracked character devices), a sandboxed claude -p silently drops every SessionStart hook, and just release runs git push and gh inside a recipe body the harness cannot see, so the git exclusion never reaches them." \
    "prohibitions: could not parse $settings — sandbox excludedCommands left unchecked"
fi

# Three outcomes, not two. A bare `jq -e '.sandbox.enabled == true' || exit 0`
# collapses "sandbox off" and "jq could not evaluate this" into the same
# silent pass — and a wrong-typed `.sandbox` is valid JSON, so it clears the
# parse gate above and only fails here. Naming the third outcome is what keeps
# the check's silence meaningful.
# Each wrong shape is classified inside jq rather than left to blow up, so
# the only thing on stderr is a real jq failure: the top-level type is checked
# before `.sandbox` is indexed, and `.sandbox`'s before `.excludedCommands`
# is. The `||` is the belt-and-braces for anything unforeseen, not the
# mechanism.
state="$(jq -r '
  if type != "object" then "bad-settings"
  elif .sandbox == null or .sandbox == false then "off"
  elif (.sandbox | type) != "object" then "bad-sandbox"
  elif .sandbox.enabled != true then "off"
  elif ((.sandbox.excludedCommands // []) | type) != "array" then "bad-excluded"
  else "on"
  end' "$settings")" || state="bad-settings"

case "$state" in
  off) exit 0 ;;
  on) ;;
  *)
    case "$state" in
      bad-excluded) detail="sandbox.excludedCommands is not a list" ;;
      bad-sandbox) detail="sandbox is not an object" ;;
      *) detail="the file is not a JSON object" ;;
    esac
    warn "In $settings, $detail, so the sandbox exclusion check could not run.
If the sandbox is enabled, run git, find, ls, claude -p and just release with dangerouslyDisableSandbox: true until that key is fixed — sandboxed, git/find/ls see phantom dotfiles (user-home dotfiles bind-mounted to /dev/null show up as untracked character devices), a sandboxed claude -p silently drops every SessionStart hook, and just release runs git push and gh inside a recipe body the harness cannot see, so the git exclusion never reaches them." \
      "prohibitions: $settings — $detail, sandbox excludedCommands left unchecked"
    ;;
esac

# The five sandbox-sensitive patterns, inline in the jq program that reads
# them. Array subtraction is exact-string membership and preserves the order
# on its left, so the result is the missing set, listed as written here. The
# release entry carries its space and is `just release:*`, not `just:*`: the
# prohibition is about the release path, which pushes to two remotes and calls
# `gh`, not about every recipe in every repo.
missing="$(jq -r '
  ["git:*", "find:*", "ls:*", "claude:*", "just release:*"]
  - ((.sandbox.excludedCommands? // []) | if type == "array" then . else [] end)
  | join(", ")' "$settings")"
[ -n "$missing" ] || exit 0

warn "The harness sandbox is enabled, but $settings does not list $missing under sandbox.excludedCommands.
Until that is fixed, run git, find, ls, claude -p and just release with dangerouslyDisableSandbox: true: sandboxed, git/find/ls see phantom dotfiles (user-home dotfiles bind-mounted to /dev/null show up as untracked character devices), a sandboxed claude -p silently drops every SessionStart hook, and just release runs git push and gh inside a recipe body the harness cannot see, so the git exclusion never reaches them." \
  "prohibitions: $settings sandbox.excludedCommands is missing $missing — add them so those commands run unsandboxed"
