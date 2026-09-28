# Fixture: a file that skips itself at top level (e.g. a missing tool).
skip "tool not installed"
test_never_runs() { fail "should not run" }
