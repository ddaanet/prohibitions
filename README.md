# prohibitions

A Claude Code plugin that enforces `ddaanet` behavioural rules with
`PreToolUse` hooks instead of always-on prose. Where a rule has a clean
mechanical detection, a hook blocks it at the moment of action — paid
only when the situation arises, with a denial message that teaches the
recovery instead of just saying no.

## What it blocks (and asks)

- **Never call `AskUserQuestion`** — deny.
- **Never `git commit`/`git push --no-verify`** — deny, with the
  stale-push-hook recovery in the message.
- **GitHub PR/issue bodies must not hard-wrap** a paragraph across
  physical lines (every newline renders as `<br>`) — deny, naming the
  offending file and line.
- **Never hand-edit a vendored `plugin-dev/` subtree** — deny.
- **No volatile git state** (40-hex shas, `origin/*` tips) **written
  into memory files** — deny.
- **Creating or switching a branch or worktree** — ask, since it can be
  legitimate (executing an instruction to merge onto a named base).
- **Editing a file outside the project directory** — ask, since
  dropping a note in another repo is legitimate; only unreviewed edits
  aren't.

See [`docs/design.md`](docs/design.md) for the full matcher table, the
rationale behind each decision, and what was rejected along the way.

## Installing

```
/plugin marketplace add ddaanet/claude-plugins
/plugin install prohibitions@ddaanet
```

## Requirements

`bash`, `jq`.

## Development

```sh
just precommit   # shellcheck, bash -n, and every tests/*-test.sh
just release     # bump plugin.json, commit, tag, push, gh release
```

See [`CLAUDE.md`](CLAUDE.md) for repo layout and conventions.

## License

MIT
