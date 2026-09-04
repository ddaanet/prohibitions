# Changelog

Write-time records, newest first. This project is small enough that
each entry lives here directly rather than in a separate dated file per
entry — see [[design-doc-writing]] for when that split is worth making.

- **2026-09-03** — `warn-sandbox-excluded-commands.sh` checks a fifth
  pattern, `just release:*`. The other four cover commands the harness
  can see; a recipe body it cannot, and `excludedCommands` matches
  statically against the segments of the Bash call, so the `git:*` entry
  never reaches the `git push` and `gh` calls `release.sh` makes inside
  the recipe. `just release:*` and not `just:*`, which would unsandbox
  every recipe in every repo — the prefix still covers the bump
  arguments. The pattern was probed before being written down (two
  identical recipes named `probe` and `release`, both writing outside
  the sandbox's write allowlist: the first refused, the second
  succeeded), because a two-word prefix is not obviously parseable by
  the harness. `~/.claude/settings.json` already carried the entry;
  this change is the hook, its docs and its tests catching up. Membership
  is exact-string, so the suite now pins a bare `just release` and a
  `just:*` alongside the existing bare-`git` case — red-checked against
  the four-pattern script, where the bare-release case passed silently.

- **2026-09-02** — The frontmatter fence stays an exact `---` match,
  diverging from gitlore's `strip()`, and the suite now pins both
  directions: a `--- ` opener is not a fence, so a sha in the block it
  opens denies; a `--- ` closer never closes, so the blanking runs to EOF
  and a body sha passes. The under-report is the accepted cost —
  gitlore's commit-time gate still catches it, while accepting a padded
  opener would let one stray line disarm the hook over a whole file. No
  script change; rationale in `docs/design.md`.
- **2026-09-02** — `deny-git-add-all.sh` denies the quoted whole-tree
  pathspecs it was missing. Only `'*'` and `':/'` were unwrapped ahead of
  the quote strip, so `git add '.'`, `git add "."`, `git add './'` and
  `git add "./"` reached git unblocked while their bare spellings were
  denied — the guard's own README line already claimed `.` was covered.
  Red-checked: the four cases failed against the unchanged script, the
  two quoted `:/` forms passed as expected. The escaping-heavy `sed` that
  did the unwrap is now a loop over the four pathspecs using bash
  substitution, with the pattern quoted so `*` stays literal rather than
  becoming a glob. A probe for the obvious false-deny — `git add 'a'.'b'`,
  one path `a.b` to the shell — showed it passes through, since the
  unwrapped dot lands back inside a quoted region that then strips; that
  case and the other adjacent-quote forms are now in the suite rather
  than a throwaway run. The residual bound in the header was corrected to
  the one that holds: an interpolated pathspec (`git add "$dir"` with
  `dir=.`) is invisible to a textual hook and under-denies.
- **2026-09-02** — `deny-ask-user-question.sh` splits its output three
  ways by audience. The recovery — ask inline in numbered plain prose,
  each question carrying a stated default — moved off
  `permissionDecisionReason` onto `additionalContext`, leaving the deny
  reason a single line saying the call is refused, and the
  `systemMessage` was rewritten to the curt lowercase house style. The
  reason renders beside the blocked call; the recovery is agent-only and
  silent, so the instruction no longer prints at the human every time
  the guard fires. That `additionalContext` is delivered on a **deny**
  and not merely on a failed call was probed against CC 2.1.258 under a
  nested `claude --print` with scratch `--settings`: it arrives as a
  `hook_additional_context` attachment bound to the denied call's
  `toolUseID`. The test asserts the split in both directions — the
  recovery present in `additionalContext`, absent from the deny reason —
  and was red-checked by dropping the field from the emitted JSON.
- **2026-08-27** — `deny-git-add-all` and
  `warn-sandbox-excluded-commands` are executable, script and test
  alike; both landed 100644 while every other component is 100755.
  Nothing was broken by it — `hooks/hooks.json` invokes each script as
  `bash "<path>"` and `just precommit` runs each test the same way, so
  neither path consults the mode — but a mode that only two of ten
  components carry is a trap for any later caller that does execute
  them directly.
- **2026-08-27** — `docs/design.md` records the hook audit's scope: a
  Limitations entry saying `plugin-dev/` was never scanned, so its
  absence reads as a boundary rather than a clean bill. The Architecture
  matcher table was re-checked row by row against `hooks/hooks.json` and
  each script's own guard; the only drift beyond the two rows the anchor
  change rewrote was the off-project row, which claimed every new `.md`
  `Write` is exempt without naming the `CLAUDE.md` and `.claude/`
  carve-outs the script applies.
