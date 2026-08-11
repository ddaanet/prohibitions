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
tool call, a specific command shape. For that subset, a `PreToolUse`
hook that blocks at the moment of action is paid only when the
situation arises, and its denial message teaches more reliably than
remembered prose.

Roughly two thirds of `shared-claude.md` is judgement with no
mechanical trigger and stays prose — this plugin does not aim to
replace the whole file, only the rules with a clean detection. Full
scoping rationale: `plans/brief-prohibitions-plugin-bootstrap.md`.

## Requirements

### Functional

- One `PreToolUse` hook per rule in scope, denying or asking per the
  rule's own contract (see Architecture below for the current set).
- Each hook's denial/ask message carries the recovery detail the prose
  it replaces used to carry — e.g. the `--no-verify` block names the
  stale-push-hook recovery (`(cd <repo> && claude -p ping)`), not just
  "no."
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
- **`hooks/hooks.json`** — wires seven rules to eight scripts (branch/worktree
  creation needs two scripts to cover both its `Bash` and
  `EnterWorktree` matchers):

  | Rule | Matcher | Decision | Script |
  | --- | --- | --- | --- |
  | Never call `AskUserQuestion` | tool name `AskUserQuestion` | deny | `deny-ask-user-question.sh` |
  | Other repos stay read-only | `Write\|Edit`, path outside `CLAUDE_PROJECT_DIR` | **ask** | `ask-write-edit-outside-project.sh` |
  | Never hand-edit a vendored subtree | `Write\|Edit`, path matches `*/plugin-dev/*` | deny | `deny-plugin-dev-edit.sh` |
  | Never `--no-verify` | `Bash`, regex over `git commit`/`git push` | deny | `deny-no-verify.sh` |
  | Never create/switch branches or worktrees | `Bash` (`checkout -b`, `switch -c`, `worktree add`) | **ask** | `ask-branch-worktree-bash.sh` |
  | ″ | `EnterWorktree` | **ask** | `ask-enter-worktree.sh` |
  | No volatile git state in memory files | `Write\|Edit` on `memory/**.md`, 40-hex sha / `origin/*` tips | deny | `deny-volatile-memory-state.sh` |
  | GitHub bodies are not hard-wrapped | `Bash` on `gh pr\|issue create\|comment\|edit\|review` with `--body-file` | deny | `deny-hardwrapped-gh-body.sh` |

- **`scripts/*.sh` + `tests/*-test.sh`** — one script per hook, one
  end-to-end test per script, driven by synthetic `PreToolUse` JSON
  payloads through `jq`. `just precommit` runs `shellcheck`, `bash -n`,
  and every `tests/*-test.sh`.
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

Two of the seven rules cannot be `deny`: merging onto a base my human
partner named is executing their instruction, not originating a branch
switch, and filing a brief in another repo is legitimate — only *edits*
there are forbidden. A hook that denies either blocks legitimate work,
so both use the `ask` permission decision instead.

### Strip quoted and heredoc regions before matching

`deny-no-verify.sh` and `ask-branch-worktree-bash.sh` strip `'...'`/
`"..."` spans from the command string before matching, so a commit
message that *mentions* `--no-verify` or `checkout -b` in prose doesn't
false-trigger. A heredoc body (`<<'EOF' … EOF`) isn't wrapped in quote
characters at all, and this project's own commit-message convention
uses heredocs for multi-line messages — so a real commit documenting
these hooks (e.g. "Document that `--no-verify` is refused by the new
hook") false-triggered both scripts, including a hard **deny** blocking
a safe commit. Both scripts now strip heredoc bodies (tracking the
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

### Deny output is stdout + exit 0, never stderr + exit 2

All eight scripts emit their `hookSpecificOutput` JSON on stdout with
exit 0, including deny decisions. `exit 2` is a valid deny mechanism but
carries no `ask` capability and no `systemMessage` channel for a
human-facing summary distinct from the agent-facing reason — using the
JSON channel uniformly keeps every script's shape identical regardless
of its decision, and matches
[[hook-output-channels]] in the shared memory tier.

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

- **No pairing check yet.** A repo that mounts the `ddaanet` memory tier
  without enabling this plugin is unguarded with no visible symptom.
  The check belongs in gitlore's `SessionStart`, not here, and doesn't
  exist yet — so `shared-claude.md`'s prose stays in place alongside
  every hook shipped here, undiminished, until it does.
- **Detection is co-occurrence-based in places** (e.g. `gh`/`pr|issue`/
  `create|comment|edit|review` for the hard-wrap guard), not full
  adjacency parsing. Accepted where exploiting the gap needs a
  contrived command real `gh` usage wouldn't produce; flagged, not
  fixed, where it does.

## History

Write-time records of each change live in
[changelog.md](changelog.md). This document states what the plugin
*is*; the changelog states how it got there.
