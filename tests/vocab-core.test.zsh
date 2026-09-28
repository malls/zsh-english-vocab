# Tests for the vocab plugin core (functions/_zev_vocab_*): paths, word-list
# loading and lookup, shuffle, queue rotation and state files, locking,
# suppression, display formatting, hygiene, a real-pty run and timing.

# Most tests compare whole display lines; turn word-wrapping off (exported so
# child shells inherit it). The wrap tests set their own width.
export ZEV_VOCAB_WIDTH=0

autoload -Uz $ZEV_ROOT/functions/_zev_vocab_*(N.:t)

typeset -g PLUGIN=$ZEV_ROOT/zsh-english-vocab.plugin.zsh
typeset -ga WORDS5
WORDS5=(laconic lac ephemeral 'bête noire' sesquipedalian)
typeset -g TAB=$'\t'
typeset -g HIST_TS='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+00:00'

setup() {
  export ZEV_VOCAB_WORDS=$ZEV_FIXTURES/vocab/words5.tsv
  typeset -g SD=$XDG_STATE_HOME/zsh-english-vocab
}

teardown() {
  # Undo chmod tests so the runner can delete the temp dir.
  [[ -d $XDG_STATE_HOME ]] && chmod -R u+rwx $XDG_STATE_HOME 2>/dev/null
  return 0
}

# ---- helpers -------------------------------------------------------------

# gen_list N FILE -- write N synthetic entries w1..wN.
gen_list() {
  local i
  for (( i = 1; i <= $1; i++ )); do
    print -r -- "w$i${TAB}n.${TAB}synthetic definition number $i${TAB}from the test suite"
  done >| $2
}

# file_lines FILE -- reply=non-empty lines of FILE (empty if missing).
file_lines() {
  reply=()
  [[ -f $1 ]] && reply=( ${(f)"$(<$1)"} )
  return 0
}

