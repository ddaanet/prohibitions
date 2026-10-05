## Current task

Shipping `deny-sandboxed-excluded-command.sh` with its harness-excluded carve-out, plus the SessionStart check's `cmd *` syntax, as release 0.3.0 (`just release minor`). The quoted `git add` fix, the exact-`---` fence and the `just release *` check already shipped in v0.2.3, so this release carries only those two changes. A preflight came back GO once the work is committed; its warnings (executable bits, the `git -C` contradiction in `docs/design.md`, leftover `git:*` spellings) are fixed. The hook only goes live in sessions after the release and a plugin update.
