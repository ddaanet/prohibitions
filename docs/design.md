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
  would catch.
- **Mechanical, not a shell parser.** Detection is regex/word-boundary
  matching over the command string (with quoted and heredoc regions
  stripped first, so prose mentioning a trigger word doesn't fire the
  guard), not a full shell grammar.
- **POSIX and bash 3.2, so the hooks run on macOS as well as Linux.**
  These scripts run wherever Claude Code runs, and the plugin is
  installed from a marketplace rather than built per machine, so a
  GNU-only construct is a defect even when every machine in sight is a
  Linux one. Two contracts, both enforced by
  `tests/portability-test.sh`:

  - **Utilities are POSIX; GNU extensions are out.** No `realpath -m`
    or `readlink -f` (BSD realpath has no `-m`, and macOS before 12.3
    ships no realpath at all — `ask-write-edit-outside-project.sh`
    carries a portable `abspath()` built from `cd -P` and `pwd`), no
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
- **`hooks/hooks.json`** — wires nine rules to ten scripts (branch/worktree
  creation needs two scripts to cover both its `Bash` and
  `EnterWorktree` matchers):

  | Rule | Matcher | Decision | Script |
  | --- | --- | --- | --- |
  | Never call `AskUserQuestion` | tool name `AskUserQuestion` | deny (reason + `additionalContext` + `systemMessage`) | `deny-ask-user-question.sh` |
  | Other repos stay read-only | `Write\|Edit`, path outside `CLAUDE_PROJECT_DIR`; a `Write` creating a new `.md` exempt, except `CLAUDE.md` and anything under `.claude/` | **ask** | `ask-write-edit-outside-project.sh` |
  | Never hand-edit a vendored subtree | `Write\|Edit`, a `plugin-dev` segment at a git tree root (`.git`-adjacent) | deny | `deny-plugin-dev-edit.sh` |
  | Never `--no-verify` | `Bash`, regex over `git commit`/`git push` | deny | `deny-no-verify.sh` |
  | Never create/switch branches or worktrees | `Bash` (`checkout -b`, `switch -c`, `worktree add`, `stash branch`) | **ask** | `ask-branch-worktree-bash.sh` |
  | ″ | `EnterWorktree` | **ask** | `ask-enter-worktree.sh` |
  | No volatile git state in memory files | `Write\|Edit` on `*.md` under a `memory` segment at a git tree root (`.git`-adjacent), `` `[0-9a-f]{5,40}` `` minus digits/hex-words/frontmatter/UUIDs/`hygiene-ok` lines | deny | `deny-volatile-memory-state.sh` |
  | GitHub bodies are not hard-wrapped | `Bash` on `gh pr\|issue create\|comment\|edit\|review` with `--body-file` | deny | `deny-hardwrapped-gh-body.sh` |
  | No whole-tree `git add` | `Bash` (`git add -A/--all/./:/`, `*`) | deny | `deny-git-add-all.sh` |
  | Never run sandboxed `git`/`find`/`ls`/`claude -p`/`just release` | `SessionStart`, checks `~/.claude/settings.json` `sandbox.excludedCommands` ⊇ `git:*`, `find:*`, `ls:*`, `claude:*`, `just release:*` | **warn** (`additionalContext` + `systemMessage`) | `warn-sandbox-excluded-commands.sh` |

- **`scripts/*.sh` + `tests/*-test.sh`** — one script per hook, one
  end-to-end test per script, driven by synthetic hook JSON payloads
  through `jq`. `just precommit` runs `shellcheck`, `bash -n`,
  and every `tests/*-test.sh`. One test is not paired with a hook:
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

Two of the eight `PreToolUse` rules cannot be `deny`: merging onto a base my human
partner named is executing their instruction, not originating a branch
switch, and filing a brief in another repo is legitimate — only *edits*
there are forbidden. A hook that denies either blocks legitimate work,
so both use the `ask` permission decision instead.

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

