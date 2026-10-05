## Remaining

- Publish memory with /gitlore:push.
- Cut the release with `just release minor` (0.2.3 to 0.3.0).
- After the plugin update, dogfood the deny hook: a bare `git status` must pass, `git status | head` must deny.
- Triage the four untracked briefs in `inbox/`; they are proposals for future hooks, not release content, and stay out of commits until accepted.
