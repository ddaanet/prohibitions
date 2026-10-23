# shellcheck shell=bash
# Shared git command-line walk, sourced by the hook scripts that need to
# find a git subcommand behind its global options. Sources shell-text.sh so
# a caller that walks git also has the heredoc stripper.
#
# git_walk <word>... walks one command segment's words. Each word is passed
# flagged: its first byte is `L` (literal, known text) or `X` (value
# unknown, e.g. an expansion); comparisons use the word without that byte.
# `git` must be the command word: the first word after `VAR=value` words,
# the reserved words `!` `{` `if` `then` `else` `elif` `do` `while` `until`,
# and the wrappers `env`, `time`, `nice`, `command`, `exec`, `nohup`,
# `sudo`, `doas`, `xargs`, `setsid`, `stdbuf`, `ionice` and `timeout <dur>`
# (with their own options, per the arity table in
# `wrapper_option_takes_value`), so `echo git add -A` is not a git command.
# A command word counts as `git` when it is `git` or ends in `/git`
# (`/usr/bin/git`, `./git`); `\git` is the callers' to unescape. Other
# wrappers (`busybox`, `watch`, `chronic`, `eval`, `bash -c`) are opaque.
# It then skips git's global options: `-C`, `-c`, `--git-dir`,
# `--work-tree`, `--namespace` and `--config-env` consume the next word,
# any other `-*` word is skipped, and the `--opt=value` spellings are
# single words. It sets these globals:
#   git_sub_index    index, in the argument list, of the subcommand word;
#                    -1 when there is no `git` or no subcommand
#   git_c_dirs       array of the `-C` operands in order, flag stripped
#   git_dir_unknown  1 when a `-C` operand is X-flagged, `--git-dir` /
#                    `--work-tree` appears in either spelling
#                    (`--git-dir=...` included), or `env -C`/`--chdir` or
#                    `sudo -D`/`--chdir` moves the command; else 0
#
# git_checkout_parse <effdir> <sub> <word>... classifies a checkout, switch
# or restore. <effdir> is the directory the command runs in, empty when
# unknown; <word>... are the flagged words after the subcommand. It sets:
#   gc_mode   create | switch | discard_switch | restore | none
#   gc_paths  array of the pathspec words, each keeping its flag
# This is the one branch-vs-path rule, shared by every hook that asks
# whether `git checkout <x>` names a branch.
# `checkout -b/-B/--orphan` is `create`, or `discard_switch` with `-f`: a
# forced create resets the worktree (probed on git 2.47.3), so force wins
# in `switch` too. With `--`, the words after it are
# paths (`restore`, or `none` when there are none). Without `--`, the
# operands are the non-option words. None: `switch`. One operand: a path
# candidate is a word that exists under <effdir>, or has a pathspec-magic or
# glob shape (starts with `:`, or holds one of `*?[`); a candidate is a path
# iff it does not resolve as a commit, because a rev wins over a file of the
# same name (probed on git 2.47.3). Two or more operands: when the first is
# a path by that test all are paths, otherwise the first is the tree-ish
# and the rest are paths. `-f` turns `switch` into `discard_switch`. `-` and
# `--detach` mean `switch`. With <effdir> unknown a bare operand is
# `switch`, and an X-flagged operand has no known name to look up, so only
# its shape makes it a candidate. The commit test runs only for a candidate,
# so `git checkout main` spawns nothing.
# The commit test runs `git -C <effdir>` only when <effdir> is inside the
# trusted root (`gc_in_trusted_root`): a PreToolUse hook would otherwise run
# git, before approval, in a repository the unapproved command names.
# git 2.47.3's `rev-parse --verify` was probed not to run `core.fsmonitor` or
# hooks, so this is defence in depth against config-driven execution in other
# git versions. Outside the root there is no subprocess and a candidate is a
# path (fail safe: the hook asks or denies). Residuals: an outside branch
# named like an existing file asks; a repository nested under the root is
# inside it.
# `switch`: `-f`, `--force`, `--discard-changes` give `discard_switch`;
# otherwise `-c`, `-C`, `--orphan` give `create`. `restore`: the worktree
# is touched iff `-W`/`--worktree` appears or `-S`/`--staged` does not;
# untouched, or without paths, the mode is `none`; otherwise `restore` with
# every non-option word a path. `-s`/`--source` take a value. A short
# cluster is read left to right, and a value-taking letter (`b`/`B`,
# `c`/`C`, `s`) ends it: its value is the rest of the cluster, or the next
# word when the letter is last, so `-sHEAD .` keeps `.` a path.
# `--pathspec-from-file`, in either spelling, adds one X path whose text is
# the option itself, e.g. `--pathspec-from-file=list.txt`.

