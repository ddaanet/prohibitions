# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`prohibitions@ddaanet` — a Claude Code plugin, published in the `ddaanet`
marketplace (`ddaanet/claude-plugins`), that holds PreToolUse hooks
intercepting ddaanet behavioural rules at the moment of action instead of
carrying them as always-on prose. The rules being converted currently live in
`/Users/david/code/gitlore/memory/ddaanet/shared-claude.md`, the tier every
ddaanet repo's `CLAUDE.md` imports; every line there is paid by every session
in every one of those repos, while a hook is paid only when the situation
arises.

**Status: all seven hooks implemented.** `hooks/hooks.json` wires up all
seven PreToolUse hooks from the brief, each with a script in `scripts/` and
an end-to-end test in `tests/`. The living design — full matcher table,
design decisions with rationale, rejected alternatives — is
`docs/design.md`; read it before touching a hook here. The original
bootstrap brief is `plans/brief-prohibitions-plugin-bootstrap.md`. The
rationale for *which* rules convert to hooks vs. stay prose is in
`/Users/david/code/gitlore/plans/context-rules-vs-hooks-audit.md`.

## Commands

Release tooling comes from the vendored `plugin-dev/` toolkit (see below).

```sh
just precommit    # commit gate: lint plugin.json/hooks.json, shellcheck, bash -n, run every tests/*-test.sh
just prerelease   # release gate, defaults to precommit
just release [patch|minor|major]   # bump plugin.json, commit, tag, push, gh release
just update-plugin-dev vX.Y.Z      # pull a newer plugin-dev/ toolkit version
```

## Layout

- **`.claude-plugin/plugin.json`** — the plugin manifest. Its `.version`
  field holds the *last released* version and can only be changed by `just
  release`; a PreToolUse hook (`plugin-dev/version-guard.sh`, wired in
  `.claude/settings.json`) refuses direct edits to it.
- **`plugin-dev/`** — the `claude-plugin-dev` toolkit, vendored via `git
  subtree` from `/Users/david/code/claude-plugin-dev`, pinned to a tag
  (currently v0.5.0). Read-only: never hand-edit it. Changes go to the
  source repo, get tagged, then pulled in here with `just
  update-plugin-dev`.
- **`hooks/hooks.json`**, **`scripts/`**, **`tests/`** — the seven rules'
  wiring, one script per hook, one end-to-end test per script. Full matcher
  table and rationale: `docs/design.md`.
- **`docs/design.md`** — living rationale for every design decision. States
  what the plugin *is*; update when a design choice changes.
- **`docs/changelog.md`** — write-time record of each change, newest first.
- **`plans/`** — prospective content only: the bootstrap brief and any
  future implementation plans. `docs/` holds what is true now.
- **`memory/`** — the `ddaanet` shared memory tier, mounted as a submodule
  via gitlore; includes `shared-claude.md`, the prose these hooks are
  converting rule-by-rule. This plugin's installation (via the marketplace)
  and the tier's mounting (via gitlore) are independent — nothing here
  couples them, so the prose in `shared-claude.md` must not be trimmed
  until the corresponding hook exists here and is verified; that pairing
  check itself belongs in gitlore's SessionStart, not in this repo.

@memory/ddaanet/shared-claude.md
