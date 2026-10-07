# shellcheck shell=bash
# Shared git command-line walk, sourced by the hook scripts that need to
# find a git subcommand behind its global options. Sources shell-text.sh so
# a caller that walks git also has the heredoc stripper.
#
# git_walk <word>... walks one command segment's words. Each word is passed
# flagged: its first byte is `L` (literal, known text) or `X` (value
# unknown, e.g. an expansion); comparisons use the word without that byte.
# It finds the first word equal to `git` (anywhere in the segment, so
# env assignments, `sudo` or a redirection before it are skipped), then
# skips git's global options: `-C`, `-c`, `--git-dir`, `--work-tree`,
# `--namespace` and `--config-env` consume the next word, any other `-*`
# word is skipped, and the `--opt=value` spellings are single words. It
# sets these globals:
#   git_sub_index    index, in the argument list, of the subcommand word;
#                    -1 when there is no `git` or no subcommand
#   git_c_dirs       array of the `-C` operands in order, flag stripped
#   git_dir_unknown  1 when a `-C` operand is X-flagged or `--git-dir` /
#                    `--work-tree` appears in either spelling
#                    (`--git-dir=...` included); else 0

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

  while (( i < count )) && [ "${words[i]:1}" != "git" ]; do i=$((i + 1)); done
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
