# prohibitions — Design

Living design document. Updated when meaningful design decisions land
or get overturned. Not a changelog of features — a record of *why this
project has the shape it has*.

## Motivation

ddaanet behavioural rules — "never call `AskUserQuestion`", "never
`--no-verify`", "GitHub bodies are not hard-wrapped", and others — live
as always-on prose in `shared-claude.md`, the tier every ddaanet repo's
`CLAUDE.md` imports. Every line there is paid by every session in every
one of those repos, whether or not the situation it addresses ever
arises.

A subset of those rules has a clean mechanical detection: a specific
tool call, a specific command shape, a specific setting. For that
subset, a hook that acts at the moment of action — `PreToolUse` except
where noted — is paid only when the situation arises, and its denial
message teaches more reliably than remembered prose.

Roughly two thirds of `shared-claude.md` is judgement with no
mechanical trigger and stays prose — this plugin does not aim to
replace the whole file, only the rules with a clean detection. Full
scoping rationale: `plans/brief-prohibitions-plugin-bootstrap.md`.

The same economics hold for a workflow or harness hazard that no
`shared-claude.md` rule names, when its failure is silent and its
trigger mechanical: a gate piped into `tail` reports `tail`'s exit
status, a `git checkout -- <file>` issued to undo a probe discards
every uncommitted edit that file held, whoever made it, and an edit
under a directory the session loads as a plugin fails in auto mode with
no reason the agent can act on. Prose there would be a new always-on
line rather than a converted one, so such a hazard gets a hook directly
or nothing.

## Requirements

### Functional

- One hook per rule in scope — `PreToolUse` except where noted —
  denying, asking or warning per the rule's own contract (see
  Architecture below for the current set).
- Each hook carries the recovery detail the prose it replaces used to
  carry — e.g. the `--no-verify` block names the stale-push-hook
  recovery (`(cd <repo> && claude -p ping)`), not just "no." Where that
  detail is instruction rather than verdict it rides
  `additionalContext`, which reaches the agent without rendering.
- `ask` decisions use the `PreToolUse` permission-decision output, never
  a bare `exit 2` — `exit 2` is deny-only and cannot produce an `ask`.

### Non-functional

- **Every guard is verified against a real command expecting ALLOW**,
  not just the commands it should block. The branching and
  `--no-verify` matchers over-match most easily: `git checkout <file>`,
  `git branch` with no argument, and `gh pr create` bodies that
  legitimately contain newlines are all real traffic a naive matcher
  would catch. `git checkout <file>` must pass the branch guard; the
  worktree-discard guard asks on it, since it overwrites that file's
  uncommitted edits.
- **Mechanical, not a shell parser.** Detection is regex/word-boundary
  matching over the command string, or a word walk over `shell_split`'s
  quote-aware split. Heredoc bodies and quoted text are kept out of the
  match, so prose mentioning a trigger word doesn't fire the guard. It
  is not a full shell grammar: expansions are not performed, and
  `$( … )`, `bash -c` and `eval` stay opaque.
- **POSIX and bash 3.2, so the hooks run on macOS as well as Linux.**
  These scripts run wherever Claude Code runs, and the plugin is
  installed from a marketplace rather than built per machine, so a
  GNU-only construct is a defect even when every machine in sight is a
  Linux one. Two contracts, both enforced by
  `tests/portability-test.sh`:

  - **Utilities are POSIX; GNU extensions are out.** No `realpath`
    or `readlink` with any option (BSD realpath has no `-m`, macOS
    before 12.3 ships no realpath at all, and `readlink -f`, `-e` and
    `-m` are GNU-only — `scripts/lib/path.sh` carries a portable
    `abspath()` built from `cd -P` and `pwd`; a bare `readlink`, one
    link at a time, exists on both), no
    `\b` in an ERE, no `sed -i` without a suffix, no `grep -P`, `date
    -d`, `stat -c`, `find -printf` or `timeout`. `jq`, `awk`, `sed -E`
    and `tr` are fair game in their POSIX subsets; awk interval
    expressions (`{n,m}`) are not, which is why the volatile-state
    matcher tests token length rather than writing the interval.
  - **`#!/usr/bin/env bash` means bash 3.2**, the version Apple has
    shipped since 2007: no associative arrays, `mapfile`, `${var,,}`,
    `wait -n`, or `inherit_errexit`.

  `\b` deserves the specific note, because it is the reason this is a
  requirement and not a preference. A GNU-only *flag* dies loudly with
  `illegal option`; `\b` has no POSIX ERE equivalent, so BSD grep does
  not reject it — the match simply stops firing, and a guard that
  silently stops guarding looks exactly like a guard with nothing to
  do. Boundaries are spelled `(^|[^A-Za-z0-9_])` and
  `([^A-Za-z0-9_]|$)` throughout.
- **`shared-claude.md` itself is untouched by this plugin.** Trimming
  its prose once a hook exists is a separate, later change — deleting a
  rule from the tier before its hook is installed and verified in every
  consuming repo would leave that repo unguarded with no visible
  symptom. The pairing check that enforces this belongs in gitlore's
  `SessionStart`, not here — this repo and the tier's mounting are
  installed independently, with nothing coupling them.

## Architecture

- **`.claude-plugin/plugin.json`** — the plugin manifest. Its
  `.version` reflects the *last released* version; a `PreToolUse` hook
  from the vendored toolkit (`plugin-dev/version-guard.sh`) refuses
  direct edits to it, so only `just release` can bump it.
