#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit|NotebookEdit) guard: deny an edit under a
# directory this Claude Code session loads as a plugin, when nobody is there
# to approve it.
#
# Why (Claude Code 2.1.293): the harness treats every file under a loaded
# plugin root (`--plugin-dir`, `--plugin-dir-no-mcp`, `CLAUDE_CODE_PLUGIN_DIRS`)
# as sensitive and asks before editing it. With no human to answer, in auto
# mode the edit fails hard with an opaque "skipped this action" and the agent
# retries into the same wall. This hook refuses first, naming the cause and
# the recovery.
#
# Mode scope: `auto` and `dontAsk` deny. `default` and `acceptEdits` only add
# a note for the human, because Claude Code's own prompt there can be
# approved and a deny would remove that. Any other mode (`plan`,
# `bypassPermissions`, unknown) passes silently.
#
# Roots come from two sources, env entries first, then argv in order; the
# first root containing the target is the one reported:
#   - CLAUDE_CODE_PLUGIN_DIRS, split on `:` by parameter expansion (entries
#     may hold spaces; leading and trailing spaces and tabs are trimmed per
#     entry, as Claude Code does, and an empty entry skipped), a leading
#     `~` expanded against HOME, non-absolute entries dropped as Claude
#     Code drops them;
#   - the `--plugin-dir[-no-mcp]` options in the argv of the first ancestor
#     process whose `comm` is exactly `claude`, found through /proc (Linux
#     only). A flag-only launch never creates the env variable, so both are
#     needed. A relative value resolves against CLAUDE_PROJECT_DIR, else that
#     process's cwd. The walk gives up after 8 hops.
#
# Residuals: Claude Code case-folds the comparison and this does not
# (under-fires on a case-insensitive volume); `..` in a non-existent tail is
# not collapsed (abspath); a `.zip` root matches only a Write to the zip
# itself; a root path holding `:` cannot be expressed in the env list; on
# macOS or without /proc only the env source is read; an npm/Node install
# (`comm` may not be `claude`) and a direct exec of the versioned binary fall
# back to env-only too.
#
# Failure policy: always exit 0 and never write to stderr; a step that fails
# drops its source or root and the hook carries on.
# Rationale: docs/design.md, "Deny edits under a loaded plugin root in
# unattended modes".
set -euo pipefail

# abspath(), the portable `realpath -m`; sourcing it also clears CDPATH.
# shellcheck source-path=SCRIPTDIR source=lib/path.sh
. "${BASH_SOURCE[0]%/*}/lib/path.sh"

input="$(cat)"
{ IFS= read -r tool_name || true; IFS= read -r mode || true; } \
  <<<"$(jq -r '(.tool_name // ""), (.permission_mode // "")' <<<"$input")"

case "$tool_name" in
  Write | Edit | MultiEdit | NotebookEdit) ;;
  *) exit 0 ;;
esac

case "$mode" in
  auto | dontAsk) branch=deny ;;
  default | acceptEdits | '') branch=note ;;
  *) exit 0 ;;
esac

root_paths=()
root_srcs=()
nroots=0

# Every `2>/dev/null` below is on an abspath or readlink whose expected
# failure is a directory the hook may not enter (`cd: Permission denied`).
# That failure is handled by dropping the root or target, and no channel
# exists for the message: this hook never writes to stderr, so a refused
# `cd -P` must not surface beside the tool call. The exit status still
# drives the drop, so nothing is silenced that changes the verdict.
add_root() { # add_root <label> <path>; resolves, drops the root on failure
  local resolved
  resolved="$(abspath "$2" 2>/dev/null)" || return 0
  root_paths[nroots]="$resolved"
  root_srcs[nroots]="$1"
  nroots=$((nroots + 1))
  return 0
}

