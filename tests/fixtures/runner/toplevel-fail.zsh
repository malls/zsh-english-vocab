# Fixture: a failing assertion at top level is reported, then a file error.
assert_equal "top" "level"
test_never_runs() { fail "should not run" }
