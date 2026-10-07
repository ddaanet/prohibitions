#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny git commands that discard uncommitted work in
# bulk, and ask before a per-file restore.
#
# Deny: `reset --hard`/`--merge`, `clean -f` without a dry run, `stash drop`
# and `stash clear`, a forced `checkout`/`switch`, and a `checkout`/`restore`
# whose pathspec is bulk (`.`, `..`, `:/`, other `:` magic, a trailing `/`,
# a glob, or a directory). Ask: a `checkout`/`restore` of named files, which
# overwrites their uncommitted edits. A restore that clobbers an agent's own
# edit costs the edit, and a probe that overwrites a file to see how it
# behaves does the same to a human's work; the redirect is to set the file
# aside with `cp` and put it back afterwards. The deny splits by audience:
# the reason refuses, additionalContext carries the recovery, and
# systemMessage is the human's curt line. The ask carries no systemMessage:
# the dialog is the human's channel, and in headless runs the reason is also
# the agent's tool_result, so it names the paths and holds no imperative.
# Rationale: docs/design.md, "Deny bulk discards, ask per-file restores".
#
# Mechanism: the command text is heredoc-stripped, split quote-aware into
# simple commands and words by `shell_split`, and each segment is walked by
# `git_walk` (scripts/lib/git-command.sh: `git` must be the command word,
# global options skipped). `git_checkout_parse` decides whether a
# `checkout <x>` names a branch or a path; it spawns `git rev-parse` once,
# only for an operand that exists on disk or has a pathspec shape. The
# effective directory starts at the payload cwd, follows `cd <literal>`
# and `git -C`, and goes unknown on any other `cd`, `pushd`, `popd`, an
# X-flagged `-C` operand, `--git-dir`/`--work-tree`, or a chdir by the
# `env`/`sudo` wrapper. Deny beats ask beats pass across segments.
#
# Residuals: subshell scoping is not modelled for `cd`; `$VAR`, `~`, globs
# and braces are not expanded, so an unknown directory under-denies; discards
# through `$( ... )`, backticks, `bash -c` and `eval` are opaque, as are the
# arguments `xargs` feeds a git command (a walked wrapper only when git is
# its direct command); a word holding \036 or \037 mis-splits. Out of scope:
# `-c clean.requireForce=false clean`, `git rm -f <modified>`, `git worktree
# remove --force`, and non-git overwrites (`cp`, `sed -i`, `rm`).
# The recovery texts quote command text in backticks on purpose.
# shellcheck disable=SC2016
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/git-command.sh
. "$(dirname "$0")/lib/git-command.sh"

main() {
  local input command cwd stripped split seg
  input="$(cat)"
  [ "$(jq -r '.tool_name // ""' <<<"$input")" = "Bash" ] || exit 0

  command="$(jq -r '.tool_input.command // ""' <<<"$input")"
  cwd="$(jq -r '.cwd // ""' <<<"$input")"
  [ -n "$cwd" ] || cwd="$PWD"
  # Read by gc_in_trusted_root in the lib.
  # shellcheck disable=SC2034
  gc_cwd="$cwd"

  stripped="$(strip_heredocs "$command")"
  [[ "$stripped" == *git* ]] || exit 0
  [[ "$stripped" =~ (checkout|restore|reset|clean|stash|switch) ]] || exit 0

  effdir="$cwd"
  ask_subs=""
  ask_paths=""
  # Captured rather than read from a process substitution, whose exit status
  # is lost. A failing awk then ends the hook with awk's status: 2 for a
  # syntax error, which blocks the call with awk's stderr as the reason. That
  # fails closed for prefiltered commands only, instead of passing them all.
  split="$(shell_split "$stripped")"
  while IFS= read -r -d $'\036' seg; do
    judge_segment "$seg"
  done <<<"$split"

  [ -n "$ask_paths" ] || exit 0
  emit_ask
}

# Judges one simple command: tracks the effective directory, and for a git
# command emits a deny or records ask paths.
judge_segment() {
  local -a words=() args=()
  local sub d segdir
  IFS=$'\037' read -r -d '' -a words < <(printf '%s' "$1") || true

  git_walk "${words[@]}"
  if (( git_sub_index < 0 )); then
    track_directory "${words[@]}"
    return 0
  fi

  segdir="$effdir"
  for d in ${git_c_dirs[@]+"${git_c_dirs[@]}"}; do
    segdir="$(resolve_dir "$segdir" "$d")"
  done
  (( git_dir_unknown == 0 )) || segdir=""

  sub="${words[git_sub_index]:1}"
  if (( ${#words[@]} > git_sub_index + 1 )); then
    args=("${words[@]:git_sub_index+1}")
  fi

  case "$sub" in
    reset) judge_reset "${args[@]+"${args[@]}"}" ;;
    clean) judge_clean "${args[@]+"${args[@]}"}" ;;
    stash)
      case "${args[0]+${args[0]:1}}" in
        drop | clear) emit_deny "git stash ${args[0]:1}" 'Leave stash entries in place.' ;;
      esac ;;
    checkout | switch | restore)
      git_checkout_parse "$segdir" "$sub" "${args[@]+"${args[@]}"}"
      judge_checkout "$sub" "$segdir" ;;
  esac
}

