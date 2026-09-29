# zsh-english-vocab — Spec

An oh-my-zsh **theme** with a detailed, async git prompt, and a separate oh-my-zsh
**plugin** that prints an English vocabulary word each time an interactive shell
starts. The two are independent: the plugin works with any theme, and the theme
works without the plugin.

Decisions below come from the planning interview (2026-09-27). Items marked
**(default)** were not discussed explicitly and are open to change.

---

## 1. Repository layout

The repo is cloned directly into `$ZSH_CUSTOM/plugins/zsh-english-vocab`; the
theme is symlinked into `$ZSH_CUSTOM/themes/`.

```
zsh-english-vocab.plugin.zsh   # plugin entry point (oh-my-zsh naming convention)
zsh-english-vocab.zsh-theme    # theme
functions/                     # autoloaded helpers (vocab command, rotation, git async)
data/words.tsv                 # bundled word list
tools/lint-words               # word-list linter
tools/bench-vocab              # startup-cost benchmark
tools/make-screenshot          # regenerates docs/screenshot.svg (uses tools/ansi2svg)
tests/                         # tests; run with tests/run (no deps)
docs/screenshot.svg
SPEC.md  README.md  CLAUDE.md  LICENSE
```

Resulting `~/.zshrc`:

```zsh
ZSH_THEME="zsh-english-vocab"
plugins=(git zsh-english-vocab)
```

Keep `git` in `plugins` for its aliases. The theme does not depend on it.

---

## 2. Theme

### Layout: two lines, no RPROMPT

```
~/Code/zsh-english-vocab  main ⇡1 ● ● ≡1  took 4s  14:32
[1] ❯
```

**Line 1**, left to right:

| Segment  | Details |
|----------|---------|
| Path     | Full `$PWD` with `~` substitution (`~/Code/zsh-english-vocab`), so it can be copied. Set `ZEV_PATH_STYLE=short` to shorten intermediate dirs to their first char (`~/C/zsh-english-vocab`) |
| Git      | Branch (or short SHA if detached), ahead/behind, then status markers. Hidden outside repos |
| Duration | `took Ns` / `took 1m4s`: only if the last command ran ≥ `ZEV_DURATION_THRESHOLD` seconds (default 3) |
| Clock    | `HH:MM`, time the prompt was drawn |

**Line 2:** `[N] ` exit code, shown only when non-zero, then `❯` in green on success
and red on failure.

### Git markers (plain Unicode only; no Nerd Font)

Two styles, chosen with `ZEV_GIT_STYLE`. Both show `⇡N` / `⇣N` (ahead / behind
upstream) and `≡N` (stash entries).

**`dots` (default; requested by Forrest after trying the theme):**
`main ⇡1 ● ● ≡1`

| Marker | Meaning |
|--------|---------|
| green `●` | something is staged |
| red `●` | unstaged, untracked or conflicted changes |
| no dot | clean |

**`counts`:** `main ⇡1 +2 !1 ?3 ≡1`

| Marker | Meaning |
|--------|---------|
| `~N` | conflicted (unmerged; counted as neither staged nor unstaged) |
| `+N` | staged |
| `!N` | unstaged modifications |
| `?N` | untracked |
| `✓`  | clean: shown instead of `~ + ! ?` when all are zero; `⇡⇣≡` still shown |

Colors come from the terminal's 16/256 palette via `%F{…}`; no truecolor
requirement. All markers and colors can be overridden with `ZEV_*` variables.

### Async git

- The prompt must never wait on git. Draw the prompt immediately, run
  `git status --porcelain=v2 --branch --show-stash` (one call) in the background,
  then refresh the prompt with `zle reset-prompt` when the result arrives.
- Implemented with zsh built-ins (`zle -F` on a background fd); no vendored
  library.
- On `cd` into a different repo, blank the segment until the new result
  arrives; never show stale status for a different repo.
- Discard results from a previous prompt if a newer job has started.

---

## 3. Vocab plugin

### When it prints

Once, when the plugin loads in a new shell. It is skipped when:

- the shell is not interactive (`[[ -o interactive ]]` is false)
- `$SSH_CONNECTION` / `$SSH_TTY` is set
- `$TMUX` is set (never shown inside tmux)
- stdout is not a terminal (e.g. `zsh -i -c` spawned by an editor or another
  tool to read the environment)
- `ZEV_VOCAB_DISABLE` is set to anything other than empty or `0` **(default; a
  universal opt-out)**

### Display: word-wrapped at word boundaries

```
petrichor (n.): the earthy scent produced when rain falls on dry ground — coined
in 1964 from Greek petra "stone" + ichōr, the fluid in the veins of the gods
```

Word in bold, part of speech dimmed, definition in normal weight, etymology dimmed
after an em dash. Nothing is truncated. On a terminal the entry is word-wrapped
to the terminal width, so line breaks fall only between words (Forrest's
request); `ZEV_VOCAB_WIDTH` overrides the width (`0` turns wrapping off).
Piped output keeps one line per entry.

