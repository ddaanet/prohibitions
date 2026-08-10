# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`prohibitions@ddaanet` — a Claude Code plugin, published in the `ddaanet`
marketplace (`ddaanet/claude-plugins`), that will hold PreToolUse hooks
intercepting ddaanet behavioural rules at the moment of action instead of
carrying them as always-on prose. The rules being converted currently live in
`/Users/david/code/gitlore/memory/ddaanet/shared-claude.md`, the tier every
ddaanet repo's `CLAUDE.md` imports; every line there is paid by every session
in every one of those repos, while a hook is paid only when the situation
arises.

**Status: bootstrap only.** The repo currently holds the plugin manifest and
the vendored release toolkit — no hooks have been implemented yet. Full
design context, the seven rules in scope, their matchers/decisions, and the
constraints on how they must be built lives in
`brief-prohibitions-plugin-bootstrap.md` at the repo root — read it before
implementing any hook here. The rationale for *which* rules convert to hooks
vs. stay prose is in `/Users/david/code/gitlore/plans/context-rules-vs-hooks-audit.md`.

## Commands

Release tooling comes from the vendored `plugin-dev/` toolkit (see below).

```sh
just precommit    # commit gate — currently just validates plugin.json is valid JSON
just prerelease   # release gate, defaults to precommit
just release [patch|minor|major]   # bump plugin.json, commit, tag, push, gh release
just update-plugin-dev vX.Y.Z      # pull a newer plugin-dev/ toolkit version
```

`precommit`/`prerelease` are stubs (from `plugin-dev/install.sh`'s scaffold)
and must grow real checks (hook tests, `hooks.json` lint, shellcheck) as
hooks are added — see the toolkit's own README for the gate contract.

## Architecture

- **`.claude-plugin/plugin.json`** — the plugin manifest. Its `.version`
  field holds the *last released* version and can only be changed by `just
  release`; a PreToolUse hook (`plugin-dev/version-guard.sh`, wired in
  `.claude/settings.json`) refuses direct edits to it.
- **`plugin-dev/`** — the `claude-plugin-dev` toolkit, vendored via `git
  subtree` from `/Users/david/code/claude-plugin-dev`, pinned to a tag
  (currently v0.5.0). Read-only: never hand-edit it. Changes go to the
  source repo, get tagged, then pulled in here with `just
  update-plugin-dev`.
- **Hooks (planned, not yet present)** — per the brief, this plugin will
  ship a `hooks/hooks.json` with seven PreToolUse hooks, five denying and
  two asking (branch/worktree creation, and edits outside
  `CLAUDE_PROJECT_DIR`, must ask rather than deny — see the brief's
  "Constraints" section for why). Each hook's denial/ask message must carry
  the recovery detail the prose currently carries, and each guard must be
  verified against a real command expecting ALLOW, not just the commands it
  should block.
- **Decoupling from the tier**: this plugin's installation (via the
  marketplace) and the `shared-claude.md` tier's mounting (via gitlore) are
  independent — nothing here couples them. Per the brief, the prose in
  `shared-claude.md` must not be trimmed until the corresponding hook exists
  here and is verified; that pairing check itself belongs in gitlore's
  SessionStart, not in this repo.

@memory/ddaanet/shared-claude.md