# shellcheck source-path=SCRIPTDIR source=shell-text.sh
. "${BASH_SOURCE[0]%/*}/shell-text.sh"

# The result globals are read by the sourcing script.
# shellcheck disable=SC2034
git_walk() {
  local -a words=("$@")
  local count=${#words[@]} i=0 w
  git_sub_index=-1
  git_c_dirs=()
  git_dir_unknown=0

  while (( i < count )); do
    w="${words[i]:1}"
    # Assignments first: `GIT_EXEC=/usr/bin/git` ends in `/git` too.
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      i=$((i + 1))
      continue
    fi
    [ "$w" = "git" ] || [[ "$w" == */git ]] && break
    case "$w" in
      '!' | '{' | if | then | else | elif | do | while | until) i=$((i + 1)) ;;
      env | time | command | nice | exec | nohup | sudo | doas | xargs | setsid | stdbuf | ionice | timeout)
        i=$((i + 1))
        while (( i < count )); do
          case "${words[i]:1}" in
            -*) ;;
            *) break ;;
          esac
          case "$w ${words[i]:1}" in
            "env -C"* | "env --chdir"* | "sudo -D"* | "sudo --chdir"*) git_dir_unknown=1 ;;
          esac
          if wrapper_option_takes_value "$w" "${words[i]:1}"; then
            i=$((i + 2))
          else
            i=$((i + 1))
          fi
        done
        [ "$w" = "timeout" ] && i=$((i + 1)) ;;
      *) return 0 ;;
    esac
  done
  (( i < count )) || return 0
  i=$((i + 1))

  while (( i < count )); do
    w="${words[i]:1}"
    case "$w" in
      -C)
        if (( i + 1 < count )); then
          git_c_dirs+=("${words[i + 1]:1}")
          [ "${words[i + 1]:0:1}" = "X" ] && git_dir_unknown=1
        fi
        i=$((i + 2)) ;;
      --git-dir | --work-tree)
        git_dir_unknown=1
        i=$((i + 2)) ;;
      -c | --namespace | --config-env) i=$((i + 2)) ;;
      --git-dir=* | --work-tree=*) git_dir_unknown=1; i=$((i + 1)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  (( i < count )) || return 0
  git_sub_index=$i
}

# wrapper_option_takes_value <wrapper> <option>: the option's value is the
# next word.
wrapper_option_takes_value() {
  case "$1" in
    env) case "$2" in -u | -C | -S | --unset | --chdir | --split-string) return 0 ;; esac ;;
    nice) case "$2" in -n | --adjustment) return 0 ;; esac ;;
    timeout) case "$2" in -k | -s | --kill-after | --signal) return 0 ;; esac ;;
    time) case "$2" in -f | -o | --format | --output) return 0 ;; esac ;;
    exec) case "$2" in -a) return 0 ;; esac ;;
    sudo) case "$2" in -u | -g | -C | -D | -p | -r | -t | -T | -U | -R) return 0 ;; esac ;;
    doas) case "$2" in -u | -C) return 0 ;; esac ;;
    xargs)
      case "$2" in
        -I | -n | -L | -P | -s | -d | -E | -a | -J | -R | -S) return 0 ;;
        --arg-file | --delimiter | --eof | --max-args | --max-chars | --max-lines | --max-procs | --process-slot-var) return 0 ;;
      esac ;;
    stdbuf) case "$2" in -i | -o | -e | --input | --output | --error) return 0 ;; esac ;;
    ionice) case "$2" in -c | -n | -p | -P | -u | --class | --classdata | --pid | --pgid | --uid) return 0 ;; esac ;;
  esac
  return 1
}

