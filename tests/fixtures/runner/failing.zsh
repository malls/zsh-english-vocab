# Fixture for tests/runner.test.zsh: deliberately failing tests, one per
# assertion kind, plus one passing and one skipped test.
# Expected summary: Tests: 1 passed, 12 failed, 1 skipped
# (Line numbers matter to runner.test.zsh only loosely: it matches
# "failing.zsh:<digits>".)

test_fail_equal() {
  assert_equal "actual value" "expected value"
}

test_fail_not_equal() {
  assert_not_equal same same
}

test_fail_match() {
  assert_match "hello" '^[0-9]+$'
}

test_fail_contains() {
  assert_contains "haystack" "needle"
}

test_fail_true() {
  assert_true false
}

test_fail_false() {
  assert_false true
}

test_fail_status() {
  assert_status 3 sh -c 'exit 4'
}

test_fail_file_exists() {
  assert_file_exists "$ZEV_TEST_TMPDIR/no such file"
}

test_fail_file_contents() {
  print -r -- "one line" > "$ZEV_TEST_TMPDIR/f"
  assert_file_contents "$ZEV_TEST_TMPDIR/f" "other line"
}

test_fail_explicit() {
  fail "explicit failure message"
}

test_fail_nonzero_return() {
  return 3
}

test_fail_in_command_substitution() {
  local x
  x=$(assert_equal inner outer; print survived)
  print -r -- "x=$x"
}

test_ok_passes() {
  assert_equal ok ok
}

test_skip_skipped() {
  skip "fixture skip reason"
  fail "unreachable"
}
