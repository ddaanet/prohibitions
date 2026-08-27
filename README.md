# prohibitions

A Claude Code plugin that enforces `ddaanet` behavioural rules with hooks
— `PreToolUse` except where noted — instead of always-on prose. Where a
rule has a clean mechanical detection, a hook acts at the moment of
action — paid only when the situation arises, with a message that
teaches the recovery instead of just saying no.

## What it blocks (and asks, and warns)

- **Never call `AskUserQuestion`** — deny.
- **Never `git commit`/`git push --no-verify`** — deny, with the
  stale-push-hook recovery in the message.
- **GitHub PR/issue bodies must not hard-wrap** a paragraph across
  physical lines (every newline renders as `<br>`) — deny, naming the
  offending file and line.
- **Never hand-edit a vendored `plugin-dev/` subtree** — deny.
- **No volatile git state** (commit ids, abbreviated or full) **written
  into memory files** — deny.
- **Never `git add -A` / `--all` / `.`** (whole-tree staging) — deny;
  name the paths, or `git add -u` for tracked files only.
- **Creating or switching a branch or worktree** — ask, since it can be
  legitimate (executing an instruction to merge onto a named base).
- **Editing a file outside the project directory** — ask, since
  dropping a note in another repo is legitimate; only unreviewed edits
  aren't.
- **A harness sandbox that doesn't exclude `git`, `find`, `ls` and
  `claude`** — a `SessionStart` warning, since sandboxed those see
  phantom dotfiles or silently drop SessionStart hooks.

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
