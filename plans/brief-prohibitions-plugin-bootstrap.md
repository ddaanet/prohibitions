## Brief: bootstrap the `prohibitions@ddaanet` plugin

2026-08-10

A Claude Code plugin holding hooks that intercept ddaanet behavioural rules at
the moment of action, so those rules can stop being always-on prose.

The rules currently live in `/Users/david/code/gitlore/memory/ddaanet/shared-claude.md`,
the always-in-context tier imported by every ddaanet repo's `CLAUDE.md`. Every
line there is paid by every session in every one of those repos. A hook that
blocks at the moment of action is paid only when the situation arises, and its
denial message teaches more reliably than remembered prose.

Full audit: `/Users/david/code/gitlore/plans/context-rules-vs-hooks-audit.md`.
Read it — it classifies all the rules, not just the convertible ones.

### Decisions

- **Plugin name `prohibitions`, in the `ddaanet` marketplace** (`ddaanet/claude-plugins`).
  Scoped by content so it repels unrelated hooks; `guards` was rejected as a name
  that accretes anything hook-shaped.
- **Not in gitlore's `hooks/hooks.json`.** gitlore ships to gitlore-plugin
  consumers, which is a different population from ddaanet tier mounters.
- **Contract is "intercept at the moment of action"**, with deny as the common
  case rather than the definition — two of the seven rules must *ask*.
- **Seven rules in scope**, each a PreToolUse hook:

  | Rule | Matcher / detection | Decision |
  | --- | --- | --- |
  | Never call `AskUserQuestion` | tool name `AskUserQuestion` | deny |
  | Other repos stay read-only | `Write\|Edit`, path outside `CLAUDE_PROJECT_DIR` | **ask** |
  | Never hand-edit a vendored subtree | `Write\|Edit`, path matches `*/plugin-dev/*` | deny |
  | Never `--no-verify` | `Bash`, regex over `git commit`/`git push` | deny |
  | Never create/switch branches or worktrees | `Bash` (`checkout -b`, `switch -c`, `worktree add`) + `EnterWorktree` | **ask** |
  | No volatile git state in memory files | `Write\|Edit` on `memory/**.md`, 40-hex sha / `origin/*` tips | deny |
  | GitHub bodies are not hard-wrapped | `Bash` on `gh pr create`/`gh issue comment` with `--body-file`; lint for mid-paragraph newlines | deny |

- **Denial messages carry the detail the prose currently carries.** The
  `--no-verify` block must include the stale-hook-path recovery (a push failing
  with `.git/gitlore-pre-push: exec: .../pre-push: not found` is a stale shim,
  fixed by `(cd /path/to/repo && claude -p ping)`, not a reason to bypass). That
  recovery is three lines of standing context today and should end up here.
- **Use the PreToolUse permission-decision output for `ask`**, not a bare exit 2 —
  exit 2 is deny-only.

### Constraints

- **The two `ask` rules cannot be deny.** Merging onto a base my human partner
  named is executing their instruction, not originating a branch switch. Filing a
  brief in another repo is permitted — it is only *edits* that are forbidden.
  A hook that denies these blocks legitimate work.
- **Verify every guard with a command the system genuinely issues, expecting
  ALLOW.** A guard verified only against the commands it should block can forbid
  everything and look correct. The branching and `--no-verify` matchers over-match
  most easily: `git checkout <file>`, `git branch` with no argument, and
  `gh pr create` bodies that legitimately contain newlines are all real traffic.
- **Do not touch `shared-claude.md`.** Deleting the prose is a separate, later
  change, and it lands in every ddaanet repo at once. Nothing comes out until the
  hooks exist, are verified, and the pairing check below is in place.
- **The pairing check belongs in gitlore, not here.** The tier mounts through
  gitlore while this plugin installs through the marketplace, with nothing
  coupling them — a repo that mounts the tier without enabling this plugin would
  be permanently unguarded once the prose is gone, with no visible symptom.
  gitlore's SessionStart should warn when the ddaanet tier is mounted and
  `prohibitions@ddaanet` is absent from `enabledPlugins`.
- **Release infra comes from the claude-plugin-dev toolkit.** Vendor it as
  `plugin-dev/`, always pinned to a tag, never `main`; refresh with
  `just update-plugin-dev vX.Y.Z`. `plugin-dev/` is generated and read-only —
  changes go to `/Users/david/code/claude-plugin-dev`, then a tagged release.
- **`${CLAUDE_PLUGIN_ROOT}` is set in hook commands but unset in agent Bash.**

### Rejected approaches

- **Hooks in gitlore's `hooks/hooks.json`** — wrong audience, as above.
- **Keeping the prose as a fallback alongside the hooks** — forfeits the whole
  benefit, which is the standing context cost.
- **A guard on "refer to my human partner, never by name"** — false-positive
  prone. Git authorship and content written in their name for an external
  audience legitimately carry the real name, and a guard that fires on
  legitimate writes trains the agent to work around it.
- **A guard enforcing "Sonnet is the floor for any reviewer"** — mechanically
  possible via the `Agent` tool's `model` parameter, but low value relative to
  the false-positive risk.

### Additional context

Roughly two thirds of `shared-claude.md` is judgement with no mechanical trigger
and stays prose — the *Working with my human partner*, *Deciding and planning*,
*Tests* and *Code* sections. This plugin will not shrink that file dramatically;
the win is qualitative, in that every remaining line becomes guidance rather than
a tripwire.

The governing principle, already recorded in the tier: *a gate that emits its own
instructions is invoked, not pre-satisfied* — its precondition is that the gate be
cheap, reversible and self-describing, which all seven candidates satisfy.
