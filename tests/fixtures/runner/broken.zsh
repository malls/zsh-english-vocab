# Fixture for tests/runner.test.zsh: a syntax error at source time.

test_never_runs() {
  if [[ x ]; then
    :
  fi
}