track_directory() {
  local w cmd_word="${1#?}" n_cd_args=0 target="" flag=""
  case "$cmd_word" in
    pushd | popd) effdir=""; return 0 ;;
    cd) ;;
    *) return 0 ;;
  esac
  [ "${1%"${1#?}"}" = "L" ] || { effdir=""; return 0; }
  shift
  for w in "$@"; do
    case "${w#?}" in
      --) ;;
      -*) if [ "${w#?}" = "-" ]; then
            n_cd_args=$((n_cd_args + 1)); target="-"; flag="${w%"${w#?}"}"
          fi ;;
      *) n_cd_args=$((n_cd_args + 1)); target="${w#?}"; flag="${w%"${w#?}"}" ;;
    esac
  done
  if (( n_cd_args == 1 )) && [ "$flag" = "L" ] && [ "$target" != "-" ]; then
    case "$target" in
      "~"*) effdir="" ;;
      *) effdir="$(resolve_dir "$effdir" "$target")" ;;
    esac
  else
    effdir=""
  fi
}

# Unknown base and a relative operand stay unknown (empty).
resolve_dir() {
  case "$2" in
    "~"*) printf '' ;;
    /*) printf '%s' "$2" ;;
    *) if [ -n "$1" ]; then printf '%s/%s' "$1" "$2"; fi ;;
  esac
}

judge_reset() {
  local w
  for w in "$@"; do
    case "${w:1}" in
      --) return 0 ;;
      --hard | --merge)
        emit_deny "git reset ${w:1}" 'To move HEAD, use `git reset --keep <commit>`; it refuses to overwrite uncommitted edits.' ;;
    esac
  done
}

# Forced: `-f`, `--force` or a short cluster holding f, and no dry run. A
# cluster is read up to `e`, whose value (`-e<pattern>`) is not flags.
judge_clean() {
  local w cluster force=0 dry=0
  for w in "$@"; do
    case "${w:1}" in
      --) break ;;
      --force) force=1 ;;
      --dry-run) dry=1 ;;
      --*) ;;
      -*)
        cluster="${w:2}"
        cluster="${cluster%%e*}"
        case "$cluster" in *f*) force=1 ;; esac
        case "$cluster" in *n*) dry=1 ;; esac ;;
    esac
  done
  if (( force && ! dry )); then
    emit_deny 'git clean -f' 'List candidates with `git clean -n`, then `rm` the files you created, by name.'
  fi
}

judge_checkout() {  # $1 = subcommand, $2 = effective directory
  local p
  case "$gc_mode" in
    discard_switch)
      emit_deny "git $1 -f" 'Restore only files you edited, by name: `git restore -- <file>…`.' ;;
    restore)
      for p in "${gc_paths[@]}"; do
        if is_bulk "$p" "$2"; then
          emit_deny "git $1 -- ${p:1}" 'Restore only files you edited, by name: `git restore -- <file>…`.'
        fi
      done
      case " $ask_subs " in
        *" $1 "*) ;;
        *) ask_subs="${ask_subs:+$ask_subs }$1" ;;
      esac
      for p in "${gc_paths[@]}"; do
        case "$ask_paths" in
          *$'\037'"${p:1}"$'\037'*) ;;
          *) ask_paths="$ask_paths"$'\037'"${p:1}"$'\037' ;;
        esac
      done ;;
  esac
}

# A bulk pathspec: whole-tree spellings, magic, a trailing slash, a glob, or
# a known directory. An X word is bulk only by shape.
is_bulk() {  # $1 = flagged path, $2 = effective directory
  local p="${1:1}" full
  case "$p" in
    . | ./ | .. | :/ | :* | */ | *[\*\?\[]*) return 0 ;;
  esac
  [ "${1:0:1}" = "L" ] && [ -n "$p" ] || return 1
  case "$p" in
    /*) full="$p" ;;
    *) [ -n "$2" ] || return 1; full="$2/$p" ;;
  esac
  [ -d "$full" ]
}

emit_deny() {  # $1 = trigger, $2 = recovery for the agent
  jq -nc --arg r "\`$1\` is refused: it discards uncommitted work." --arg a "$2" \
    --arg s "blocked: worktree-discarding git — $1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r, additionalContext: $a}, systemMessage: $s}'
  exit 0
}

# Only checkout and restore reach here, so ask_subs holds one or both.
emit_ask() {
  local list="${ask_paths#$'\037'}" subject="\`git ${ask_subs% *}\` overwrites"
  list="${list%$'\037'}"
  list="${list//$'\037'$'\037'/, }"
  if [ "$ask_subs" != "${ask_subs% *}" ]; then
    subject="\`git ${ask_subs% *}\` and \`git ${ask_subs#* }\` overwrite"
  fi
  # shellcheck disable=SC2016  # $TMPDIR is literal text for the agent
  jq -nc --arg r "$subject uncommitted edits in: $list." \
    --arg a 'Set a file aside with `cp <file> "$TMPDIR/"` before a probe and copy it back afterwards, instead of restoring it from git.' \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r, additionalContext: $a}}'
  exit 0
}

main
