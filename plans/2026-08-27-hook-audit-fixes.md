# Hook Audit Fixes Implementation Plan

> **For agentic workers:** Execute task-by-task with
> `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax for
> tracking. Do **not** dispatch subagents: every task is a few lines in one
> or two files, and the repo's whole test suite runs in under a second — the
> context churn a subagent offsets does not exist here.

**Goal:** Close the six defects a shell-gotcha audit found in the hooks that
were never scanned, and re-anchor two path matchers to the tree root.

**Architecture:** Each task is one defect in one or two scripts, paired with
a test that reds against the current code first. No new machinery: the fixes
are a quote-aware extraction regex, a payload field the hook already ignores,
one quoting fix, a `.git`-adjacency root anchor, and a test-convention
sweep.

**Tech Stack:** bash 3.2 / POSIX shell, `jq`, `grep -E`, `awk`. Tests are
plain `bash tests/*-test.sh` driven by synthetic hook JSON payloads.

**Spec:** `docs/design.md` — read the Requirements and Design decisions
sections before starting. The rationale for each hook's contract lives
there; this plan changes behaviour in two places (Tasks 4 and 6) that the
Architecture matcher table describes, so that table is part of the
deliverable.

## Global Constraints

- **POSIX utilities and bash 3.2**, per the platform requirement in
  `docs/design.md`. No `\b` in an ERE, no `realpath`/`readlink -f`, no
  `sed -i` without a suffix, no `grep -P`, `date -d`, `stat -c`,
  `find -printf`, `timeout`; no associative arrays, `mapfile`, `${var,,}`,
  `wait -n`, `inherit_errexit`. `tests/portability-test.sh` enforces this and
  runs as part of the gate — a line that names a banned construct on purpose
  opts out with a trailing `# portability-ok`.
- **`just precommit` is the gate**, run before every commit, unprompted. It
  runs `shellcheck`, `bash -n`, and every `tests/*-test.sh`.
- **shellcheck warnings are errors.** A justified suppression is a *second*
  comment: `# shellcheck disable=SC2086  # splitting intentional`.
- **Every fix gets a test that reds first.** Run the new test against the
  unmodified script and paste the failure before writing the fix. A test
  that has never failed is not evidence. Recipe used throughout this audit:

  ```sh
  old=$(mktemp -d)
  git show HEAD:scripts/<name>.sh > "$old/<name>.sh"
  sed "s#\$repo_root/scripts/<name>.sh#$old/<name>.sh#" tests/<name>-test.sh > "$old/t.sh"
  bash "$old/t.sh"
  ```

- **Test capture convention** (Task 5 makes it universal, earlier tasks
  follow it in any line they touch): a runner merges stderr into the
  captured output and swallows the exit status —
  `… | bash "$hook" 2>&1 || true` — so a hook that dies noisily fails an
  assertion instead of aborting the suite under `set -e`. `fail()` ends with
  `return 0`.
- **Never call `AskUserQuestion`** (this repo's own hook denies it). Ask
  inline in numbered prose with a stated default.
- **`docs/changelog.md` is write-time**, newest first. Each task appends its
  own entry as part of its commit.

---

### Task 1: `--body-file` path containing whitespace

**Files:**
- Modify: `scripts/deny-hardwrapped-gh-body.sh` (the `body_files` extraction
  around line 77, and the quote-stripping loop at 84–90)
- Test: `tests/deny-hardwrapped-gh-body-test.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing other tasks rely on. Task 2 modifies the same loop body
  and should be done after this one.

**The defect (confirmed by probe):** `grep -Eo -- '--body-file[= ][^[:space:]]+'`
cuts the path at its first space. The truncated value then fails
`[ ! -f "$body_file" ]` on line 91 and hits `continue`, so the hook exits
silent and the guard is bypassed entirely. The quote-stripping on lines
87–90 cannot help — the path is already cut. Measured:

```
gh pr create --body-file /tmp/x/nospace.md      → deny   (control)
gh pr create --body-file "/tmp/x/my draft.md"   → PASS
gh pr create --body-file /tmp/x/my\ draft.md    → PASS
gh pr create --body-file="/tmp/x/my draft.md"   → PASS
```

- [ ] **Step 1: Write the failing tests**

Four cases in `tests/deny-hardwrapped-gh-body-test.sh`, next to the existing
`--body-file=` case around line 125. Build a wrapped fixture at a path with
a space in it (`$work/with space/wrapped.md`, `mkdir -p` the directory), and
assert `deny` for the double-quoted, backslash-escaped, and `--body-file=`-
quoted spellings. Add a matching pass case: a *clean* body at a spaced path
must still pass, so the test distinguishes "the hook now sees the file" from
"the hook now denies everything".

- [ ] **Step 2: Run the tests to verify they fail**

Use the red recipe from Global Constraints.
Expected: 3 failures, each `wrapped body was not denied:` with empty output.

- [ ] **Step 3: Implement the quote-aware extraction**

Replace the extraction pattern with an alternation covering the three real
spellings — a double-quoted run, a single-quoted run, or a run of non-space
characters that allows backslash-escaped spaces:

```sh
body_re='--body-file[= ]("[^"]*"|'\''[^'\'']*'\''|(\\.|[^[:space:]])+)'
body_files="$(grep -Eo -- "$body_re" <<<"$command" || true)"
```

In the loop, after the existing quote stripping, unescape backslash-space:
`body_file="${body_file//\\ / }"`. State the residual in a comment — other
backslash escapes (`\"`, `\\`) are left as written, because a space is the
only one that silently defeated the extraction, and an over-eager unescape
would corrupt a path that legitimately contains a backslash.

- [ ] **Step 4: Run the full suite**

Run: `just precommit`
Expected: every suite passes, including the existing `--body-file` with no
argument case (line 89) and the missing-file case (line 139), both of which
exercise the same loop.

- [ ] **Step 5: Commit**

```bash
git add scripts/deny-hardwrapped-gh-body.sh tests/deny-hardwrapped-gh-body-test.sh docs/changelog.md
git commit -m "fix: --body-file path with whitespace no longer bypasses the hard-wrap guard"
```

---

### Task 2: relative `--body-file` resolved against the wrong directory

**Files:**
- Modify: `scripts/deny-hardwrapped-gh-body.sh` (the loop body, after Task 1)
- Test: `tests/deny-hardwrapped-gh-body-test.sh`

**Interfaces:**
- Consumes: Task 1's extraction loop.
- Produces: nothing.

**The defect (confirmed by probe):** the hook never reads `.cwd` from the
payload, so `[ -f "$body_file" ]` resolves a relative path against whatever
cwd the hook process inherited. Same payload, two cwds:

```
cwd=/tmp/x, hook run elsewhere   → PASS (silent)
cwd=/tmp/x, hook run from /tmp/x → deny
```

`scripts/deny-no-verify.sh` already reads `.cwd` for its message, so the
field is known to be present; it is simply unused here.

- [ ] **Step 1: Write the failing test**

A wrapped fixture at `$work/rel/wrapped.md`, a payload whose command is
`gh pr create --body-file wrapped.md` and whose `cwd` is `$work/rel`, run
with the test's own cwd left at the repo root. Assert `deny`. The existing
`run()` helper does not set `cwd`, so this needs a variant that does — add
`run_cwd() { jq -nc --arg c "$1" --arg d "$2" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$hook" 2>&1 || true; }`.

- [ ] **Step 2: Run the test to verify it fails**

Expected: `wrapped body was not denied:` with empty output.

- [ ] **Step 3: Resolve relative paths against the payload cwd**

Read `cwd="$(jq -r '.cwd // ""' <<<"$input")"` alongside `command`, and in
the loop, before the `-f` test:

```sh
if [ -n "$cwd" ]; then
  case "$body_file" in
    /*) ;;
    *) body_file="$cwd/$body_file" ;;
  esac
fi
```

Use `if`/`then`, not `[ -n "$cwd" ] && …`, so the intent survives a later
edit that moves it to the end of a function. Comment why: a hook process's
cwd is the live session cwd, which is *usually* right and silently is not
whenever the session has moved — the payload field is the authoritative one.

- [ ] **Step 4: Run the full suite**

Run: `just precommit`
Expected: all pass. The existing absolute-path cases are unaffected because
the `case` leaves `/*` alone.

- [ ] **Step 5: Commit**

```bash
git add scripts/deny-hardwrapped-gh-body.sh tests/deny-hardwrapped-gh-body-test.sh docs/changelog.md
git commit -m "fix: resolve a relative --body-file against the payload cwd"
```

---

### Task 3: `--no-verify` recovery command is not verbatim-runnable

**Files:**
- Modify: `scripts/deny-no-verify.sh:69` (the `human_msg` assignment)
- Test: `tests/deny-no-verify-test.sh`

**Interfaces:**
- Consumes: nothing. Produces: nothing.

**The defect (confirmed by probe):** `$cwd` is interpolated unquoted into a
command printed for a human to paste. With a spaced repo path it is broken,
and with no `.cwd` in the payload it is malformed:

```
fix: (cd /Users/david/my repo && claude -p ping)
fix: (cd  && claude -p ping)
```

shared-claude: *commands printed for a human to run must be
verbatim-runnable; substitute every real path.*

- [ ] **Step 1: Write the failing tests**

Two cases in `tests/deny-no-verify-test.sh`. First: a payload with
`cwd: "/tmp/my repo"`, asserting the `systemMessage` contains
`(cd '/tmp/my repo' && claude -p ping)`. Second: a payload with no `cwd`
key at all, asserting the message still names `claude -p ping` and does
*not* contain the empty `(cd  &&`. The existing `run()` hardcodes
`$repo_root` as cwd, so both need a payload built inline.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: 2 failures — the first on the missing quotes, the second on the
malformed `(cd  &&`.

- [ ] **Step 3: Quote the path, and drop the clause when there is no cwd**

Single-quote the substituted path in the message. When `$cwd` is empty, emit
the recovery hint without the `cd` — `claude -p ping` in the repo — rather
than a command that cannot run. Keep the message on one line.

- [ ] **Step 4: Run the full suite**

Run: `just precommit`
Expected: all pass, including the existing assertion that `systemMessage`
contains `claude -p ping` (line 33).

- [ ] **Step 5: Commit**

```bash
git add scripts/deny-no-verify.sh tests/deny-no-verify-test.sh docs/changelog.md
git commit -m "fix: quote the repo path in the --no-verify recovery command"
```

---

### Task 4: anchor `plugin-dev` and `memory` to the tree root

**Files:**
- Modify: `scripts/deny-plugin-dev-edit.sh` (the `case` at 22–25)
- Modify: `scripts/deny-volatile-memory-state.sh` (the `case` at 50–53)
- Test: `tests/deny-plugin-dev-edit-test.sh`,
  `tests/deny-volatile-memory-state-test.sh`
- Modify: `docs/design.md` (the two matcher-table rows, and the header
  comment claims in both scripts)

**Interfaces:**
- Consumes: nothing. Produces: nothing.

**The defect:** both matchers use `*/<segment>/*`, which matches the segment
at *any* depth and misses it at string start. Two consequences, both
confirmed: a bare relative `plugin-dev/release.just` or `memory/ddaanet/x.md`
passes silently (131 relative `file_path` values appear across the local
transcript corpus, so this is live traffic, not theoretical), and a nested
`vendor/thing/plugin-dev/x` false-denies.

**The contract:** the segment must sit at a git tree root. Tested by `.git`
adjacency — no subprocess, no path resolution:

```sh
case "$file_path" in
  "$seg"/*)   parent="." ;;
  */"$seg"/*) parent="${file_path%%/"$seg"/*}"; [ -n "$parent" ] || parent=/ ;;
  *) exit 0 ;;
esac
[ -e "$parent/.git" ] || exit 0
```

`%%` takes the outermost occurrence, which is the tree root by construction.
A worktree root carries `.git` as a *file* (gitlink), which `-e` catches —
this is why the anchor is not `CLAUDE_PROJECT_DIR`: `EnterWorktree` chdirs
without moving `projectRoot`, and CC worktrees live at
`.claude/worktrees/<name>` *inside* the launch repo, so a
`CLAUDE_PROJECT_DIR`-anchored match would silently stop guarding in every
worktree. Testing the *parent's* `.git` also sidesteps `memory/` being a
submodule, where a git-based `--show-prefix` would return `''` and make the
`memory/` segment vanish.

Verified verdicts for the helper:

| path | verdict |
| --- | --- |
| `plugin-dev/release.just` | deny |
| `.claude/worktrees/probe/plugin-dev/release.just` | deny |
| `vendor/nested/plugin-dev/x.sh` | pass |
| `/somewhere/else/plugin-dev/x.sh` | pass |
| `plugin-dev-notes/x.txt` | pass |
| `memory/ddaanet/x.md` | deny |
| `plugin-dev/memory/x.md` | pass |

- [ ] **Step 1: Write the failing tests**

In `tests/deny-plugin-dev-edit-test.sh`: a bare relative
`plugin-dev/release.just` must deny (run with the test's cwd at the repo
root, where `./.git` exists); a nested `$repo_root/vendor/nested/plugin-dev/x.sh`
must pass; a `plugin-dev/` under a directory with no `.git`
(`$(mktemp -d)/plugin-dev/x.sh`) must pass. Keep the existing
`plugin-dev-notes/` pass case — it is the trailing-boundary guard and must
not regress.

In `tests/deny-volatile-memory-state-test.sh`: a bare relative
`memory/ddaanet/x.md` carrying a sha must deny; a
`$(mktemp -d)/memory/x.md` carrying a sha must pass. Keep the existing
"volatile content outside memory/" case.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: the relative cases fail as "expected deny, got: " (empty), and the
nested/no-repo cases fail as "expected pass-through, got: {…deny…}".

- [ ] **Step 3: Implement the anchor in both scripts**

Apply the `case` + `[ -e "$parent/.git" ]` shape above in each script,
substituting the literal segment (`plugin-dev`, `memory`). In
`deny-volatile-memory-state.sh` the `.md` suffix condition still applies —
match `*/memory/*.md` and `memory/*.md`, then the `.git` test.

Note in a comment that the relative branch (`parent="."`) resolves against
the hook process's cwd, which CC sets to the live session cwd; that is the
best available answer for a path the model emitted relative to it.

- [ ] **Step 4: Update the two matcher-table rows and both header comments**

`docs/design.md` Architecture table: the `plugin-dev` row currently reads
"path matches `*/plugin-dev/*`" and the memory row "`Write|Edit` on
`memory/**.md`". Both must state the tree-root anchor. Both scripts' header
comments claim "any absolute path with a `plugin-dev` path component" and
similar — the absolute-path assumption is false in practice and must go.

- [ ] **Step 5: Run the full suite**

Run: `just precommit`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/deny-plugin-dev-edit.sh scripts/deny-volatile-memory-state.sh \
        tests/deny-plugin-dev-edit-test.sh tests/deny-volatile-memory-state-test.sh \
        docs/design.md docs/changelog.md
git commit -m "fix: anchor the plugin-dev and memory matchers to the tree root"
```

---

### Task 5: apply the test capture convention to the six unswept test files

**Files:**
- Modify: `tests/ask-branch-worktree-bash-test.sh`,
  `tests/ask-enter-worktree-test.sh`,
  `tests/deny-ask-user-question-test.sh`,
  `tests/deny-hardwrapped-gh-body-test.sh`,
  `tests/deny-no-verify-test.sh`,
  `tests/deny-plugin-dev-edit-test.sh`

**Interfaces:**
- Consumes: Tasks 1–4 have already touched three of these files; do this
  task last so it sweeps their additions too.
- Produces: nothing.

**The defect:** the convention the other four test files document and use is
missing or partial here. `fail()` has no trailing `return 0`; `run()` has no
`|| true`; every `passthrough="$(jq … | bash "$hook")"` lacks both `2>&1`
and `|| true`. Call sites are inconsistent —
`deny-hardwrapped-gh-body-test.sh` has `|| true` on lines 27/36/48/96 but
not on 56/72/84/89/121/125/130/134/139. A hook exiting non-zero aborts the
suite mid-run instead of reporting a FAIL, and an unmerged stderr escapes
the assertion that was supposed to catch it.

This is a refactor with no behaviour change, so it has no red step. Its
correctness check is that the suite stays green and the diff contains only
the four mechanical edits.

- [ ] **Step 1: Sweep each file**

Per file: add `return 0` to `fail()`; add `2>&1 || true` to the `run()`
helper's pipeline (several already have `2>&1` — add only what is missing);
add `2>&1 || true` to the `passthrough=` command substitution; remove the
now-redundant `|| true` from individual call sites so the convention lives
in one place. Copy the explanatory comment from
`tests/deny-git-add-all-test.sh` above each `run()`.

`tests/ask-enter-worktree-test.sh` and
`tests/deny-ask-user-question-test.sh` build payloads inline rather than
through a `run()` that needs changing — check each call site individually.

- [ ] **Step 2: Verify the convention actually catches a dying hook**

Temporarily add `exit 3` to the top of one script, run its test, and confirm
it reports a FAIL rather than aborting the suite. Revert the `exit 3`.
This is the only evidence that the sweep did what it claims — a green run
proves nothing about a failure path.

- [ ] **Step 3: Run the full suite**

Run: `just precommit`
Expected: all pass, unchanged from before the sweep.

- [ ] **Step 4: Commit**

```bash
git add tests/ docs/changelog.md
git commit -m "test: apply the stderr-capture convention to the six remaining suites"
```

---

### Task 6: record the audit in the design doc

**Files:**
- Modify: `docs/design.md` (Limitations)

**Interfaces:**
- Consumes: Tasks 1–5 are all landed. Produces: nothing.

- [ ] **Step 1: Add a Limitations entry for what the audit did not cover**

`plugin-dev/` is a vendored subtree and was not audited — findings there
belong in the claude-plugin-dev source repo, not here. Say so, so a later
reader does not mistake its absence for a clean bill.

- [ ] **Step 2: Verify the matcher table matches the shipped scripts**

Re-read the Architecture table row by row against `hooks/hooks.json` and the
`case` statements in `scripts/`. Task 4 changed two rows; confirm nothing
else drifted during this plan.

- [ ] **Step 3: Commit**

```bash
git add docs/design.md docs/changelog.md
git commit -m "docs: record the hook audit's scope and limits"
```