# history_words -- reply=the word column of the history file.
history_words() {
  file_lines $SD/history
  reply=( ${reply#*$TAB} )
}

# spawn_next N [CALLS] -- N concurrent zsh processes, each calling
# _zev_vocab_next CALLS times (default 1) and printing each word; process i
# writes to $ZEV_TEST_TMPDIR/out.$i.
spawn_next() {
  local i calls=${2:-1}
  for (( i = 1; i <= $1; i++ )); do
    zsh -f -c '
      fpath=($ZEV_ROOT/functions $fpath)
      autoload -Uz $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
      integer k
      for (( k = 0; k < $1; k++ )); do
        _zev_vocab_next && print -r -- $REPLY || print -r -- "rc=$?"
      done' zsh $calls >| $ZEV_TEST_TMPDIR/out.$i 2>&1 &
  done
  wait
}

# spawn_output N -- reply=all lines of out.1..out.N.
spawn_output() {
  local i
  local -a all
  for (( i = 1; i <= $1; i++ )); do
    file_lines $ZEV_TEST_TMPDIR/out.$i
    all+=( $reply )
  done
  reply=( $all )
}

# strip_script VAR -- remove the CRs and "^D\b\b" that script(1) adds.
strip_script() {
  local v=${(P)1}
  v=${v//$'^D\b\b'/}
  v=${v//$'\r'/}
  typeset -g $1=$v
}

# ---- 1. paths ------------------------------------------------------------

test_state_dir_default_and_xdg() {
  local REPLY
  ( unset XDG_STATE_HOME; _zev_vocab_state_dir; print -r -- $REPLY ) >| $ZEV_TEST_TMPDIR/r
  assert_file_contents $ZEV_TEST_TMPDIR/r "$HOME/.local/state/zsh-english-vocab"
  XDG_STATE_HOME=/x/state _zev_vocab_state_dir
  assert_equal "$REPLY" /x/state/zsh-english-vocab
  XDG_STATE_HOME=rel/state _zev_vocab_state_dir
  assert_equal "$REPLY" "$HOME/.local/state/zsh-english-vocab" "relative XDG_STATE_HOME ignored"
  XDG_STATE_HOME= _zev_vocab_state_dir
  assert_equal "$REPLY" "$HOME/.local/state/zsh-english-vocab"
}

test_state_dir_create() {
  local REPLY
  _zev_vocab_state_dir
  assert_equal "$REPLY" "$SD"
  assert_file_not_exists $SD
  assert_status 0 _zev_vocab_state_dir -c
  assert_dir_exists $SD
  assert_status 0 _zev_vocab_state_dir -c
  XDG_STATE_HOME=/nonexistent/ro assert_status 1 _zev_vocab_state_dir -c
}

test_words_file_default_and_override() {
  local REPLY
  _zev_vocab_words_file
  assert_equal "$REPLY" "$ZEV_FIXTURES/vocab/words5.tsv"
  unset ZEV_VOCAB_WORDS
  _zev_vocab_words_file
  assert_equal "$REPLY" "$ZEV_ROOT/data/words.tsv"
  ( unset ZEV_ROOT; _zev_vocab_words_file )
  assert_equal $? 1 "both unset"
}

# ---- 2. readfile ---------------------------------------------------------

test_readfile_roundtrips_utf8() {
  local REPLY f=$ZEV_TEST_TMPDIR/u
  print -r -- 'bête noire — Lakōnikos' > $f
  assert_status 0 _zev_vocab_readfile $f
  assert_equal "$REPLY" $'bête noire — Lakōnikos\n'
  _zev_vocab_readfile $ZEV_FIXTURES/vocab/words5.tsv
  assert_equal "$REPLY" "$(<$ZEV_FIXTURES/vocab/words5.tsv)"$'\n'
}

test_readfile_missing_and_empty() {
  local REPLY=unchanged
  assert_status 1 _zev_vocab_readfile $ZEV_TEST_TMPDIR/missing
  assert_status 1 _zev_vocab_readfile $ZEV_TEST_TMPDIR
  assert_status 1 _zev_vocab_readfile ''
  : > $ZEV_TEST_TMPDIR/empty
  assert_status 0 _zev_vocab_readfile $ZEV_TEST_TMPDIR/empty
  assert_empty "$REPLY"
}

# ---- 3. load / lookup / words --------------------------------------------

test_load_does_not_clobber_reply() {
  local REPLY=keep
  local -a _zev_vocab_lines
  assert_status 0 _zev_vocab_load
  assert_equal "$REPLY" keep
  assert_equal $#_zev_vocab_lines 5
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/missing assert_status 1 _zev_vocab_load
  : > $ZEV_TEST_TMPDIR/empty
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/empty assert_status 1 _zev_vocab_load
}

test_lookup_exact_hit() {
  local REPLY
  local -a reply _zev_vocab_lines
  assert_status 0 _zev_vocab_lookup laconic
  assert_equal $#reply 4
  assert_equal "$reply[1]" laconic
  assert_equal "$reply[2]" adj.
  assert_equal "$reply[3]" "using very few words"
  assert_equal "$reply[4]" 'from Greek Lakōnikos, "of Laconia"'
  assert_equal "$REPLY" "laconic${TAB}adj.${TAB}using very few words${TAB}from Greek Lakōnikos, \"of Laconia\""
  assert_status 0 _zev_vocab_lookup 'bête noire'
  assert_equal "$reply[1]" 'bête noire'
}

test_lookup_prefix_is_not_a_match() {
  local REPLY
  local -a reply _zev_vocab_lines
  assert_status 0 _zev_vocab_lookup lac
  assert_equal "$reply[1]" lac
  assert_equal "$reply[2]" n.
  assert_status 1 _zev_vocab_lookup lacon
  assert_status 1 _zev_vocab_lookup aconic
}

test_lookup_case_insensitive() {
  local REPLY
  local -a reply _zev_vocab_lines
  assert_status 0 _zev_vocab_lookup -i LACONIC
  assert_equal "$reply[1]" laconic
  assert_status 0 _zev_vocab_lookup -i 'BÊTE Noire'
  assert_equal "$reply[1]" 'bête noire'
  assert_status 1 _zev_vocab_lookup LACONIC
}

test_lookup_missing_and_glob_chars() {
  local REPLY
  local -a reply _zev_vocab_lines
  assert_status 1 _zev_vocab_lookup nosuchword
  assert_status 1 _zev_vocab_lookup ''
  assert_status 1 _zev_vocab_lookup 'lac*'
  assert_status 1 _zev_vocab_lookup '[l]ac'
  assert_status 1 _zev_vocab_lookup '?ac'
  assert_status 1 _zev_vocab_lookup '*'
  assert_status 1 _zev_vocab_lookup -i 'LAC*'
  assert_status 1 _zev_vocab_lookup 'bête*'
}

test_lookup_loads_when_array_set_but_empty() {
  local REPLY
  local -a reply _zev_vocab_lines
  assert_status 0 _zev_vocab_lookup laconic
  # And the missing-file case is an error, not a crash.
  _zev_vocab_lines=()
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/missing assert_status 1 _zev_vocab_lookup laconic
}

test_lookup_tricky_entries() {
  local REPLY
  local -a reply _zev_vocab_lines
  export ZEV_VOCAB_WORDS=$ZEV_FIXTURES/vocab/words-tricky.tsv
  assert_status 0 _zev_vocab_lookup hapax
  assert_equal $#reply 4 "empty etymology still gives 4 fields"
  assert_empty "$reply[4]"
  assert_status 0 _zev_vocab_lookup "o'clock"
  assert_equal "$reply[2]" adv.
  assert_status 0 _zev_vocab_lookup printf
  assert_equal "$reply[3]" 'a format string like %d \n * [x] with $HOME and `cmd` kept verbatim'
}

test_words_in_file_order() {
  local -a reply _zev_vocab_lines
  assert_status 0 _zev_vocab_words
  assert_equal "${(j:|:)reply}" "${(j:|:)WORDS5}"
  _zev_vocab_lines=()
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/missing assert_status 1 _zev_vocab_words
}

# ---- 4. shuffle ----------------------------------------------------------

test_shuffle_is_permutation_and_deterministic() {
  local -a reply a b in
  in=( ${(f)"$(print -l w{1..30} 'x y' '*')"} )
  RANDOM=42
  _zev_vocab_shuffle $in
  a=( "$reply[@]" )
  assert_equal $#a $#in
  assert_equal "${(j:|:)${(@o)a}}" "${(j:|:)${(@o)in}}"
  RANDOM=42
  _zev_vocab_shuffle $in
  b=( "$reply[@]" )
  assert_equal "${(j:|:)b}" "${(j:|:)a}" "same seed, same order"
}

test_shuffle_edge_sizes() {
  local -a reply
  reply=(stale)
  _zev_vocab_shuffle
  assert_equal $#reply 0
  _zev_vocab_shuffle 'only one'
  assert_equal "${(j:|:)reply}" 'only one'
}

test_shuffle_not_identity() {
  local -a reply in
  in=( {1..20} )
  RANDOM=7
  _zev_vocab_shuffle $in
  assert_not_equal "${(j:|:)reply}" "${(j:|:)in}"
}

test_shuffle_first_position_uniform() {
  local -a reply
  local -A count
  integer i
  RANDOM=1
  for (( i = 0; i < 2000; i++ )); do
    _zev_vocab_shuffle a b c d
    (( count[$reply[1]]++ ))
  done
  print -r -- "first-position counts: a=$count[a] b=$count[b] c=$count[c] d=$count[d]"
  local k
  for k in a b c d; do
    (( count[$k] >= 400 && count[$k] <= 600 )) || fail "count[$k]=$count[$k] not in 400..600"
  done
}

# ---- 5-6. first run and full cycle ---------------------------------------

test_first_run_creates_state() {
  local REPLY
  local -a reply q all
  assert_file_not_exists $SD/queue
  assert_status 0 _zev_vocab_next
  local w=$REPLY
  assert_equal "$reply[1]" "$w" "reply holds the entry"
  assert_equal $#reply 4
  file_lines $SD/queue; q=( $reply )
  assert_equal $#q 4
  assert_equal ${#${(u)q}} 4 "queue words are distinct"
  all=( $w $q )
  assert_equal "${(j:|:)${(@o)all}}" "${(j:|:)${(@o)WORDS5}}"
  assert_file_contents $SD/current "$w"
  file_lines $SD/history
  assert_equal $#reply 1
  assert_match "$reply[1]" "$HIST_TS$TAB$w\$"
}

test_full_cycle_several_seeds() {
  local REPLY seed
  local -a reply shown
  integer i
  for seed in 1 2 3 7 42 1000; do
    rm -rf $SD
    RANDOM=$seed
    shown=()
    for (( i = 1; i <= 6; i++ )); do
      _zev_vocab_next || fail "seed $seed call $i: rc $?"
      shown+=( "$REPLY" )
    done
    assert_equal "${(j:|:)${(@o)shown[1,5]}}" "${(j:|:)${(@o)WORDS5}}" "seed $seed: calls 1-5"
    assert_not_equal "$shown[6]" "$shown[5]" "seed $seed: no repeat at cycle boundary"
    file_lines $SD/history
    assert_equal $#reply 6 "seed $seed: history lines"
    file_lines $SD/queue
    assert_equal $#reply 4 "seed $seed: queue after refill"
  done
}

# ---- 7-8. removed and added words ----------------------------------------

test_removed_words_are_skipped() {
  local REPLY
  _zev_vocab_state_dir -c
  print -l gone1 laconic gone2 > $SD/queue
  assert_status 0 _zev_vocab_next
  assert_equal "$REPLY" laconic
  assert_file_contents $SD/queue gone2
  assert_status 0 _zev_vocab_next
  (( ${WORDS5[(Ie)$REPLY]} )) || fail "not a fixture word: $REPLY"
  file_lines $SD/queue
  assert_equal $#reply 4 "refilled after skipping gone2"
}

test_queue_of_unknown_words_refills() {
  local REPLY
  _zev_vocab_state_dir -c
  print -l x y 'z z' > $SD/queue
  assert_status 0 _zev_vocab_next
  (( ${WORDS5[(Ie)$REPLY]} )) || fail "not a fixture word: $REPLY"
  file_lines $SD/queue
  assert_equal $#reply 4
}

test_added_words_appear_after_refill() {
  local REPLY list=$ZEV_TEST_TMPDIR/list.tsv
  local -a shown
  integer i
  cp $ZEV_FIXTURES/vocab/words5.tsv $list
  export ZEV_VOCAB_WORDS=$list
  _zev_vocab_next
  print -r -- "newword${TAB}n.${TAB}a fresh addition${TAB}from the test" >> $list
  for (( i = 1; i <= 4; i++ )); do
    _zev_vocab_next || fail "call $i"
    assert_not_equal "$REPLY" newword "not before the queue is exhausted"
  done
  assert_equal "$(<$SD/queue)" "" "queue exhausted"
  shown=()
  for (( i = 1; i <= 6; i++ )); do
    _zev_vocab_next || fail "cycle 2 call $i"
    shown+=( "$REPLY" )
  done
  (( ${shown[(Ie)newword]} )) || fail "newword not shown after refill: $shown"
  assert_equal ${#${(u)shown}} 6
}

# ---- 9. robustness -------------------------------------------------------

test_queue_with_blank_lines_and_duplicates() {
  local REPLY
  _zev_vocab_state_dir -c
  print -rn -- $'\n\nlac\n\nlac\nephemeral\n\n' > $SD/queue
  assert_status 0 _zev_vocab_next
  assert_equal "$REPLY" lac
  assert_status 0 _zev_vocab_next
  assert_equal "$REPLY" lac
  assert_status 0 _zev_vocab_next
  assert_equal "$REPLY" ephemeral
  assert_equal "$(<$SD/queue)" ""
  assert_status 0 _zev_vocab_next
}

test_missing_current_is_ok() {
  local REPLY
  _zev_vocab_next
  rm -f $SD/current
  assert_status 0 _zev_vocab_next
  assert_status 1 eval 'rm -f $SD/current; _zev_vocab_current'
}

test_missing_or_empty_words_file() {
  export ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/missing.tsv
  assert_status 1 _zev_vocab_next
  assert_file_not_exists $SD/queue
  : > $ZEV_TEST_TMPDIR/empty.tsv
  export ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/empty.tsv
  assert_status 1 _zev_vocab_next
  assert_file_not_exists $SD/queue
  export _ZEV_VOCAB_ASSUME_TTY=1
  export ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/missing.tsv
  run _zev_vocab_startup
  assert_status 0
  assert_empty "$output"
  assert_empty "$stderr"
}

test_unwritable_state_dir_is_silent() {
  local impl
  export _ZEV_VOCAB_ASSUME_TTY=1
  for impl in flock mkdir; do
    rm -rf $SD
    _zev_vocab_state_dir -c
    assert_equal "$(print -r -- $SD/*(DN))" "" "state dir starts empty"
    chmod 500 $SD
    _ZEV_VOCAB_LOCK_IMPL=$impl run _zev_vocab_startup
    chmod 700 $SD
    assert_status 0
    assert_empty "$output" "$impl: no output"
    assert_empty "$stderr" "$impl: no stderr"
  done
}

test_readonly_queue_fails_without_recording() {
  local REPLY
  export _ZEV_VOCAB_ASSUME_TTY=1
  _zev_vocab_next
  local cur="$(<$SD/current)"
  chmod 444 $SD/queue
  assert_status 1 _zev_vocab_next
  run _zev_vocab_startup
  assert_status 0
  assert_empty "$output"
  assert_empty "$stderr"
  assert_file_contents $SD/current "$cur"
  file_lines $SD/history
  assert_equal $#reply 1 "no history written"
}

# ---- 10. locking ---------------------------------------------------------

_check_spawn8() {
  local list=$ZEV_TEST_TMPDIR/w20.tsv
  gen_list 20 $list
  export ZEV_VOCAB_WORDS=$list ZEV_VOCAB_LOCK_TIMEOUT=10
  spawn_next 8
  spawn_output 8
  assert_equal $#reply 8 "8 words printed"
  assert_equal ${#${(u)reply}} 8 "8 distinct words: $reply"
  assert_equal ${#${(M)reply:#w<->}} 8 "all are words: $reply"
  file_lines $SD/queue
  assert_equal $#reply 12
  file_lines $SD/history
  assert_equal $#reply 8
}

test_lock_concurrent_8_flock() {
  _check_spawn8
}

test_lock_concurrent_8_mkdir() {
  export _ZEV_VOCAB_LOCK_IMPL=mkdir
  _check_spawn8
  assert_file_not_exists $SD/lock.d
}

_check_stress() {
  local list=$ZEV_TEST_TMPDIR/w12.tsv
  local -a words hist chunk
  integer i
  gen_list 12 $list
  words=( w{1..12} )
  export ZEV_VOCAB_WORDS=$list ZEV_VOCAB_LOCK_TIMEOUT=20
  spawn_next 16 4
  spawn_output 16
  assert_equal $#reply 64 "64 pops"
  assert_equal ${#${(M)reply:#w<->}} 64 "every pop succeeded: ${(M)reply:#rc=*}"
  history_words
  hist=( $reply )
  assert_equal $#hist 64
  for (( i = 1; i + 11 <= $#hist; i += 12 )); do
    chunk=( $hist[i,i+11] )
    assert_equal "${(j: :)${(@on)chunk}}" "${(j: :)${(@on)words}}" "chunk at $i is a permutation"
  done
  for (( i = 2; i <= $#hist; i++ )); do
    [[ $hist[i] != $hist[i-1] ]] || fail "adjacent repeat at history line $i: $hist[i]"
  done
}

test_lock_stress_flock() {
  _check_stress
}

test_lock_stress_mkdir() {
  export _ZEV_VOCAB_LOCK_IMPL=mkdir
  _check_stress
}

# _check_contention IMPL -- another process holds the lock: timeout, then
# success after the holder dies.
_check_contention() {
  local REPLY ready=$ZEV_TEST_TMPDIR/ready q h
  integer holder i
  _zev_vocab_next || fail "initial next"
  q="$(<$SD/queue)" h="$(<$SD/history)"
  if [[ $1 == mkdir ]]; then
    zsh -f -c 'zmodload zsh/zselect; mkdir $1/lock.d && print -r -- $$ > $1/lock.d/pid && : > $2 && zselect -t 3000' \
      zsh $SD $ready &
  else
    zsh -f -c 'zmodload zsh/system zsh/zselect; zsystem flock -f fd $1/lock && : > $2 && zselect -t 3000' \
      zsh $SD $ready &
  fi
  holder=$!
  for (( i = 0; i < 500; i++ )); do
    [[ -e $ready ]] && break
    zselect -t 1
  done
  [[ -e $ready ]] || fail "holder never became ready"
  ZEV_VOCAB_LOCK_TIMEOUT=0.2 assert_status 2 _zev_vocab_next
  assert_equal "$(<$SD/queue)" "$q" "queue unchanged"
  assert_equal "$(<$SD/history)" "$h" "history unchanged"
  kill $holder
  wait $holder 2>/dev/null
  assert_status 0 _zev_vocab_next
  file_lines $SD/history
  assert_equal $#reply 2
}

test_lock_contention_flock() {
  zmodload zsh/zselect
  _check_contention flock
}

test_lock_contention_mkdir() {
  zmodload zsh/zselect
  export _ZEV_VOCAB_LOCK_IMPL=mkdir
  _check_contention mkdir
  assert_file_not_exists $SD/lock.d
}

test_lock_mkdir_stale_pid_is_broken() {
  zmodload zsh/datetime
  local REPLY
  integer dead
  export _ZEV_VOCAB_LOCK_IMPL=mkdir ZEV_VOCAB_LOCK_TIMEOUT=1
  zsh -f -c : &
  dead=$!
  wait $dead
  _zev_vocab_state_dir -c
  mkdir $SD/lock.d
  print -r -- $dead > $SD/lock.d/pid
  float t0=$EPOCHREALTIME
  assert_status 0 _zev_vocab_next
  (( EPOCHREALTIME - t0 < 0.9 )) || fail "stale lock took $(( EPOCHREALTIME - t0 ))s"
  assert_file_not_exists $SD/lock.d
  local -a leftovers
  leftovers=( $SD/lock.d.stale*(N) )
  assert_equal $#leftovers 0 "no leftover stale dirs"
}

test_lock_mkdir_empty_pid_is_broken_at_timeout() {
  local REPLY
  export _ZEV_VOCAB_LOCK_IMPL=mkdir ZEV_VOCAB_LOCK_TIMEOUT=0.1
  _zev_vocab_state_dir -c
  mkdir $SD/lock.d
  assert_status 0 _zev_vocab_next
  assert_file_not_exists $SD/lock.d
}

test_lock_sequential_calls_do_not_deadlock() {
  local REPLY impl
  integer i
  for impl in flock mkdir; do
    for (( i = 1; i <= 3; i++ )); do
      _ZEV_VOCAB_LOCK_IMPL=$impl ZEV_VOCAB_LOCK_TIMEOUT=0.2 assert_status -m "$impl call $i" 0 _zev_vocab_next
    done
  done
  file_lines $SD/history
  assert_equal $#reply 6
}

test_lock_unlock_tokens() {
  local REPLY tok
  _zev_vocab_state_dir -c
  assert_status 0 _zev_vocab_lock $SD
  tok=$REPLY
  assert_match "$tok" '^[0-9]+$'
  _zev_vocab_unlock $tok
  _ZEV_VOCAB_LOCK_IMPL=mkdir assert_status 0 _zev_vocab_lock $SD
  assert_equal "$REPLY" "dir:$SD/lock.d"
  assert_file_contents $SD/lock.d/pid $$
  _zev_vocab_unlock $REPLY
  assert_file_not_exists $SD/lock.d
  assert_status 1 _zev_vocab_lock $ZEV_TEST_TMPDIR/nonexistent
}

test_lock_mkdir_unlock_leaves_a_lock_taken_over_by_another_process() {
  local REPLY tok
  _zev_vocab_state_dir -c
  _ZEV_VOCAB_LOCK_IMPL=mkdir assert_status 0 _zev_vocab_lock $SD
  tok=$REPLY
  print -r -- 999999 >| $SD/lock.d/pid      # another process now owns it
  _zev_vocab_unlock $tok
  assert_dir_exists $SD/lock.d
  assert_file_contents $SD/lock.d/pid 999999
}

test_record_without_datetime_leaves_timestamp_empty() {
  local REPLY
  _zev_vocab_state_dir -c
  strftime() { return 1 }
  _zev_vocab_record laconic
  assert_file_contents $SD/history $'\tlaconic'
}

test_lookup_i_non_ascii_under_no_multibyte() {
  local REPLY
  local -a reply _zev_vocab_lines
  setopt no_multibyte
  assert_status 0 _zev_vocab_lookup -i $'B\u00caTE NOIRE'
  assert_equal "$reply[1]" 'bête noire'
}

# ---- word wrap -------------------------------------------------------------

# wrapcheck TEXT WIDTH -- REPLY wrapped; assert every visible line fits, no word
# is split (re-joining lines with spaces gives the text back) and SGR takes no
# width.
wrapcheck() {
  local text=$1 l plain
  ZEV_VOCAB_WIDTH=$2 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap "$text"
  assert_equal "${REPLY//$'\n'/ }" "$text" "no word split (width $2)"
  for l in "${(@f)REPLY}"; do
    plain=${l//$'\e'\[[0-9;]#m/}
    (( ${#plain} <= $2 )) || [[ $plain != *' '* ]] || fail "line too wide at $2: $plain"
  done
}

test_wrap_breaks_only_between_words() {
  setopt extended_glob
  local REPLY
  local -a reply _zev_vocab_lines
  export ZEV_VOCAB_WORDS=$ZEV_ROOT/data/words.tsv
  _zev_vocab_lookup petrichor
  _zev_vocab_format "${reply[@]}"
  local plain=$REPLY
  wrapcheck "$plain" 40
  assert_true -m "wrapped into several lines" test "${#${(@f)REPLY}}" -ge 3
  _zev_vocab_format -c "${reply[@]}"
  wrapcheck "$REPLY" 40
  local stripped=${REPLY//$'\e'\[[0-9;]#m/}
  assert_equal "${stripped//$'\n'/ }" "$plain" "colored text wraps like plain"
}

test_wrap_every_real_entry_at_common_widths() {
  setopt extended_glob
  local REPLY line w
  local -a f
  for w in 40 80 120; do
    while IFS= read -r line; do
      f=( "${(@ps:\t:)line}" )
      _zev_vocab_format -c "${f[@]}"
      wrapcheck "$REPLY" $w
    done < $ZEV_ROOT/data/words.tsv
  done
}

test_wrap_short_long_and_off() {
  local REPLY
  ZEV_VOCAB_WIDTH=40 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap 'short line'
  assert_equal "$REPLY" 'short line'
  ZEV_VOCAB_WIDTH=20 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap 'a floccinaucinihilipilification b'
  assert_equal "$REPLY" $'a\nfloccinaucinihilipilification\nb' "long word on its own line"
  local long='one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty'
  ZEV_VOCAB_WIDTH=0 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap "$long"
  assert_equal "$REPLY" "$long" "width 0 turns wrapping off"
  unset ZEV_VOCAB_WIDTH
  _zev_vocab_wrap "$long"
  assert_equal "$REPLY" "$long" "not a tty: unchanged"
  COLUMNS=50 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap "$long"
  assert_equal "${#${(@f)REPLY}}" 3 "COLUMNS used when ZEV_VOCAB_WIDTH is unset"
  COLUMNS=5 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap "$long"
  assert_equal "${#${(@f)REPLY}}" 2 "tiny COLUMNS falls back to 80"
  ZEV_VOCAB_WIDTH=auto COLUMNS=50 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap "$long"
  assert_equal "${#${(@f)REPLY}}" 3 "non-numeric ZEV_VOCAB_WIDTH falls back to COLUMNS"
  ZEV_VOCAB_WIDTH=5 COLUMNS=50 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap "$long"
  assert_equal "${#${(@f)REPLY}}" 3 "tiny ZEV_VOCAB_WIDTH falls back to COLUMNS"
  ZEV_VOCAB_WIDTH=20 _ZEV_VOCAB_ASSUME_TTY=1 _zev_vocab_wrap '日本語日本語日本語 日本語日本語'
  assert_equal "$REPLY" $'日本語日本語日本語\n日本語日本語' "wide characters count two columns"
}

test_startup_wraps_to_width() {
  local REPLY
  export ZEV_VOCAB_WORDS=$ZEV_ROOT/data/words.tsv _ZEV_VOCAB_ASSUME_TTY=1 NO_COLOR=1
  run zsh -f -c 'fpath=($1/functions $fpath); autoload -Uz $1/functions/_zev_vocab_*(N:t)
    ZEV_VOCAB_WIDTH=30 _zev_vocab_startup' zsh $ZEV_ROOT
  assert_status 0
  assert_true -m "several lines" test "$#lines" -ge 2
  local l
  for l in "${lines[@]}"; do
    (( ${#l} <= 30 )) || [[ $l != *' '* ]] || fail "too wide: $l"
  done
}

# ---- 11-12. suppression and once per shell -------------------------------

test_suppression_env_rules() {
  local -a cases
  local c
  export _ZEV_VOCAB_ASSUME_TTY=1
  cases=(
    'ZEV_VOCAB_DISABLE=1:disabled'
    'ZEV_VOCAB_DISABLE=yes:disabled'
    'TMUX=/tmp/x,1,0:tmux'
    'SSH_CONNECTION=1 2 3 4:ssh'
    'SSH_TTY=/dev/ttys9:ssh'
  )
  for c in $cases; do
    run env ${c%:*} zsh -f -c '
      fpath=($ZEV_ROOT/functions $fpath)
      autoload -Uz $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
      _zev_vocab_suppressed && print -r -- "reason=$REPLY"
      _zev_vocab_startup; print -r -- "rc=$?"'
    assert_equal "$output" "reason=${c##*:}"$'\nrc=0' "$c"
    assert_empty "$stderr" "$c"
    assert_file_not_exists $SD "$c: no state dir"
  done
}

test_suppression_disable_zero_or_empty_prints() {
  local v
  export _ZEV_VOCAB_ASSUME_TTY=1
  for v in 0 ''; do
    run env ZEV_VOCAB_DISABLE=$v zsh -f -c '
      fpath=($ZEV_ROOT/functions $fpath)
      autoload -Uz $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
      _zev_vocab_suppressed || print -r -- not-suppressed
      _zev_vocab_startup'
    assert_equal $#lines 2 "DISABLE='$v'"
    assert_equal "$lines[1]" not-suppressed
    assert_match "$lines[2]" '(laconic|lac|ephemeral|bête noire|sesquipedalian)'
  done
}

test_suppression_noninteractive_without_seam() {
  local REPLY
  unset _ZEV_VOCAB_ASSUME_TTY
  assert_status 0 _zev_vocab_suppressed
  assert_equal "$REPLY" noninteractive
  run _zev_vocab_startup
  assert_status 0
  assert_empty "$output"
  assert_file_not_exists $SD
}

test_startup_once_per_shell() {
  export _ZEV_VOCAB_ASSUME_TTY=1
  run eval '_zev_vocab_startup; _zev_vocab_startup; print -r -- "rc=$?"'
  assert_equal $#lines 2
  assert_equal "$lines[2]" rc=0
  file_lines $SD/history
  assert_equal $#reply 1
}

# ---- 13. display ---------------------------------------------------------

test_format_plain_and_color() {
  local REPLY
  _zev_vocab_format laconic adj. 'using very few words' 'from Greek Lakōnikos, "of Laconia"'
  assert_equal "$REPLY" 'laconic (adj.): using very few words — from Greek Lakōnikos, "of Laconia"'
  _zev_vocab_format -c laconic adj. 'using very few words' 'from Greek Lakōnikos, "of Laconia"'
  assert_equal "$REPLY" $'\e[1mlaconic\e[0m \e[2m(adj.)\e[0m: using very few words\e[2m — from Greek Lakōnikos, "of Laconia"\e[0m'
}

test_format_empty_etymology() {
  local REPLY
  _zev_vocab_format hapax n. 'a word that occurs once' ''
  assert_equal "$REPLY" 'hapax (n.): a word that occurs once'
  _zev_vocab_format -c hapax n. 'a word that occurs once' ''
  assert_equal "$REPLY" $'\e[1mhapax\e[0m \e[2m(n.)\e[0m: a word that occurs once'
  assert_not_contains "$REPLY" ' — '
}

test_startup_prints_tricky_definition_verbatim() {
  local want
  export _ZEV_VOCAB_ASSUME_TTY=1 NO_COLOR=1
  export ZEV_VOCAB_WORDS=$ZEV_FIXTURES/vocab/words-tricky.tsv
  _zev_vocab_state_dir -c
  print -r -- printf > $SD/queue
  run _zev_vocab_startup
  want='printf (n.): a format string like %d \n * [x] with $HOME and `cmd` kept verbatim — from C print formatted'
  assert_equal "$output" "$want"
}

test_color_rules() {
  unset NO_COLOR _ZEV_VOCAB_ASSUME_TTY
  assert_false -m "no tty, no seam" _zev_vocab_color
  export _ZEV_VOCAB_ASSUME_TTY=1
  assert_true -m "seam" _zev_vocab_color
  NO_COLOR=1 assert_false -m NO_COLOR _zev_vocab_color
  TERM=dumb assert_false -m TERM=dumb _zev_vocab_color
}

test_startup_colored_and_no_color() {
  export _ZEV_VOCAB_ASSUME_TTY=1
  _zev_vocab_state_dir -c
  print -r -- laconic > $SD/queue
  run _zev_vocab_startup
  assert_equal "$output" $'\e[1mlaconic\e[0m \e[2m(adj.)\e[0m: using very few words\e[2m — from Greek Lakōnikos, "of Laconia"\e[0m'
  print -r -- lac > $SD/queue
  NO_COLOR=1 run _zev_vocab_startup
  assert_equal "$output" 'lac (n.): a resinous substance secreted by the lac insect, used to make shellac — from Hindi lākh, from Sanskrit lākṣā'
}

# ---- 14. hygiene ---------------------------------------------------------

test_hygiene_user_options() {
  export _ZEV_VOCAB_ASSUME_TTY=1 NO_COLOR=1
  _zev_vocab_state_dir -c
  print -rl -- 'bête noire' laconic > $SD/queue
  run zsh -f -c '
    fpath=($ZEV_ROOT/functions $fpath)
    autoload -Uz $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
    setopt ksh_arrays sh_word_split no_multibyte extended_glob
    before="$(setopt)"
    _zev_vocab_startup
    _zev_vocab_lookup -i LACONIC && print -r -- "lookup=${(j:|:)reply[@]}"
    _zev_vocab_shuffle "a b" c && print -r -- "n=${#reply[@]}"
    _zev_vocab_words && print -r -- "words=${#reply[@]}"
    _zev_vocab_next && print -r -- "next=$REPLY"
    [[ "$(setopt)" == "$before" ]] && print options-unchanged'
  assert_empty "$stderr"
  assert_equal "$lines[1]" 'bête noire (n.): a person or thing one particularly dislikes — from French, literally "black beast"'
  assert_equal "$lines[2]" 'lookup=laconic|adj.|using very few words|from Greek Lakōnikos, "of Laconia"'
  assert_equal "$lines[3]" n=2
  assert_equal "$lines[4]" words=5
  assert_equal "$lines[5]" next=laconic
  assert_equal "$lines[6]" options-unchanged
}

test_hygiene_no_new_globals() {
  export _ZEV_VOCAB_ASSUME_TTY=1
  run zsh -f -c '
    fpath=($ZEV_ROOT/functions $fpath)
    autoload -Uz $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
    zmodload zsh/datetime zsh/system zsh/files zsh/zselect
    typeset -a before after new
    before=( ${(k)parameters} )
    _zev_vocab_startup >/dev/null
    after=( ${(k)parameters} )
    new=( ${after:|before} )
    print -r -- "new=${(j: :)${(@o)new}}"
    print -r -- "lines=${+_zev_vocab_lines}"
    for impl in mkdir; do
      _ZEV_VOCAB_LOCK_IMPL=$impl
      unset _zev_vocab_started
      before=( ${(k)parameters} )
      _zev_vocab_startup >/dev/null
      after=( ${(k)parameters} )
      new=( ${after:|before} )
      print -r -- "new=${(j: :)${(@o)new}}"
    done'
  assert_empty "$stderr"
  assert_equal "$lines[1]" new=_zev_vocab_started
  assert_equal "$lines[2]" lines=0
  assert_equal "$lines[3]" new=_zev_vocab_started "mkdir lock"
  file_lines $SD/history
  assert_equal $#reply 2
}

test_hygiene_no_path_needed() {
  export _ZEV_VOCAB_ASSUME_TTY=1
  run eval 'path=(/nonexistent); _zev_vocab_startup'
  assert_empty "$stderr"
  assert_match "$output" 'laconic|lac|ephemeral|bête noire|sesquipedalian'
  run eval 'path=(/nonexistent); _ZEV_VOCAB_LOCK_IMPL=mkdir _zev_vocab_startup'
  assert_empty "$stderr"
  assert_not_empty "$output"
}

test_hygiene_no_command_substitution() {
  run grep -nE '\$\([^(<]|`' $ZEV_ROOT/functions/_zev_vocab_*
  assert_empty "$output"
  assert_status 1
}

# ---- 15. real pty end-to-end ---------------------------------------------

test_pty_end_to_end() {
  run script -q /dev/null zsh -f -c '[[ -t 1 ]] && print TTY'
  [[ $output == *TTY* ]] || skip "script(1) gives no pty here"
  run script -q /dev/null zsh -f -i -c "source ${(q)PLUGIN}"
  strip_script output
  assert_match "$output" $'\e\\[1m(laconic|lac|ephemeral|bête noire|sesquipedalian)\e\\[0m'
  assert_file_exists $SD/current
  assert_equal $#lines 1

  rm -rf $SD
  run script -q /dev/null zsh -f -i -c "source ${(q)PLUGIN} >/dev/null"
  assert_file_not_exists $SD/queue "stdout not a tty: no word consumed"

  run env TMUX=x script -q /dev/null zsh -f -i -c "source ${(q)PLUGIN}"
  strip_script output
  assert_empty "$output"
  assert_file_not_exists $SD/queue
}

# ---- 16. timing ----------------------------------------------------------

# _time_startups N [REFILL] -- reply=ms for N fresh shells sourcing the plugin.
_time_startups() {
  local -a ms
  integer i
  for (( i = 1; i <= $1; i++ )); do
    [[ -n $2 ]] && rm -f $SD/queue
    ms+=( "$(zsh -f -c 'zmodload zsh/datetime; t0=$EPOCHREALTIME; source $1 >/dev/null; print $(( (EPOCHREALTIME-t0)*1000 ))' zsh $PLUGIN)" )
  done
  reply=( $ms )
}

test_timing_startup() {
  local list=$ZEV_TEST_TMPDIR/w1200.tsv best
  local REPLY
  gen_list 1200 $list
  export ZEV_VOCAB_WORDS=$list _ZEV_VOCAB_ASSUME_TTY=1
  _zev_vocab_next || fail "initial next"
  _time_startups 5
  best=${${(@on)reply}[1]}
  print -r -- "steady state ms: ${(j: :)${(@)reply%.*}} (best ${best%.*})"
  (( best < 25 )) || fail "steady-state best ${best} ms >= 25 ms"
  _time_startups 3 refill
  best=${${(@on)reply}[1]}
  print -r -- "refill ms: ${(j: :)${(@)reply%.*}} (best ${best%.*})"
  (( best < 60 )) || fail "refill best ${best} ms >= 60 ms"
}