rest="${CLAUDE_CODE_PLUGIN_DIRS-}"
home="${HOME-}"
while [ -n "$rest" ]; do
  case "$rest" in
    *:*) entry="${rest%%:*}"; rest="${rest#*:}" ;;
    *) entry="$rest"; rest="" ;;
  esac
  # CC trims whitespace around each entry; inner spaces are part of the path.
  while [ "${entry#[ $'\t']}" != "$entry" ]; do entry="${entry#[ $'\t']}"; done
  while [ "${entry%[ $'\t']}" != "$entry" ]; do entry="${entry%[ $'\t']}"; done
  [ -n "$entry" ] || continue
  if [ -n "$home" ]; then
    # A literal ~ on purpose: expanding it against HOME is the job, as CC's.
    # shellcheck disable=SC2088
    case "$entry" in
      '~') entry="$home" ;;
      '~/'*) entry="$home/${entry#'~/'}" ;;
    esac
  fi
  case "$entry" in
    /*) add_root CLAUDE_CODE_PLUGIN_DIRS "$entry" ;;
  esac
done

if [ -r "/proc/$$/status" ]; then
  pid=$$
  hops=0
  claude_pid=""
  while [ "$hops" -lt 8 ]; do
    hops=$((hops + 1))
    [ -r "/proc/$pid/status" ] || break
    ppid=""
    while read -r key val _; do
      if [ "$key" = "PPid:" ]; then
        ppid="$val"
        break
      fi
    done <"/proc/$pid/status"
    case "$ppid" in
      '' | *[!0-9]*) break ;;
    esac
    [ "$ppid" -gt 1 ] || break
    pid="$ppid"
    [ -r "/proc/$pid/comm" ] || break
    comm=""
    read -r comm <"/proc/$pid/comm" || true
    if [ "$comm" = claude ]; then
      claude_pid="$pid"
      break
    fi
  done

  if [ -n "$claude_pid" ] && [ -r "/proc/$claude_pid/cmdline" ]; then
    if [ -n "${CLAUDE_PROJECT_DIR-}" ]; then
      base="$CLAUDE_PROJECT_DIR"
    else
      base="/proc/$claude_pid/cwd"
    fi
    pending=""
    while IFS= read -r -d '' arg; do
      label=""
      value=""
      if [ -n "$pending" ]; then
        label="$pending"
        value="$arg"
        pending=""
      else
        case "$arg" in
          --) break ;;
          --plugin-dir | --plugin-dir-no-mcp) pending="$arg" ;;
          --plugin-dir=*) label=--plugin-dir; value="${arg#*=}" ;;
          --plugin-dir-no-mcp=*) label=--plugin-dir-no-mcp; value="${arg#*=}" ;;
        esac
      fi
      if [ -z "$label" ] || [ -z "$value" ]; then continue; fi
      case "$value" in
        /*) add_root "$label" "$value" ;;
        *) add_root "$label" "$base/$value" ;;
      esac
    done <"/proc/$claude_pid/cmdline"
  fi
fi

[ "$nroots" -gt 0 ] || exit 0

file_path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
[ -n "$file_path" ] || exit 0

t1="$(abspath "$file_path" 2>/dev/null)" || exit 0
t2=""
if [ -L "$t1" ]; then
  cur="$t1"
  n=0
  while [ -L "$cur" ] && [ "$n" -lt 16 ]; do
    n=$((n + 1))
    link="$(readlink "$cur" 2>/dev/null)" || break
    case "$link" in
      /*) cur="$link" ;;
      *) cur="${cur%/*}/$link" ;;
    esac
  done
  t2="$(abspath "$cur" 2>/dev/null)" || t2=""
fi

root=""
src=""
i=0
while [ "$i" -lt "$nroots" ]; do
  r="${root_paths[i]%/}"
  for t in "$t1" "$t2"; do
    [ -n "$t" ] || continue
    case "$t" in
      "$r" | "$r"/*)
        root="${root_paths[i]}"
        src="${root_srcs[i]}"
        break 2
        ;;
    esac
  done
  i=$((i + 1))
done
[ -n "$root" ] || exit 0

if [ "$branch" = note ]; then
  jq -nc --arg root "$root" --arg src "$src" \
    '{systemMessage: ("edit under loaded plugin root " + $root + " (" + $src + ") — claude code asks for each one")}'
  exit 0
fi

jq -nc --arg root "$root" --arg src "$src" --arg path "$file_path" '
  {hookSpecificOutput: {
     hookEventName: "PreToolUse",
     permissionDecision: "deny",
     permissionDecisionReason: ("Refused: " + $path + " is under " + $root
       + ", which this session loads as a plugin (" + $src
       + "), so Claude Code lets no unattended edit land there."),
     additionalContext: ("Every edit under " + $root
       + " fails the same way for the rest of this session; do not retry it. If "
       + $root + " is a generated copy of a plugin source tree, make the edit in that source tree instead. Otherwise tell the user this edit needs a session that does not load "
       + $root + ", and carry on with work outside it.")},
   systemMessage: ("blocked: edit under loaded plugin root " + $root + " (" + $src + ")")}'
exit 0
