# Build report: deny worktree-discarding git

Design: `plans/2026-10-07-design-deny-worktree-discarding-git.md`, run
through `edify:build` (no runbook). Baseline 94c30e1. Every dispatch ran
sequentially with `name` unset; implementers Sonnet (prose: Opus),
reviewers Opus. Per-dispatch reports are scratch, under
`/tmp/claude/build-wdg/` (not committed).

## Commits (five; design asked for four, see Deviations)

1. `♻️ extract strip_heredocs and the git walk into scripts/lib/`
2. `✨ deny worktree-discarding git, ask on per-file restores`
3. `🐛 harden git_walk and confine the commit test to the project root`
   (security-review findings, inserted on the coordinator's instruction)
4. `🐛 move ask-branch-worktree-bash onto shell_split and the git walk`
5. `🐛 move deny-git-add-all onto shell_split`

`just precommit` exited 0 (status read directly) before each commit.
Each commit used `git commit -- <paths>`; `.claude/handoff-todo.md`
stayed staged and out of every commit. `grep -rn MUTATION scripts tests`
was run before the security commit and before commit 5, and
`git grep -n MUTATION <c> -- scripts tests` over every commit in
94c30e1..HEAD returns nothing: no mutation text is in any of the five
commits.

Commit 3 (security) was gated on a tree that also held commit 4's
uncommitted branch-hook rewrite, so it was re-checked in isolation from
`git archive 841bf10`: every suite passes except
`ask-write-edit-outside-project`, `deny-plugin-dev-edit` and
`deny-volatile-memory-state`, which fail identically in archives of
94c30e1 and HEAD (they need a real `.git` tree), so they are an artifact
of the archive, not of the commit. The discard suite failed once in that
archive run and passed on two re-runs; the failure output was not kept,
and it is consistent with the timing flake noted below.

## Red-check evidence per commit

- **Commit 1** (behaviour-preserving, no red by design): no test file
  changed; suite green before and after; `grep strip_heredocs() {`
  hits only `scripts/lib/shell-text.sh`. The reviewer ran a 56-case
  differential of every consumer (HEAD vs tree, from `/` under
  `env -i`): zero output or exit differences.
- **Commit 2**: against an inert stub hook and stub `shell_split` /
  `git_checkout_parse`, all 33 §6 deny cases, the 100 KB bound, all 14
  ask cases and all 19 lib cases failed on their verdict/output
  assertion with no harness error; `echo git add -A` failed against the
  real pre-change add hook. Post-green, each rule was disabled in turn
  (design §6): bulk shape → `git checkout :/`, `-- '*.txt'`,
  `-- "$d"/` red; clean `-n` exemption → `git clean -fn`,
  `--dry-run -f` red; rev test → `git checkout both` red; `cd`
  tracking → `cd src && git checkout a.txt` red; reverting
  `shell_split`'s buffered appends → the 120 KB bound red. Recorded in
  the changelog entry.
- **Commit 3 (security)**: new denies `/usr/bin/git reset --hard`,
  `sudo -u bob /usr/bin/git reset --hard`, `xargs git reset --hard`,
  `xargs git add -A` (+ `-0`, `-n1`), `/usr/bin/git add -A` and kin, and
  the outside-root ask/no-rev-parse cases all failed against the
  unchanged lib. Wrapper-with-option forms the review named
  (`sudo -u`, `env -i`, `timeout -s KILL 5`, `command -p`, `nice -n`,
  `time -p`, `exec`, `nohup`) already denied: added as pins, proven
  by mutation (below).
- **Commit 4**: `echo checkout -b x`, `echo git checkout -b x`,
  `echo git worktree add ../x`, `git log --oneline -- checkout -b`
  (pass) failed against the regex hook. The design's two ask cases
  (`git -C d checkout -b x`, `git -c a=b switch -c x`) already asked
  under the regex, so they are pins; disabling `git_walk`'s
  global-option skip redded both.
- **Commit 5**: `git add "-A"`, `git add '--all'`,
  `2>/dev/null git add -A`, `>/dev/null 2>&1 git add .`,
  `\git add -A` (deny) and `echo "say \"; git add -A; \" here"` (pass)
  failed against the previous hook.

## Security-review findings (coordinator, mid-run)

1. **control-regression** — real. Differential of the add hook at
   94c30e1 vs the command-word rule: `xargs …`, `stdbuf`, `ionice`,
   `setsid` forms flipped deny→pass. Fixed: those wrappers joined
   `git_walk` with per-wrapper option arity (incl. BSD xargs `-J -R -S`).
   Remaining deny→pass deltas, documented: `echo git add -A` (by
   design), a `git` behind an unlisted wrapper or `function` keyword
   (`busybox`, `watch`, `chronic`, `eval`), `git add -A"$x"` (unknown
   value never denies), and `# git add -A` (a comment). Improvements:
   `/usr/bin/git add -A`, `\git add -A`, `(git add -A)` now deny.
   `2>/dev/null git add -A` passed between commits 2 and 5 only.
2. **guard-bypass** — partly real. `/usr/bin/git`, `./git` and `xargs git`
   bypassed; fixed by basename matching and the `xargs` wrapper. The
   review of the fix found the basename test ran before the assignment
   skip (`GIT_EXEC=/usr/bin/git git reset --hard` passed); fixed with a
   case. `\git`, `command -p`, `env -i`, `timeout -s KILL 5`, `sudo -u`,
   `nohup`, `exec` were not bypasses (pins added).
3. **pre-approval-execution** — real as a design risk, not exploitable on
   git 2.47.3: a probe with a hostile repo (`core.fsmonitor`,
   `core.hooksPath` post-checkout) showed `rev-parse --verify` ran
   neither. Fixed anyway: the commit test runs only when the directory
   is inside `CLAUDE_PROJECT_DIR` (then payload cwd, then `$PWD`),
   physical paths, boundary pattern `"${root%/}"/*`; outside it no `git`
   is spawned and an existing operand is a path (ask/deny, never silent
   pass). Hardening applied (costs nothing): `GIT_CONFIG_NOSYSTEM=1 git
   -c core.fsmonitor=false -c core.hooksPath=/dev/null -C …`, with a
   test asserting the flags reach the call. Tests: outside `-C`, outside
   `cd`, prefix sibling `<root>x` (a real repo), payload cwd outside
   `CLAUDE_PROJECT_DIR`, inside root via symlink — the outside ones
   assert through a logging `git` shim that no `rev-parse` ran. The
   branch hook now passes no directory to the parser and spawns no `git`
   at all (shim test with a discard-hook control). The suite unsets an
   inherited `CLAUDE_PROJECT_DIR`.

The coordinator's sightings of `return 0` first in `gc_in_trusted_root`,
the slash-less `"${root%/}"*)`, and `gc_cwd` precedence were the
reviewer's in-flight mutations M4, M5, M7 (below); all reverted. The
committed form is `root="${CLAUDE_PROJECT_DIR:-${gc_cwd:-$PWD}}"` and
`"${root%/}"/*)`. `git grep -n 'return 0' HEAD -- scripts/lib/git-command.sh`
hits lines 111, 114, 135 (`git_walk` loop exits), 143–156 (one per
wrapper in `wrapper_option_takes_value`), 220, 224, 229, 236, 243, 248
(`git_checkout_parse` mode returns), 281 (`gc_is_path`: outside the
root → path, no subprocess), 304 and 306 (`gc_in_trusted_root`:
equality and boundary-prefix hits). None disables a check.

## Mutations applied for red checks (each by exact-string Edit, reverted by the inverse Edit)

- Item 1 review: an unused variable appended to probe SC2034 scope.
- Item 2 code review: bulk-shape case → `MUTATION_NO_SHAPE`; clean
  `force && ! dry` → `force`; rev test → `true # MUTATION_NO_REV`; `cd)`
  → `cd) return 0 ;; # MUTATION_NO_CD`; `ap()` → `w = w s`; awk
  `BEGIN {` → `BEGIN {{ # MUTATION_AWK_SYNTAX`.
- Item 3 + security review: M1 global-option loop → `while false`; M2
  basename rule removed; M2b basename `*/git` → `*git`; M3 `xargs`
  dropped from wrappers; M4 `return 0` first in `gc_in_trusted_root`;
  M5 `"${root%/}"/*` → `"${root%/}"*`; M6 `cd -P`/`pwd -P` → `-L`; M7
  root precedence swapped.
- Orchestrator: `-c core.hooksPath=/dev/null` removed from the
  `rev-parse` call (hardening assertion redded twice), then restored.
- Item 4 review: L-flag check → `: MUTATION-L` (suite stayed green: the
  check is unobservable, since an X word's text keeps its `$`/backtick
  and cannot equal a whole-tree token — kept as a contract, recorded in
  the changelog); the old quote-strip `sed` re-inserted (13 cases red);
  `strip_heredocs` bypassed with `# MUTATION-H` (red only after a new
  unquoted-heredoc case; the old heredoc pin had been vacuous).

All reverted: `grep -rn MUTATION scripts tests` is empty, the reviewers
grepped each mutation text absent, and `just precommit` exited 0 at
every commit.

## Review findings and resolution (all FIXED unless noted)

- Item 1: SC2034 disable was file-wide (narrowed to `git_walk`); a
  comment overclaimed the walk; design.md `scripts/lib/` line stale.
- Item 2 test review: `git checkout :/` contradicted §2's one-operand
  rule (resolved: shape candidates, see Deviations); heredoc pass case
  never exercised stripping; `git -C "$repo" checkout main` tested
  nothing (added `… onlyfile.txt`); ask path lists unchecked for
  tree-ish/option words; combining rule uncovered; non-Bash pass
  vacuous; fixture exposed to git-hook env.
- Item 2 code review: reserved words/`sudo`/`nohup`/`exec` regressed
  the walk; forced create passed; `restore -sHEAD .` and `clean -fd
  -enode` cluster misreads; `--pathspec-from-file` flag leak and space
  form; quadratic `shell_split`; unbalanced-quote newline; ask subject
  named only the first subcommand; awk exit status lost behind process
  substitution; `env -C`/`sudo -D` chdir; `--orphan=` etc.
- Item 2 docs review: floor-path trigger, stale "only spawns git",
  ambiguous unknown-dir sentence, narrated proposal, repetition, wrap.
- Item 3 + security review: see Security findings; plus branch hook
  spawning `rev-parse` for nothing (fixed), BSD xargs arity, over-match
  pins (`legit`, `gitk`, `/x/git-foo`, `env echo git add -A`,
  `sudo -u git ls -A`). Judged, no change: the branch hook no longer
  asks on a forced create (`checkout -f -b x` parses as a forced
  switch; the discard hook denies it, and deny beats ask).
- Item 4 review: X-word pass pin added; changelog "again"/count fixes;
  `-A"$x"` delta disclosed; "Strip quoted…" section named every
  stripping script and the `deny-hardwrapped-gh-body.sh` exception;
  three hooks capture `shell_split`; matcher row; vacuous heredoc pin
  repaired; `function f { git add -A; }` gap documented.

## Deviations from the design

- **Five commits, not four**: the security fixes are their own commit
  between design commits 2 and 3, per the coordinator.
- **Branch-vs-path rule**: a no-`--` operand is a path *candidate* if it
  exists **or** has a `:`-magic/glob shape (§2 said exists only); needed
  for §6's deny `git checkout :/`. The rev still wins.
- **Force beats create** (§2 ordered create first; §5 says `git checkout
  -f -b x` is denied). Bare `git switch -f -c x` with no start point is
  an accepted over-deny (probe: it keeps edits).
- **Command-word rule widened** beyond §2's wrapper list: reserved words,
  `exec`, `nohup`, `sudo`, `doas`, `xargs`, `setsid`, `stdbuf`,
  `ionice`, basename `git`.
- **`rev-parse` confined to the trusted root and hardened** (security).
- **Awk failure exits non-zero** under `set -e` (a syntax error exits 2
  and blocks); §4 said every emit is exit 0, and design.md has a titled
  decision "Deny output is stdout + exit 0, never stderr + exit 2".
  Documented there as the one failure-path exception (fails closed for
  prefiltered commands instead of passing them silently). Your yes/no
  wanted; the alternative is to catch the failure and pass.
- **CLAUDE.md Status paragraph** edited (it named stale hook counts).
- **Build-skill gates**: `verify-step.sh` was not used (the parent's
  staged handoff file and untracked `inbox/`/plans make it permanently
  DIRTY); substituted `git status` inspection plus `just precommit`.
  Review reports were not committed (scratch). `triage-feedback.sh` and
  `tdd-auditor` were skipped (no `plans/<job>/` directory). No separate
  `final-review`: per-item reviews covered the whole baseline diff, the
  last one including the committed docs of commits 3–4.
- Item-3 docs were written in-session and reviewed in the item-4 review
  (fixes landed in commit 5), not before commit 4.

## Left undone / open

- **BSD awk never run.** `shell_split` ran on mawk only (BSD awk reviewed
  statically; building Apple's awk was refused by the classifier). One
  `just precommit` on a Mac would settle behaviour and the two size
  bounds' timing.
- **Timing flake risk**: the 120 KB pieces bound measured 4 s once on a
  loaded box (`SECONDS` granularity makes "under 4 s" effectively ~3 s).
  Not recurred in gate runs; may need loosening.
- `docs/design.md` is ~730 lines against the 400-line soft cap (was ~604
  before); not split.
- Residuals as documented: unlisted wrappers, `function` keyword,
  `$( … )`/`bash -c`/`eval`, arguments `xargs` feeds to git, a branch
  outside the root named like a file asks, a repo nested under the root
  counts as inside.
- Design §8.7: a one-line `shared-claude.md` rule is to be proposed in
  that repo; nothing written there from here.
