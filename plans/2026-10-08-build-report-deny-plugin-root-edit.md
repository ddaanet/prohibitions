# Build report: deny-plugin-root-edit

2026-10-08. `/build` run on
`plans/2026-10-07-design-deny-plugin-root-edit.md` (no runbook). Baseline
`5b371e1`. Not committed.

## Commits

1. `6850e36` ♻️ lift abspath into scripts/lib/path.sh
2. `a57596d` ✨ deny edits under a loaded plugin root in unattended modes

Each was committed with `git commit -- <paths>` after
`git diff --cached --name-only`. The parent's staged
`.claude/handoff-todo.md` showed in the index both times and went into
neither commit (`git show --stat` confirmed). `inbox/` and the untracked
`plans/2026-10-07-*` files were not touched. `just precommit` exited 0,
read directly, before each commit, and `grep -rn MUTATION scripts tests`
was empty before each commit.

## Commit 1: abspath lift

- `scripts/lib/path.sh` (new): `abspath` moved verbatim with its comment.
  `unset CDPATH` moved with it and now runs when the file is sourced.
- `scripts/ask-write-edit-outside-project.sh` sources it with
  `. "${BASH_SOURCE[0]%/*}/lib/path.sh"` plus a `shellcheck source=`
  directive.
- References updated: the comment in `tests/portability-test.sh` and the
  portability bullet in `docs/design.md`, which used to say the sibling
  hook carries abspath. Changelog entry added.
- Evidence that behaviour is unchanged: precommit green on the baseline
  and after the move, and the sibling suite was not edited. Its
  `realpath`/`readlink` stub-out case still passes, so sourcing works
  under a stubbed PATH.

## Commit 2: the hook

Files: `scripts/deny-plugin-root-edit.sh`,
`tests/deny-plugin-root-edit-test.sh`, `hooks/hooks.json` (a new
`PreToolUse` block after `Write|Edit`, matcher
`Write|Edit|MultiEdit|NotebookEdit`, timeout 5), `tests/portability-test.sh`,
`docs/design.md`, `docs/changelog.md`.

Who did what. I wrote the test and ran the RED check in-session. A
separate Sonnet `edify:artisan` dispatch wrote the GREEN implementation,
the `hooks.json` block and the portability-regex change, working only
from the design and the already-red suite. It did not edit the test. I
wrote the docs. An Opus `edify:corrector` reviewed the whole baseline
diff. No agent did both a red step and its green step. All dispatches
ran one at a time, with `name` unset.

### Red check against the unchanged tree

Stub `scripts/deny-plugin-root-edit.sh`: `cat >/dev/null; exit 0`, first
line `# MUTATION: red stub`. Log: `/tmp/claude/drpe/red-stub.keep`.

- Suite before GREEN, against the stub: exit 1, 29 failures. Every D case
  (26 assertions: 1×2, 2, 5×2, 7×2, 8, 9, 10×2, 11, 12, 13, 15, 17, 18–24,
  27×2, 29) and every N case (25 × default/acceptEdits/absent) failed on
  its verdict assertion. Each one printed `got:` with empty output, so
  the failure was the verdict and not a crash. Every P case passed.
- After the stub run I deleted it and confirmed the MUTATION grep was
  empty.
- The final suite, with the reviewer's cases added, run against the same
  stub (`/tmp/claude/drpe/red-stub-final.log`): exit 1, 31 failures, all
  28 D and 3 N. The new D cases (the split-cwd 13 and 31) red; P case
  32 passes. The stub was then replaced with the final hook from a
  saved copy, `cmp` showed it identical, and the grep was empty.

### Per-condition mutations (after GREEN)

A driver (`/tmp/claude/drpe/mutate.sh`) applied one `sed` edit per
mutation to the working-tree hook. Each edit carried a `# MUTATION …`
comment. The driver confirmed the edit applied, ran the suite, recorded
the FAIL lines, restored the hook from a saved copy and checked the
restore with `cmp`. Log: `/tmp/claude/drpe/mutations.log`.

| Mutation | Redded |
| --- | --- |
| env source off (`rest=""`) | 1 and every other env-sourced D/N case |
| argv source off (`if false` on the /proc gate) | 8, 9, 10×2, 11, 12, 13, 15, 17 |
| `--plugin-dir=` form off | 9 |
| project-dir anchor off | 12 (both assertions) |
| first-match `break` removed | 14, 15 |
| `--` ignored | 16 |
| leaf-symlink follow (`t2`) off | 20 |
| mode gate: every mode → deny | 25 ×3, 26 ×3 |
| `notebook_path` dropped | 27 NotebookEdit |
| hop cap 8 → 9 (extra) | 17, ninth-ancestor case |

Every mutation was reverted, with `cmp` equal to the saved copy each time.
After the run, `grep -rn MUTATION scripts tests` was empty.

**Mutations the Opus corrector applied** (its report, verbatim list):
each marked `MUTATION`, restored from a backup, and the grep empty
afterwards. The case each redded is in parentheses:

- project anchor → `$PWD` (the new split-cwd 13)
- stderr redirect removed in `add_root` (31)
- cap 9 (the ninth-ancestor 17)
- cap 7 (the eighth-ancestor 17)
- first-match `break` removed (8–15)
- `--` ignored (16)
- `t2` disabled (20)
- `notebook_path` dropped (27)
- `=` form disabled (9)
- bare-prefix match (3)
- `~/` expansion disabled (7)
- empty-value guard removed (32)

