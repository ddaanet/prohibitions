## Brief: add `just release:*` to the sandbox exclusion set

2026-09-02

### Decisions

- The checked set in `warn-sandbox-excluded-commands.sh` grows from four
  patterns to five: `git:*`, `find:*`, `ls:*`, `claude:*`, `just release:*`.
- The literal is `just release:*`, with the space — not `just:*`. The
  membership test is exact-string, no globbing, so the string in the hook must
  match the string in `settings.json` character for character.
- `~/.claude/settings.json` **already carries the entry**; that side is done.
  The work here is only making the hook, its docs and its tests agree with it.
  Do not edit `settings.json`.

### Constraints

- A `just` recipe's body is invisible to the harness. `sandbox.excludedCommands`
  matches statically against the segments of the Bash call, so `git:*` never
  reaches a `git push` that `release.sh` runs *inside* a recipe. That is why the
  release path needs its own top-level entry rather than inheriting the git one.
- One matching segment unsandboxes the **whole** call, so
  `cd <dir> && just release` is unsandboxed in its entirety.
- Silence is the pass signal for this hook. Every "could not run" path already
  warns; adding a fifth pattern must not introduce a path that passes quietly.
- The repo's self-application rule still holds: shellcheck-clean, and
  `just precommit` runs every `tests/*-test.sh`.

### Rejected approaches

- **`just:*`** — unsandboxes every recipe in every repo, including ones that
  should stay sandboxed. The prohibition being encoded is specific to the
  release path, which pushes to two remotes and calls `gh`.
- **Enumerating `just release`, `just release minor`, `just release major`** —
  the design doc already settled the prefix-vs-enumeration question for `git:*`
  (line ~276): a prefix buys the variants an enumeration misses, at the price of
  an unnecessary auto-classifier call on harmless invocations. Same reasoning
  applies; `just release:*` covers the bump arguments for free.

### Additional context

**The pattern was verified empirically, not assumed.** A two-word prefix is not
obviously parseable by the harness, so it was probed before this brief was
written. Method: one `justfile` in a temp dir with two recipes of identical
body, `release` and `probe`, each doing `touch /Users/david/.probe-*-delete-me`
— a write outside the sandbox's `write.allowOnly` list.

- `just probe` → `touch: cannot touch '...': Read-only file system`, exit 1.
  The sandbox is active.
- `just release` → exit 0, file created outside the allowlist.

A second tell appeared on the first `release` run: `$TMPDIR` expanded empty,
which is the documented signature of a call that left the sandbox (`TMPDIR` is
set only inside it). Both probe artifacts were removed.

So `just release:*` works as written. The verification does not need repeating.

**Artifacts to change** (paths relative to the repo root):

- `scripts/warn-sandbox-excluded-commands.sh` — the jq array near the bottom
  (`["git:*", "find:*", "ls:*", "claude:*"]`); the header comment, which says
  "the four `<cmd>:*` prefixes"; and the prose in all four `warn` message
  bodies, which enumerate "git, find, ls and claude -p" and give a reason
  specific to phantom dotfiles and dropped SessionStart hooks. The release
  reason is different — a nested `git push`/`gh` that the outer exclusion cannot
  see — so those sentences need a clause, not just a name added to a list.
- `tests/warn-sandbox-excluded-commands-test.sh` — `all_four` at line ~107 (the
  name has to change too); the all-present fixtures at lines ~134, ~141 and
  ~150; the partial case at ~175 and the bare-entry case at ~188, both of which
  assert over the full set. Add a case pinning that a bare `just release` entry
  without the `:*` does not satisfy the pattern, mirroring the existing
  `bare git entry` case.
- `docs/design.md` — the matcher table row at line ~110, and the section "A
  SessionStart check for sandbox exclusions, not a PreToolUse guard" (~line
  256), whose opening sentence states the prohibition as four commands.
- `README.md` — the bullet beginning "A harness sandbox that doesn't exclude
  `git`, `find`, `ls` and `claude`".

**Not in scope:** the `.mcp.json` gap. Separately observed this session, a
sandboxed hook launch in a repo with no `.mcp.json` dies with
`bwrap: Can't open source .../.mcp.json: No such file or directory` before
exec. That is a harness-level bind-mount problem, unrelated to
`excludedCommands`, and adding a pattern here will not address it.
