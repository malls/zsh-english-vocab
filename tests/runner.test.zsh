# Meta-tests for tests/run: run the runner on fixture files and check exit
# codes and output. Fixtures live in tests/fixtures/runner/.

typeset -g RUNNER=$ZEV_ROOT/tests/run
typeset -g FX=$ZEV_FIXTURES/runner

test_passing_fixture_exits_0_and_ends_ok() {
  run "$RUNNER" "$FX/passing.zsh"
  assert_status 0
  assert_equal "$lines[-1]" OK
  assert_contains "$output" "Tests: 2 passed, 0 failed, 0 skipped"
  assert_contains "$output" "ok    test_passes_equal"
  assert_not_contains "$output" "visible-only-with-verbose" "output hidden without -v"
  assert_not_contains "$output" "Checks:" "checks are skipped with FILE args"
}

test_verbose_shows_passing_output() {
  run "$RUNNER" -v "$FX/passing.zsh"
  assert_status 0
  assert_contains "$output" "visible-only-with-verbose"
}

test_failing_fixture_reports_every_failure() {
  local t
  run "$RUNNER" "$FX/failing.zsh"
  assert_status 1
  for t in equal not_equal match contains true false status file_exists \
           file_contents explicit nonzero_return in_command_substitution; do
    assert_contains "$output" "  FAIL  test_fail_$t"$'\n'
  done
  assert_contains "$output" "  ok    test_ok_passes"
  assert_contains "$output" "  skip  test_skip_skipped (fixture skip reason)"
  assert_contains "$output" "Tests: 1 passed, 12 failed, 1 skipped"
  assert_equal "$lines[-1]" FAILED
}

test_failing_fixture_reports_location_and_values() {
  local a
  run "$RUNNER" "$FX/failing.zsh"
  for a in assert_equal assert_not_equal assert_match assert_contains \
           assert_true assert_false assert_status assert_file_exists \
           assert_file_contents fail; do
    assert_match "$output" "failing\\.zsh:[0-9]+: $a" "location for $a"
  done
  assert_contains "$output" 'expected: "expected value"'
  assert_contains "$output" 'actual:   "actual value"'
  assert_contains "$output" 'actual:   "hello"'
  assert_contains "$output" 'needle:   "needle"'
  assert_contains "$output" 'actual:   "haystack"'
  assert_contains "$output" 'expected: "outer"'
  assert_contains "$output" 'fail: explicit failure message'
  assert_contains "$output" 'test exited with status 3'
}

test_broken_fixture_is_a_file_error() {
  run "$RUNNER" "$FX/broken.zsh"
  assert_status 1
  assert_contains "$output" "FAIL  tests/fixtures/runner/broken.zsh (file error)"
  assert_contains "$output" "parse error"
  assert_equal "$lines[-1]" FAILED
}

test_toplevel_skip_skips_whole_file() {
  run "$RUNNER" "$FX/toplevel-skip.zsh"
  assert_status 0
  assert_contains "$output" "skip  (file) (tool not installed)"
  assert_contains "$output" "0 passed, 0 failed, 1 skipped"
}

test_toplevel_assertion_failure_is_reported() {
  run "$RUNNER" "$FX/toplevel-fail.zsh"
  assert_status 1
  assert_contains "$output" "FAIL  tests/fixtures/runner/toplevel-fail.zsh (file error)"
  assert_contains "$output" "toplevel-fail.zsh:2"
}

test_filter_selects_one_test() {
  run "$RUNNER" -f 'test_fail_equal' "$FX/failing.zsh"
  assert_status 1
  assert_contains "$output" "Tests: 0 passed, 1 failed, 0 skipped"
}

test_filter_matching_nothing_exits_2() {
  run "$RUNNER" -f 'nomatch*'
  assert_status 2
  assert_contains "$stderr" "no tests selected"
}

test_nonexistent_file_exits_2() {
  run "$RUNNER" "$FX/does-not-exist.zsh"
  assert_status 2
  assert_contains "$stderr" "no such file"
}

test_unknown_option_exits_2() {
  run "$RUNNER" --bogus
  assert_status 2
  assert_contains "$stderr" "unknown option: --bogus"
}

test_filter_without_argument_exits_2() {
  run "$RUNNER" -f
  assert_status 2
}

test_checks_only_with_files_exits_2() {
  run "$RUNNER" --checks-only "$FX/passing.zsh"
  assert_status 2
}

test_help_exits_0() {
  run "$RUNNER" --help
  assert_status 0
  assert_contains "$output" "usage: tests/run"
}

test_checks_only_runs_checks_dir() {
  run env ZEV_TEST_CHECKS_DIR="$FX/checks" "$RUNNER" --checks-only
  assert_status 1
  assert_contains "$output" "  ok    pass"
  assert_contains "$output" "  FAIL  fail"
  assert_contains "$output" "boom"
  assert_contains "$output" "Checks: 1 passed, 1 failed"
  assert_equal "$lines[-1]" FAILED
}

test_relative_checks_dir_resolves_against_cwd() {
  cd "$ZEV_ROOT"
  run env ZEV_TEST_CHECKS_DIR=tests/fixtures/runner/checks "$RUNNER" --checks-only
  assert_status 1
  assert_contains "$output" "  ok    pass"
}

test_depth_guard_skips_runner_tests_when_nested() {
  run env ZEV_TEST_DEPTH=2 "$RUNNER" -f 'zzz_nomatch'
  assert_status 2
  assert_contains "$output" "tests/assert.test.zsh"
  assert_not_contains "$output" "tests/runner.test.zsh"
}

test_no_leaked_temp_dirs() {
  local -a before after
  before=($TMPDIR/zev-tests.*(N))
  run "$RUNNER" "$FX/passing.zsh"
  assert_status 0
  run "$RUNNER" "$FX/failing.zsh"
  assert_status 1
  after=($TMPDIR/zev-tests.*(N))
  assert_equal "${#after}" "${#before}"
}

test_keep_keeps_temp_dir() {
  run "$RUNNER" --keep "$FX/passing.zsh"
  assert_status 0
  assert_match "$output" 'kept temp dir: [^'$'\n'']+'
  local dir=${${output##*kept temp dir: }%%$'\n'*}
  assert_dir_exists "$dir"
  rm -rf -- "$dir"
}