- **`hooks/hooks.json`** — wires twelve rules to fifteen scripts
  (branch/worktree creation needs two scripts to cover both its `Bash` and
  `EnterWorktree` matchers, the sandbox rule two — a
  `SessionStart` check and a `Bash` deny — and the piped-gate rule two,
  a `PreToolUse` deny and a `PostToolUse` warning):

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

- **`scripts/*.sh` + `tests/*-test.sh`** — one script per hook, one
  end-to-end test per script, driven by synthetic hook JSON payloads
  through `jq`. `scripts/lib/` holds helpers shared between hooks,
  sourced rather than run: command-text parsing for the `Bash` guards,
  path resolution for the edit guards. `just precommit` runs
  `shellcheck`, `bash -n`, and every `tests/*-test.sh`. One test is not
  paired with a hook:
  `tests/portability-test.sh` is a static scan of every script and
  test for the GNU-only constructs the platform contract above rules
  out, since a suite that only ever runs on Linux is green on those by
  construction. A line that names a banned construct on purpose opts
  out with a trailing `# portability-ok`.
- **`plugin-dev/`** — the `claude-plugin-dev` release toolkit, vendored
  via `git subtree`, pinned to a tag. Read-only; see its own
  `docs/design.md` for why.
- **`plans/`** — prospective content: the bootstrap brief and any
  future implementation plans.
- **`docs/`** — this file and its changelog: what the project *is*, now.
- **`memory/`** — the `ddaanet` shared memory tier, mounted as a
  submodule via gitlore. Includes `shared-claude.md`, the prose this
  plugin's hooks are converting rule-by-rule.

## Design decisions

### Ask, not deny, for branch/worktree creation and off-project edits

The branch/worktree and off-project rules cannot be `deny`: merging onto
a base my human partner named is executing their instruction, not
originating a branch switch, and filing a brief in another repo is
legitimate — only *edits* there are forbidden. A hook that denies
either blocks legitimate work, so both use the `ask` permission
decision instead.

### Off-project note drops pass without asking

The prose draws its own line: other repos are never *edited in place*,
but "dropping a note or brief in that repo is permitted". The hook
originally asked on every out-of-project `Write`/`Edit`, so the
permitted case — the typical one — paid a confirmation prompt every
time. It now passes a `Write` whose target does not yet exist and ends
in `.md` (excluding `CLAUDE.md` and anything under `.claude/`, the two
`.md` locations that change behaviour); `Edit`, `Write` over an
existing file, and new non-`.md` files still ask.

The alternative was dropping the hook and relying on the sandbox plus
the auto-mode classifier. The sandbox does cover Bash-path writes (its
write allowlist is the working directory plus scratch), but `Write`/
`Edit` are not sandboxed, and probing showed the classifier allows an
unprompted `Edit` of a pre-existing file in a sibling repo — with no
rule, with the prose in `CLAUDE.md`, and with a custom
`autoMode.soft_deny` naming exactly that case. It reads a one-line edit
as task-serving and non-destructive; "being right does not authorize
it" is not a safety property it scores. In `default` and `acceptEdits`
modes Claude Code already prompts for out-of-cwd edits, so the hook's
value is confined to `auto` and `bypassPermissions` — which is exactly
where its `ask` is the only prompt the user sees. A hook `ask` always
prompts the user, never the classifier, so narrowing the trigger was
the only way to remove the prompt from the permitted case.

### Strip quoted and heredoc regions before matching

A commit message that *mentions* `--no-verify`, `checkout -b` or `git
add -A` in prose must not trigger the hook that refuses it. A heredoc
body (`<<'EOF' … EOF`) isn't wrapped in quote characters at all, and
this project's own commit-message convention uses heredocs for
multi-line messages — so a real commit documenting these hooks (e.g.
"Document that `--no-verify` is refused by the new hook")
false-triggered `deny-no-verify.sh` and `ask-branch-worktree-bash.sh`,
including a hard **deny** blocking a safe commit. Every script that
reads command text, except `deny-hardwrapped-gh-body.sh`, therefore
strips heredoc bodies first (`strip_heredocs`,
`scripts/lib/shell-text.sh`: the opener, its optional `-` tab-stripping
mode, and its terminator line).

What follows differs by script. `deny-no-verify.sh` and the piped-gate
detector (`scripts/lib/piped-gate.sh`) delete `'...'`/`"..."` spans and
match what is left; `deny-sandboxed-excluded-command.sh` drops quoted
text in its own scan. The three git-walking hooks —
`deny-git-add-all.sh`, `deny-worktree-discarding-git.sh` and
`ask-branch-worktree-bash.sh` — split the text quote-aware with
`shell_split` instead and walk the words, so a quoted argument stays an
argument while prose inside a `-m` message is one word that is never a
command word.

### Check every `--body-file` match, not just the first

`deny-hardwrapped-gh-body.sh` originally extracted the `--body-file`
argument with `grep -Eom1` (first match only). A compound command
chaining two `gh` body-posting calls — e.g. creating a linked issue
then a PR — only had its first file linted; a hard-wrapped second file
silently passed the gate. The extraction now walks every
`--body-file` match in the command and denies on the first violation
found among them.

### Deny, not ask, for whole-tree `git add`

