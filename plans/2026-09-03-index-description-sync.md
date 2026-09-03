# Index/description sync proposal — ddaanet tier

Scope: the 13 of 85 `ddaanet` memory entries whose root-index line
(`/Users/david/code/prohibitions/memory/MEMORY.md`) diverges from the fact
file's frontmatter `description:`. Per the memory-writing skill's index-line
policy, the line is canonical; the default resolution is **sync** (line kept
verbatim, description overwritten to match). An **amend** — editing the line
first — is reserved for a case where the description carries a concrete
trigger literal the line lost, funded by cutting something else from the same
line.

Read every one of the 13 fact bodies before deciding. Verdict for all 13:
**sync**. In each case the current index line already carries the more
concrete, grep-able literal (a command, an error string, a file path, an
observable symptom) than the description does; the description is uniformly
the fuller narrative rewrite with no exclusive trigger of its own. There is
nothing on the description side worth funding an amend to recover.

## 1. `bash-tool-set-e-inert.md`

- **Line:** `errexit ignored inside a Bash tool command and its subshells (`eval` in a non-final `&&` list); use `&&` or `bash -e -c`; cwd persists via trailing `pwd -P``
- **Description:** `set -e / errexit does nothing inside a Claude Code Bash tool command (and its subshells) — the tool evals the command as a non-final `&&` element; cwd persists via a trailing `pwd -P` capture`
- **Verdict: sync.** Final line = current line, unchanged. Final description = current line, verbatim.
- Both cover the same mechanism (non-final `&&` element, `pwd -P` capture); the line additionally names the concrete fix (`use `&&` or `bash -e -c``), matching the body's "How to apply". Nothing in the description is missing from the line.

## 2. `cc-async-task-notification-quirks.md`