# The result globals are read by the sourcing script.
# shellcheck disable=SC2034
git_checkout_parse() {
  local effdir="$1" sub="$2"
  shift 2
  local -a args=("$@") operands=() after=()
  local count=${#args[@]} i=0 w dd=0 create=0 force=0 detach=0 pfile=""
  local wt=0 st=0 cluster c
  gc_mode=none
  gc_paths=()

  while (( i < count )); do
    w="${args[i]:1}"
    if (( dd )); then
      after+=("${args[i]}")
    else
      case "$w" in
        --) dd=1 ;;
        --orphan | --create | --force-create) create=1; i=$((i + 1)) ;;
        --orphan=* | --create=* | --force-create=*) create=1 ;;
        --force | --discard-changes) force=1 ;;
        --detach) detach=1 ;;
        --worktree) wt=1 ;;
        --staged) st=1 ;;
        --pathspec-from-file=*) pfile="$w" ;;
        --pathspec-from-file)
          if (( i + 1 < count )); then pfile="$w=${args[i + 1]:1}"; fi
          i=$((i + 1)) ;;
        --source | --conflict | --unified | --inter-hunk-context) i=$((i + 1)) ;;
        --*) ;;
        -?*)
          # Left to right; a value-taking letter ends the cluster, its value
          # being the rest of it or, when the letter is last, the next word.
          cluster="${w#-}"
          while [ -n "$cluster" ]; do
            c="${cluster:0:1}"
            cluster="${cluster:1}"
            case "$c" in
              f) force=1 ;;
              d) detach=1 ;;
              W) wt=1 ;;
              S) st=1 ;;
            esac
            case "$sub:$c" in
              checkout:[bB] | switch:[cC]) create=1 ;;
              restore:s) ;;
              *) continue ;;
            esac
            [ -n "$cluster" ] || i=$((i + 1))
            break
          done ;;
        *) operands+=("${args[i]}") ;;
      esac
    fi
    i=$((i + 1))
  done

  case "$sub" in
    restore)
      if (( wt == 0 && st == 1 )); then return 0; fi
      gc_paths=(${operands[@]+"${operands[@]}"} ${after[@]+"${after[@]}"})
      [ -z "$pfile" ] || gc_paths+=("X$pfile")
      (( ${#gc_paths[@]} > 0 )) && gc_mode=restore
      return 0 ;;
    switch)
      if (( force )); then gc_mode=discard_switch
      elif (( create )); then gc_mode=create
      else gc_mode=switch; fi
      return 0 ;;
  esac

  # A forced create still resets the worktree: force wins.
  if (( create )); then
    gc_mode=create
    if (( force )); then gc_mode=discard_switch; fi
    return 0
  fi
  if (( dd )) || [ -n "$pfile" ]; then
    # Operands before `--` are the tree-ish, not paths.
    gc_paths=(${after[@]+"${after[@]}"})
    [ -z "$pfile" ] || gc_paths+=("X$pfile")
    (( ${#gc_paths[@]} > 0 )) && gc_mode=restore
    return 0
  fi

  gc_mode=switch
  (( force )) && gc_mode=discard_switch
  (( detach )) && return 0
  case ${#operands[@]} in
    0) ;;
    1)
      if [ "${operands[0]:1}" != "-" ] && gc_is_path "$effdir" "${operands[0]}"; then
        gc_paths=("${operands[0]}")
        gc_mode=restore
      fi ;;
    *)
      if gc_is_path "$effdir" "${operands[0]}"; then
        gc_paths=("${operands[@]}")
      else
        gc_paths=("${operands[@]:1}")
      fi
      gc_mode=restore ;;
  esac
}

# gc_is_path <effdir> <flagged word>: a path candidate (exists under effdir,
# or has a pathspec-magic or glob shape) that does not resolve as a commit.
gc_is_path() {
  local effdir="$1" w="${2:1}" candidate=0
  [ -n "$effdir" ] || return 1
  case "$w" in
    :* | *[\*\?\[]*) candidate=1 ;;
  esac
  if (( candidate == 0 )) && [ "${2:0:1}" = "L" ]; then
    case "$w" in
      /*) [ -e "$w" ] && candidate=1 ;;
      *) [ -e "$effdir/$w" ] && candidate=1 ;;
    esac
  fi
  (( candidate )) || return 1
  gc_in_trusted_root "$effdir" || return 0
  # The failure is the mechanism: a word that is not a commit is a path.
  # stderr is dropped because --quiet does not silence the `fatal: not a git
  # repository` an effdir outside any repo prints; that case is "not a commit".
  # The system config, fsmonitor and hooks are switched off as defence in
  # depth: the command naming this directory is not approved yet.
  ! GIT_CONFIG_NOSYSTEM=1 git -c core.fsmonitor=false \
    -c core.hooksPath=/dev/null -C "$effdir" \
    rev-parse --verify --quiet "$w^{commit}" >/dev/null 2>&1
}

# gc_in_trusted_root <dir>: <dir> is the trusted root or under it, compared
# as physical paths with a path-boundary test. The root is CLAUDE_PROJECT_DIR
# when set and non-empty, else gc_cwd (the payload cwd, set by the hook
# before parsing), else the process's own directory. A directory that does
# not resolve is outside.
gc_in_trusted_root() {
  local dir root
  root="${CLAUDE_PROJECT_DIR:-${gc_cwd:-$PWD}}"
  # A directory that does not resolve counts as outside; cd's complaint
  # about it is that expected outcome, so it is dropped.
  dir="$(cd -P -- "$1" 2>/dev/null && pwd -P)" || return 1
  root="$(cd -P -- "$root" 2>/dev/null && pwd -P)" || return 1
  [ "$dir" = "$root" ] && return 0
  case "$dir" in
    "${root%/}"/*) return 0 ;;
  esac
  return 1
}