Across 45 days of transcripts, 77% of `git add` segments already named
their paths and only 0.4% used `-u`, so the disciplined form is the
norm and the remedy for the other 23% is purely mechanical: name the
paths. An `ask` would therefore be pure latency — the correct answer to
the prompt is always the same — so this rule denies. `git add -u` stays
allowed: it is bounded to already-tracked files and cannot stage
something the author never told git about, which is the whole failure
mode. The deny does not *offer* it, though: `-u` stages every tracked
edit, a half-finished sibling included, so a redirect naming it would
recommend the very spill the refusal exists to stop. The redirect is to
name the paths, on `additionalContext` per "A deny splits three ways by
audience". `-A` with a pathspec (`git add -A src/`) is still denied and
nothing is lost by that: since git 2.0 a plain `git add <pathspec>`
already behaves as `-A` within that pathspec, so the flag is redundant
wherever it is safe.

Detection walks words rather than pattern-matching the raw string: the
command is split quote-aware by `shell_split`, `git_walk` finds `git`
as the command word and skips its global options, the subcommand must
be exactly `add` or `stage`, and then a whole-tree word is looked for
among the rest. That is what keeps `git add-something -A`, `git log --
.`, `git diff .` and `echo git add -A` passing. Because quotes are
removed the way the shell removes them, a quoted pathspec or flag is
the same word as its bare spelling — `git add '*'`, `git add "."` and
`git add "-A"` are all denied — so any spelling the rule denies bare,
it denies quoted. Deleting quoted spans, as `deny-no-verify.sh` does,
would delete the very argument this rule exists to catch, and a list
of quoted spellings to unwrap first can only trail the bare ones. A
word whose value is unknown never denies: `"$f"`, and also `-A"$x"`,
where a whole-tree token is joined to an expansion. That under-denies,
the safe direction; the value is not available before the command
runs.

### Deny bulk discards, ask per-file restores

`deny-worktree-discarding-git.sh` guards a workflow hazard, not a
converted prose rule: git can discard uncommitted edits with no record
to recover them from. The bulk forms in the matcher table are denied.
`reset --merge` is among them because it reverts a staged-only change
and the transcript corpus held no use of it; a glob or `:`-magic
pathspec, because it is often narrow but never names its files, and
the redirect is to name them. A restore of named files asks instead:
it is often right, and only the edits' owner knows. A clean path is not
exempt, since a restore runs because the path is dirty.

**What the ask does**, read from the CC 2.1.292 bundle, with the
deciding code present in 2.1.284 and 2.1.290 under renamed
identifiers. A hook `ask` reaches `canUseTool` as a forced decision, so
the permission engine and the auto-mode classifier never see it; the
main session, a foreground subagent and a background subagent under an
interactive parent get the dialog. Where nobody can answer it becomes
a deny. Probed on 2.1.292 with a scratch `--settings` hook asking on
`git checkout -- f.txt` under `claude -p`: the reason came back as an
`is_error` `tool_result`, `additionalContext` arrived, and the file was
untouched. When a deny rule, an ask rule or a safety check also
applies — `dangerouslyDisableSandbox` is the common case — the call
takes the engine's floor path instead, where a classifier allow
re-surfaces as the ask and a context that avoids prompts denies. No
traced path turns an `ask` into an allow; its cost is prompt volume,
up to 436 per-file restores in the corpus. The reason is the human's
dialog text and, headless, the agent's `tool_result`, so it names the
paths and holds no imperative; the ask carries no `systemMessage`,
since the dialog is the human's channel.

**Branch or path.** `git checkout <x>` without `--` is ambiguous, and
`git_checkout_parse` (`scripts/lib/git-command.sh`) is the one rule
that decides it. A word is a path candidate when it exists under the
effective directory or has a `:`-magic or glob shape, which is what
lets `git checkout :/` deny. A candidate is a path only if it does not
resolve as a commit, because the rev wins: probed on git 2.47.3, branch
`foo` plus a dirty file `foo` switched branch carrying the edit, and
tag `t` plus file `t` detached HEAD. The test is `git rev-parse
--verify --quiet`, run only for a candidate, so `git checkout main`
spawns nothing. It is the only `git` subprocess in these hooks, kept
because the subprocess-free test, "exists on disk means path",
false-denies `git checkout docs` where branch `docs` and directory
`docs/` both exist. Force beats create: probed on git 2.47.3,
`checkout -f -b x`, `checkout -B x -f` and `switch -f -c x <start>`
each discarded a dirty edit, so they are denied; a bare `switch -f -c
x` keeps it and is denied anyway, an accepted over-deny. The parser
also tells `git checkout main` from `git checkout <file>`, which makes
"never switch unprompted" detectable; no hook asks on a plain switch,
a separate call with prompt volume to weigh.

**Effective directory.** Path tests run where the command will: the
payload `cwd`, moved by each `cd <literal>` in segment order and by
git's `-C` operands. Any other `cd`, `pushd` or `popd`, an expanded
`-C` operand, `--git-dir`/`--work-tree`, or a chdir by `env -C` or
`sudo -D` makes it unknown. Then a bare one-operand checkout counts as
a switch and a pathspec is bulk by its shape alone: the hook
under-denies rather than guesses.

