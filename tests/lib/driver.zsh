# tests/lib/driver.zsh -- run the tests in one file. Invoked by tests/run as
#   env -i <base env> zsh -f tests/lib/driver.zsh FILE
# Prints a report for the file and writes "<relpath> <pass> <fail> <skip>" to
# $ZEV_TEST_RESULTS. A missing results line means the file itself errored.
# Driver internals are prefixed _zev_ to stay out of the test files' way.

typeset -g _zev_file=$1
typeset -g _zev_rel=${_zev_file#$ZEV_ROOT/}

# Internal settings: copy into non-exported globals and unset, so tests never
# see (or leak) them.
typeset -g _zev_results=${ZEV_TEST_RESULTS-} _zev_filter=${ZEV_TEST_FILTER-}
typeset -g _zev_verbose=${ZEV_TEST_VERBOSE:-0} _zev_color=${ZEV_TEST_COLOR:-0}
unset ZEV_TEST_RESULTS ZEV_TEST_FILTER ZEV_TEST_VERBOSE ZEV_TEST_COLOR

typeset -g _zev_c_ok= _zev_c_fail= _zev_c_skip= _zev_c_off=
if (( _zev_color )); then
  _zev_c_ok=$'\e[32m' _zev_c_fail=$'\e[31m' _zev_c_skip=$'\e[33m' _zev_c_off=$'\e[0m'
fi

# _zev_indent FILE -- print FILE's lines indented under a test line.
_zev_indent() {
  local _zev_l
  while IFS= read -r _zev_l || [[ -n $_zev_l ]]; do
    print -r -- "        $_zev_l"
  done < $1
}

print -r -- "$_zev_rel"

fpath=("$ZEV_ROOT/functions" $fpath)
source "$ZEV_ROOT/tests/lib/assert.zsh" || exit 1

# Per-file temp dir (shared by the file's tests) and a throwaway HOME for the
# file's top-level code.
export ZEV_TEST_FILE_TMP=$TMPDIR/file.$$
export HOME=$ZEV_TEST_FILE_TMP/home
mkdir -p -- "$HOME" || exit 1
cd -- "$HOME" || exit 1

# If top-level code calls skip or an assertion, it exits the driver while the
# file is being sourced. Report that here: a top-level skip skips the whole
# file; a top-level assertion failure is shown before the runner's file error.
typeset -gi _zev_sourced=0
zshexit() {
  (( _zev_sourced )) && return
  local _zev_bk=$ZEV_TEST_FILE_TMP/.zev
  if [[ -e $_zev_bk/skip ]]; then
    local _zev_reason="$(<$_zev_bk/skip)"
    print -r -- "  ${_zev_c_skip}skip${_zev_c_off}  (file)${_zev_reason:+ ($_zev_reason)}"
    print -r -- "$_zev_rel 0 0 1" > $_zev_results
  elif [[ -s $_zev_bk/fail ]]; then
    print -ru2 -- "top-level failure in $_zev_rel:"
    _zev_indent $_zev_bk/fail >&2
  fi
}

# Top-level code must succeed: a parse error or a non-zero status from the
# file is reported by the runner as a file error.
source "$_zev_file"
typeset -g _zev_src_rc=$?
if (( _zev_src_rc )); then
  print -ru2 -- "sourcing $_zev_rel returned status $_zev_src_rc (top-level code must succeed)"
  exit 1
fi
_zev_sourced=1

typeset -ga _zev_tests
_zev_tests=(${(ok)functions[(I)test_*]})
if [[ -n $_zev_filter ]]; then
  _zev_tests=(${(M)_zev_tests:#${~_zev_filter}})
fi

typeset -gi _zev_n=0 _zev_pass=0 _zev_fail=0 _zev_skip=0 _zev_rc=0
typeset -g _zev_t _zev_T

for _zev_t in $_zev_tests; do
  (( _zev_n++ ))
  _zev_T=$ZEV_TEST_FILE_TMP/$_zev_n
  mkdir -p -- $_zev_T/{.zev,home,state,config,cache,data}
  (
    export HOME=$_zev_T/home ZDOTDIR=$_zev_T/home XDG_STATE_HOME=$_zev_T/state \
      XDG_CONFIG_HOME=$_zev_T/config XDG_CACHE_HOME=$_zev_T/cache \
      XDG_DATA_HOME=$_zev_T/data ZEV_TEST_TMPDIR=$_zev_T
    ZEV_TEST_NAME=$_zev_t
    cd -- "$HOME" || exit 1
    if (( $+functions[setup] )); then
      setup || {
        _zev_s=$?
        print -r -- "setup failed (status $_zev_s)" >> $_zev_T/.zev/fail
        exit 1
      }
    fi
    ( $_zev_t )
    _zev_s=$?
    if (( $+functions[teardown] )); then
      teardown
    fi
    exit $_zev_s
  ) >$_zev_T/.zev/out 2>&1 </dev/null
  _zev_rc=$?

  if [[ -e $_zev_T/.zev/skip ]]; then
    (( _zev_skip++ ))
    typeset _zev_reason="$(<$_zev_T/.zev/skip)"
    print -r -- "  ${_zev_c_skip}skip${_zev_c_off}  $_zev_t${_zev_reason:+ ($_zev_reason)}"
    (( _zev_verbose )) && [[ -s $_zev_T/.zev/out ]] && {
      print -r -- "        --- output ---"
      _zev_indent $_zev_T/.zev/out
    }
  elif [[ -s $_zev_T/.zev/fail ]] || (( _zev_rc != 0 )); then
    (( _zev_fail++ ))
    print -r -- "  ${_zev_c_fail}FAIL${_zev_c_off}  $_zev_t"
    if [[ -s $_zev_T/.zev/fail ]]; then
      _zev_indent $_zev_T/.zev/fail
    else
      print -r -- "        test exited with status $_zev_rc"
    fi
    if [[ -s $_zev_T/.zev/out ]]; then
      print -r -- "        --- output ---"
      _zev_indent $_zev_T/.zev/out
    fi
  else
    (( _zev_pass++ ))
    print -r -- "  ${_zev_c_ok}ok${_zev_c_off}    $_zev_t"
    (( _zev_verbose )) && [[ -s $_zev_T/.zev/out ]] && {
      print -r -- "        --- output ---"
      _zev_indent $_zev_T/.zev/out
    }
  fi
done

print -r -- "$_zev_rel $_zev_pass $_zev_fail $_zev_skip" > $_zev_results
exit 0