It also injected a `readlink -fn` line into the hook to check that the
narrowed portability regex catches it, then reverted it.

**All mutations in this run, in one list:**

- the red stub, twice: before GREEN, and against the final suite
- my ten single-condition mutations in the table above
- the corrector's twelve probes and its `readlink -fn` injection

All were reverted, and the final tree has no `MUTATION` text in
`scripts/` or `tests/`.

The `/tmp/claude/drpe/*` logs cited in this report are transient scratch
files. The tables and lists here carry the evidence.

The suite passes both unsandboxed (precommit) and inside the Bash
sandbox. In the sandbox the PID namespace hides the real session, but
the fixture `claude` is a descendant, so the walk still finds it and no
argv case is skipped.

## Review findings and resolution

Report: `/tmp/claude/drpe/review-report.md` (Opus corrector). No
UNFIXABLE (grep count 0). All findings FIXED by the corrector:

- **Major: stderr leak.** A root the hook cannot enter made `cd -P`
  inside `abspath` print `Permission denied`, which breaks the
  never-stderr policy. Fixed with `2>/dev/null` at the hook's
  `abspath`/`readlink` call sites, pinned by new case 31. *My follow-up:*
  the redirects had no justification, which `no-stderr-suppression`
  requires, so I added an inline comment saying why each one is the
  mechanism (expected failure, handled by the drop, no channel exists).
- **Major: case 13 could pass for the wrong reason.** The claude and the
  hook shared a cwd, so `base="$PWD"` passed. A new `run_split_cwd`
  helper and a second case 13 now red that mutation.
- **Major: skipping empty argv values was untested.** New P case 32
  (`--plugin-dir= --plugin-dir ""`).
- **Minor: cap case depended on the host's `/bin/sh`.** Where `/bin/sh`
  is bash, it execs the last command and shifts the hop count. The
  layer runner's `sh` now ends in `; exit $?`.
- **Minor: portability regex too loose.** It missed `readlink -e/-m/-fn`.
  It now bans `readlink` with any option and still allows a bare
  `readlink <path>`. design.md and the changelog were updated to match.
- **Minor:** section-banner comments removed from the hook (no other
  script uses them). The design table row now also names the absent
  mode. The design text now covers the hop wording for an `sh` that
  execs. The Motivation paragraph was reflowed.
- **Recommendations, not applied:** (a) CC trims each
  `CLAUDE_CODE_PLUGIN_DIRS` entry and this hook does not, so an entry
  with surrounding whitespace under-fires. Design §3 does not ask for
  trimming, so it was left out. (b) Non-JSON stdin makes `jq` print to
  stderr, as the sibling hooks do; CC never sends non-JSON.

## Deviations from the design, and why

1. **`tests/portability-test.sh` narrowed.** The design (§4, §9) assumed
   a bare `readlink` was not banned, but the regex banned the word
   outright. The check now bans `realpath` outright and `readlink` with
   any option. That matches the design's intent, avoids a
   `# portability-ok` escape, and still catches the GNU-only
   `-f`/`-e`/`-m` forms.
2. **`unset CDPATH` moved into `scripts/lib/path.sh`**, run when the file
   is sourced, instead of being left for each sourcing script.
3. **Tests beyond the §9 table:** a lone `~` env entry (§3 specifies it),
   the hop cap tested at its exact edge (8th ancestor found, 9th not)
   rather than only "9 layers → P", an unknown mode under 26, and the
   reviewer's split-cwd 13, 31 and 32.
4. **Changelog/design wording.** design.md says "tell the user", as
   instructed. The new design section sits before "Deny output is stdout
   + exit 0". Counts were taken from the tree: 12 distinct rule rows and
   15 `scripts/*.sh`, so "twelve rules to fifteen scripts" and "All
   fifteen scripts". `CLAUDE.md` gives no hook count and names hooks only
   as "among them …", so it was left as is.
5. **/build ceremony adapted to this repo and to the instructions.**
   - The entry gate (`verify-step.sh`) reported DIRTY, but only on the
     paths I was told to leave alone (the staged handoff file, `inbox/`,
     the untracked plans). I recorded that and used "precommit green, and
     no dirt outside those paths" as the clean check after each commit.
   - The baseline sha and all reports live under `/tmp/claude/drpe/`, not
     `tmp/` or `plans/<job>/reports/`. `tmp/` is not gitignored here, and
     there is no job directory.
   - So `triage-feedback.sh` returned `no-classification`, with a
     "No corrector report" warning: it looks for reports in the job
     directory, and the corrector report is in `/tmp/claude/drpe/`.
   - The skill's dispatch `name`s were left unset, per instructions.

## Left undone

- `docs/design.md` is now about 825 lines, over the 400-line soft cap.
  Splitting it was explicitly out of scope.
- Not dogfooded live. That needs a session loading a plugin root in auto
  mode, and nested `claude` sessions were off-limits. Design open
  question 3 (does `claude --worktree` keep the project dir as CC's
  original cwd?) is still unverified.
- Retiring the memory fact `cc-plugin-dir-edits-sensitive` in edify's
  mount: to be proposed there after dogfooding, per design §10.
- Not exercised: macOS and other no-`/proc` hosts (the suite skips the
  argv cases there and says so), and npm/Node installs (env-only by
  design).
- Release and version bump not done, as instructed.