**Words, not text.** The command is split quote-aware by `shell_split`
(`scripts/lib/shell-text.sh`), one POSIX awk program, so a quoted
pathspec is a word, a redirection is dropped with its target, and a
100 KB command stays fast — appends are buffered, so the split is
linear in practice. `git` must be the command word, by basename
(`/usr/bin/git` counts), reached past assignments, the shell's reserved
words and the wrappers `git_walk` lists (`sudo`, `env`, `xargs`,
`timeout <dur>` and kin, each with its own option arity), so `echo git
checkout -- .` passes, here and in `deny-git-add-all.sh`, which shares
the split and the walk. Against matching `git` anywhere in a segment,
the command-word rule gives up a `git` behind an unlisted wrapper
(`busybox`, `watch`, `chronic`, `eval`) or reserved word (`function f {
git …; }`); `echo git add -A` passing is the point of it.

**Trusted root for the commit test.** The `rev-parse` runs before the
command is approved, in a directory the command names. It runs only
when that directory is inside `CLAUDE_PROJECT_DIR` (else the payload
`cwd`), compared as physical paths. Outside it no `git` is spawned and
an existing or pathspec-shaped operand is taken as a path, so the hook
asks or denies rather than passes. On git 2.47.3 `rev-parse --verify`
was probed not to run `core.fsmonitor` or hooks from a hostile
repository's config; the root check is defence in depth against other
versions, and so is running it with `GIT_CONFIG_NOSYSTEM=1`, `-c
core.fsmonitor=false` and `-c core.hooksPath=/dev/null`, inside the
root too. Residuals: outside the root, a branch named like an existing
file asks; the root is a directory, not a repository, so a repository
nested under it, such as one cloned there, is inside.

Residuals: subshell scoping of `cd` is not modelled; `$VAR`, `~`, globs
and braces are not expanded; discards through `$( … )`, backticks,
`bash -c` and `eval` are opaque, as is anything `xargs` feeds a `git`
command; a word holding `\036` or `\037`, `shell_split`'s separators,
mis-splits. Out of scope: `-c clean.requireForce=false clean`, `git rm
-f` on a modified file, `git worktree remove --force`, and non-git
overwrites (`cp`, `sed -i`, `rm`). Any `shared-claude.md` line for this
hazard is proposed to the tier's own repo, never edited from here.

### Abbreviated shas, with a closed exclusion list

The volatile-state hook shipped scoped to full 40-hex shas, justified in
its header by the claim that abbreviated hex would false-positive on
ordinary prose. Measured, that claim is wrong in both directions: over a
real 165-file memory store the 40-hex pattern had *zero* true positives
available to it — the store contains no full shas at all — while missing
four abbreviated commit ids that are live violations of the rule.
The dictionary surface the narrow scope was protecting against is a
closed set: words spellable in `a`–`f` alone number 47 at length ≥ 5, and
`\b[a-f]{7,40}\b` returns nothing at all over the corpus. So the matcher
is now `\b[0-9a-f]{5,40}\b` — five being git's floor for a usable
abbreviation — with five exclusions: an all-digit run (file modes,
byte budgets, token counts), the 47-word hex list, the YAML frontmatter
block, UUIDs, and any line carrying `<!-- hygiene-ok`. On that corpus the
composed rule yields 4 hits, 4 true positives, 0 false positives. The
residual is stated rather than implied: a sha split across a line break
or abbreviated below five characters passes, and so does the ~4% of
seven-character shas that happen to be all digits — `(10/16)**7`.

Lowercase only, because git never emits an uppercase sha while `FDA` and
`EBCDIC` are ordinary acronyms; the old `[0-9a-fA-F]` bought nothing and
cost precision. Content is read raw, no code-span or fence stripping,
because every real hit in the corpus sat inside backticks — a sha's
natural habitat in prose — so a code-stripped scan finds none of them.
The rule deliberately mirrors gitlore's `check-memory-hygiene.py`
`volatile-state` check, matcher and word list and suppression marker
alike, so the write-time gate here and the commit-time gate there agree
on what a violation is. One divergence is intentional: this hook also
blanks UUIDs inside the body, not just inside frontmatter, because an
`Edit.new_string` fragment carrying `originSessionId:` arrives with no
frontmatter boundary to detect — gitlore always sees the whole file and
does not need it.

A second divergence is deliberate: a frontmatter fence is an exact `---`
line here, where gitlore `strip()`s before comparing. Matching exactly
costs one case — a `--- ` closer never closes, so the blanking runs to
EOF and a sha in the body goes unreported — and buys the symmetric one,
where a `--- ` line does not open a block whose contents would then be
blanked away. The under-report is the cheaper failure: gitlore's
commit-time gate still catches it, while a spurious open silently
disarms the hook over a whole file. Both directions are asserted in
`tests/deny-volatile-memory-state-test.sh`.

### A SessionStart check for sandbox exclusions

