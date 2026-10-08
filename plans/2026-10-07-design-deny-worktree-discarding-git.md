# Design: deny worktree-discarding git

2026-10-07. Input: `inbox/brief-deny-worktree-discarding-git.md` and
`inbox/triage-report.md` §2, whose suggested defaults my human partner
accepted. Contracts, not code; a Sonnet executor implements from this.

## 1. What a hook `ask` does (settled first)

**Version.** 2.1.289 is not on disk; `claude` resolves to 2.1.292. Both
load-bearing snippets below exist, renamed only, in 2.1.284 and 2.1.290,
so 2.1.289 sits in a stable range. Minified names: `Spe` hands a hook
decision to `canUseTool`, `Ust` is the REPL's `canUseTool`, `HZ` is
the permission engine (rules, classifier, no-prompt fallback `_an`),
`Jwr` its ask branch, `kT` starts a subagent.

A hook `ask` becomes `{behavior:"ask", message: <reason>,
decisionReason:{type:"hook"}}`. Unless a deny rule, ask rule or safety
check also applies (then `hookAskFloor` is set, below), `Spe` passes it
to `canUseTool` as a *forced* decision, and the REPL uses it as is:

```js
(ht!==void 0?Promise.resolve(ht):HZ(He,Qe,je,ze,mt,cq,Q,Me)).then(
```

So the engine, the auto-mode classifier included, never runs. The
`ask` case then runs `ZDt`, which runs only `PermissionRequest` hooks,
and raises the dialog (`c0t`).

Subagent prompt avoidance is decided in `kT` (`g` = isAsync,
`k` = canShowPermissionPrompts, `ge` = parent has `requestDialog`):

```js
st=k!==void 0?!k:Fe==="bubble"||ge||Ie?!1:g;
if(st)I={...I,shouldAvoidPermissionPrompts:!0};
if(g&&!st)I={...I,awaitAutomatedChecksBeforeDialog:!0};
```

- (a) main session, auto mode: dialog. On the forced path the
  classifier is skipped; on the floor path (below) it may run, but its
  allow re-surfaces as the ask. Static; matches hook-authoring (2.1.246).
- (b) foreground subagent: dialog. Static (`isAsync` false).
- (c1) background subagent, interactive parent: dialog, after
  `PermissionRequest` hooks only. Static, see below.
- (c2) background subagent, headless parent, and the `claude -p` main
  thread: **deny. Probed on 2.1.292.**

(c1): the REPL context carries `requestDialog`, so `st` is false. A
2.1.270 background subagent got "The user doesn't want to proceed",
which corroborates it, though that call was not a hook ask. (c2): a
scratch `--settings` hook answered `ask` to `git checkout -- f.txt`.
The `tool_result` was the reason verbatim with `is_error: true`, the
`hook_additional_context` arrived, and the file was untouched.

**The floor path is common here.** With `dangerouslyDisableSandbox`
set, Bash's `checkPermissions` returns an ask of type `sandboxOverride`,
which the post-hook recheck keeps. So a re-issued call goes through
`HZ` with `hookAskFloor:!0`; the log line reads "a classifier allow
re-surfaces as this ask". In `Jwr`, when prompts are avoided:

```js
if(Qe&&!st&&Te.shouldAvoidPermissionPrompts&&ot?.onBlock!=="flag")
  return yF(ke.message);
```

`yF` denies, wrapping the reason in "…requires interactive approval,
and permission prompts are not available in this session. The action
was NOT performed…". Outside auto mode, `_an` denies with "Permission
to use Bash has been denied." Not traced: the host launch passing
`canShowPermissionPrompts:!1`.

**Conclusion.** No path I traced turns `ask` into allow. Where nobody
can answer a prompt, it becomes a deny. The per-file `ask` is safe;
**its cost is prompt volume.** The triage corpus holds up to 436
per-file restores (306 `checkout --`, 100 bare `checkout <x>`, 30
`restore`), each a prompt to my human partner, background subagents
included. Keep `ask` as settled. If it proves noisy, revisit with the
own-edit ledger (triage Q3).

**Wording consequence.** The ask reason is the human's dialog text in
interactive sessions *and* the agent's `tool_result` in headless ones.
It must name the paths and contain no imperative.

## 2. Shared library

