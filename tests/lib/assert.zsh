# tests/lib/assert.zsh -- assertion and helper API for zsh-english-vocab tests.
#
# Sourced by tests/lib/driver.zsh before each test file. Every assertion takes an
# optional trailing MESSAGE (for assert_true/assert_false/assert_status use
# `-m MESSAGE` as the first argument, since their command is variadic).
#
# On failure an assertion appends a report (caller file:line, assertion name,
# quoted expected/actual) to $ZEV_TEST_TMPDIR/.zev/fail and runs `exit 1`, which
# ends the test body (tests run in a subshell). Because the report goes to a
# file, a failure inside $(...) or a pipeline still fails the test.

# Directory for per-test bookkeeping files (.zev/ under the test's temp dir).
_zev_bookdir() {
  REPLY=${ZEV_TEST_TMPDIR:-${ZEV_TEST_FILE_TMP:-${TMPDIR:-/tmp}}}/.zev
  [[ -d $REPLY ]] || mkdir -p -- "$REPLY"
}

# Quote a value so whitespace is visible; use $'...' form for control chars.
_zev_q() {
  if [[ $1 == *[[:cntrl:]]* ]]; then
    REPLY=${(qqqq)1}
  else
    REPLY=${(qqq)1}
  fi
}

# _zev_record NAME MESSAGE [DETAIL_LINE...] -- append a failure report, exit 1.
# Always reached via exactly one helper (_zev_assert_fail / _zev_fail_ea) called
# from an assertion, so $funcfiletrace[3] is where the assertion was called.
_zev_record() {
  local name=$1 msg=$2 where=${funcfiletrace[3]:-unknown} line REPLY
  shift 2
  where=${where#$ZEV_ROOT/}
  _zev_bookdir
  {
    print -r -- "$where: $name${msg:+: $msg}"
    for line in "$@"; do
      print -r -- "  $line"
    done
  } >> $REPLY/fail
  exit 1
}

# _zev_assert_fail NAME MESSAGE [DETAIL_LINE...]
_zev_assert_fail() {
  _zev_record "$@"
}

# _zev_fail_ea NAME MESSAGE EXPECTED ACTUAL [EXPECTED_LABEL]
_zev_fail_ea() {
  local name=$1 msg=$2 e a label="${5:-expected}:" REPLY
  if (( $#label < 10 )); then label=${(r:10:)label}; else label+=' '; fi
  _zev_q "$3"; e=$REPLY
  _zev_q "$4"; a=$REPLY
  _zev_record "$name" "$msg" "$label$e" "actual:   $a"
}

_zev_usage_fail() {
  _zev_record "$1" "" "usage: $2"
}

# run CMD... -- run CMD in a subshell; set $output, $stderr (trailing newlines
# stripped), $lines (array of output lines) and $rc. Always succeeds.
run() {
  (( $# )) || _zev_usage_fail run "run CMD [ARG...]"
  local REPLY
  _zev_bookdir
  local _zev_d=$REPLY
  ( "$@" ) >$_zev_d/run.out 2>$_zev_d/run.err
  local _zev_s=$?
  typeset -g rc=$_zev_s
  typeset -g output="$(<$_zev_d/run.out)"
  typeset -g stderr="$(<$_zev_d/run.err)"
  typeset -ga lines
  if [[ -n $output ]]; then
    lines=("${(@f)output}")
  else
    lines=()
  fi
  return 0
}

assert_equal() {
  (( $# >= 2 )) || _zev_usage_fail assert_equal "assert_equal ACTUAL EXPECTED [MSG]"
  [[ $1 == "$2" ]] && return 0
  _zev_fail_ea assert_equal "$3" "$2" "$1"
}

assert_not_equal() {
  (( $# >= 2 )) || _zev_usage_fail assert_not_equal "assert_not_equal ACTUAL UNEXPECTED [MSG]"
  [[ $1 != "$2" ]] && return 0
  _zev_fail_ea assert_not_equal "$3" "$2" "$1" unexpected
}

assert_match() {
  (( $# >= 2 )) || _zev_usage_fail assert_match "assert_match STRING REGEX [MSG]"
  local MATCH MBEGIN MEND
  local -a match mbegin mend
  [[ $1 =~ $2 ]] && return 0
  _zev_fail_ea assert_match "$3" "$2" "$1" "regex"
}

assert_not_match() {
  (( $# >= 2 )) || _zev_usage_fail assert_not_match "assert_not_match STRING REGEX [MSG]"
  local MATCH MBEGIN MEND
  local -a match mbegin mend
  [[ $1 =~ $2 ]] || return 0
  _zev_fail_ea assert_not_match "$3" "$2" "$1" "regex"
}

assert_contains() {
  (( $# >= 2 )) || _zev_usage_fail assert_contains "assert_contains HAYSTACK NEEDLE [MSG]"
  [[ $1 == *"$2"* ]] && return 0
  _zev_fail_ea assert_contains "$3" "$2" "$1" "needle"
}

assert_not_contains() {
  (( $# >= 2 )) || _zev_usage_fail assert_not_contains "assert_not_contains HAYSTACK NEEDLE [MSG]"
  [[ $1 != *"$2"* ]] && return 0
  _zev_fail_ea assert_not_contains "$3" "$2" "$1" "needle"
}

assert_empty() {
  (( $# >= 1 )) || _zev_usage_fail assert_empty "assert_empty VALUE [MSG]"
  [[ -z $1 ]] && return 0
  _zev_fail_ea assert_empty "$2" "" "$1"
}

assert_not_empty() {
  (( $# >= 1 )) || _zev_usage_fail assert_not_empty "assert_not_empty VALUE [MSG]"
  [[ -n $1 ]] && return 0
  _zev_assert_fail assert_not_empty "$2" "value is empty"
}

# assert_true [-m MSG] CMD...  -- CMD (run in the current shell) exits 0.
assert_true() {
  local msg=
  if [[ $1 == -m ]]; then msg=$2; shift 2; fi
  (( $# )) || _zev_usage_fail assert_true "assert_true [-m MSG] CMD [ARG...]"
  "$@" && return 0
  local s=$?
  _zev_assert_fail assert_true "$msg" "command:  ${(j: :)${(q-)@}}" "status:   $s (expected 0)"
}

# assert_false [-m MSG] CMD...  -- CMD exits non-zero.
assert_false() {
  local msg=
  if [[ $1 == -m ]]; then msg=$2; shift 2; fi
  (( $# )) || _zev_usage_fail assert_false "assert_false [-m MSG] CMD [ARG...]"
  "$@" || return 0
  _zev_assert_fail assert_false "$msg" "command:  ${(j: :)${(q-)@}}" "status:   0 (expected non-zero)"
}

# assert_status [-m MSG] N [CMD...]  -- CMD's exit status is N; without CMD,
# checks $rc from the last `run`.
assert_status() {
  local msg=
  if [[ $1 == -m ]]; then msg=$2; shift 2; fi
  (( $# )) || _zev_usage_fail assert_status "assert_status [-m MSG] N [CMD...]"
  local want=$1 got
  shift
  if (( $# )); then
    "$@"
    got=$?
  else
    got=${rc-}
    [[ -n $got ]] || _zev_assert_fail assert_status "$msg" "no CMD given and \$rc is unset (call run first)"
  fi
  [[ $got == "$want" ]] && return 0
  if (( $# )); then
    _zev_assert_fail assert_status "$msg" "command:  ${(j: :)${(q-)@}}" "expected: $want" "actual:   $got"
  else
    _zev_assert_fail assert_status "$msg" "expected: $want" "actual:   $got (\$rc from last run)"
  fi
}

assert_file_exists() {
  (( $# >= 1 )) || _zev_usage_fail assert_file_exists "assert_file_exists PATH [MSG]"
  [[ -e $1 ]] && return 0
  local REPLY; _zev_q "$1"
  _zev_assert_fail assert_file_exists "$2" "path: $REPLY does not exist"
}

assert_file_not_exists() {
  (( $# >= 1 )) || _zev_usage_fail assert_file_not_exists "assert_file_not_exists PATH [MSG]"
  [[ ! -e $1 ]] && return 0
  local REPLY; _zev_q "$1"
  _zev_assert_fail assert_file_not_exists "$2" "path: $REPLY exists"
}

assert_dir_exists() {
  (( $# >= 1 )) || _zev_usage_fail assert_dir_exists "assert_dir_exists PATH [MSG]"
  [[ -d $1 ]] && return 0
  local REPLY; _zev_q "$1"
  _zev_assert_fail assert_dir_exists "$2" "path: $REPLY is not a directory"
}

# assert_file_contents PATH EXPECTED [MSG] -- trailing newlines are ignored.
assert_file_contents() {
  (( $# >= 2 )) || _zev_usage_fail assert_file_contents "assert_file_contents PATH EXPECTED [MSG]"
  local REPLY
  if [[ ! -f $1 ]]; then
    _zev_q "$1"
    _zev_assert_fail assert_file_contents "$3" "path: $REPLY is not a file"
  fi
  local actual="$(<$1)" want=$2
  while [[ $want == *$'\n' ]]; do want=${want%$'\n'}; done
  [[ $actual == "$want" ]] && return 0
  _zev_fail_ea assert_file_contents "$3" "$want" "$actual"
}

# assert_file_contains PATH NEEDLE [MSG] -- literal substring.
assert_file_contains() {
  (( $# >= 2 )) || _zev_usage_fail assert_file_contains "assert_file_contains PATH NEEDLE [MSG]"
  local REPLY
  if [[ ! -f $1 ]]; then
    _zev_q "$1"
    _zev_assert_fail assert_file_contains "$3" "path: $REPLY is not a file"
  fi
  local actual="$(<$1)"
  [[ $actual == *"$2"* ]] && return 0
  _zev_fail_ea assert_file_contains "$3" "$2" "$actual" "needle"
}

# fail MESSAGE -- explicit failure.
fail() {
  _zev_assert_fail fail "$*"
}

# skip REASON -- mark the test skipped and end the test body with status 0.
skip() {
  local REPLY
  _zev_bookdir
  print -r -- "$*" > $REPLY/skip
  exit 0
}