The prohibition is "never run sandboxed `git`, `find`, `ls`, `claude
-p` or `just release`": sandboxed, the first three see phantom dotfiles
— user-home dotfiles bind-mounted to `/dev/null` show up as untracked
character devices — and a sandboxed `claude -p` silently drops every
SessionStart hook. The harness's own `sandbox.excludedCommands` runs
those commands unsandboxed, while the auto-mode classifier still vets
them for danger, so the first half of the rule is checking that setting
is present, once, at session start, and saying what is missing. This
replaces the retired `unsandbox-git-status` plugin. The setting covers
only part of the traffic, so a `PreToolUse` deny backs it (next
section).

The exclusion is `git *`, not `git status`-shaped patterns. Mutating
git commands must run unsandboxed to succeed at all; the
dotfile-sensitive reads (`status`, `add`, `ls-files`) must run
unsandboxed to be *truthful*; and the remaining harmless git commands
pay only an unnecessary auto-classifier call. That is the price of a
prefix exclusion, and it buys coverage of every subcommand and argument
an enumerated list would miss — though not of `git -C X status`, which
the harness keeps sandboxed whatever the entry (next section).

`just release` is on the list for a different reason, and it does not
inherit the `git *` entry. A recipe body is invisible to the harness,
which matches `excludedCommands` statically against the segments of the
Bash call — so `git *` never reaches the `git push` and `gh` calls
`release.sh` makes *inside* the recipe, and the release path needs its
own top-level entry. The pattern is `just release *`, space included,
not `just *`: unsandboxing every recipe in every repo is far more than
the prohibition asks for, and the same prefix-over-enumeration argument
above covers the bump arguments (`just release minor`) for free.
Verified empirically rather than assumed, since a two-word prefix is not
obviously parseable: two recipes with identical bodies writing outside
the sandbox's write allowlist, `just probe` refused with a read-only
filesystem error and `just release` succeeded, with `$TMPDIR` expanding
empty on the unsandboxed run.

Each pattern counts in either spelling. The documented form is `cmd *`
— a trailing ` *` makes the arguments optional, so `git *` also matches
a bare `git` — and the legacy `cmd:*` is still parsed as the same prefix
(Claude Code permissions docs; bundle parser, CC 2.1.289). Accepting
both keeps a settings file written before the docs changed from warning
spuriously; a missing pattern is named in the documented form.

The exclusion reaches far less than this section originally assumed.
Since CC 2.1.277 *every* segment of a Bash call must match an entry —
before, one matching segment unsandboxed the whole call, which the
changelog calls a bug — so `git log | head` stays sandboxed. A `cd`
anywhere in the call, a redirection to a file, a subshell or command
substitution, a non-allowlisted `VAR=` prefix, and (#95455, open)
git's value-taking global options `-C`, `-c`, `--git-dir`,
`--work-tree` all keep the call sandboxed too. Observed on 2.1.289:
`ls -la <path>` ran unsandboxed, while `ls -la <dir> | head`, `cd <dir>
&& ls -la .bashrc` and `git -C <dir> status` ran sandboxed and showed
phantom dotfiles. The setting is necessary but no longer sufficient.

Silence is the pass signal, so the failure paths are loud: an
unparseable `settings.json` warns instead of passing, because a check
that could not run must not look like one that ran clean. The warning
reaches both channels — `additionalContext` tells the agent to pass
`dangerouslyDisableSandbox` until the setting is fixed, `systemMessage`
tells the human who owns the file, naming only the patterns actually
missing. Residual: only the user-level `~/.claude/settings.json` is
read; project or managed settings that set the same key are not
consulted.

### Deny any sandboxed excluded command

`deny-sandboxed-excluded-command.sh` denies a `Bash` call that leaves
`dangerouslyDisableSandbox` unset when *any* of its subcommands matches
an entry of `sandbox.excludedCommands`. The entries name the commands
that misbehave sandboxed, and they misbehave wherever they sit in the
call: `git commit | tail` still cannot write, `git status | sort` and
`ls | head` still list phantom dotfiles. The harness excludes a call only
when every subcommand matches and none of its refused shapes is present,
so such calls run sandboxed with nothing to say so. Re-issued with the
flag, the whole call leaves the sandbox and goes through the full
permission checks, which is the correct outcome; the hook makes the
failure early and explicit instead of silent.

A call the harness already excludes passes — a bare `git status`, `ls a
&& ls b`, `git log | ls`. My human partner asked for this: denying them
cost a refused call and a re-issue on the commonest commands. The hook
cannot read the harness's decision: in the 2.1.289 bundle the PreToolUse
payload's `dangerouslyDisableSandbox` is only the model's flag, and the
exclusion is computed after the hook runs. So it recomputes the decision,
leaning the other way from the harness: the call passes only when every
non-empty subcommand matches an entry *and* none of these shapes is
present.

- unquoted `<` or `>`, including `2>&1` and a heredoc's `<<` — `2>&1` was
  observed sandboxed although the docs exempt fd duplication;
- a `$` outside single quotes — unquoted `$HOME` observed sandboxed,
  double-quoted untested;
- unquoted glob characters `*`, `?`, `[` (a glob observed sandboxed), and
  tilde or brace expansion by analogy, untested;
- `(`, `)`, or a lone `&` (`&&` is fine);
- a backslash-newline continuation;
- any leading `VAR=` assignment — `LANG=C` was observed excluded, but the
  harness strips only a short allowlist of variables, so every assignment
  denies;
- a skipped keyword or brace (`{ } ! if then elif else fi do done while
  until`);
- a command word of `cd`, `pushd`, `popd`, `sudo`, `eval` or `xargs`;
- for git, any option between `git` and its subcommand (`-C`, `-c`,
  `--git-dir`, `--no-pager`, …), or a `clone`, `init`, `worktree` or
  `bundle` subcommand.

Observed unsandboxed, and pinned as passes in the suite: `&&`, `|` and
`;` chains, a quoted argument, a `\.` escape, a trailing `# comment`
after a double space, and bare `git status --porcelain`. The asymmetry is
the point. A shape wrongly refused costs one re-issued call; a shape
wrongly let through runs silently sandboxed — the failure this hook
exists to stop. So anything not observed or documented as excluded counts
as refused, `git --no-pager` included although the bundle exempts boolean
flags, and the list can only shrink on evidence. Tracking an
undocumented, version-specific matcher is the cost; when the harness
narrows its exclusion again, a call this hook passes runs sandboxed, as
every such call did before the hook existed.

What counts as a subcommand is deliberately simple. Quoted text and
heredoc bodies are arguments, never subcommands. A call carrying a
command or process substitution is not matched at all: quoting inside
`$( … )` defeats a flat scan, and the call is left as it is. Leading
`VAR=value` tokens and shell keywords are skipped, so `FOO=1 git
status` and `if …; then ls; fi` still match. The patterns are read from
`~/.claude/settings.json` in the harness's own syntax, so the deny
tracks whatever the user excludes rather than a hard-coded list; with
the sandbox off, or the file unreadable, it passes and the SessionStart
check is what reports. Residual: wrappers (`timeout 5 git …`) and
commands reached through `xargs`, `sudo` or `sh -c` are not matched, so
the deny under-fires there.

### Piped gates: deny where the status is the verdict, warn elsewhere

Without `pipefail`, `just precommit | tail -40` exits with `tail`'s
status, so a failing gate reports success. Transcripts show it is the
habitual form, not a slip: of `just precommit` calls with the runner at
a command start, 864 were piped and 667 bare, and 85 of the piped ones
carried failure text in a result marked successful. The brief that
proposed this hook came from a backgrounded run whose completion notice
read `exit code 0` over a failed recipe.

A blanket deny on every piped runner was rejected. It would fire on
about 3,700 calls in that corpus, some 6% of all `Bash` calls, and its
redirect — run it bare — floods context everywhere but gitlore, whose
`run-bats.sh` prints only failures; raw `bats`, `pytest` and a `just`
recipe echo everything, which is why agents pipe them. The deny is
scoped to the two shapes where the masked status *is* the verdict: a
call run in the background, whose notice is all the agent sees, and a
pipeline followed by `&&` or `||`, which commits or pushes on it (124
`<gate> | tail && git commit` calls in the corpus). A foreground pipe
with nothing chained passes, and a `PostToolUse` hook reads its output
instead: a piped call that exits 0 arrives there, and when the output
carries a failure line the hook quotes it back as `additionalContext`.
That costs nothing on a green run.

`pipefail` or `PIPESTATUS` anywhere in the command passes, since either
keeps the gate's own status. So do probes that report no verdict
(`--version`, `--collect-only`, `--list` and kin). The redirect names
the act — drop the pipe, or start with `set -o pipefail;` — rather than
"run it bare". A piped `just release` is also refused by
`deny-sandboxed-excluded-command.sh`, whose redirect keeps the command
as it is; the two compose rather than conflict, since one adds the
sandbox flag and the other the `pipefail`.

Runners match by name: `just` recipes named precommit, prerelease,
release, lint or test, alone or with a `-`/`_` suffix, and `pytest`,
`bats`, `run-bats.sh` by basename, behind `VAR=` prefixes, `(`,
`timeout`, `uv run` or `python -m`. Residual: other gate names (`just
check`, `make test`), runners inside `bash -c` or `$( … )`, and masking
without a pipe (`just precommit > log; tail log`) go unmatched; the
`PostToolUse` half recognises only the listed output formats. The
detector lives in `scripts/lib/piped-gate.sh`, the first shared
library here. `strip_heredocs` lives in `scripts/lib/shell-text.sh`,
shared by every script that strips heredocs, and the git global-option
walk in `scripts/lib/git-command.sh`.

### Tree-root anchoring by `.git` adjacency

`deny-plugin-dev-edit.sh` and `deny-volatile-memory-state.sh` both key on
a path *segment* — `plugin-dev`, `memory` — and both originally spelled it
`*/<segment>/*`. That glob is wrong at both ends. It misses the segment at
string start, so a bare relative `plugin-dev/release.just` passed silently;
relative `file_path` values are ordinary traffic, not a corner case. And it
matches the segment at any depth, so a `vendor/thing/plugin-dev/x` that has
nothing to do with the vendored subtree false-denied.

What both rules actually mean is that the segment sits at the root of a git
tree. That is tested by `.git` adjacency:

```sh
case "$file_path" in
  "$seg"/*)   parent="." ;;
  */"$seg"/*) parent="${file_path%%/"$seg"/*}"; [ -n "$parent" ] || parent=/ ;;
  *) exit 0 ;;
esac
[ -e "$parent/.git" ] || exit 0
```

`%%` takes the outermost occurrence, which is the tree root by construction.
`-e` rather than `-d`, because a linked worktree carries `.git` as a gitlink
*file*; the suite proves this distinction is load-bearing rather than
defensive — swapping `-e` for `-d` reds the worktree case and nothing else.

Not `CLAUDE_PROJECT_DIR`. `EnterWorktree` chdirs without moving
`projectRoot`, and Claude Code's worktrees live at
`.claude/worktrees/<name>` *inside* the launch repo, so a comparison
anchored on the project root would silently stop guarding in every
worktree — the environment where an unreviewed edit is most likely.

Not `git rev-parse --show-prefix`. It returns the path relative to the
*submodule's* root, so a gitlore store mounted at `<root>/memory/` yields
`''` and the segment vanishes. Testing the *parent's* `.git` sidesteps that
entirely, and costs no subprocess.

The relative branch resolves `.` against the hook process's cwd. That is
the live session cwd, which is the best available answer for a path the
model emitted relative to it — there is no payload field carrying a
worktree root.

Verdicts the tests encode:

| path | verdict |
| --- | --- |
| `plugin-dev/release.just` | deny |
| a worktree root's `plugin-dev/release.just` (gitlink `.git` file) | deny |
| `vendor/nested/plugin-dev/x.sh` | pass |
| `plugin-dev/` under a directory that is no git tree | pass |
| `plugin-dev-notes/x.txt` | pass |
| `memory/ddaanet/x.md` | deny |
| `plugin-dev/memory/x.md` | pass |

### Deny edits under a loaded plugin root in unattended modes

Claude Code treats every path at or below a directory it loads a plugin
from as a sensitive file for `Write`, `Edit`, `MultiEdit` and
`NotebookEdit`. Read from the 2.1.293 bundle: the roots are the
`--plugin-dir` list, the hidden `--plugin-dir-no-mcp` list and
`CLAUDE_CODE_PLUGIN_DIRS`, resolved against the launch directory and
through `realpath`; the test is at-or-below and case-folded, with no
manifest filter, so a "folder of plugins" root covers everything under
it. In `default` and `acceptEdits` CC asks, with no reason line, and the
human can approve. In `auto` the edit fails as "(it skipped this
action)", in the branch that calls it a hard failure not to retry; why
the server skips it is inferred, not traced. The agent sees an opaque
refusal and retries, renames, or drops the edit without saying why.

