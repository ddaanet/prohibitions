# Changelog

Write-time records, newest first. This project is small enough that
each entry lives here directly rather than in a separate dated file per
entry — see [[design-doc-writing]] for when that split is worth making.

- **2026-08-27** — `deny-volatile-memory-state.sh` widened from full
  40-hex shas to `\b[0-9a-f]{5,40}\b`: the old scope had zero true
  positives available to it in a real 165-file store while missing four
  live commit ids. Precision comes from exclusions instead — all-digit
  runs, the closed 47-entry a-f-only word list, the YAML frontmatter
  block, UUIDs, and `<!-- hygiene-ok` lines — mirroring gitlore's
  `check-memory-hygiene.py` `volatile-state` so the write-time and
  commit-time gates agree; rationale in `docs/design.md`.
- **2026-08-26** — New hook `deny-git-add-all.sh`: whole-tree staging
  (`git add -A`, `--all`, `.`, `./`, `:/`, `'*'`, the `stage` synonym,
  short-flag clusters containing `A`) is refused, with the deny reason
  naming the remedy — stage the paths you mean, or `git add -u` for
  already-tracked files only. Detection tokenizes each command segment
  and requires `add` to be the git subcommand, so `git add-something
  -A`, `git log -- .` and `git add ./path` pass.
- **2026-08-26** — `ask-write-edit-outside-project.sh` no longer asks
  for a `Write` creating a new `.md` file outside the project (except
  `CLAUDE.md` and paths under `.claude/`): dropping a note in another
  repo is the permitted case, and it was paying a prompt every time.
  Backed by auto-mode probes showing the classifier does not block
  unprompted in-place edits in a sibling repo, so the hook stays for
  those; rationale in `docs/design.md`.
- **2026-08-11** — `ask-branch-worktree-bash.sh` now also asks before
  `git stash branch <name>`, which creates and checks out a branch like
  the other three covered forms but previously fell through unasked.
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
