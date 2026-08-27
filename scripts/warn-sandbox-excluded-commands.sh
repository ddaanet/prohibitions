#!/usr/bin/env bash
# SessionStart check: warn when the harness sandbox is on but
# `~/.claude/settings.json` does not exclude `git`, `find`, `ls` and `claude`
# from it.
#
# Sandboxed, `git`/`find`/`ls` see phantom dotfiles — user-home dotfiles are
# bind-mounted to `/dev/null` and show up as untracked character devices — and
# a sandboxed `claude -p` silently drops every SessionStart hook. The harness's
# own `sandbox.excludedCommands` runs those commands unsandboxed while the
# auto-mode classifier still vets them, so the plugin only has to check the
# setting is present: once, at session start, naming what is missing.
#
# Mechanical: exact-string membership of the four `<cmd>:*` prefixes in
# `.sandbox.excludedCommands` — no globbing, the patterns are compared as
# literals. Silence is the pass signal, so an unparseable settings.json warns
# rather than passing: a check that could not run must not look like one that
# ran clean. Residual: only the user-level `~/.claude/settings.json` is read;
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
If the sandbox is enabled, run git, find, ls and claude -p with dangerouslyDisableSandbox: true until that file parses again — sandboxed, git/find/ls see phantom dotfiles (user-home dotfiles bind-mounted to /dev/null show up as untracked character devices) and a sandboxed claude -p silently drops every SessionStart hook." \
    "prohibitions: could not parse $settings — sandbox excludedCommands left unchecked"
fi

jq -e '.sandbox.enabled == true' "$settings" >/dev/null 2>&1 || exit 0

# The four sandbox-sensitive prefixes, inline in the jq program that reads
# them. Array subtraction is exact-string membership and preserves the order
# on its left, so the result is the missing set, listed as written here.
missing="$(jq -r '
  ["git:*", "find:*", "ls:*", "claude:*"]
  - ((.sandbox.excludedCommands? // []) | if type == "array" then . else [] end)
  | join(", ")' "$settings")"
[ -n "$missing" ] || exit 0

warn "The harness sandbox is enabled, but $settings does not list $missing under sandbox.excludedCommands.
Until that is fixed, run git, find, ls and claude -p with dangerouslyDisableSandbox: true: sandboxed, git/find/ls see phantom dotfiles (user-home dotfiles bind-mounted to /dev/null show up as untracked character devices) and a sandboxed claude -p silently drops every SessionStart hook." \
  "prohibitions: $settings sandbox.excludedCommands is missing $missing — add them so those commands run unsandboxed"
