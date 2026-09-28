# Fixture for tests/runner.test.zsh: every test passes.
# (Suffix is .zsh, not .test.zsh, so discovery never picks it up.)

test_passes_equal() {
  assert_equal "a" "a"
}

test_passes_with_output() {
  print -r -- "visible-only-with-verbose"
  assert_true true
}
