## Current task

All 7 PreToolUse hooks are implemented, tested, and reviewed; the repo has been reorganized into `plans/` (prospective content) and `docs/` (current truth) with a new `README.md` and `docs/design.md`/`docs/changelog.md`. Three commits landed this session: `5a86456` (remaining 6 hooks), `cea9663` (CLAUDE.md status fix), `87a52bd` (reorg + README + design doc). `just precommit` is green.

## Open decisions

- Whether/when to cut the first release (`just release`) is undecided — my human partner's call, not blocking.
- Two minor gaps left unfixed as scope calls, recorded in `docs/design.md`'s Limitations: `ask-branch-worktree-bash.sh` doesn't cover `git stash branch <name>`; `deny-hardwrapped-gh-body.sh`'s gh-subcommand detection is co-occurrence-based rather than fully adjacent.
- No git remote is configured, so `just release`'s push step has nothing to push to yet — worth surfacing before the first release, not before now.