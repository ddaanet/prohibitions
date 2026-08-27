## Open decisions

- Whether to `just release minor` now: three hooks landed since the last release (`deny-git-add-all`, the widened `deny-volatile-memory-state`, the `SessionStart` `warn-sandbox-excluded-commands`); none is live in consuming repos until released. Release runs unsandboxed (marketplace bump fails sandboxed).

## Remaining

- `deny-git-add-all.sh`: quoted bare dot (`git add "."`, `git add '.'`) still passes — only `'*'`/`':/'` are unwrapped before quote stripping. Test first, then add `'.'`/`"."`/`'./'` to the unwrap list.
- `deny-volatile-memory-state.sh`: frontmatter fence matched as exact `---`; gitlore's gate uses `strip()`, so a `--- ` with trailing whitespace keeps blanking to EOF here (fails closed, under-reports). Align or leave, with a test either way.
- `memory/ddaanet/sandbox-effects.md` still names the retired `unsandbox-git-status` hook as an escape; the replacement is `sandbox.excludedCommands` in `~/.claude/settings.json`, checked at SessionStart by this plugin.
- `memory/ddaanet/MEMORY.md` has a stale pointer `auto-mode-classifier-vs-hook-ask.md` naming no file in the tier (gitlore SessionStart warning); drop or redirect it.