`deny-plugin-root-edit.sh` names the cause. In `auto` and `dontAsk` it
denies: the reason says the path is under a root this session loads as
a plugin and names the source; `additionalContext` says every edit there
fails the same way, to edit the source tree when the root is a generated
copy of one, and otherwise to tell the user the edit needs a session
that does not load the root; `systemMessage` names root and source,
which tells the human what to drop on relaunch. The relaunch is withheld
from the agent: told to relaunch without `--plugin-dir`, it may spawn
`claude` itself. In `default`, `acceptEdits` or an absent mode the hook
only notes on `systemMessage`, explaining the prompt CC is about to
show — a deny there would take away an approval the human can give.
`plan`, `bypassPermissions` and unknown modes are silent: whether
`bypassPermissions` skips CC's check was not traced, and a deny there
could block an edit CC allows.

Two root sources, because neither sees every launch.

- **The environment.** `CLAUDE_CODE_PLUGIN_DIRS` reaches the hook, and
  the dogfood shim sets it. Split on `:` by parameter expansion, since
  entries hold spaces; `~` expanded against `HOME`; relative entries
  dropped, as CC drops them.
- **The `claude` process's argv.** CC creates the variable only when it
  was already set, so a flag-only launch leaves it absent. The hook
  walks its ancestors by the `PPid:` line of `/proc/<pid>/status` to the
  first whose `comm` is exactly `claude` — two hops in production, hook
  `bash` under `/bin/sh` under `claude`, one where `sh` execs its last
  command; it gives up after eight — and
  reads that process's NUL-separated `cmdline`, `--flag value` and
  `--flag=value` alike, stopping at `--`. The walk is builtins only.
  The first `claude` is what gives a nested `claude -p` its own argv
  rather than its parent's; it inherits the outer variable, but CC loads
  that value too, so the env source stays truthful.