- **2026-08-27** — The capture convention now holds in all ten test
  files. The six that had it partially or not at all — `fail()` without
  a trailing `return 0`, a `run()` helper without `2>&1 || true`, a
  `passthrough=` substitution with neither, and `|| true` scattered
  across some call sites but not others — are swept. Verified rather
  than assumed: with `exit 3` at the top of `ask-enter-worktree.sh` the
  old suite aborted at the first case with no output at all, naming
  nothing; the swept one reports nine FAILs and exits through the normal
  failure path.
- **2026-08-27** — `deny-plugin-dev-edit.sh` and
  `deny-volatile-memory-state.sh` anchor their path segment to a git
  tree root, tested by `.git` adjacency. `*/<segment>/*` was wrong at
  both ends: it missed the segment at string start, so a bare relative
  `plugin-dev/release.just` or `memory/ddaanet/x.md` passed silently —
  and relative `file_path` values are ordinary traffic — while matching
  it at any depth, so a `vendor/thing/plugin-dev/x` false-denied. `-e`
  and not `-d`, since a linked worktree's `.git` is a gitlink file;
  swapping it reds the worktree case and nothing else. Full rationale,
  including why neither `CLAUDE_PROJECT_DIR` nor `git rev-parse
  --show-prefix` can anchor this, in `docs/design.md` under "Tree-root
  anchoring by `.git` adjacency".
- **2026-08-27** — `deny-no-verify.sh`'s recovery command is now
  verbatim-runnable. The repo path was interpolated unquoted, so a
  spaced path printed `cd /Users/david/my repo` — a two-argument `cd`
  — and a payload with no `cwd` printed the unrunnable
  `(cd  && claude -p ping)`. The path is single-quoted, an embedded
  single quote re-quoted as `'\''`, and with no `cwd` the `cd` clause is
  dropped rather than emitted empty.
- **2026-08-27** — `deny-hardwrapped-gh-body.sh` resolves a relative
  `--body-file` against the payload's `cwd`. The hook had never read the
  field, so a relative path resolved against whatever cwd the hook
  process inherited: the same payload denied when the hook happened to
  run from the right directory and passed silently otherwise. The hook
  process's cwd is the live session cwd, which is usually right and
  silently is not once the session has moved, so the payload field is
  the authoritative one.
- **2026-08-27** — `deny-hardwrapped-gh-body.sh` extracts the
  `--body-file` value quote-aware. `[^[:space:]]+` cut the path at its
  first space, and a truncated path fails the `-f` test and hits
  `continue`, so a spaced path did not degrade the check — it bypassed
  the guard silently, in all three spellings (`"…"`, `'…'`, `\ `). The
  pattern is now an alternation over a double-quoted run, a
  single-quoted run, and a run allowing backslash-escaped characters,
  with `\ ` unescaped after the quote stripping; other escapes are left
  as written, since a space is the only one that defeated the
  extraction and a path may legitimately contain a backslash.
- **2026-08-27** — macOS/BSD compatibility recorded as a requirement in
  `docs/design.md` (POSIX utilities, bash 3.2) and enforced by a new
  `tests/portability-test.sh`, plus the four GNU-only constructs that
  requirement made non-conformant. `ask-write-edit-outside-project.sh`
  drops `realpath -m` — GNU-only, and fatal under `set -e` on a Mac —
  for a portable `abspath()` over `cd -P`/`pwd`, and now runs the
  literal `/tmp` through it too, so the scratch exemption survives
  `/tmp` being a symlink to `/private/tmp`. `\b` is gone from
  `deny-volatile-memory-state.sh` (which tokenizes in awk instead),
  `deny-no-verify.sh`, `deny-hardwrapped-gh-body.sh` and
  `ask-branch-worktree-bash.sh`: it has no POSIX ERE equivalent, so BSD
  grep does not reject it — the guard silently stops matching, which is
  the worse failure. All four rewrites were differential-tested against
  the previous scripts over 46 commands with no behavioural change.
- **2026-08-27** — `warn-sandbox-excluded-commands.sh` no longer treats
  a settings.json it cannot read as a pass. `jq -e '.sandbox.enabled ==
  true' … || exit 0` collapsed "sandbox off" and "jq could not evaluate
  this" into the same silence, and a wrong-typed `.sandbox` is valid
  JSON, so it cleared the parse gate and failed only there — the one
  case where the sandbox may well be on and nothing warns. The shape is
  now classified inside jq (`off`, `on`, or which key is malformed) and
  every not-knowing warns, as the script's header always claimed.
