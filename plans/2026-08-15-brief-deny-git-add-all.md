# Deny `git add -A` / `git add .` — stage named paths instead

2026-08-15

Add a `deny-git-add-all.sh` PreToolUse(Bash) rule refusing whole-tree staging.
"Add all" is sloppy: it stages whatever happens to be in the tree, including
files deliberately left pending — a half-finished sibling edit, a scratch
fixture, a brief written for another repo — and the author only discovers it
after the commit exists.

## Decisions

- Deny `git add -A`, `git add --all`, `git add .`, and the equivalent pathspecs
  `git add :/` and `git add '*'`, in all cases including `git -C <dir> add …`.
- Keep `git add -u` allowed. It is bounded to already-tracked files, cannot
  introduce anything unintended, and is used 4 times in 45 days.
- Keep targeted `git add <path>` allowed, `git add ./path` included — a leading
  `./` on a real path is targeted, only the bare `.` is whole-tree.
- Deny rather than ask. The remedy is mechanical (name the paths), so an ask
  costs a round-trip and teaches nothing.
- Wire it into the existing `Bash` matcher block in `hooks/hooks.json`,
  alongside `deny-no-verify.sh`.

## Evidence

Across 1,190 session transcripts from the last 45 days, 898 `git add` segments:

| form | count | share |
| --- | --- | --- |
| targeted paths | 689 | 76.7% |
| add-all (`-A` / `--all` / `.`) | 204 | 22.7% |
| `-u` (tracked only) | 4 | 0.4% |
| bare `git add` | 1 | 0.1% |

The disciplined form is already the norm at better than three to one. The rule
codifies existing practice rather than imposing a new one, and it would fire
roughly four times a day.

**Independent reinforcement, measured 2026-08-15.** Under Claude Code's command
sandbox, the project root carries 22 paths bind-mounted to `/dev/null` and
stat-ing as character devices — `.bashrc`, `.gitconfig`, `.mcp.json`,
`.claude/skills`, `.claude/hooks`, `.git/config.lock` among them. A sandboxed
`git ls-files --others --exclude-standard` therefore reports 19 untracked paths
in the gitlore repo where the truth is 3. An add-all run in a sandboxed session
stages character devices and masked config paths, and the agent has no signal
that the listing it acted on was fabricated.

This is reinforcement, not the rationale. The rule stands on staging discipline
alone; the sandbox interaction is why the failure is currently silent.

## Constraints

- Strip heredoc bodies and quoted regions before matching, exactly as
  `deny-no-verify.sh` does. A commit message or a prompt string that mentions
  `git add -A` in prose must not trigger a block.
- Match `add` as a word and only as the git subcommand, so `git add-something`
  and unrelated `add` tokens do not match.
- `.` needs regex escaping and a word boundary that survives `git add . && …`
  and `git add .;`.
- `git -C <dir> add -A` must match; the `-C <dir>` operand sits between `git`
  and `add`.
- The deny reason should name the alternative directly: stage the paths you
  mean, or `git add -u` for tracked files only.

## Rejected approaches

- **Denying `git add` outright.** 77% of use is legitimate targeted staging.
- **An ask rule instead of a deny.** The correct action is always the same, so
  a prompt is pure latency.
- **Leaning on the sandbox finding as the justification.** It is real but
  environment-specific, and it would date the rule to a sandbox implementation
  detail rather than to staging discipline.

## Additional context

- House style for the rule script: `scripts/deny-no-verify.sh` — `set -euo
  pipefail`, read stdin, gate on `.tool_name == "Bash"`, strip heredocs and
  quotes, emit `hookSpecificOutput.permissionDecision = "deny"` with a
  `permissionDecisionReason` for the agent and a short `systemMessage` for the
  human.
- Tests follow `tests/<script-name>-test.sh`; every existing rule has one.
  Cover at least: `-A`, `--all`, bare `.`, `:/`, `git -C dir add -A`, and the
  negatives `git add path/file`, `git add ./path/file`, `git add -u`, and the
  flag named inside a quoted commit message.
- Brief naming and evidence-led style follow
  `brief-volatile-state-abbreviated-shas.md`.