`deny-no-verify.sh`, `ask-branch-worktree-bash.sh` and
`deny-git-add-all.sh` strip `'...'`/`"..."` spans from the command
string before matching, so a commit message that *mentions*
`--no-verify`, `checkout -b` or `git add -A` in prose doesn't
false-trigger. A heredoc body (`<<'EOF' … EOF`) isn't wrapped in quote
characters at all, and this project's own commit-message convention
uses heredocs for multi-line messages — so a real commit documenting
these hooks (e.g. "Document that `--no-verify` is refused by the new
hook") false-triggered the first two scripts, including a hard **deny**
blocking a safe commit. All three strip heredoc bodies (tracking the
opener, its optional `-` tab-stripping mode, and its terminator line)
ahead of the quote strip.

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
mode. `-A` with a pathspec (`git add -A src/`) is still denied and
nothing is lost by that: since git 2.0 a plain `git add <pathspec>`
already behaves as `-A` within that pathspec, so the flag is redundant
wherever it is safe.

Detection walks tokens rather than pattern-matching the raw string:
find `git`, skip its global options (consuming the operand of `-C`,
`-c`, `--git-dir`, `--work-tree`, `--namespace`, `--config-env`),
require the subcommand to be exactly `add` or `stage`, then look for a
whole-tree token among the rest. That is what keeps `git add-something
-A`, `git log -- .` and `git diff .` passing. One wrinkle: a quoted
whole-tree pathspec is an *argument*, not prose, so it is unwrapped to
its bare form before the shared quote strip runs — otherwise the strip
that protects commit messages would delete the very token the rule
exists to catch. The unwrap covers all four spellings in both quote
styles, not just the two that must be quoted to work: `'*'` and `':/'`
shipped covered because quoting them is how they are normally written,
but `git add '.'` and `git add './'` are the same command as their bare
forms and passed the guard until the list was completed. Any spelling
the rule denies bare, it denies quoted.

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

### A SessionStart check for sandbox exclusions, not a PreToolUse guard

The prohibition is "never run sandboxed `git`, `find`, `ls`, `claude
-p` or `just release`": sandboxed, the first three see phantom dotfiles
— user-home dotfiles bind-mounted to `/dev/null` show up as untracked
character devices — and a sandboxed `claude -p` silently drops every
SessionStart hook. A `PreToolUse` deny would strand every such call,
which is most of them. The harness already has the right mechanism: its own
`sandbox.excludedCommands` runs those commands unsandboxed
automatically, while the auto-mode classifier still vets them for
danger. So the plugin has nothing to block — it only has to check the
setting is present, once, at session start, and say what is missing.
This replaces the retired `unsandbox-git-status` plugin.

The exclusion is `git:*`, not `git status`-shaped patterns. Mutating
git commands must run unsandboxed to succeed at all; the
dotfile-sensitive reads (`status`, `add`, `ls-files`) must run
unsandboxed to be *truthful*; and the remaining harmless git commands
pay only an unnecessary auto-classifier call. That is the price of a
prefix exclusion, and it buys coverage of variants like `git -C X
status` that an enumerated list would miss.

`just release` is on the list for a different reason, and it does not
inherit the `git:*` entry. A recipe body is invisible to the harness,
which matches `excludedCommands` statically against the segments of the
Bash call — so `git:*` never reaches the `git push` and `gh` calls
`release.sh` makes *inside* the recipe, and the release path needs its
own top-level entry. The pattern is `just release:*`, space included,
not `just:*`: unsandboxing every recipe in every repo is far more than
the prohibition asks for, and the same prefix-over-enumeration argument
above covers the bump arguments (`just release minor`) for free. One
matching segment unsandboxes the whole call, so `cd <dir> && just
release` runs unsandboxed in its entirety. Verified empirically rather
than assumed, since a two-word prefix is not obviously parseable: two
recipes with identical bodies writing outside the sandbox's write
allowlist, `just probe` refused with a read-only filesystem error and
`just release` succeeded, with `$TMPDIR` expanding empty on the
unsandboxed run.

Silence is the pass signal, so the failure paths are loud: an
unparseable `settings.json` warns instead of passing, because a check
that could not run must not look like one that ran clean. The warning
reaches both channels — `additionalContext` tells the agent to pass
`dangerouslyDisableSandbox` until the setting is fixed, `systemMessage`
tells the human who owns the file, naming only the patterns actually
missing. Residual: only the user-level `~/.claude/settings.json` is
read; project or managed settings that set the same key are not
consulted.

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

### Deny output is stdout + exit 0, never stderr + exit 2

All ten scripts emit their `hookSpecificOutput` JSON on stdout with
exit 0, including deny decisions. `exit 2` is a valid deny mechanism but
carries no `ask` capability and no `systemMessage` channel for a
human-facing summary distinct from the agent-facing reason — using the
JSON channel uniformly keeps every script's shape identical regardless
of its decision, and matches
[[hook-output-channels]] in the shared memory tier.

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