A relative argv root resolves against `CLAUDE_PROJECT_DIR`, falling back
to the claude process's `/proc/<pid>/cwd`. CC resolves against its
original cwd, which the project dir keeps and the process cwd leaves on
`EnterWorktree`; the gitlore shim's `--plugin-dir .` makes relative
roots real traffic. Unverified for a `claude --worktree` launch.

Both sides of the match go through `abspath` (`scripts/lib/path.sh`),
and a target that is itself a symlink is also followed through its link
chain with a bare `readlink`, at most 16 links, since CC resolves the
leaf too. A target matches at the root or below `root/`, never on a bare
string prefix.

Composition. `plugin-dev/dogfood.sh pre-tool` (project settings) denies
edits into the `dist/plugin` copy this repo loads and names the source
path; this hook denies the same edit with a recovery that agrees, and
passes the source tree beside the copy, which the suite pins.
Special-casing `dist/plugin` was rejected: it couples to the toolkit's
layout and leaves another project loading that copy unexplained. With a
root outside the project, `ask-write-edit-outside-project.sh` asks and
this hook denies, and in auto the deny wins, which is right since the
edit cannot land. A root holding `plugin-dev/` or `memory/` can draw two
denies; either reason may render, and both contexts arrive. CC's
`.claude`-segment sensitivity is a separate trigger this hook does not
detect, so the deny names only the root it found.

Cost: every edit-tool call pays bash, one `jq` and the walk, about
50 ms on the common no-root path; a second `jq` and one `cd -P` per
root come only under a root.

