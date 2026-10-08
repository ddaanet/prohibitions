# Design: deny edits under a loaded plugin root

2026-10-07. For a Sonnet executor. Source: inbox brief
`inbox/brief-plugin-dir-sensitive-edits.md`, triage §4 of
`inbox/triage-report.md`. Settled by my human partner: a per-edit
`PreToolUse` deny that names the cause and the recovery, not a
`SessionStart` warning. Everything below is a contract. Stamps are the
installed bundle `~/.local/share/claude/versions/2.1.293` unless noted.

## 1. Findings that shape the design

- **CC's own check.** `Xos(e)` builds its roots as
  `v()=[...hk(),...q$()].map(e=>P(Ee(),e))`: the `--plugin-dir` and
  `--plugin-dir-no-mcp` lists, `path.resolve`d against `originalCwd`.
  It tests at-or-below, case-folded (`gv(s,{foldCase:!0})`). The memory
  fact `cc-plugin-dirs-env-var` (2.1.283 read) adds that roots and
  target go through `fs.realpathSync.native`. The trigger is list
  membership: no manifest filter. A "folder of plugins" root (flag help:
  "loads each child") covers everything below it.
- **Auto mode fails hard.** `server_call_skipped` maps to
  `" (it skipped this action)"`, in the branch reading "This is a hard
  failure, not a transient one … Don't retry it". Why the server skips
  this edit stays inferred (brief, triage #2), not traced.
- **Env var.** `DVn()` splits `CLAUDE_CODE_PLUGIN_DIRS` on `:`, trims,
  keeps absolute entries. `kDr()` writes the normalized list back only
  `if(a.CLAUDE_CODE_PLUGIN_DIRS!==void 0)`, so a flag-only launch never
  creates the variable: the argv source is required. Hook env is
  `Xn={...as(),…}`, `as()` being `process.env` plus the settings `env`
  block. Observed: this session's claude process
  (`/proc/414422/environ`) and its Bash children carry
  `CLAUDE_CODE_PLUGIN_DIRS=…/prohibitions/dist/plugin`, set by
  `plugin-dev/bin/claude`. `dogfood.sh session-start` already relies on
  the variable reaching a hook.
- **Flags.** `"--plugin-dir <path>"` (repeatable) and a hidden
  `"--plugin-dir-no-mcp <path>"`, commander options. The `=` form is
  verified in the bundled commander: `if(/^--[^=]+=/.test(o)){let
  h=o.indexOf("="),u=this._findOption(o.slice(0,h));if(u&&(u.required
  ||u.optional)){this.emit(…,o.slice(h+1))`. The gitlore shim prepends
  `--plugin-dir .` under `GITLORE_AUTO_CLAUDE_PLUGIN_DIR`, so relative
  roots are real traffic.
- **Hook spawn.** `yye(zn,[],{env:Xn,cwd:ln,shell:si,…})` with
  `shell:true` runs `/bin/sh -c '<command>'`: hook `bash` → `sh` →
  `claude`, or `bash` → `claude` where `sh` execs its last command.
  Proxy probe, unsandboxed `sh -c "bash walk.sh"` from a Bash call
  (Debian dash 0.5.12, no exec): 3 hops to `comm=claude`; a hook is one
  hop shorter. Inside the sandboxed Bash tool the walk sees a PID
  namespace (`$$`=2) and finds nothing, so a failed walk must degrade
  to env-only.
- **Naming.** Native install: `comm` `claude`, `exe`
  `…/claude/versions/2.1.292`, `argv[0]` `~/.local/bin/claude`. CC sets
  `process.title="claude"` unless `CLAUDE_CODE_DISABLE_TERMINAL_TITLE`;
  under Bun `cmdline` survives it (a spaced `--resume` title came back
  as one NUL-separated element). Both shims `exec`, so no shim sits in
  the chain. npm/Node installs are unprobed.
- **Worktrees.** `Am(dir)` (`process.chdir`) runs on worktree entry and
  exit, so `/proc/<pid>/cwd` leaves `originalCwd` after
  `EnterWorktree`; `CLAUDE_PROJECT_DIR` does not move (design.md,
  "Tree-root anchoring").
- **Aggregation.** `deny` > `defer` > `ask` > `allow` across hooks,
  which run in parallel; with two denies, whose reason renders is
  unspecified. `additionalContext` is collected from every hook (`Lmt`)
  and each `systemMessage` renders.
- **Tools.** The edit-tool set is
  `["Write","Edit","MultiEdit","NotebookEdit"]`; `MultiEdit` appears
  only in rule aliasing, matching it is free. `NotebookEdit` names its
  target `notebook_path`.
- **Modes.** `default acceptEdits bypassPermissions plan dontAsk auto`.
  In `default`/`acceptEdits` CC's own `ask` ("…which is a sensitive
  file") reaches the human, who can approve. Whether `bypassPermissions`
  skips the check was not traced.

## 2. The rule

New script `scripts/deny-plugin-root-edit.sh`.

**Inputs.** Payload `tool_name`, `permission_mode`,
`tool_input.file_path // tool_input.notebook_path`. Environment
`CLAUDE_CODE_PLUGIN_DIRS`, `CLAUDE_PROJECT_DIR`, `HOME`; `/proc` on
Linux.

**Decision rules, cheapest first:**

1. One `jq` call prints `tool_name` and `permission_mode` on two lines
   (neither can hold a newline). Tool not in `Write Edit MultiEdit
   NotebookEdit` → silent.
2. Mode gate (open question 1): `auto`, `dontAsk` → deny branch;
   `default`, `acceptEdits`, absent → note branch; anything else
   (`plan`, `bypassPermissions`, unknown) → silent.
3. Collect roots (§3). None → silent: the common exit.
4. Second `jq` call for the path. Empty → silent.
5. Match (§4). No root contains the target → silent.
6. Emit the branch's output (§5).

Always exit 0. A failure while collecting (unreadable `/proc` entry,
failed `cd -P`) drops that source or root and carries on — never a
block, never stderr. Under `set -e`, guard each such step with `|| …`.

## 3. Root collection

Each root carries a **source label**: `--plugin-dir`,
`--plugin-dir-no-mcp` or `CLAUDE_CODE_PLUGIN_DIRS`. Env entries come
first, then argv in order; the first matching root is reported.

**Env source.** Split on `:` by parameter expansion, as
`dogfood.sh session-start` does — never `IFS` splitting, entries hold
spaces. Skip empty entries; expand a leading `~/` or lone `~` against
`$HOME`; skip anything still not absolute, which CC drops. The `~`
handling moved between versions: the memory fact says 2.1.283 dropped
`~` entries, while 2.1.293's warning ("an absolute local path or starts
with ~") says they are accepted, so row 7 encodes 2.1.293. Residual:
a path holding `:` cannot be expressed here, for CC either.

**Argv source, only when `/proc/$$/status` is readable.**

- Walk from `$$` by `PPid:` (`while read -r key val _` over
  `/proc/<pid>/status`); read `/proc/<pid>/comm` with `read -r`; stop at
  the first comm exactly `claude`. Give up at pid ≤ 1, an unreadable
  file, or 8 hops. Builtins only: the walk forks nothing.
- First-match is what gives a nested `claude -p` its own argv. It
  inherits the outer env var, but CC loads that value too, so the env
  source stays truthful.
- Read `/proc/<pid>/cmdline` with `while IFS= read -r -d '' arg`,
  NUL-exact. Scan every element (the fixture's first three are bash's
  own); stop at `--`. `--plugin-dir` / `--plugin-dir-no-mcp` take the
  next element; `--plugin-dir=V` / `--plugin-dir-no-mcp=V` take `V`;
  skip empty values.
- A relative value resolves against `CLAUDE_PROJECT_DIR` when set,
  else `/proc/<pid>/cwd`: CC resolves against `originalCwd`, which the
  project dir matches and the process cwd leaves on `EnterWorktree`
  (open question 3).

**macOS, or no `/proc`: env source only.** `ps -o args=` space-joins
argv, so a spaced root is unrecoverable — rejected (open question 4).
A `--plugin-dir` launch there under-fires, leaving CC's own opaque
outcome: the status quo, not a new failure. The dogfood shim, the
brief's recommended recovery, sets the env var and is covered.

## 4. Matching

`abspath()` moves verbatim from `ask-write-edit-outside-project.sh`
into `scripts/lib/path.sh` (§8): absolute, symlinks resolved on the
longest existing prefix, a missing tail kept as written — so a `Write`
creating `R/new/dir/f` resolves through `R`.

- `root_r = abspath(root)`.
- `t1 = abspath(path)`, a relative path against the hook's cwd as in
  the sibling hooks.
- `t2`: when `t1` is a symlink (`[ -L ]`), follow plain `readlink`
  (not `-f`; present on macOS and Linux, not banned), at most 16 links,
  a relative link against its directory, then `abspath`. `abspath`
  resolves directories only; CC resolves the leaf too.
- Match when `t1` or `t2` equals `root_r` or starts with `root_r/` —
  never a bare prefix, so `R-sibling/x` does not match `R`.
- Residuals for the header: CC case-folds and this does not
  (under-fire on a case-insensitive volume); `..` in a non-existent
  tail is not collapsed (from `abspath`); a `.zip` root matches only a
  `Write` to the zip itself.

## 5. Output

Three-way split per design.md, "A deny splits three ways by audience".
Build every string with `jq --arg`. `<root>` is `root_r`, `<src>` the
source label, `<path>` the payload path as given.

**Deny branch**, `permissionDecision: "deny"`:

- `permissionDecisionReason`: `Refused: <path> is under <root>, which
  this session loads as a plugin (<src>), so Claude Code lets no
  unattended edit land there.`
- `additionalContext`: `Every edit under <root> fails the same way for
  the rest of this session; do not retry it. If <root> is a generated
  copy of a plugin source tree, make the edit in that source tree
  instead. Otherwise tell the user this edit needs a session
  that does not load <root>, and carry on with work outside it.`
- `systemMessage`: `blocked: edit under loaded plugin root <root>
  (<src>)`.

Wording (`craft:directive-writing`). The relaunch is withheld from the
agent, which, told "relaunch without `--plugin-dir`", may spawn
`claude` itself; the human reads which flag or variable to drop from
`<src>`, a fact rather than an instruction (open question 5). No
rename (the brief: it does nothing), and no route around the refusal is
named. Both recoveries are the brief's; "generated copy → edit the
source" is also `dogfood.sh pre-tool`'s ("The source of … is …. Make
the edit there."). Per `plugin-craft:verifying-plugin-changes`,
`claude -c` is a full restart that keeps the conversation, so the
human's relaunch loses nothing and the agent text needs no
reassurance.

**Note branch**: no `permissionDecision`, no `additionalContext`; only
`systemMessage`: `edit under loaded plugin root <root> (<src>) — claude
code asks for each one`. The brief saw the acceptEdits prompt carry no
reason line; this tells the human why it appears.

## 6. Interactions

- **`ask-write-edit-outside-project.sh`**, a root outside the project
  (e.g. `--plugin-dir ~/code/edify/plugin`): in auto, ask + deny → deny,
  no prompt, both `systemMessage`s — right, the edit cannot land. In
  prompting modes this hook only notes; one prompt.
- **`deny-plugin-dev-edit.sh`, `deny-volatile-memory-state.sh`**, a
  root containing `plugin-dev/` or `memory/`: two denies, either reason
  may render, both contexts arrive. No contradiction: the vendored
  redirect points outside the root.
- **`plugin-dev/dogfood.sh pre-tool`** (project settings, root
  `<repo>/dist/plugin`): an edit into the copy gets both denies, and
  ours agrees with dogfood's exact source path. An edit to the source
  passes ours — the point of the copy pattern, pinned in tests.
  Special-casing `dist/plugin` was rejected: it couples to the toolkit
  layout and leaves another project loading that copy unexplained.
- **CC's `.claude`-segment sensitivity** (brief) is another trigger,
  out of scope; the deny names the root it found, never claiming a
  `.claude` prompt.

No hook may assume another has run: registration is not an order.

## 7. Cost

Every `Write`/`Edit` pays it. Measured here: `bash -c true` 14 ms,
`jq -n 1` 31 ms, the walk ≈1.4 ms (50 in-process: 70 ms), an argv read
≈0.2 ms. Common path (no roots): bash, one `jq`, the walk ≈ 50 ms wall,
below each sibling `Write|Edit` hook (two `jq` calls, ~0.1 s in a
loop). Under a root: one more `jq` and a `cd -P` subshell per root.
Nothing cheaper than the mode gate can rule roots out: the argv source
is invisible without the walk.

## 8. Wiring and shared library

- **`scripts/lib/path.sh`** (`# shellcheck shell=bash`): `abspath`,
  moved with its comment. Sourced as
  `. "${BASH_SOURCE[0]%/*}/lib/path.sh"`, the worktree design's idiom;
  the name avoids its `shell-text.sh` and `git-command.sh`.
- **`hooks/hooks.json`**: a new `PreToolUse` block after `Write|Edit`,
  matcher `Write|Edit|MultiEdit|NotebookEdit`, this script only,
  `"timeout": 5` — a separate block keeps the other three scripts off
  `NotebookEdit`. The other agent edits this file: re-read it first.

## 9. Test plan: `tests/deny-plugin-root-edit-test.sh`

Shape of `tests/deny-plugin-dev-edit-test.sh`: `fail()`, a count, a
recap line, stderr merged into the capture.

**Isolation.** `unset CLAUDE_CODE_PLUGIN_DIRS` at the top (this repo's
dogfood session exports it); set `HOME` and `CLAUDE_PROJECT_DIR` per
case. Run **every** call under a fixture `claude`: otherwise the walk
reaches the real session running `just precommit`, whose argv may hold
`--plugin-dir .` (gitlore shim), and verdicts would depend on how my
human partner launched.

**Fixture — production code path, no test-only branch.**
`ln -s "$(command -v bash)" "$work/bin/claude"`: a process exec'd
through it has `comm` `claude` and NUL-exact argv (probed: spaced root
and `--plugin-dir=rel/x` intact, 2 hops). Helper
`run_under <cwd> <payload-file> [claude-args…]`:

```text
(cd "$cwd" && "$work/bin/claude" -c \
  'sh -c "bash \"\$1\"" sh "$1" <"$2"; exit $?' \
  claude-fixture "$hook" "$payload" "$@")
```

`; exit $?` stops bash exec'ing the child, which would replace the
fixture's `comm`; the inner `sh -c` mirrors production's `/bin/sh`.
Without `/proc`, skip argv cases and say so in the recap.

**Cases** — mode `auto` unless stated, `R` a real dir under `$work`.
D = deny, all three channels non-empty; N = note only; P = no output.

| # | Setup | Target | Verdict |
| --- | --- | --- | --- |
| 1 | env `R` | `R/x.sh`, Edit and Write | D, names `CLAUDE_CODE_PLUGIN_DIRS` |
| 2 | env `R` | `R` itself | D |
| 3 | env `R` | `R-sibling/x` | P |
| 4 | env `R` | `$work/o/x` | P |
| 5 | env `A:R`; env `::R:` | `R/x` | D |
| 6 | env `rel` | `$PWD/rel/x` | P |
| 7 | env `~/r`, `HOME=$work` | `$work/r/x` | D |
| 8 | `--plugin-dir R` | `R/x` | D, names `--plugin-dir` |
| 9 | `--plugin-dir=R` | `R/x` | D |
| 10 | `--plugin-dir-no-mcp R`; `=R` | `R/x` | D |
| 11 | `--plugin-dir "$work/My Root"` | `My Root/x`; `$work/My/x` | D; P |
| 12 | `--plugin-dir p`, project `P`, cwd `Q` | `P/p/x`; `Q/p/x` | D; P |
| 13 | as 12, project unset | `Q/p/x` | D |
| 14 | outer `--plugin-dir R`, inner bare | `R/x` | P |
| 15 | outer bare, inner `--plugin-dir R` | `R/x` | D |
| 16 | `-- --plugin-dir R` | `R/x` | P |
| 17 | 9 `bash -c` layers under `--plugin-dir R` | `R/x` | P (cap) |
| 18 | env `L` (→ `R`) | `R/x` | D |
| 19 | env `R` | `L/x` | D |
| 20 | env `R`; outside `S` → `R/y` | `S` | D (`t2`) |
| 21 | env `R`; `R/z` → outside file | `R/z` | D (`t1`) |
| 22 | env `R` | Write `R/new/dir/f` | D |
| 23 | env `R`, cwd `R` | relative `x.sh` | D |
| 24 | env `R`, `dontAsk` | `R/x` | D |
| 25 | env `R`, `default`/`acceptEdits`/absent | `R/x` | N |
| 26 | env `R`, `plan`/`bypassPermissions` | `R/x` | P |
| 27 | env `R` | NotebookEdit `R/n.ipynb`; MultiEdit `R/x` | D |
| 28 | env `R` | tool `Read`, `Bash` | P |
| 29 | env `W/dist/plugin` | `W/scripts/x.sh`; `W/dist/plugin/x` | P; D |
| 30 | bare fixture, env unset | `R/x` | P |

N asserts `systemMessage` non-empty and both `permissionDecision` and
`additionalContext` absent.

**Red check.** Before commit 2, run the suite against a stub that only
reads stdin: every D and N case fails on its verdict assertion. After,
disable each condition in turn and confirm its case reds: env source
(1), argv source (8), `=` form (9), project anchor (12), first-match
(14), `--` (16), `t2` (20), mode gate (25, 26), `notebook_path` (27).
Record it in the changelog, as 2026-10-06 did. `portability-test.sh`
scans the script and lib: no `realpath`, `readlink -f` or `\b`.

## 10. Commit sequence and docs

`just precommit` before each commit.

1. **♻️ Lift `abspath` into `scripts/lib/path.sh`.** Behaviour-
   preserving; `ask-write-edit-outside-project.sh` sources it; no test
   changes; green before and after. That script is outside the other
   agent's modified set — check `git status` anyway.
2. **✨ `deny-plugin-root-edit.sh`.** Script, test, `hooks.json` block,
   docs, changelog.

**Docs in commit 2.** design.md is changing under the worktree work:
re-read it, edit last, recount rather than copy numbers.

- Architecture: the rule/script count and a table row — "Edits under a
  loaded plugin root fail opaquely" | `Write|Edit|MultiEdit|
  NotebookEdit`, target at/below a `CLAUDE_CODE_PLUGIN_DIRS` entry or
  the first `claude` ancestor's `--plugin-dir[-no-mcp]` | deny in
  auto/dontAsk, note in default/acceptEdits | the script.
- The `scripts/lib/` sentence: now also cross-rule helpers; reword to
  fit what the worktree change left.
- Motivation: this hook as a second harness-hazard example; it converts
  no `shared-claude.md` rule.
- "Deny output is stdout + exit 0": recount "All eleven scripts".
- New section "Deny edits under a loaded plugin root in unattended
  modes": §1 with the 2.1.293 stamp, the mode scope, both sources and
  why both, first-`claude`, the relative-root anchor, the dogfood
  composition, macOS, the residuals.
- Limitations: the argv source is Linux-only; no-`/proc` is untested.
- changelog.md: one entry per commit, newest first.

Not here: retiring the memory fact `cc-plugin-dir-edits-sensitive`,
which exists only in edify's mount (triage #8) of another repo's tier.
Propose it there once this hook has been dogfooded.

## 11. Open questions (defaults in force unless overridden)

1. **Mode gating.** The settled reason covers unattended modes; in
   `default`/`acceptEdits` a deny would remove the human's approval,
   and in `bypassPermissions` might block an edit CC allows. *Default:
   deny in `auto`/`dontAsk`, note in `default`/`acceptEdits`/absent,
   silent otherwise.* Deny-everywhere turns rows 25–26 into D.
2. **The note branch.** *Default: keep, `systemMessage` only.*
   Dropping it lets prompting modes exit before the walk.
3. **Relative-root anchor.** Proposed as `/proc/<pid>/cwd`, which the
   bundle shows moving on worktree entry. *Default: `CLAUDE_PROJECT_DIR`,
   fallback `/proc/<pid>/cwd`.* Unverified for a `claude --worktree`
   launch; a hook logging both there would settle it.
4. **macOS argv via `ps -o args=`**, whitespace-split, a value kept only
   when it names an existing directory (spaced roots under-fire).
   *Default: no, env-only.* Revisit if macOS flag launches prove common.
5. **Relaunch hint on `systemMessage`** — an instruction, the exception
   design.md grants `deny-no-verify`. *Default: no; `<src>` suffices.*
6. **Naming a Bash-routed write** ("…here or through another tool").
   *Default: withhold;* add it if dogfooding shows Bash rewrites.
7. **Canary** (brief): a live `claude -p` checking CC itself, to flag
   retirement. *Default: later,* its own recipe outside `precommit`,
   acceptEdits variant only (triage Q3); needs an unsandboxed nested
   `claude`, not run here.
8. **Process naming beyond the native symlink.** An npm/Node install
   (`comm` may be `node`, the title setter may rewrite `cmdline`) and a
   direct exec of the versioned binary (`comm` `2.1.293`) both miss.
   *Default: `comm` = `claude` only;* those fall back to env-only.
9. **Brief items not carried forward:** the `PATH` `bin/` source
   (refuted, triage #7), edify's shim as live trigger (stale, triage
   #9), the triage's `SessionStart` default (overruled). *Default:
   dropped.*