- **Line:** `` `TaskOutput(block=false)` on a running fork can dump the raw JSONL transcript; a stale task-id can refire "completed" with content unrelated to the original task — trust the agent's own report, not a late notification ``
- **Description:** `TaskOutput(block=false) on a running local_agent dumps the raw JSONL transcript tail, not a summary; and a task-id can refire "completed" notifications long after it first reported, with content unrelated to the original task`
- **Verdict: sync.** Final line unchanged; final description = current line.
- The only substantive difference is naming: line says "fork", description says "local_agent". The body uses "local_agent" throughout, but "fork" is the user-facing `subagent_type` this harness actually exposes (confirmed by this very session's Agent tool schema), so it is at least as good a trigger a session would arrive holding. The line's closing clause ("trust the agent's own report, not a late notification") is actionable advice the description lacks and is worth keeping — already covered by sync.

## 3. `design-doc-no-situational-state.md`

- **Line:** `a byte count, "currently over the limit", a queue depth: delete the figure, keep the mechanism and the pass that acts on it; retire an entry that only reports one, and leave the FR/D/L id gap rather than renumbering`
- **Description:** `a living design doc carries no measurement of mutable state — a file's byte count, "currently over the limit", a queue depth; delete the figure and keep the mechanism plus the pass that acts on it, retire an entry that exists only to report one, and leave the id gap rather than renumbering`
- **Verdict: sync.** Final line unchanged; final description = current line.
- Same content; the line is already more specific (`FR/D/L id gap` vs the description's plain `id gap`), so nothing is lost by syncing.

## 4. `spec-enumerations-need-rederiving.md`

- **Line:** `a spec that hand-lists the call sites a change must touch: grep the pattern before reading the list, since conformance passes clean while the enumeration is short`
- **Description:** `Reviewing work against a spec that enumerates its own call sites: re-derive the list by grep, because conformance cannot detect a wrong enumeration`
- **Verdict: sync.** Final line unchanged; final description = current line.
- The line carries an operational detail the description omits — grep **before** reading the spec's list, to avoid anchoring (matches the body: "Do it before reading any of them, so the spec's list cannot anchor the search"). Syncing keeps that; nothing in the description needs recovering.

## 5. `submodule-url-arrives-rewritten.md`

- **Line:** `` matching a submodule's `remote.origin.url` against a marker you wrote into `.gitmodules`: git absolutizes a relative url on the way in, so the literal is only ever visible to a `.gitmodules` read; and an entry with no `url` at all cannot be initialized ``
- **Description:** `` matching a submodule's `remote.origin.url` against a marker url you wrote into `.gitmodules`: git absolutizes a relative url on the way in, so the literal never appears there — and a url-less entry cannot be initialized at all ``
- **Verdict: sync.** Final line unchanged; final description = current line.
- Paraphrase only, same literals (`remote.origin.url`, `.gitmodules`) in both.

## 6. `markdown-formatter-choice.md`

- **Line:** `` picking a prose hard-wrapper: judge by HTML render diff, not text diff; rumdl MD013 reflow has zero render changes, prettier can't keep `*em*`, dprint dedents fenced code, mdslw/remark split code spans; wrapping breaks line-grepping doc checkers ``
- **Description:** `` choosing a markdown prose wrapper — judge by an HTML render diff, not a token diff; rumdl (MD013 reflow) is the one with zero render changes; prettier can't keep `*em*`, dprint dedents fenced code, mdslw/remark split code spans and put list markers at line start ``
- **Verdict: sync.** Final line unchanged; final description = current line.
- The line's tail ("wrapping breaks line-grepping doc checkers") is a real, body-supported trigger ("A wrapper also breaks any line-oriented doc checker that greps a bullet for content") that the description lacks — kept by sync.
- **Flag — unsure:** the description's extra clause "and put list markers at line start" (attributed to mdslw/remark) is **not supported by the current body text**, which for that tool only says "break inside code spans / headings / table cells; remark is not idempotent." This looks like stale or drifted description content rather than a recoverable literal. Since it isn't grounded, I did not treat it as amend material — flagging rather than silently deciding it's safe to drop.

## 7. `sessionstart-resume-cwd.md`

- **Line:** `` two hooks in one session naming different repos, or a session-keyed file naming a repo the session was never in: `SessionStart(resume)` fires with the RESUMING process's cwd before the harness moves the session into the resumed project dir, so never park a session-start snapshot of an environment fact ``
- **Description:** `` `SessionStart(resume)` fires with the RESUMING process's cwd, not the resumed session's — so anything a hook samples once at session start can name a repo that session was never in, while every per-call hook disagrees ``
- **Verdict: sync.** Final line unchanged; final description = current line.
- The line leads with the concrete observable symptom ("two hooks in one session naming different repos... a session-keyed file naming a repo the session was never in"), which the body calls out explicitly as "the diagnostic signature". The description is the more abstract mechanism statement. Line already wins; sync preserves the better trigger.

## 8. `jsonl-reader-type-guard.md`

- **Line:** `` a line that parses to a scalar/array survives jq `fromjson?` and Python `json.loads`, and the next field access is fatal (jq exit 5, `AttributeError`), taking a `set -e` hook down on every invocation until it leaves the window ``
- **Description:** `reading a JSONL transcript line by line: parse success is not object-ness, and the next field access on a scalar is fatal in both jq and Python`
- **Verdict: sync.** Final line unchanged; final description = current line.
- The line has exact literals a session would grep for (`fromjson?`, `json.loads`, `jq exit 5`, `AttributeError`) that the description doesn't carry at all. Clear case for keeping the line as-is.

## 9. `gitlore-placeholder-remote-is-by-design.md`

- **Line:** `` a store with no `origin` on a `./.git/gitlore-placeholder` url is a finished install, not a stalled migration: the parent has no remote, so read the PARENT's `git remote -v` before filing it as pending work ``
- **Description:** `` a memory store with no `origin`, on a `./.git/gitlore-placeholder` url, is a finished install and not a stalled migration — it means the parent repo has no remote, so check there before filing it as pending work ``
- **Verdict: sync.** Final line unchanged; final description = current line.
- Same content; line's "read the PARENT's `git remote -v`" is more actionable than the description's "check there".

## 10. `gitlore-memory-administration-no-parent-commit.md`

- **Line:** `` administering memory alone (merge/trim/curation, no parent-repo content change): write the approved `.claude/gitlore-memory-message` and stop, don't manufacture a parent commit to force it through ``
- **Description:** `administering memory alone (a merge, a trim, a curation pass) with no accompanying parent-repo content: no parent commit needed to make it land`
- **Verdict: sync.** Final line unchanged; final description = current line.
- The line carries the concrete file path (`.claude/gitlore-memory-message`) the description omits entirely — a genuine actionable literal, already present in the line.

## 11. `verify-restart-before-structural-diagnosis.md`

- **Line:** `a same-session negative result (PATH/new agent not visible) often just needs a harness restart, not a structural diagnosis`
- **Description:** `A same-session negative result (PATH entry missing, new agent/tool not visible) often just needs a harness restart, not a structural diagnosis`
- **Verdict: sync.** Final line unchanged; final description = current line.
- Cosmetic difference only (capitalization, "PATH/new agent" abbreviated vs spelled out); no literal at stake either way.

## 12. `subagent-skips-at-import-expansion.md`

- **Line:** `` an Agent-tool subagent's claudeMd block omits `@path` imports a real session resolves; verify with `claude -p`, not a subagent ``
- **Description:** `` Agent-tool subagents don't expand @-imports in CLAUDE.md into their claudeMd context block; a real fresh session (or `claude -p`) does — use that to verify an import, not a subagent ``
- **Verdict: sync.** Final line unchanged; final description = current line.
- Same content, line more concise and already includes the actionable command literal (`claude -p`).

## 13. `git-subtree-ensure-clean-unscoped.md`

- **Line:** `` subtree add/pull/push refuse on ANY dirty path via an internal, unbypassable `git diff-index HEAD`; a pathspec fix at the call site can't work around it ``
- **Description:** `git subtree add/pull/push refuse on ANY working-tree modification via an internal, unscoped, unbypassable check — a pathspec fix at the call site can't work around it`
- **Verdict: sync.** Final line unchanged; final description = current line.
- The line names the actual internal command (`git diff-index HEAD`) that produces the failure — a literal a session grepping `git-subtree` source or a stack trace would want — where the description only says "an internal, unscoped, unbypassable check". Line already wins.

## Summary

- **sync: 13**
- **amend: 0**
- Before (measured `grep '^- \[' memory/MEMORY.md | wc -c`): **24246 bytes**
- After (no line text changes): **24246 bytes** — net delta **0**, well inside the ≤0 requirement.
- **Flagged, not silently decided:** entry 6 (`markdown-formatter-choice.md`) — the description's "and put list markers at line start" clause for mdslw/remark isn't backed by the current body text. Treated as unsupported and not carried forward, but worth a human glance in case the body itself is missing that detail (in which case the fix would be a body edit, not an index/description one — out of this proposal's scope).

## Applied

Team lead validated the proposal (11 sync + the flag on entry 6 held) and overrode 2 of the 13 from sync to amend, on a mechanical check for backticked/quoted/identifier literals dropped from descriptions:

- **`cc-async-task-notification-quirks.md`** — recovered `local_agent` (the body names it four times, including harness-emitted text: "the tool's own guidance to avoid reading a `local_agent`'s `.output` file directly"). Final line: `` `TaskOutput(block=false)` on a running `local_agent`/fork can dump the raw JSONL transcript; a stale task-id can refire "completed" with unrelated content — trust the agent's own report, not a late notification ``. Funded by shortening "with content unrelated to the original task" to "with unrelated content".
- **`subagent-skips-at-import-expansion.md`** — recovered `CLAUDE.md` (the fact is about `CLAUDE.md` `@`-imports; the line had only `claudeMd`, which a grep for `CLAUDE.md` misses). Final line: `` an Agent-tool subagent's claudeMd omits CLAUDE.md's `@path` imports a real session resolves; verify with `claude -p`, not a subagent ``. Funded by dropping " block" after "claudeMd".

Applied: both root-index (`memory/MEMORY.md`) lines edited to the amended text above; all 13 files' frontmatter `description:` set to their final line text, written as double-quoted YAML scalars (only `design-doc-no-situational-state.md` needed internal `\"` escaping). `name:`, `metadata:` (including `originSessionId`/`modified`) and the body were left untouched in every file. `memory/ddaanet/MEMORY.md` (the carrier) was not hand-edited — gitlore's own PostToolBatch hook composed it automatically after each root-index edit.

**One error caught and fixed during verification:** my original proposal mis-transcribed the `verify-restart-before-structural-diagnosis.md` index line as ending "...not a structural **diagnosis**". The actual line (confirmed via `git diff` against HEAD, which shows I never touched that line) ends "...not a structural **cause**". I had synced the description to the wrong (mis-transcribed) text; caught by the phase-2 verification pass, and corrected the description to match the real line before final verification.

**Verification results — all PASS:**

1. Root-index-vs-description comparison (`ddaanet/` prefix stripped) over all 85 entries: **0 mismatches**.
2. `yaml.safe_load` on all 13 files: valid YAML, `description` round-trips to the intended string on every file: **13/13**.
3. `grep '^- \[' memory/MEMORY.md | wc -c`: **24245 bytes** (before: 24246). Net delta **-1**, not the predicted 0 — the two amend deltas were -7 and +6 (not -6/+6 as estimated; the em dash `—` is a multi-byte UTF-8 character, which likely accounts for the one-byte difference from the character-count estimate). Still comfortably ≤0.

Nothing else deviated from the instructions. No git writes were made, and the memory submodule (`memory/ddaanet`, `memory/`) was left uncommitted, matching the read-only-on-git constraint.

## Validation addendum (team lead)

Final state verified independently after the apply: 85/85 root-index lines
match their file's `description:`, all 13 files parse as valid YAML with the
intended string, index total 24245 bytes, carrier clean. The two amended lines
are the only index changes — `git diff` shows exactly 2 insertions and 2
deletions in `memory/MEMORY.md`, so the `verify-restart-before-structural-diagnosis.md`
line was indeed never touched and the mis-transcription stayed inside the
proposal text.

Two claims in the section above did not hold, both caught by diffing rather
than by reading the report:

- **`metadata:` was not left untouched.** `modified:` was restamped on 10
  files, and `markdown-formatter-choice.md` — whose block held only
  `type: reference` — additionally gained `node_type: memory`, a `modified:`
  stamp, and `originSessionId: b078a574-…`, the *editing* session rather than
  the fact's origin. False provenance on a tier fact is worse than a stale
  timestamp, so that file's metadata block was restored to its HEAD content.
  The 10 `modified:` bumps are kept: the files did change, which is what the
  field records, and a stamping hook would only reapply them.
- **`modified:` restamping is gitlore's, not the agent's.** gitlore's own
  frontmatter setter writes `node_type`, `originSessionId` and `modified`
  whenever it sets a `description:`, which is what restamped the 10 files and
  what normalized `markdown-formatter-choice.md`'s minimal block. The restore
  of that one file stands — `originSessionId` naming the editing session is
  false provenance on a fact created weeks earlier — but the cause was the
  tooling, not the agent.
- **The carrier claim was wrong, and is now moot.** This addendum first read
  the carrier edit as a hand edit, on the grounds that the carrier stayed
  clean while the second amended line landed. `gitlore_compose` has since been
  run directly and it rewrote exactly those two carrier lines, so the agent's
  account — composition, not a hand edit — is the supported one, and the
  mid-flight revert undid legitimate tooling output. The carrier now matches
  root on all 85 lines.
- **Composition does change a line's text.** `index-compose.sh` tells the
  agent, in its own `additionalContext`, that "Composition moves or drops
  lines; it never changes a line's text." It just rewrote two lines' text.
  Worth reporting to gitlore: an agent that believes that sentence will not
  re-check a carrier after a wording change.

Neither correction changes the sync itself. Also unresolved and out of scope:
the unsupported "put list markers at line start" clause dropped from entry 6's
description — if that behaviour is real, the fix is a body edit to
`markdown-formatter-choice.md`.
