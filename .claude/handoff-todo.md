## Open decisions

- Whether to `just release minor`. Four hooks' worth of change now sits unreleased — `deny-git-add-all`, the widened `deny-volatile-memory-state`, the `SessionStart` `warn-sandbox-excluded-commands`, and the macOS/BSD portability pass — and none of it reaches consuming repos until released. Release runs unsandboxed; the marketplace bump fails sandboxed. Landing the audit plan first would put it all in one release.
- `memory/MEMORY.md` is 27302 bytes, past both gitlore's 25600-byte advisory budget and Claude Code's 24.4KB loader cap, so entries beyond the cutoff never reach a session at all. The fix is retiring entries, not shortening lines — shortening under-triggers the facts it shortens. Which entries retire is the open question.

## Remaining

- `deny-git-add-all.sh`: a quoted bare dot (`git add "."`, `git add '.'`) still passes — only `'*'` and `':/'` are unwrapped ahead of quote stripping. Confirmed by probe. Write the test first, then add `'.'`/`"."`/`'./'` to the unwrap list.
- `deny-volatile-memory-state.sh`: the frontmatter fence is matched as an exact `---`, while gitlore's `check-memory-hygiene.py` uses `strip()`. A `--- ` with trailing whitespace therefore keeps blanking to EOF here, so the hook fails closed and under-reports. Align with gitlore or diverge deliberately, with a test either way.