- **2026-08-27** — Test hygiene alongside the above: the capture
  convention the suite documents (merge stderr, swallow the exit
  status, assert on the output) is now applied in
  `deny-git-add-all-test.sh` and `ask-write-edit-outside-project-test.sh`,
  which had cases that aborted the run under `set -e` or let a hook's
  stderr escape unasserted; the `shared-claude.md` fixture is cut by
  lines rather than by `head -c`, which splits a UTF-8 sequence the
  moment an edit upstream shifts the boundary; and the volatile-state
  matcher gained the case `\b` was carrying — a hex run embedded in a
  longer word (`codefaced`) must pass.
- **2026-08-27** — New hook `warn-sandbox-excluded-commands.sh`, the
  plugin's first non-`PreToolUse` rule: at `SessionStart` it checks that
  `~/.claude/settings.json` excludes `git:*`, `find:*`, `ls:*` and
  `claude:*` from the harness sandbox, and warns on both channels
  (`additionalContext` for the agent, `systemMessage` for the human)
  naming only the patterns actually missing. Sandboxed, `git`/`find`/`ls`
  see phantom dotfiles and `claude -p` silently drops SessionStart hooks;
  the harness's own exclusion list fixes that while the auto-mode
  classifier still vets the commands, so the plugin checks the setting
  rather than blocking the calls. An unparseable settings.json warns
  rather than passing. Replaces the retired `unsandbox-git-status`
  plugin; rationale in `docs/design.md`.
- **2026-08-27** — `deny-volatile-memory-state.sh` widened from full
  40-hex shas to `\b[0-9a-f]{5,40}\b`: the old scope had zero true
  positives available to it in a real 165-file store while missing four
  live commit ids. Precision comes from exclusions instead — all-digit
  runs, the closed 47-entry a-f-only word list, the YAML frontmatter
  block, UUIDs, and `<!-- hygiene-ok` lines — mirroring gitlore's
  `check-memory-hygiene.py` `volatile-state` so the write-time and
  commit-time gates agree; rationale in `docs/design.md`.
- **2026-08-26** — New hook `deny-git-add-all.sh`: whole-tree staging
  (`git add -A`, `--all`, `.`, `./`, `:/`, `'*'`, the `stage` synonym,
  short-flag clusters containing `A`) is refused, with the deny reason
  naming the remedy — stage the paths you mean, or `git add -u` for
  already-tracked files only. Detection tokenizes each command segment
  and requires `add` to be the git subcommand, so `git add-something
  -A`, `git log -- .` and `git add ./path` pass.
- **2026-08-26** — `ask-write-edit-outside-project.sh` no longer asks
  for a `Write` creating a new `.md` file outside the project (except
  `CLAUDE.md` and paths under `.claude/`): dropping a note in another
  repo is the permitted case, and it was paying a prompt every time.
  Backed by auto-mode probes showing the classifier does not block
  unprompted in-place edits in a sibling repo, so the hook stays for
  those; rationale in `docs/design.md`.
- **2026-08-11** — `ask-branch-worktree-bash.sh` now also asks before
  `git stash branch <name>`, which creates and checks out a branch like
  the other three covered forms but previously fell through unasked.
- **2026-08-11** — Reorganized the repo: `plans/` and `docs/` created,
  the bootstrap brief moved to `plans/`, `README.md` and `docs/design.md`
  added.
- **2026-08-11** — `CLAUDE.md` updated to drop the stale "bootstrap
  only" framing now that all seven hooks are implemented.
- **2026-08-10/11** — Landed the remaining six hooks (`deny-no-verify`,
  `deny-hardwrapped-gh-body`, `ask-branch-worktree-bash`,
  `ask-enter-worktree`, `deny-plugin-dev-edit`,
  `deny-volatile-memory-state`, `ask-write-edit-outside-project`), each
  with an end-to-end test. Two independent review passes (an Opus
  review, then a manual pass after a dispatched review agent failed to
  return output) found and fixed 14 issues total, including a heredoc
  gap in quote-stripping and a compound-command `--body-file` gap — see
  `docs/design.md` "Design decisions" for the two that changed the
  shipped behavior.
- **2026-08-10** — First hook landed: `deny-ask-user-question`, with its
  test suite and the `just precommit` gate.
- **2026-08-10** — Bootstrapped the plugin: manifest, vendored
  `plugin-dev` release toolkit, mounted the `ddaanet` shared memory
  tier via gitlore.
