# Tests for the assertion library (tests/lib/assert.zsh) and the driver's
# per-test isolation guarantees. Every test here passes; the failing side of
# each assertion is covered by tests/fixtures/runner/failing.zsh via
# tests/runner.test.zsh.

setup() {
  SETUP_VALUE=from-setup
}

teardown() {
  : > "$ZEV_TEST_FILE_TMP/teardown.$ZEV_TEST_NAME"
}

# ---- assertions ----------------------------------------------------------

test_assert_equal_passes() {
  assert_equal "a b" "a b"
  assert_equal "" ""
}

test_assert_not_equal_passes() {
  assert_not_equal a b
  assert_not_equal "a" "a "
}

test_assert_match_passes() {
  assert_match "laconic (adj.)" '^[a-z]+ \(adj\.\)$'
}

test_assert_not_match_passes() {
  assert_not_match "hello" '^[0-9]+$'
}

test_assert_contains_passes() {
  assert_contains "a haystack with a needle in it" "needle"
  assert_contains "glob*chars?[x]" "*chars?[x]"
}

test_assert_not_contains_passes() {
  assert_not_contains "haystack" "needle"
  assert_not_contains "abc" "*"
}

test_assert_empty_and_not_empty_pass() {
  assert_empty ""
  assert_not_empty " "
}

test_assert_true_and_false_pass() {
  assert_true true
  assert_true -m "with a message" test 1 -eq 1
  assert_false false
  assert_false -m "with a message" test 1 -eq 2
}

test_assert_status_with_command() {
  assert_status 0 true
  assert_status 4 sh -c 'exit 4'
  assert_status -m "with a message" 1 false
}

test_assert_status_uses_rc_from_run() {
  run sh -c 'exit 7'
  assert_status 7
}

test_assert_file_assertions_pass() {
  local d=$ZEV_TEST_TMPDIR/files
  mkdir -p "$d"
  printf 'line one\nline two\n\n' > "$d/f"
  assert_dir_exists "$d"
  assert_file_exists "$d/f"
  assert_file_not_exists "$d/missing"
  assert_file_contents "$d/f" $'line one\nline two'
  assert_file_contents "$d/f" $'line one\nline two\n'
  assert_file_contains "$d/f" "one"$'\n'"line"
}

test_fail_and_skip_are_defined() {
  assert_true -m "fail is a function" test -n "${functions[fail]}"
  assert_true -m "skip is a function" test -n "${functions[skip]}"
}

test_skip_marks_test_skipped() {
  # The runner meta-tests prove skip is reported as "skip"; here we only
  # check that skip ends the body with status 0 and records the reason.
  ( skip "because" ; exit 9 )
  assert_status 0 test $? -eq 0
  assert_file_contents "$ZEV_TEST_TMPDIR/.zev/skip" "because"
  rm -f -- "$ZEV_TEST_TMPDIR/.zev/skip"
}

# ---- run -----------------------------------------------------------------

test_run_captures_stdout_stderr_rc_lines() {
  run sh -c 'printf "one\ntwo\n\n"; printf "err\n" >&2; exit 3'
  assert_equal "$output" $'one\ntwo'
  assert_equal "$stderr" "err"
  assert_equal "$rc" 3
  assert_equal "${#lines}" 2
  assert_equal "$lines[1]" one
  assert_equal "$lines[2]" two
}

test_run_empty_output_gives_empty_lines() {
  run true
  assert_equal "$rc" 0
  assert_empty "$output"
  assert_empty "$stderr"
  assert_equal "${#lines}" 0
}

test_run_does_not_affect_current_shell() {
  local v=before
  run eval 'v=after; cd /'
  assert_equal "$v" before
  assert_equal "$PWD" "$HOME"
}

test_run_works_with_shell_functions() {
  _helper() { print -r -- "helper:$1"; return 5 }
  run _helper x
  assert_equal "$output" "helper:x"
  assert_status 5
}

# ---- setup / teardown ----------------------------------------------------

test_setup_ran_before_test() {
  assert_equal "$SETUP_VALUE" from-setup
}

test_teardown_a_marker() {
  # teardown writes $ZEV_TEST_FILE_TMP/teardown.test_teardown_a_marker
  :
}

test_teardown_b_ran_for_a() {
  assert_file_exists "$ZEV_TEST_FILE_TMP/teardown.test_teardown_a_marker"
}

# ---- environment isolation -----------------------------------------------

_check_isolated_env() {
  assert_equal "$HOME" "$ZEV_TEST_TMPDIR/home"
  assert_equal "$ZDOTDIR" "$ZEV_TEST_TMPDIR/home"
  assert_equal "$XDG_STATE_HOME" "$ZEV_TEST_TMPDIR/state"
  assert_equal "$XDG_CONFIG_HOME" "$ZEV_TEST_TMPDIR/config"
  assert_equal "$XDG_CACHE_HOME" "$ZEV_TEST_TMPDIR/cache"
  assert_equal "$XDG_DATA_HOME" "$ZEV_TEST_TMPDIR/data"
  assert_dir_exists "$XDG_STATE_HOME"
  assert_equal "$PWD" "$HOME"
  assert_equal "${+TMUX}" 0 "TMUX must be unset"
  assert_equal "${+SSH_TTY}" 0 "SSH_TTY must be unset"
  assert_equal "${+SSH_CONNECTION}" 0 "SSH_CONNECTION must be unset"
  assert_equal "${+ZEV_VOCAB_DISABLE}" 0 "ZEV_VOCAB_DISABLE must be unset"
  assert_equal "${+ZEV_TEST_RESULTS}" 0 "driver internals must be unset"
  assert_equal "${+ZEV_TEST_FILTER}" 0 "driver internals must be unset"
  assert_equal "${+ZEV_TEST_VERBOSE}" 0 "driver internals must be unset"
  assert_equal "$TZ" UTC
  assert_equal "$ZEV_FIXTURES" "$ZEV_ROOT/tests/fixtures"
  assert_file_exists "$ZEV_ROOT/tests/lib/assert.zsh"
  assert_equal "$fpath[1]" "$ZEV_ROOT/functions"
}

test_env_a_is_isolated() {
  _check_isolated_env
  print -r -- a > "$HOME/marker"
  print -r -- "$HOME" > "$ZEV_TEST_FILE_TMP/env_a_home"
}

test_env_b_is_isolated_from_a() {
  _check_isolated_env
  assert_file_exists "$ZEV_TEST_FILE_TMP/env_a_home" "test_env_a should have run first"
  assert_not_equal "$HOME" "$(<$ZEV_TEST_FILE_TMP/env_a_home)"
  assert_file_not_exists "$HOME/marker"
}
