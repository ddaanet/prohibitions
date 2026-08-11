# Changelog

Write-time records, newest first. This project is small enough that
each entry lives here directly rather than in a separate dated file per
entry — see [[design-doc-writing]] for when that split is worth making.

- **2026-08-11** — Reorganized the repo: `plans/` and `docs/` created,
  the bootstrap brief moved to `plans/`, `README.md` and `docs/design.md`
  added.
- **2026-08-11** — `CLAUDE.md` updated to drop the stale "bootstrap
  only" framing now that all seven hooks are implemented.
- **2026-08-10/11** — Landed the remaining six hooks (`deny-no-verify`,
  `deny-hardwrapped-gh-body`, `ask-branch-worktree-bash`,
  `ask-enter-worktree`, `deny-plugin-dev-edit`,
  `deny-volatile-memory-state`, `ask-write-edit-outside-project`), each
  with an end-to-end test. Two independent review passes (an Opus
  review, then a manual pass after a dispatched review agent failed to
  return output) found and fixed 14 issues total, including a heredoc
  gap in quote-stripping and a compound-command `--body-file` gap — see
  `docs/design.md` "Design decisions" for the two that changed the
  shipped behavior.
- **2026-08-10** — First hook landed: `deny-ask-user-question`, with its
  test suite and the `just precommit` gate.
- **2026-08-10** — Bootstrapped the plugin: manifest, vendored
  `plugin-dev` release toolkit, mounted the `ddaanet` shared memory
  tier via gitlore.
