# zsh-english-vocab

## Project conventions

- **Run `tests/run` before handing off.** It must end with `OK` (exit 0). It
  needs only zsh 5.9 + macOS tools; there is no zunit. `tests/run --help` lists
  options (`-v`, `-f GLOB`, `-k`, `--no-checks`, `--checks-only`; FILE args run
  just those files).
- **Add files under `functions/`; never edit the entry files**
  (`zsh-english-vocab.plugin.zsh`, `zsh-english-vocab.zsh-theme`). The entry
  files autoload by name, so a function exists exactly when its file exists.
  One function per file, named after the file, no subdirectories.
- **Naming prefixes** (enforced by the loader globs):
  - plugin: `vocab`, `_vocab`, `_zev_vocab_*`
  - theme: `_zev_prompt_*`
  - Anything else in `functions/` is not autoloaded.
- **Hooks called by the entry files, if their file exists:**
  - `_zev_vocab_startup` (plugin, at load; owns all suppression logic).
  - `compdef _vocab vocab` (plugin, when compinit has run). `functions/_vocab`
    must start with `#compdef vocab`.
  - `_zev_prompt_setup` (theme; otherwise a stub two-line `PROMPT` is used).
  - Hooks run with the user's options (outside the loader's `emulate -L`), so
    `setopt prompt_subst` / `add-zsh-hook` in `_zev_prompt_setup` persist.
    Functions are autoloaded `-Uz`. Start ordinary functions with
    `emulate -L zsh`; a hook that must change the user's options must not use
    `emulate -L` / `local_options`.
- **Test files:** `tests/<area>.test.zsh`, plain zsh sourced by
  `tests/lib/driver.zsh` in a fresh `zsh -f` with a scrubbed environment.
  - Tests are functions named `test_<snake_case>`, run in alphabetical order,
    each in its own subshell; they must be independent. Optional `setup` /
    `teardown` run around each test (`$ZEV_TEST_NAME` holds the test name).
  - Top-level code runs once per file (e.g. `autoload -Uz` of the functions
    under test; `fpath` already starts with `$ZEV_ROOT/functions`). It must
    succeed: a non-zero status or parse error is reported as a file error.
  - Env: `ZEV_ROOT`, `ZEV_FIXTURES` (`tests/fixtures`), `ZEV_TEST_TMPDIR` (per
    test), `ZEV_TEST_FILE_TMP` (per file), and a fresh `HOME`/`ZDOTDIR`/
    `XDG_*_HOME` per test (cwd is `$HOME`). `TMUX`, `SSH_*` and `ZEV_*` from the
    caller never leak in; `TZ=UTC`.
  - Assertions (`tests/lib/assert.zsh`): `run CMD...` (sets `output`, `stderr`,
    `lines`, `rc`), `assert_equal`, `assert_not_equal`, `assert_match` (ERE),
    `assert_not_match`, `assert_contains`, `assert_not_contains`,
    `assert_empty`, `assert_not_empty`, `assert_true`, `assert_false`,
    `assert_status N [CMD...]`, `assert_file_exists`, `assert_file_not_exists`,
    `assert_dir_exists`, `assert_file_contents`, `assert_file_contains`, `fail`,
    `skip`. Optional trailing message; `-m MSG` first for `assert_true`,
    `assert_false`, `assert_status`.
  - Gotcha: never name a variable `status` (read-only in zsh); use `rc`.
  - Fixtures under `tests/fixtures/` use a plain `.zsh` (or other) suffix, never
    `.test.zsh`, so discovery skips them.
- **Checks:** executables in `tests/checks/` run after the tests with cwd
  `$ZEV_ROOT` (exit 0 = pass). Non-executable files are ignored.
