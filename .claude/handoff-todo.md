## Remaining

- Briefs 3, 1, 2 and 4 landed, unreleased (through 8f108f1). Designs and build reports are committed under `plans/2026-10-0*`; `inbox/` now holds only its README.
- Brief 2 open: BSD awk never run (one `just precommit` on a Mac settles it; an awk failure now passes with a `systemMessage` instead of blocking); the 120 KB timing bound may flake on a loaded box.
- Brief 4 open: `claude --worktree` anchor (design Q3) unverified; macOS and npm/Node installs unexercised.
- Migrate the other denies that carry the recovery on the reason (`deny-volatile-memory-state`, `deny-hardwrapped-gh-body`, `deny-plugin-dev-edit`) to the three-way split, one commit each.
- Split `docs/design.md` (~825 lines, against the 400 soft cap).
- After the next release and plugin update, dogfood briefs 1, 2 and 4: a backgrounded `just precommit 2>&1 | tail` must deny and a foreground piped failing suite draw the PostToolUse warning; `git checkout -- .` must deny and `git checkout -- <file>` ask; an Edit under a loaded `--plugin-dir` root in auto mode must deny naming the root.
- Proposals for other repos, note only, no edit: the one-line `shared-claude.md` rule for brief 2 (gitlore); retiring `cc-plugin-dir-edits-sensitive` in edify's mount after brief 4 is dogfooded.
