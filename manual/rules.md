# The rules

Each rule the plugin enforces, the tool call or event its hook matches, what the
hook decides, and the script under `scripts/` that implements it. A **deny**
refuses the call with a message that names the recovery; an **ask** hands the
call to you for approval; a **warn** adds a note for the agent and a one-line
notice for you without stopping anything; a **note** is the notice alone.

| Rule | Matcher | Decision | Script |
| --- | --- | --- | --- |
| Never call `AskUserQuestion` | tool name `AskUserQuestion` | deny (reason + `additionalContext` + `systemMessage`) | `deny-ask-user-question.sh` |
| Other repos stay read-only | `Write\|Edit`, path outside `CLAUDE_PROJECT_DIR`; a `Write` creating a new `.md` exempt, except `CLAUDE.md` and anything under `.claude/` | **ask** | `ask-write-edit-outside-project.sh` |
| Never hand-edit a vendored subtree | `Write\|Edit`, a `plugin-dev` segment at a git tree root (`.git`-adjacent) | deny | `deny-plugin-dev-edit.sh` |
| Never `--no-verify` | `Bash`, regex over `git commit`/`git push` | deny | `deny-no-verify.sh` |
| Never create/switch branches or worktrees | `Bash`, `git` as the command word: `checkout -b/-B/--orphan`, `switch -c/-C/--orphan`, `worktree add`, `stash branch` | **ask** | `ask-branch-worktree-bash.sh` |
| ″ | `EnterWorktree` | **ask** | `ask-enter-worktree.sh` |
| No volatile git state in memory files | `Write\|Edit` on `*.md` under a `memory` segment at a git tree root (`.git`-adjacent), `` `[0-9a-f]{5,40}` `` minus digits/hex-words/frontmatter/UUIDs/`hygiene-ok` lines | deny | `deny-volatile-memory-state.sh` |
| GitHub bodies are not hard-wrapped | `Bash` on `gh pr\|issue create\|comment\|edit\|review` with `--body-file` | deny | `deny-hardwrapped-gh-body.sh` |
| No whole-tree `git add` | `Bash`, `git` as the command word: `add`/`stage` with `-A` (alone or in a cluster), `--all`, `--no-ignore-removal`, `.`, `./`, `:/` or `*`, quoted or bare | deny | `deny-git-add-all.sh` |
| Uncommitted work is not discarded by git | `Bash`, `git` as the command word: `reset --hard\|--merge`, `clean -f` without `-n`, `stash drop\|clear`, a forced `checkout`/`switch` (forced create included), a `checkout`/`restore` of a bulk pathspec (`.`, `..`, `:/`, other `:` magic, a glob, a trailing `/`, a directory) → deny; a `checkout`/`restore` of named files → ask | deny / **ask** | `deny-worktree-discarding-git.sh` |
| Never run sandboxed `git`/`find`/`ls`/`claude -p`/`just release` | `SessionStart`, checks `~/.claude/settings.json` `sandbox.excludedCommands` ⊇ `git *`, `find *`, `ls *`, `claude *`, `just release *` (each also accepted as legacy `cmd:*`) | **warn** (`additionalContext` + `systemMessage`) | `warn-sandbox-excluded-commands.sh` |
| ″ | `Bash` with `dangerouslyDisableSandbox` unset, any subcommand matching a `sandbox.excludedCommands` entry, unless every subcommand matches and the call has none of the shapes the harness keeps sandboxed; quoted text and heredoc bodies skipped, a call with `$( … )`, backticks, `<( … )` or `>( … )` not matched | deny | `deny-sandboxed-excluded-command.sh` |
| A gate's exit status must not be the pipe's | `Bash`, a runner (`just` precommit/prerelease/release/lint/test recipe, `pytest`, `bats`, `run-bats.sh`) at a pipeline start with a pipe after it, run in the background or followed by `&&`/`\|\|`; `pipefail`/`PIPESTATUS` and probe flags pass | deny | `deny-piped-gate-status.sh` |
| ″ | `PostToolUse` on `Bash`, the same runner piped, foreground, output carrying a failure line | **warn** (`additionalContext` + `systemMessage`) | `warn-piped-gate-failure.sh` |
| Edits under a loaded plugin root fail opaquely | `Write\|Edit\|MultiEdit\|NotebookEdit`, target at or below a `CLAUDE_CODE_PLUGIN_DIRS` entry or a `--plugin-dir[-no-mcp]` of the first `claude` ancestor | deny in `auto`/`dontAsk`; **note** (`systemMessage` only) in `default`/`acceptEdits` or with no mode | `deny-plugin-root-edit.sh` |
