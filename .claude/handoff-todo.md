## Open decisions

- Release bump. `just release minor` would ship the audit fixes plus four earlier hooks' worth of change that never reached consuming repos — `deny-git-add-all`, the widened `deny-volatile-memory-state`, the `SessionStart` `warn-sandbox-excluded-commands`, and the macOS/BSD portability pass. Confirm `minor` is right before running it. `just release` needs an unsandboxed shell; the marketplace bump fails sandboxed.
- Which `memory/MEMORY.md` entries retire. The index is at 106% of gitlore's 25600-byte advisory budget and past Claude Code's 24.4KB loader cap, so its tail never reaches a session at all. The fix is retiring entries, not shortening lines — shortening under-triggers the facts it shortens. This session added one line, so the pressure is up, not down.

## Remaining

- `deny-git-add-all.sh`: a quoted bare dot (`git add "."`, `git add '.'`) still passes — only `'*'` and `':/'` are unwrapped ahead of quote stripping. Confirmed by probe. Write the test first, then add `'.'`/`"."`/`'./'` to the unwrap list.
- `deny-volatile-memory-state.sh`: the frontmatter fence is matched as an exact `---`, while gitlore's `check-memory-hygiene.py` uses `strip()`. A `--- ` with trailing whitespace therefore keeps blanking to EOF here, so the hook fails closed and under-reports. Align with gitlore or diverge deliberately, with a test either way.
- The red-check recipe in `plans/2026-08-27-hook-audit-fixes.md` Global Constraints is unsafe as written: it relocates the test file to a temp dir, which rebinds `repo_root` and manufactures failures unrelated to the defect. Correct it in the plan or mark it superseded.