### Rotation: random, no repeats

- On first run, or when the queue is empty, shuffle the whole list (Fisher–Yates
  with `$RANDOM`; macOS has no `shuf`) and write it to the queue file.
- Each shell pops the head of the queue.
- The queue stores **words**, not line numbers, so editing `words.tsv` does not
  corrupt it. Skip queued words that are no longer in the list; new words are
  added at the next reshuffle.
- Concurrent shell starts (e.g. restoring several tabs) must not show the same
  word or corrupt the queue. Use a lock (`zsystem flock` or `mkdir`).
- Startup cost budget: **< 10 ms** added to shell start. Use only zsh built-ins
  on the hot path; avoid subprocesses.

### State

`${XDG_STATE_HOME:-$HOME/.local/state}/zsh-english-vocab/`

| File | Contents |
|------|----------|
| `queue` | remaining shuffled words, one per line |
| `current` | the word shown most recently |
| `history` | `ISO-8601 timestamp<TAB>word`, append-only |
| `favorites` | one word per line |
| `lock` | lock file (empty) |

### `vocab` command

| Command | Behavior |
|---------|----------|
| `vocab` | Print the current word again |
| `vocab next` | Pop and show a new word (advances the queue) |
| `vocab search <term>` | Case-insensitive match on words (and definitions with `-d`); print matching entries |
| `vocab fav [word]` | Favorite the current word, or the named one |
| `vocab unfav <word>` | Remove a favorite |
| `vocab favs` | List favorites with definitions |
| `vocab history [N]` | Last N words shown (default 20) |
| `vocab help` | Usage |

Include zsh completion for the subcommands and for word arguments.

---

## 4. Word data

- **Format:** `data/words.tsv`, UTF-8, one entry per line, 4 tab-separated
  fields:
  `word<TAB>pos<TAB>definition<TAB>etymology`
  No header, comments or blank lines; LF line endings with a final newline; no
  quoting or escaping. `word` is lowercase letters (any script) joined by single
  spaces, hyphens or apostrophes. Full rules: `tools/lint-words --help`.
- **pos** must be one of `n.`, `v.`, `adj.`, `adv.`, `prep.`, `conj.`, `interj.`,
  `pron.`
- **Size and level:** about 2,200 entries. The bar is **rare** (Forrest's
  decision after finding the first batch "not particularly obscure"): a well-read adult
  probably does not know the word, so nothing from GRE/SAT lists or everyday
  educated prose. Every word must be attested in MW (incl. Unabridged), OED,
  Collins or AH; archaic words are allowed if labeled.
- **Exception: the vocab-108 test.** Every word tested by the
  [vocab-108 vocabulary test](https://taketest.xyz/vocab-108) is in the list,
  defined in the sense the test uses. These are exempt from the rarity bar and
  from the family check, so some are common (`heap`, `whisper`). Do not remove
  them.
- **Near-synonyms are allowed:** a new word may mean nearly the same as an
  existing one. Spelling variants and members of the same word family are not
  (one per family), and productive suffix series (-mancy, -latry, ...) are
  capped.
- **Source:** Claude writes the entries in batches (about 150–200 per batch).
  A blind rarity judge rates every candidate, a separate check catches
  variants and word-family relatives, and a separate agent fact-checks every
  entry (sense, pos, etymology, attestation); Forrest spot-checks. One sense
  per entry (a closely related extension is fine); definitions ≤ 120 chars;
  etymology ≤ 100 chars.
- No offensive or slur entries; no proper nouns.

### Linter (`tools/lint-words`)

Fails when any of these is true:

- a line does not have exactly 4 non-empty fields
- a word is duplicated (case-insensitive)
- a pos is not in the allowed set
- a line has leading or trailing whitespace, or contains CR characters
- a definition is over 120 or an etymology over 100 characters
- a line has invalid UTF-8, control or non-printable characters, double or
  non-breaking spaces
- the file is missing its final newline
- the list has fewer than 1000 entries (the floor is set in
  `tests/checks/lint-words`; currently 1000)

---

## 5. Testing

- Tests (in-repo runner `tests/run`, zsh only, no external deps) for: queue
  shuffle/pop/refill, skipping removed words, locking, suppression rules, `vocab`
  subcommands (against a temp `XDG_STATE_HOME`), parsing
  `git status --porcelain=v2` into markers (using fixture output), and
  formatting duration and exit codes.
- **Word-list linter**, run as part of the test suite.
- No CI for now.

---

## 6. Out of scope

- Online dictionary APIs, pronunciation, and example sentences
- Nerd Font glyphs and RPROMPT
- Non-oh-my-zsh plugin managers (they may work, but are not tested)
- Publishing to a registry
