# `deny-volatile-memory-state` never fires — widen it to abbreviated shas

`scripts/deny-volatile-memory-state.sh` matches `\b[0-9a-fA-F]{40}\b`. Measured
against a real memory store of 165 files, that pattern has **zero** true
positives available to it — the store contains no full shas at all — while it
misses **four** commit ids that are live violations of the rule it enforces.

The header justifies the narrow scope as "abbreviated hex would false-positive
on ordinary prose". That is the claim this brief disputes, with numbers.

## The dictionary surface is six words

Words spellable in a-f only are a solved enumeration; the canonical generated
list is at <https://alecjacobson.com/weblog/475.html> (a regex over an English
word list). Of its 161 entries, those of length ≥5 number 47, and of length ≥7
number six: `Fabaceae`, `acceded`, `deedeed`, `defaced`, `effaced`, `facaded`.

A closed 47-word set is a whitelist, not a reason to abandon a check.

## The corpus surface, which is what settles it

Scanning a 165-file store, frontmatter excluded, for `\b[0-9a-f]{5,40}\b`:

| Class | Hits | Verdict |
| --- | --- | --- |
| all-digit | 17 | false positive — file modes `100644`/`160000`, byte budgets `25600`/`26754`, token counts `197354`/`87253` |
| in the hex-word list | 8 | false positive — every one is `added` |
| residual | **4** | **true positive — all four are commit ids** |

`\b[a-f]{7,40}\b`, the entire dictionary-collision class, returns **zero** hits
over the whole store. The words are a theoretical surface, not an observed one.

## Recommended rule

Match `\b[0-9a-f]{5,40}\b`, then drop a hit when any of these hold:

1. **It is inside the frontmatter block.** `originSessionId` is a UUID the
   harness writes into every file, and its dash-separated groups are 8 and 12
   hex characters — 196 of the 200 raw hits in this store are exactly that.
   Skipping frontmatter is what makes the check viable at all.
2. **It is all digits.** Every number of five or more digits matches otherwise,
   and that class is unbounded. The cost is the shas that happen to be
   all-digit: `(10/16)**7` of seven-character ones, about 4%.
3. **It is in the hex-word list.** The 47 entries of length ≥5 from the link
   above. Only `added` occurs in this store, but the list is closed, so no
   later word can surprise it.

Two further scoping notes:

- **Lowercase only.** Git never emits an uppercase sha, and `FDA`, `CDC`,
  `EBCDIC` are ordinary acronyms. The shipped `[0-9a-fA-F]` buys nothing and
  costs precision.
- **Read raw; do not strip code spans.** All four true positives sit inside
  backticks, which is a sha's natural habitat in prose. A code-stripped scan
  finds none of them.

On this corpus the composed rule yields 4 hits, 4 true positives, 0 false
positives.

## Residual, stated rather than implied

The 4% all-digit miss is real and deliberate. A commit id written without
backticks, split across a line break, or abbreviated to four characters still
passes. This is a cheap high-precision filter, not a proof of absence.

## Provenance

Found while verifying all eight guards fire, by probing each with a command the
system genuinely issues and expecting ALLOW. Seven behaved exactly as
documented. This one allowed `landed as afb02b9 on live` into a memory file,
which is the rule's own example of what it forbids.

The equivalent check is implemented and green in gitlore's
`scripts/check-memory-hygiene.py` as `volatile-state`, covered by
`tests/check_memory_hygiene.bats`, if a working reference is useful. Landing it
here would catch the write; landing it there only catches the commit.