Residuals. CC case-folds and this does not, so it under-fires on a
case-insensitive volume. `..` in a non-existent tail is not collapsed.
A `.zip` root matches only a `Write` to the zip itself. A path holding
`:` cannot be expressed in the variable, for CC either. Without `/proc`
— macOS included — only the env source exists, because `ps -o args=`
space-joins argv and a spaced root would be unrecoverable; a
`--plugin-dir` launch there under-fires and leaves CC's own opaque
outcome, the status quo rather than a new failure. An npm/Node install,
whose `comm` may be `node`, and a direct exec of the versioned binary
fall back to env-only the same way.

### Deny output is stdout + exit 0, never stderr + exit 2

All fifteen scripts emit their `hookSpecificOutput` JSON on stdout with
exit 0, including deny decisions. `exit 2` is a valid deny mechanism but
carries no `ask` capability and no `systemMessage` channel for a
human-facing summary distinct from the agent-facing reason — using the
JSON channel uniformly keeps every script's shape identical regardless
of its decision, and matches
[[hook-output-channels]] in the shared memory tier.

One non-zero exit is a failure, not a decision. The three git-walking
hooks capture `shell_split`'s output under `set -e`, so an awk that
fails ends the hook with awk's status. A syntax error exits 2, which
blocks the call with awk's stderr as the reason: a broken awk refuses
the commands past the hook's prefilter instead of passing them all.
Any other non-zero status is a non-blocking error, and the call
proceeds.

### A deny splits three ways by audience

Within that JSON the channels are not interchangeable, and a deny has
three audiences, not two. `permissionDecisionReason` becomes the
`tool_result` the blocked call fails with — it is what renders beside
the intercepted call, so it says only that the call is refused.
`additionalContext` is agent-only and never echoed, so it carries the
recovery — the form the question should take instead.
`systemMessage` is the human's single curt line.

Putting the recovery on the deny reason instead conflates the two: the
instructional prose renders with every block, which is noise for the
human and no better targeted for the agent. `deny-ask-user-question.sh`
is the worked example; the same split is what
`warn-sandbox-excluded-commands.sh` already does on its warn path.

That `additionalContext` survives a **deny** is verified, not assumed —
the shared-tier note covers a tool call that *fails*, which a blocked
call is not. Probed against CC 2.1.258 with a scratch `--settings` hook
under a nested `claude --print`: the field arrives as a transcript
attachment of type `hook_additional_context`, bound to the same
`toolUseID` as the denied call, and the receiving agent reported both it
and the deny reason. Re-probe before assuming a future version still
does this; the failure mode is silent, since a dropped
`additionalContext` leaves the deny working and only the teaching gone.

## Rejected alternatives

- **Hooks in gitlore's `hooks/hooks.json`.** Wrong audience: gitlore
  ships to gitlore-plugin consumers, a different population from
  ddaanet-tier mounters.
- **Keeping the prose as a fallback alongside the hooks.** Forfeits the
  whole benefit, which is removing the standing context cost — a rule
  kept in both places is paid twice, not once.
- **A guard on "refer to my human partner, never by name."** False-positive
  prone: git authorship and content written in their name for an
  external audience legitimately carry the real name. A guard that
  fires on legitimate writes trains the agent to work around it rather
  than teaching the rule.
- **A guard enforcing "Sonnet is the floor for any reviewer."**
  Mechanically possible via the `Agent` tool's `model` parameter, but
  low value relative to the false-positive risk of guessing agent
  intent from a prompt string.

## Limitations

- **The portability contract is checked statically, not exercised.**
  `tests/portability-test.sh` scans for the GNU-only constructs
  already known to bite; it cannot catch a new one nobody has listed,
  and nothing here runs the suite on a Mac. The one construct with
  behavioural coverage is path resolution, which
  `ask-write-edit-outside-project-test.sh` exercises with `realpath`
  and `readlink` stubbed out of PATH. The symlinked-scratch case in
  that same test states the invariant macOS depends on — both sides of
  the comparison resolved, so `/tmp` matching `/private/tmp` — but it
  passes on Linux either way, so it documents rather than proves.
  `shell_split`'s awk program has run only under mawk; it was reviewed
  against BSD awk, not run there, and its speed there is unmeasured.
- **The plugin-root argv source is Linux-only.** It reads `/proc`;
  elsewhere `deny-plugin-root-edit.sh` sees only
  `CLAUDE_CODE_PLUGIN_DIRS`, and that no-`/proc` path is untested, since
  the suite skips its argv cases there and nothing runs it on a Mac.
- **No pairing check yet.** A repo that mounts the `ddaanet` memory tier
  without enabling this plugin is unguarded with no visible symptom.
  The check belongs in gitlore's `SessionStart`, not here, and doesn't
  exist yet — so `shared-claude.md`'s prose stays in place alongside
  every hook shipped here, undiminished, until it does.
- **`plugin-dev/` was not audited.** The shell-gotcha audit behind
  these hooks' shape covered `scripts/` and `tests/` only.
  `plugin-dev/` is a vendored subtree of claude-plugin-dev, so a
  finding there belongs in that repo and would be undone by the next
  `just update-plugin-dev` if fixed here. Its absence from the audit is
  a scope boundary, not a clean bill.
- **Detection is co-occurrence-based in places** (e.g. `gh`/`pr|issue`/
  `create|comment|edit|review` for the hard-wrap guard), not full
  adjacency parsing. Accepted where exploiting the gap needs a
  contrived command real `gh` usage wouldn't produce; flagged, not
  fixed, where it does.

## History

Write-time records of each change live in
[changelog.md](changelog.md). This document states what the plugin
*is*; the changelog states how it got there.
