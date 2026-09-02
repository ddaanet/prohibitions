## Open decisions

- Which `memory/MEMORY.md` entries retire. The composed root index is 25846 bytes against gitlore's 25600-byte advisory budget and past Claude Code's ~24.4KB loader cap, so its tail reaches no session in any repo mounting `ddaanet`. The lever is retiring entries, never shortening lines — shortening is where routing gets lost.

## Remaining

- `deny-git-add-all.sh`: a quoted bare dot (`git add "."`, `git add '.'`) still passes — only `'*'` and `':/'` are unwrapped ahead of quote stripping. Confirmed by probe. Write the test first, then add `'.'`/`"."`/`'./'` to the unwrap list.
- `deny-volatile-memory-state.sh`: the frontmatter fence is matched as an exact `---`, while gitlore's `check-memory-hygiene.py` uses `strip()`. A `--- ` with trailing whitespace keeps blanking to EOF here, so the hook fails closed and under-reports. Align with gitlore or diverge deliberately, with a test either way.
- Correct or supersede the red-check recipe in `plans/2026-08-27-hook-audit-fixes.md` Global Constraints: it relocates the test file to a temp dir, which rebinds `repo_root` and manufactures failures unrelated to the defect. The plan's step boxes are ticked; this recipe is the one part not settled.
- ~14 index lines in the `ddaanet` tier's `MEMORY.md` do not match their files' `description:` frontmatter. They pre-date the last tier merge and exist identically upstream — fold into the same `/gitlore:index-audit` pass as the retirement decision.
