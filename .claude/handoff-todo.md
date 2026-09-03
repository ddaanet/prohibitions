## Open decisions

- Which `memory/MEMORY.md` entries retire. The index is 24245 bytes over 85 lines, every one of them a `ddaanet` tier line — this repo carries no project index lines of its own — leaving ~740 bytes under Claude Code's ~24.4KB loader cutoff. Re-measure before deciding. The lever is retiring entries, never shortening lines: shortening is where routing gets lost.
- `markdown-formatter-choice.md`'s description claimed mdslw/remark "put list markers at line start". The body does not support it, so the sync dropped the clause. Decide whether the behaviour is real — in which case the fix is a body edit, not an index one — or the claim was always wrong.

## Remaining

- Cut a release carrying the quoted whole-tree `git add` fix and the exact-`---` fence entries in the suite, `docs/design.md` and `docs/changelog.md`.