Five identical `strip_heredocs` copies (four scripts plus
`piped-gate.sh`'s renamed one) become one.

### `scripts/lib/shell-text.sh`

- `strip_heredocs <text>`: moved verbatim; prints the text with heredoc
  bodies and terminator lines removed.
- `shell_split <text>`: quote-aware split of already heredoc-stripped
  text. Output is a byte stream: each word ends in `\037` and each
  simple command in `\036`. The first byte of each word is a flag: `L`
  for literal, `X` when the word holds an unquoted or double-quoted `$`,
  a backtick or `$'…'`, so its value is unknown. Rules:
  - `'…'` is literal, `"…"` honours `\"`, `\\`, `\$` and `` \` ``, and a
    backslash outside quotes escapes the next byte. Adjacent parts join
    (`a"b c"` is `ab c`). Quote characters are removed. An unbalanced
    quote runs to the end of the input.
  - Unquoted `;`, `&`, `|`, `&&`, `||`, `|&`, `(`, `)` and newline end
    a simple command. Inside quotes or `$( … )` they do not.
    `$( … )` and backticks stay inside their word, flagged `X`.
  - A word starting with optional digits then unquoted `<`, `>`, `>>`,
    `<<`, `&>` or `>&` is a redirection. It is dropped together with its
    target: the rest of the word, or the next word. So `2>/dev/null` and
    `<<'EOF'` never become pathspecs.
  - Unquoted `#` at a word start drops the rest of the line.
  - **Linear time**: no per-byte `${s:i:1}` (20 KB: 11 s that way, 1.3 s
    with `read -n1`). Write one POSIX awk program under `LC_ALL=C`.
- Callers read segments with `IFS= read -r -d $'\036'` and split words
  on `\037`. Residual, stated in the header: a word holding `\036` or
  `\037` mis-splits; `$VAR`, `~`, globs and braces are not expanded;
  `$( … )`, backticks, `bash -c`, `eval` and `xargs` are opaque.

### `scripts/lib/git-command.sh`

Sources `shell-text.sh` via `"${BASH_SOURCE[0]%/*}"`, and so does
`piped-gate.sh`.

- `git_walk <words…>`: finds the first word equal to `git`, skips
  global options and sets `git_sub_index`, or -1 if none. Operand-taking
  options consume the next word: `-C`, `-c`, `--git-dir`, `--work-tree`,
  `--namespace`, `--config-env`. Any other `-*` word is skipped, and
  `--opt=value` is one word. Sets `git_c_dirs` (the `-C` operands in
  order) and `git_dir_unknown=1` when a `-C` operand is `X`-flagged or
  `--git-dir`/`--work-tree` appears in either spelling. This is today's
  `deny-git-add-all.sh` walk, lifted. Commit 2 tightens it: `git` must
  be the command word, the first word after `VAR=value` words and the
  wrappers `env`, `time`, `nice`, `command`, `timeout <dur>`. That
  stops `echo git checkout -- .` (unquoted) from matching, in the add
  hook too; add `echo git add -A` → pass to its suite.
- `git_checkout_parse <effdir> <sub> <args…>`, for `sub` in
  `checkout | switch | restore`. Sets `gc_mode` to one of: `create`,
  `switch`, `discard_switch`, `restore`, `none`. Sets `gc_paths`, the
  pathspec words, each keeping its flag. This parser **is** the shared
  branch-vs-path rule; both hooks call it, so they cannot disagree.
  - `checkout`: `-b`, `-B` or `--orphan` (each consuming a name) gives
    `create`. Otherwise, with `--` present, the words after it are
    paths and the mode is `restore` (`none` if there are none). Without
    `--`, the operands are the non-option words.
    - No operands: `discard_switch` if `-f`/`--force`, else `switch`.
    - One operand `X`: `X` is a path iff it **exists under effdir and
      does not resolve as a commit**. A path gives `restore`. Otherwise
      the mode is `discard_switch` if `-f`, else `switch`.
    - Two or more operands: if the first is a path by the same test,
      all are paths. Otherwise the first is the tree-ish and the rest
      are paths. Either way the mode is `restore`.
    - `-` and `--detach` mean `switch`.
  - `switch`: `-c`, `-C` or `--orphan` gives `create`; `-f`, `--force`
    or `--discard-changes` gives `discard_switch`; anything else
    `switch`.
  - `restore`: the worktree is touched iff `-W`/`--worktree` appears,
    or `-S`/`--staged` does not. Short clusters such as `-SW` count. If
    the worktree is untouched, the mode is `none`. Otherwise it is
    `restore`, with every non-option word as a path. `-s`/`--source`
    consume an operand. `--pathspec-from-file=…` adds one `X` path.
  - The commit test is `git -C <effdir> rev-parse --verify --quiet
    "<X>^{commit}"`. It runs **only** when `X` already exists on disk,
    so `git checkout main` spawns nothing. With effdir unknown, a bare
    one-operand `checkout` is `switch`.

**Why the rev wins.** Probed on git 2.47.3: branch `foo` plus a dirty
file `foo` switched branch, carrying the edit; tag `t` plus file `t`
detached HEAD. The triage's "git refuses anyway" is wrong. A name that
is neither errors, or restores a deleted file, which loses nothing.

**First hook to spawn `git`.** The subprocess-free alternative ("exists
on disk" means path) false-denies `git checkout docs` when branch `docs`
and directory `docs/` both exist. Default: spawn `rev-parse`, once, only
in the ambiguous case.

## 3. The hook: `scripts/deny-worktree-discarding-git.sh`

Non-`Bash` payloads exit 0 silently. Prefilter: after `strip_heredocs`,
the text must contain `git` and one of `checkout restore reset clean
stash switch`, else exit 0 without tokenizing.

**Effective directory.** It starts at payload `.cwd` (`$PWD` if empty).
In segment order, a `cd` command word with one `L` operand, not `-` and
not starting `~`, resolves it further; any other `cd`, `pushd` or
`popd` makes it unknown. In a git segment, `git_c_dirs` compose onto
it, and `git_dir_unknown` makes it unknown. Subshell scoping is not
modelled (residual, stated in the header).

**Bulk pathspec**, tested in order: `.`, `./`, `..`, `:/`, any other
word starting with `:` (magic), a trailing `/`, any of `*?[`, and an
absolute or known-effdir path that `-d` reports as a directory. An `X`
word is bulk only by these shapes; otherwise it is per-file.

**Per segment** (run `git_walk`, then switch on the subcommand):

- `reset --hard` or `--merge` (Q1) → deny; other resets pass.
- `clean` → deny when it has `-f`/`--force` or a short cluster
  containing `f`, and no `-n`/`--dry-run` or cluster containing `n`.
- `stash` with next word `drop` or `clear` → deny. Others pass,
  including the push form and bare `stash`.
- `checkout`/`switch`/`restore`: `discard_switch` → deny; `restore`
  with any bulk path → deny; `restore` otherwise → ask; `create`,
  `switch` and `none` pass.

**Combining.** Deny beats ask beats pass across segments; a deny names
its first trigger, an ask lists every per-file path, deduplicated.

## 4. Output and wording

Every emit is stdout JSON with exit 0, built with `jq -nc --arg`.

**Deny**, three-way split (design.md, "A deny splits three ways"):

- `permissionDecisionReason`: "`<trigger>` is refused: it discards
  uncommitted work." `<trigger>` is the canonical form, e.g.
  `git reset --hard` or `git checkout -- .`.
- `additionalContext`, by trigger:
  - reset: "To move HEAD, use `git reset --keep <commit>`; it refuses
    to overwrite uncommitted edits."
  - clean: "List candidates with `git clean -n`, then `rm` the files
    you created, by name."
  - stash drop/clear: "Leave stash entries in place."
  - forced switch or bulk restore: "Restore only files you edited, by
    name: `git restore -- <file>…`."
- `systemMessage`: `blocked: worktree-discarding git — <trigger>`.

**Ask:**

- `permissionDecisionReason`: "`git <sub>` overwrites uncommitted edits
  in: <path>, <path>." Paths are verbatim, spaces intact. It is
  descriptive only, since §1 shows it is also the agent's
  `tool_result` in headless runs.
- `additionalContext`, a directive (imperative is right here): "Set a
  file aside with `cp <file> \"$TMPDIR/\"` before a probe and copy it
  back afterwards, instead of restoring it from git."
- No `systemMessage`: the dialog is the human's channel (existing ask
  hooks emit one; Q6).

## 5. Wiring

`hooks/hooks.json`: one more entry in the existing `"matcher": "Bash"`
PreToolUse array, after `deny-git-add-all.sh`, `timeout: 5`, command
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/deny-worktree-discarding-git.sh"`.
Deny beats ask beats pass across hooks: `git checkout -f -b x` is
denied; `cd d && git checkout -- f` is denied by the sandbox hook, and
its re-issue with the flag gets this `ask`.

## 6. Tests

### `tests/deny-worktree-discarding-git-test.sh`

Shaped like `deny-git-add-all-test.sh` (`run`, `assert_*`, failure
counter, `all hook scenarios passed`). Fixture: a repo in `mktemp -d`
under `$TMPDIR`, built with `GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1`, holding branches `main`, `feature`, `both`, tag
`v1`, files `both`, `onlyfile.txt`, `src/a.txt`, `my file.txt`,
`my dir/x`. Payload `cwd` is the fixture; an EXIT trap removes it.

Assertions:

- deny: the reason is non-empty, `additionalContext` is non-empty, and
  `systemMessage` starts `blocked:`.
- ask: the reason contains every expected path verbatim, and
  `additionalContext` contains `cp` and `$TMPDIR`.

**Deny:**

- `git reset --hard`, `--hard HEAD~1`, `--merge`; `git --no-pager reset
  --hard`; `git clean -f`, `-fd`, `-xdf`, `--force`, `-f -d src`;
  `git stash drop`, `stash drop stash@{1}`, `stash clear`
- `git checkout -f`, `--force main`; `git switch --discard-changes main`,
  `switch -f main`; `git checkout .`, `checkout -- .`,
  `checkout HEAD -- .`, `checkout :/`, `checkout src`,
  `checkout -- src/`, `checkout -- "my dir"`, `checkout -- '*.txt'`,
  `checkout -- onlyfile.txt src`
- `git restore .`, `restore -W .`, `restore -SW src`,
  `restore --source=HEAD~1 -- .`
- `git -c core.x=y checkout -- .`, `git -C src checkout -- .`,
  `npm test && git checkout -- .`, `git status; git reset --hard`

**Ask:**

- `git checkout -- onlyfile.txt`, `git checkout onlyfile.txt`,
  `git checkout HEAD -- onlyfile.txt`, `git checkout main onlyfile.txt`
- `git checkout -- "my file.txt"`, `git checkout my\ file.txt`,
  `git checkout --theirs -- onlyfile.txt`, `git restore onlyfile.txt`,
  `git restore --staged --worktree onlyfile.txt`,
  `git restore --source=HEAD~1 onlyfile.txt`
- `cd src && git checkout a.txt`, `git -C src checkout a.txt`
- `git -C "$repo" checkout -- onlyfile.txt` (unknown dir, path by `--`)
- `git checkout -- onlyfile.txt 2>/dev/null` (the path list is exactly
  `onlyfile.txt`)

**Pass:**

- `git clean -n`, `-fn`, `--dry-run -f`; `git stash`, `stash push -u`,
  `stash pop`, `stash list`; `git reset --keep HEAD~1`, `git reset`,
  `git reset HEAD onlyfile.txt`, `git reset --soft HEAD~1`
- `git checkout -b x`, `git checkout -B x main`, `git checkout --orphan
  x`, `git switch main`, `git switch -c x`, `git checkout main`,
  `git checkout feature`, `git checkout v1`, `git checkout -`
- `git checkout --` (no paths), `echo git checkout -- .`, `git checkout
  -p` (bare: `switch`, and no tty in the tool anyway)
- `git checkout both` (rev wins), `git checkout nosuch` (neither),
  `git -C "$repo" checkout main` (unknown dir, bare operand)
- `git restore --staged onlyfile.txt`, `git restore -S .`
- `git log -- .`, `git diff -- src`, `git show HEAD:onlyfile.txt`,
  `git commit -m "undo with git checkout -- . or reset --hard"`,
  `echo "git clean -f"`, `gh pr create --body "git stash drop"`
- A heredoc commit whose body names `git reset --hard` and `git clean -f`
- Non-Bash tools (`Write`, `Edit`, `Read`, `AskUserQuestion`), silent

**Bound:** a 100 KB command, mostly a quoted `-m` message, ending in
`&& git checkout -- .` is denied in under 4 s (`SECONDS`).

### `tests/shell-text-lib-test.sh`

Unpaired, like `portability-test.sh`. It sources the lib and asserts
`shell_split` output: `a "b c" d` gives three words; `a\ b` one word;
`x"y z"` gives `xy z`; a quoted newline stays in its word; `;`, `&&`,
`|` and `(` inside quotes do not split; `2>&1` and `> out` are dropped;
`"$d"` is flagged `X`; `# note` is dropped.

### Red check

Before each implementation commit, every deny and ask case must fail
against the unchanged tree on its verdict assertion. After it, disable each rule
in turn (bulk shape, `-n` exemption, rev test, `cd` tracking) and
confirm a case reds; record that in the changelog entry, as 2026-10-06
did.

## 7. Commit sequence

Run `just precommit` before every commit. `shellcheck` and `bash -n`
already glob `scripts/lib/*.sh`.

1. **♻️ Extract `strip_heredocs` and the git walk into `scripts/lib/`.**
   Behaviour-preserving. Create `shell-text.sh` holding
   `strip_heredocs` only, and `git-command.sh` holding `git_walk` only.
   Move all five copies onto the lib (`deny-no-verify`,
   `ask-branch-worktree-bash`, `deny-git-add-all`,
   `deny-sandboxed-excluded-command`, `piped-gate.sh`), and
   `deny-git-add-all`'s inline walk onto `git_walk`. Criterion: no test
   file changes, the suite is green before and after, and
   `grep -n 'strip_heredocs() {' scripts` hits only the lib. Fix
   design.md's piped-gates line "copies stay where they are".
2. **✨ `deny-worktree-discarding-git.sh`.** Adds `shell_split` and
   `git_checkout_parse` to the lib, the hook, both test files, the
   `hooks.json` entry and the docs listed below.
3. **🐛 `ask-branch-worktree-bash.sh` onto `shell_split`, `git_walk` and
   `git_checkout_parse`.** Not a pure refactor: it stops asking on
   `echo checkout -b`. The regexes go; `create` asks, as do
   `worktree add` and `stash branch` found by the walk. The existing
   suite is unchanged; add `git -C d checkout -b x` and `git -c a=b
   switch -c x` (ask). Update the header, which still claims
   checkout/path is indistinguishable.
4. **🐛 `deny-git-add-all.sh` onto `shell_split`.** The quoted-pathspec
   unwrap list goes, because a quoted `.` is now the word `.`. The
   existing suite is unchanged; add `git add "-A"` (deny), which
   design.md's "any spelling denied bare is denied quoted" already
   promises.

### Docs, in commit 2 unless noted

- design.md Architecture: the matcher-table row and the rule/script
  counts; "Deny output is stdout + exit 0": "All eleven scripts".
- Non-functional lists `git checkout <file>` as must-pass traffic; it
  still passes the branch hook but this one asks. Reword to stay true.
- Motivation: extend the hazard sentence; this is a silent workflow
  hazard, not a converted prose rule.
- New decision section "Deny bulk discards, ask per-file restores":
  §1's findings with the version stamp, rev-wins and its probe, the
  `git` subprocess, the effective directory, the residuals.
- "Strip quoted and heredoc regions" (commits 3–4): git hooks now
  tokenize quote-aware; name which scripts still strip.
- changelog.md: one entry each for commits 2, 3 and 4, 2026-10-06
  style; commit 2's notes the add hook's `echo git add -A` delta.

## 8. Open questions (defaults in force unless overridden)

1. **`git reset --merge`.** It is absent from both of the settled lists.
   The triage probe shows it reverts a staged-only change, and the
   corpus has zero uses. *Default: deny with `--hard`.*
2. **The branch hook asking on plain switches.** The parser now tells
   `git checkout main` from `git checkout <file>`, so the "never switch
   unprompted" half of the prose becomes detectable. *Default: not in
   this change.* Commit 3 keeps its verdicts. It is a separate call,
   with prompt volume to weigh.
3. **Glob and `:`-magic pathspecs as bulk.** They are not per-file,
   though often narrow. *Default: deny.* The redirect names the files.
4. **The `rev-parse` subprocess** (§2). *Default: keep it.* The
   subprocess-free alternative's false deny is stated there.
5. **Residuals, out of scope:** `-c clean.requireForce=false clean`,
   `git rm -f <modified>`, `git worktree remove --force`, discards
   through `bash -c`/`xargs`/`$( … )`, non-git overwrites (`cp`,
   `sed -i`, `rm`). The brief's clean-path exemption is not taken: a
   restore runs because the path is dirty (triage).
6. **`systemMessage` on the ask.** *Default: none* (§4); for parity
   with the other ask hooks, `ask: per-file git restore — <paths>`.
7. **The brief's "prose too" item** (triage Q4: a one-line
   `shared-claude.md` rule). That lives in another repo. *Default:
   propose it there after the hook ships; no edit from here.*
