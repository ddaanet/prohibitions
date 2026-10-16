## Open decisions

- `ddaanet/prohibitions-memory` returned 404 anonymously on 2026-10-13, so a keyless `/plugin install` still fails until my human partner makes it public. The agent must not change visibility itself. Should `inbox/brief-https-submodule-urls.md` (untracked, executed) be deleted so `inbox/` holds only its README?

## Remaining

- Once the repo is public, run the brief's anonymous verification clone: `HOME="$TMPDIR/anon" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false git -c credential.helper= clone --recurse-submodules https://github.com/ddaanet/prohibitions.git "$TMPDIR/anon-clone"`; expect exit 0 with `memory/ddaanet/` populated.
- Relaunch Claude Code in this repo with `claude -c`: the release printed `gitlore skipped: hooks dir is stale`.
- Brief 2 open: BSD awk never run (one `just precommit` on a Mac settles it); the 120 KB timing bound may flake on a loaded box.
- Brief 4 open: `claude --worktree` anchor (design Q3) unverified; macOS and npm/Node installs unexercised.
- Migrate the other denies that carry the recovery on the reason (`deny-volatile-memory-state`, `deny-hardwrapped-gh-body`, `deny-plugin-dev-edit`) to the three-way split, one commit each.
- Split `docs/design.md` (~825 lines, against the 400 soft cap).
- After the plugin update to 0.3.1, dogfood briefs 1, 2 and 4: a backgrounded `just precommit 2>&1 | tail` must deny and a foreground piped failing suite draw the PostToolUse warning; `git checkout -- .` must deny and `git checkout -- <file>` ask; an Edit under a loaded `--plugin-dir` root in auto mode must deny naming the root.
- Proposals for other repos, note only, no edit: the one-line `shared-claude.md` rule for brief 2 (gitlore); retiring `cc-plugin-dir-edits-sensitive` in edify's mount after brief 4 is dogfooded.