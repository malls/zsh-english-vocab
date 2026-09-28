# Tests for the vocab command (functions/vocab, functions/_zev_vocab_cmd_*)
# and its completion (functions/_vocab): dispatch, show/next, colour, search,
# favorites, history, concurrency, completion and hygiene.

# Most tests compare whole display lines; turn word-wrapping off (exported so
# child shells inherit it). The wrap tests set their own width.
export ZEV_VOCAB_WIDTH=0

autoload -Uz vocab _vocab $ZEV_ROOT/functions/_zev_vocab_*(N.:t)

typeset -g PLUGIN=$ZEV_ROOT/zsh-english-vocab.plugin.zsh
typeset -g TAB=$'\t'
typeset -g HIST_LINE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}  .+$'
typeset -g LACONIC='laconic (adj.): using very few words — from Greek Lakōnikos, "of Laconia"'

setup() {
  print -r -- $'laconic\tadj.\tusing very few words\tfrom Greek Lakōnikos, "of Laconia"
lac\tn.\ta resinous secretion of the lac insect\tfrom Hindi lākh
ephemeral\tadj.\tlasting a very short time\tfrom Greek ephēmeros, "lasting a day"
bête noire\tn.\ta person or thing one especially dislikes\tFrench, "black beast"
sesquipedalian\tadj.\tgiven to using long words\tfrom Latin sesquipedalis, "a foot and a half long"
Zeitgeist\tn.\tthe spirit of the age\tGerman, "time spirit"' >| $ZEV_TEST_TMPDIR/words.tsv
  export ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/words.tsv
  unset NO_COLOR _ZEV_VOCAB_ASSUME_TTY
  typeset -g S=$XDG_STATE_HOME/zsh-english-vocab
}

teardown() {
  [[ -n ${HOLDER-} ]] && kill $HOLDER 2>/dev/null
  return 0
}

# ---- helpers -------------------------------------------------------------

# file_lines FILE -- reply=non-empty lines of FILE (empty if missing).
file_lines() {
  reply=()
  [[ -f $1 ]] && reply=( ${(f)"$(<$1)"} )
  return 0
}

# hist_count -- REPLY=number of lines in the history file.
hist_count() {
  file_lines $S/history
  REPLY=$#reply
}

# hold_lock SECS -- a separate process takes the state lock and keeps it for
# SECS seconds (HOLDER=its pid). Returns once the lock is held.
hold_lock() {
  zmodload zsh/zselect zsh/datetime
  rm -f $ZEV_TEST_TMPDIR/ready
  zsh -f -c '
    fpath=($ZEV_ROOT/functions $fpath)
    autoload -Uz $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
    _zev_vocab_state_dir -c && _zev_vocab_lock $REPLY || exit 1
    : >$ZEV_TEST_TMPDIR/ready
    # Wait in this process: an exec would close the lock fd (close-on-exec).
    zmodload zsh/zselect
    zselect -t $(( $1 * 100 ))' zsh $1 &
  typeset -g HOLDER=$!
  float deadline=$(( EPOCHREALTIME + 5 ))
  while [[ ! -e $ZEV_TEST_TMPDIR/ready ]]; do
    (( EPOCHREALTIME < deadline )) || fail "lock holder never became ready"
    zselect -t 5
  done
}

# mkhist N -- write N history lines "2026-09-27T14:32:00+00:00<TAB>wordI".
mkhist() {
  mkdir -p $S
  print -rl -- "2026-09-27T14:32:00+00:00${TAB}word"{1..$1} >| $S/history
}

# ---- 1. dispatch and help ------------------------------------------------

test_help_variants() {
  local a w
  for a in help -h --help; do
    run vocab $a
    assert_status -m "$a" 0
    assert_empty "$stderr" "$a"
    assert_contains "$output" 'usage: vocab [command]' "$a"
    for w in next search fav unfav favs history help; do
      assert_contains "$output" "vocab $w" "$a lists $w"
    done
  done
  run vocab help extra
  assert_status -m "help rejects args" 2
  assert_empty "$output"
}

test_unknown_command() {
  run vocab bogus
  assert_status 2
  assert_empty "$output"
  assert_contains "$stderr" 'vocab: unknown command: bogus'
  assert_contains "$stderr" 'usage: vocab'
  run vocab ''
  assert_status -m "empty command" 2
  assert_contains "$stderr" 'vocab: unknown command: '
}

test_extra_args_are_usage_errors() {
  run vocab next x
  assert_status -m "next x" 2
  assert_empty "$output"
  assert_contains "$stderr" 'vocab: next takes no arguments'
  run vocab favs x
  assert_status -m "favs x" 2
  assert_contains "$stderr" 'vocab: favs takes no arguments'
  assert_file_not_exists $S "usage errors touch no state"
}

# ---- 2. show -------------------------------------------------------------

test_show_with_no_state_pops_a_word() {
  local REPLY
  run vocab
  assert_status 0
  assert_empty "$stderr"
  assert_equal $#lines 1
  assert_file_exists $S/current
  hist_count
  assert_equal $REPLY 1
}

test_show_twice_is_read_only() {
  local first queue REPLY
  run vocab
  first=$output
  queue="$(<$S/queue)"
  run vocab
  assert_status 0
  assert_equal "$output" "$first"
  hist_count
  assert_equal $REPLY 1 "reprint records nothing"
  assert_equal "$(<$S/queue)" "$queue" "queue unchanged"
}

test_show_current_not_in_list_pops() {
  local REPLY
  mkdir -p $S
  print -r -- gone >| $S/current
  mkhist 1
  run vocab
  assert_status 0
  assert_not_contains "$output" gone
  assert_equal $#lines 1
  hist_count
  assert_equal $REPLY 2
  assert_not_equal "$(<$S/current)" gone
}

test_show_ignores_suppression() {
  run env ZEV_VOCAB_DISABLE=1 TMUX=x SSH_TTY=x SSH_CONNECTION=x zsh -f -c '
    fpath=($ZEV_ROOT/functions $fpath)
    autoload -Uz vocab $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
    vocab'
  assert_status 0
  assert_equal $#lines 1
  assert_match "$output" '^(laconic|lac|ephemeral|bête noire|sesquipedalian|Zeitgeist) \('
}

# ---- 3. next -------------------------------------------------------------

test_next_advances() {
  local a b REPLY
  run vocab next
  assert_status 0
  a=$output
  run vocab next
  assert_status 0
  b=$output
  assert_not_equal "$b" "$a"
  hist_count
  assert_equal $REPLY 2
  run vocab
  assert_equal "$output" "$b" "vocab reprints the last word"
}

test_next_output_format() {
  mkdir -p $S
  print -r -- ephemeral >| $S/current
  print -rl -- laconic lac >| $S/queue
  run vocab next
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" "$LACONIC"
  assert_equal "$(<$S/current)" laconic
  assert_equal "$(<$S/queue)" lac
}

test_next_lock_busy() {
  local before REPLY
  mkhist 2
  hold_lock 3
  hist_count
  before=$REPLY
  ZEV_VOCAB_LOCK_TIMEOUT=0.2 run vocab next
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" 'vocab: state is busy'
  hist_count
  assert_equal $REPLY $before "history unchanged"
  kill $HOLDER 2>/dev/null
}

test_next_missing_or_empty_list() {
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/none run vocab next
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" "vocab: word list not found: $ZEV_TEST_TMPDIR/none"
  assert_file_not_exists $S
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/none run vocab
  assert_status 1
  assert_contains "$stderr" 'word list not found'
  : >| $ZEV_TEST_TMPDIR/empty.tsv
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/empty.tsv run vocab next
  assert_status 1
  assert_contains "$stderr" 'vocab: word list is empty'
  assert_file_not_exists $S
}

test_no_word_list_configured() {
  run zsh -f -c '
    fpath=($ZEV_ROOT/functions $fpath)
    autoload -Uz vocab $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
    unset ZEV_VOCAB_WORDS ZEV_ROOT
    vocab next'
  assert_status 1
  assert_contains "$stderr" 'vocab: no word list (set ZEV_VOCAB_WORDS or load the plugin)'
}

# ---- 4. colour -----------------------------------------------------------

test_colour() {
  _ZEV_VOCAB_ASSUME_TTY=1 run vocab
  assert_contains "$output" $'\e[1m'
  _ZEV_VOCAB_ASSUME_TTY=1 NO_COLOR=1 run vocab
  assert_not_contains "$output" $'\e'
  run vocab
  assert_not_contains "$output" $'\e' "piped: plain"
}

# ---- 5. search -----------------------------------------------------------

test_output_wraps_at_word_boundaries_on_a_tty() {
  export _ZEV_VOCAB_ASSUME_TTY=1 NO_COLOR=1
  ZEV_VOCAB_WIDTH=24 run vocab search sesquipedalian
  assert_status 0
  assert_equal "$output" $'sesquipedalian (adj.):\ngiven to using long\nwords — from Latin\nsesquipedalis, "a foot\nand a half long"'
  vocab next >/dev/null
  ZEV_VOCAB_WIDTH=40 run vocab history
  assert_true -m "history wraps too" test "$#lines" -ge 2
  assert_match "$lines[1]" '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}  ' "timestamp keeps its two spaces"
  local l
  for l in "${lines[@]}"; do
    (( ${#l} <= 40 )) || [[ $l != *' '* ]] || fail "history line too wide: $l"
    [[ $l != *' ' ]] || fail "trailing space: '$l'"
  done
  unset _ZEV_VOCAB_ASSUME_TTY
  ZEV_VOCAB_WIDTH=24 run vocab search sesquipedalian
  assert_equal "$#lines" 1 "piped output stays one line per entry"
}

test_search_exact_then_prefix() {
  run vocab search LAC
  assert_status 0
  assert_equal $#lines 2
  assert_equal "$lines[1]" 'lac (n.): a resinous secretion of the lac insect — from Hindi lākh'
  assert_equal "$lines[2]" "$LACONIC"
}

test_search_substring_unicode_and_spaces() {
  run vocab search noir
  assert_status 0
  assert_equal $#lines 1
  assert_match "$output" '^bête noire \(n\.\)'
  run vocab search BÊTE
  assert_equal $#lines 1 "unicode case folding"
  assert_match "$output" '^bête noire'
  run vocab search bête noire
  assert_status 0
  assert_equal $#lines 1 "args joined with a space"
  assert_match "$output" '^bête noire'
}

test_search_no_matches() {
  run vocab search words
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" "vocab: no matches for 'words'"
}

test_search_definitions() {
  local a
  for a in '-d words' 'words -d'; do
    run vocab search ${=a}
    assert_status -m "$a" 0
    assert_equal $#lines 2 "$a"
    assert_match "$lines[1]" '^laconic ' "$a"
    assert_match "$lines[2]" '^sesquipedalian ' "$a"
  done
  run vocab search -d time
  assert_equal $#lines 1 "etymology is not searched"
  assert_match "$output" '^ephemeral '
}

test_search_definitions_short_line() {
  # A malformed "word<TAB>pos" line has no definition; its pos is not searched.
  print -r -- $'odd\tadjunct.' >> $ZEV_VOCAB_WORDS
  run vocab search -d adjunct
  assert_status 1
  assert_contains "$stderr" "no matches for 'adjunct'"
}

test_search_definitions_bucket_order() {
  # "lac" hits the word lac (exact), laconic (prefix) and lac's own definition
  # ("the lac insect"): each entry appears once, word matches first.
  run vocab search -d lac
  assert_status 0
  assert_equal $#lines 2
  assert_match "$lines[1]" '^lac '
  assert_match "$lines[2]" '^laconic '
  # "no" hits the word "bête noire" (line 4) and lac's definition ("a
  # resinous ...", line 2): the word match still comes first.
  run vocab search -d no
  assert_equal $#lines 2
  assert_match "$lines[1]" '^bête noire '
  assert_match "$lines[2]" '^lac '
}

test_search_glob_chars_are_literal() {
  local t
  for t in '*' '[' '?' '(#i)*' 'a|b'; do
    run vocab search $t
    assert_status -m "search $t" 1
    assert_empty "$output" "search $t"
    assert_contains "$stderr" 'no matches' "search $t"
  done
  run vocab search -- -d
  assert_status -m "-- ends options" 1
  assert_contains "$stderr" "no matches for '-d'"
}

test_search_usage_errors() {
  run vocab search
  assert_status 2
  assert_contains "$stderr" 'vocab: search needs a term'
  run vocab search -d
  assert_status 2
  run vocab search ''
  assert_status 2
  run vocab search -x foo
  assert_status 2
  assert_contains "$stderr" 'vocab: unknown option: -x'
  assert_empty "$output"
}

test_search_is_read_only() {
  run vocab search la
  run vocab search -d zzz
  run vocab search
  assert_file_not_exists $S
}

# ---- 6. fav --------------------------------------------------------------

test_fav_without_current() {
  run vocab fav
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" "vocab: no current word yet; run 'vocab next'"
  assert_file_not_exists $S/favorites
}

test_fav_current() {
  local w
  vocab next >/dev/null
  w="$(<$S/current)"
  run vocab fav
  assert_status 0
  assert_equal "$output" "Added to favorites: $w"
  assert_file_contents $S/favorites "$w"
}

test_fav_named_uses_list_spelling() {
  run vocab fav zeitgeist
  assert_status 0
  assert_equal "$output" 'Added to favorites: Zeitgeist'
  assert_file_contents $S/favorites Zeitgeist
}

test_fav_twice_is_idempotent() {
  run vocab fav LACONIC
  assert_equal "$output" 'Added to favorites: laconic'
  run vocab fav LACONIC
  assert_status 0
  assert_equal "$output" 'Already a favorite: laconic'
  assert_file_contents $S/favorites laconic
}

test_fav_multiword() {
  run vocab fav bête noire
  assert_status 0
  assert_equal "$output" 'Added to favorites: bête noire'
  run vocab fav 'bête noire'
  assert_equal "$output" 'Already a favorite: bête noire'
  assert_file_contents $S/favorites 'bête noire'
}

test_fav_unknown_word() {
  run vocab fav nope
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" 'vocab: unknown word: nope'
  assert_file_not_exists $S/favorites
  vocab fav lac >/dev/null
  run vocab fav 'la*'
  assert_status 1
  assert_file_contents $S/favorites lac "unchanged"
  local -a tmps
  tmps=( $S/favorites.tmp.*(N) )
  assert_equal $#tmps 0 "no temp files left"
}

test_fav_without_final_newline() {
  mkdir -p $S
  print -n laconic >| $S/favorites
  run vocab fav lac
  assert_status 0
  file_lines $S/favorites
  assert_equal "${(j:|:)reply}" 'laconic|lac'
  assert_equal "$(wc -l < $S/favorites | tr -d ' ')" 2
}

test_fav_keeps_symlink() {
  mkdir -p $S
  print -r -- laconic >| $ZEV_TEST_TMPDIR/real
  ln -s $ZEV_TEST_TMPDIR/real $S/favorites
  run vocab fav lac
  assert_status 0
  assert_true -m "still a symlink" test -L $S/favorites
  assert_file_contents $ZEV_TEST_TMPDIR/real $'laconic\nlac'
  local -a tmps
  tmps=( $S/favorites.tmp.*(N) $ZEV_TEST_TMPDIR/real.tmp.*(N) )
  assert_equal $#tmps 0 "no temp files left"
}

test_fav_keeps_dangling_symlink() {
  # A dotfiles link whose file doesn't exist yet: the file is created where
  # the link points, and the link stays. Absolute and relative links.
  mkdir -p $S $ZEV_TEST_TMPDIR/dotfiles
  ln -s $ZEV_TEST_TMPDIR/dotfiles/favs $S/favorites
  run vocab fav laconic
  assert_status 0
  assert_empty "$stderr"
  assert_true -m "still a symlink" test -L $S/favorites
  assert_file_contents $ZEV_TEST_TMPDIR/dotfiles/favs laconic
  run vocab fav lac
  assert_status 0
  assert_file_contents $ZEV_TEST_TMPDIR/dotfiles/favs $'laconic\nlac'
  rm -f $S/favorites
  mkdir -p $XDG_STATE_HOME/rel
  ln -s ../rel/favs $S/favorites
  run vocab fav ephemeral
  assert_status 0
  assert_true -m "relative link kept" test -L $S/favorites
  assert_file_contents $XDG_STATE_HOME/rel/favs ephemeral
  local -a tmps
  tmps=( $S/favorites.tmp.*(N) $ZEV_TEST_TMPDIR/dotfiles/*.tmp.*(N) $XDG_STATE_HOME/rel/*.tmp.*(N) )
  assert_equal $#tmps 0 "no temp files left"
}

test_fav_lock_busy() {
  mkdir -p $S
  print -r -- laconic >| $S/favorites
  hold_lock 3
  ZEV_VOCAB_LOCK_TIMEOUT=0.2 run vocab fav lac
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" 'busy'
  assert_file_contents $S/favorites laconic
  kill $HOLDER 2>/dev/null
}

test_fav_unwritable() {
  mkdir -p $S
  print -r -- laconic >| $S/favorites
  : >| $S/lock
  chmod a-w $S
  run vocab fav lac
  chmod u+w $S
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" 'vocab: could not write'
  assert_file_contents $S/favorites laconic
}

# ---- 7. unfav ------------------------------------------------------------

test_unfav_case_insensitive() {
  mkdir -p $S
  print -rl -- laconic Zeitgeist >| $S/favorites
  run vocab unfav zeitgeist
  assert_status 0
  assert_equal "$output" 'Removed from favorites: Zeitgeist'
  assert_file_contents $S/favorites laconic
}

test_unfav_no_substring_removal() {
  mkdir -p $S
  print -rl -- laconic Zeitgeist >| $S/favorites
  run vocab unfav lac
  assert_status 1
  assert_empty "$output"
  assert_contains "$stderr" 'vocab: not a favorite: lac'
  assert_file_contents $S/favorites $'laconic\nZeitgeist'
}

test_unfav_usage() {
  run vocab unfav
  assert_status 2
  assert_contains "$stderr" 'vocab: unfav needs a word'
}

test_unfav_last_leaves_empty_file() {
  mkdir -p $S
  print -r -- laconic >| $S/favorites
  run vocab unfav LACONIC
  assert_status 0
  assert_file_exists $S/favorites
  assert_false -m "size 0" test -s $S/favorites
}

test_unfav_word_not_in_list_and_list_missing() {
  mkdir -p $S
  print -rl -- gone 'bête noire' >| $S/favorites
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/none run vocab unfav gone
  assert_status 0
  assert_equal "$output" 'Removed from favorites: gone'
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/none run vocab unfav bête noire
  assert_status 0
  assert_false -m "empty" test -s $S/favorites
}

test_unfav_without_favorites_creates_nothing() {
  run vocab unfav laconic
  assert_status 1
  assert_contains "$stderr" 'vocab: not a favorite: laconic'
  assert_file_not_exists $S
}

# ---- 8. favs -------------------------------------------------------------

test_favs_empty() {
  run vocab favs
  assert_status 0
  assert_empty "$output"
  assert_contains "$stderr" "vocab: no favorites yet (add one with 'vocab fav')"
  mkdir -p $S
  : >| $S/favorites
  run vocab favs
  assert_status 0
  assert_empty "$output"
  assert_contains "$stderr" 'no favorites yet'
}

test_favs_lists_in_order() {
  mkdir -p $S
  print -rl -- laconic gone LAC >| $S/favorites
  run vocab favs
  assert_status 0
  assert_empty "$stderr"
  assert_equal $#lines 3
  assert_equal "$lines[1]" "$LACONIC"
  assert_equal "$lines[2]" 'gone (not in the word list)'
  assert_match "$lines[3]" '^lac \(n\.\)'
}

# ---- 9. history ----------------------------------------------------------

test_history_default_20() {
  mkhist 30
  run vocab history
  assert_status 0
  assert_empty "$stderr"
  assert_equal $#lines 20
  assert_equal "$lines[1]" '2026-09-27 14:32  word11 (not in the word list)'
  assert_equal "$lines[-1]" '2026-09-27 14:32  word30 (not in the word list)'
  local l
  for l in "$lines[@]"; do
    assert_match "$l" "$HIST_LINE"
  done
}

test_history_n() {
  mkhist 30
  run vocab history 3
  assert_equal $#lines 3
  assert_match "$lines[1]" '  word28 '
  assert_match "$lines[3]" '  word30 '
  run vocab history 500
  assert_equal $#lines 30
  assert_match "$lines[1]" '  word1 '
}

test_history_usage_errors() {
  local a
  for a in 0 -1 abc '2 3' 1.5; do
    run vocab history ${=a}
    assert_status -m "history $a" 2
    assert_contains "$stderr" 'vocab: history takes one positive number' "history $a"
  done
}

test_history_leading_zeros() {
  mkhist 30
  run vocab history 0000000003
  assert_status 0
  assert_equal $#lines 3
  assert_match "$lines[1]" '  word28 '
  run vocab history 007
  assert_equal $#lines 7
  run vocab history 00000000000000000000
  assert_status -m "all zeros is still 0" 2
  run vocab history 00000000000000000000030
  assert_status 0
  assert_equal $#lines 30 "huge-looking but small N"
}

test_history_missing() {
  run vocab history
  assert_status 0
  assert_empty "$output"
  assert_contains "$stderr" 'vocab: no history yet'
  assert_file_not_exists $S
}

test_history_shows_definition_not_etymology() {
  mkdir -p $S
  print -rl -- "2026-09-27T14:32:00+00:00${TAB}laconic" \
    "2026-09-27T15:01:00+00:00${TAB}ZEITGEIST" >| $S/history
  run vocab history
  assert_equal "$lines[1]" '2026-09-27 14:32  laconic (adj.): using very few words'
  assert_equal "$lines[2]" '2026-09-27 15:01  Zeitgeist (n.): the spirit of the age'
  assert_not_contains "$output" '—'
  _ZEV_VOCAB_ASSUME_TTY=1 run vocab history 1
  assert_equal "$output" $'\e[2m2026-09-27 15:01\e[0m  \e[1mZeitgeist\e[0m \e[2m(n.)\e[0m: the spirit of the age'
  ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/none run vocab history
  assert_status -m "list missing is not fatal" 0
  assert_equal "$lines[1]" '2026-09-27 14:32  laconic'
}

test_history_real_record() {
  vocab next >/dev/null
  local w="$(<$S/current)"
  run vocab history 1
  assert_status 0
  assert_equal $#lines 1
  assert_match "$output" "$HIST_LINE"
  assert_contains "$output" "  $w ("
}

test_history_skips_garbage() {
  mkdir -p $S
  print -rl -- "2026-09-27T14:32:00+00:00${TAB}laconic" 'garbage without a tab' '' \
    "2026-09-27T14:33:00+00:00${TAB}lac" >| $S/history
  run vocab history
  assert_status 0
  assert_empty "$stderr"
  assert_equal $#lines 2
  assert_match "$lines[1]" '14:32  laconic'
  assert_match "$lines[2]" '14:33  lac '
}

test_history_large_file() {
  mkdir -p $S
  {
    print -rl -- "2026-09-27T14:32:00+00:00${TAB}word"{1..59999}
    print -r -- "2026-09-27T14:32:00+00:00${TAB}bête noire"
  } >| $S/history
  run vocab history 5
  assert_status 0
  assert_equal $#lines 5
  assert_equal "$lines[1]" '2026-09-27 14:32  word59996 (not in the word list)'
  assert_equal "$lines[5]" '2026-09-27 14:32  bête noire (n.): a person or thing one especially dislikes'
  run vocab history 3000
  assert_equal $#lines 3000
  assert_match "$lines[1]" '  word57001 '
  local l
  for l in "$lines[@]"; do assert_match "$l" "$HIST_LINE"; done
  zmodload zsh/datetime
  vocab history 5 >/dev/null
  float t0=$EPOCHREALTIME ms
  vocab history 5 >/dev/null
  (( ms = (EPOCHREALTIME - t0) * 1000 ))
  print -r -- "history 5 on 2 MB: $ms ms"
  (( ms < 50 )) || fail "history 5 took $ms ms"
}

test_history_many_lines_fast() {
  # Each history line is an O(1) lookup: a 1200-word list and a 20k-line
  # history render quickly. Exact spelling wins; otherwise the first entry
  # matching case-insensitively (as _zev_vocab_lookup does).
  local l
  local -a hl
  integer i
  {
    print -r -- $'Mixed\tn.\tfirst mixed\tety'
    print -r -- $'mixed\tn.\tsecond mixed\tety'
    print -r -- $'mixed\tv.\tthird mixed\tety'
    print -r -- $'BÊTE\tn.\tunicode upper\tety'
    for (( i = 1; i <= 1196; i++ )); do
      print -r -- "word$i${TAB}n.${TAB}def $i${TAB}ety"
    done
  } >| $ZEV_TEST_TMPDIR/big.tsv
  export ZEV_VOCAB_WORDS=$ZEV_TEST_TMPDIR/big.tsv
  for (( i = 1; i <= 19995; i++ )); do
    hl+=( "2026-09-27T14:32:00+00:00${TAB}word$(( i % 1300 + 1 ))" )
  done
  hl+=( "2026-09-27T14:32:00+00:00${TAB}"{mixed,Mixed,MIXED,bête,nope} )
  mkdir -p $S
  print -rl -- "$hl[@]" >| $S/history
  zmodload zsh/datetime
  float t0=$EPOCHREALTIME
  integer ms
  run vocab history 20000
  (( ms = (EPOCHREALTIME - t0) * 1000 ))
  print -r -- "history 20000 (1200-word list): $ms ms"
  assert_status 0
  assert_equal $#lines 20000
  assert_equal "$lines[1]" '2026-09-27 14:32  word2 (n.): def 2'
  assert_equal "$lines[1196]" '2026-09-27 14:32  word1197 (not in the word list)'
  assert_equal "$lines[-5]" '2026-09-27 14:32  mixed (n.): second mixed'
  assert_equal "$lines[-4]" '2026-09-27 14:32  Mixed (n.): first mixed'
  assert_equal "$lines[-3]" '2026-09-27 14:32  Mixed (n.): first mixed'
  assert_equal "$lines[-2]" '2026-09-27 14:32  BÊTE (n.): unicode upper'
  assert_equal "$lines[-1]" '2026-09-27 14:32  nope (not in the word list)'
  for l in "$lines[@]"; do
    [[ $l == 2026-09-27\ 14:32\ \ ?* ]] || fail "bad line: $l"
  done
  (( ms < 2000 )) || fail "history 20000 took $ms ms"
}

test_history_window_cut_mid_utf8() {
  # The tail window starts a fixed distance from the end of the file. Shift
  # the content under it one byte at a time (a trailing line of P bytes), so
  # the cut lands on every offset of a "bête noire" line, including inside
  # the two-byte "ê". The partial first line must be dropped, never shown.
  local want='2026-09-27 14:32  bête noire (n.): a person or thing one especially dislikes'
  local l
  integer p
  mkdir -p $S
  for (( p = 1; p <= 38; p++ )); do
    {
      repeat 200 print -r -- "2026-09-27T14:32:00+00:00${TAB}bête noire"
      print -r -- "2026-09-27T14:32:00+00:00${TAB}${(l:p::x:)}"
    } >| $S/history
    run vocab history 5
    assert_status -m "pad $p" 0
    assert_empty "$stderr" "pad $p"
    assert_equal $#lines 5 "pad $p"
    for l in "${(@)lines[1,4]}"; do
      assert_equal "$l" "$want" "pad $p"
    done
    assert_equal "$lines[5]" "2026-09-27 14:32  ${(l:p::x:)} (not in the word list)" "pad $p"
  done
}

# ---- 10. concurrency -----------------------------------------------------

test_concurrent_fav_and_next() {
  local w
  local -a pids rcs
  integer i
  export ZEV_VOCAB_LOCK_TIMEOUT=10
  mkdir -p $S
  for w in laconic lac ephemeral Zeitgeist; do
    zsh -f -c '
      fpath=($ZEV_ROOT/functions $fpath)
      autoload -Uz vocab $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
      vocab fav $1' zsh $w >/dev/null 2>>$ZEV_TEST_TMPDIR/err &
    pids+=( $! )
  done
  for i in 1 2; do
    zsh -f -c '
      fpath=($ZEV_ROOT/functions $fpath)
      autoload -Uz vocab $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
      vocab next' >/dev/null 2>>$ZEV_TEST_TMPDIR/err &
    pids+=( $! )
  done
  for i in $pids; do
    wait $i
    rcs+=( $? )
  done
  assert_equal "${(j: :)rcs}" '0 0 0 0 0 0' "every job succeeded"
  [[ -s $ZEV_TEST_TMPDIR/err ]] && fail "stderr: $(<$ZEV_TEST_TMPDIR/err)"
  file_lines $S/favorites
  local -a want
  want=( laconic lac ephemeral Zeitgeist )
  assert_equal "${(j:|:)${(@o)reply}}" "${(j:|:)${(@o)want}}" "no lost updates"
  file_lines $S/history
  assert_equal $#reply 2
}

# ---- 11. completion ------------------------------------------------------

test_completion_file_header() {
  local -a l
  l=( "${(@f)$(<$ZEV_ROOT/functions/_vocab)}" )
  assert_equal "$l[1]" '#compdef vocab'
  assert_equal "$l[2]" 'emulate -L zsh'
}

test_completion_registered_by_plugin() {
  ZEV_VOCAB_DISABLE=1 run zsh -f -c '
    autoload -Uz compinit; compinit -u -D
    source $ZEV_ROOT/zsh-english-vocab.plugin.zsh
    print -r -- $_comps[vocab]'
  assert_equal "$output" _vocab
}

# _zpty_wait PATTERN -- read the pty into BUF until it matches PATTERN
# (10 s deadline).
_zpty_wait() {
  local chunk
  float deadline=$(( EPOCHREALTIME + 10 ))
  while (( EPOCHREALTIME < deadline )); do
    while zpty -r -t z chunk; do BUF+=$chunk; done
    [[ $BUF == $~1 ]] && return 0
    zselect -t 2
  done
  zpty -d z 2>/dev/null
  fail "timed out waiting for '$1'; pty output: ${(qqqq)BUF}"
}

# _zpty_wait_tab -- wait until the completion widget has finished (it appends
# a #TABDONE marker to CAPOUT). Sending more keys earlier would be typeahead,
# which makes zle skip or cut short the completion.
_zpty_wait_tab() {
  local chunk
  float deadline=$(( EPOCHREALTIME + 10 ))
  while (( EPOCHREALTIME < deadline )); do
    while zpty -r -t z chunk; do BUF+=$chunk; done
    [[ -f $CAPOUT && "$(<$CAPOUT)" == *'#TABDONE'* ]] && return 0
    zselect -t 2
  done
  zpty -d z 2>/dev/null
  fail "timed out waiting for completion; pty output: ${(qqqq)BUF}"
}

# complete_cases INPUT... -- complete each INPUT in one interactive zsh; for
# case n, CAND_n holds the candidates offered (sorted, unique, "|"-joined).
complete_cases() {
  local input
  local -a c
  integer n=0
  typeset -g BUF=
  zpty z zsh -f -i
  zpty -w z "source ${(q)ZEV_TEST_TMPDIR}/cap.zsh"
  _zpty_wait '*READY*<P>*'
  for input in "$@"; do
    (( n++ ))
    : >| $CAPOUT
    BUF=
    zpty -w -n z "$input"$'\t'
    _zpty_wait_tab
    zpty -w -n z $'\C-u'
    zpty -w z 'print -r -- ${:-DONE}'$n
    _zpty_wait "*DONE$n*"
    c=( ${(f)"$(<$CAPOUT)"} )
    c=( ${(u)${(@o)c:#\#TABDONE}} )
    typeset -g CAND_$n="${(j:|:)c}"
  done
  zpty -d z
}

test_completion_candidates() {
  zmodload zsh/zpty 2>/dev/null || skip "zsh/zpty not available"
  zmodload zsh/zselect zsh/datetime
  mkdir -p $S
  print -rl -- laconic Zeitgeist >| $S/favorites
  export ZEV_VOCAB_DISABLE=1 CAPOUT=$ZEV_TEST_TMPDIR/cap.out
  print -r -- "PS1='<P>'
PROMPT_EOL_MARK=''
autoload -Uz compinit; compinit -u -D
source ${(q)PLUGIN}
compadd() {
  if [[ \${@[1,(i)(-|--)]} == *-(O|A|D)\ * ]]; then builtin compadd \"\$@\"; return; fi
  local -a __m; builtin compadd -A __m \"\$@\"; print -rl -- \$__m >> \$CAPOUT; builtin compadd \"\$@\"
}
_cap_tab() { zle complete-word; print -r -- '#TABDONE' >> \$CAPOUT }
zle -N _cap_tab
bindkey '^I' _cap_tab
print -r -- 'READ''Y'" >| $ZEV_TEST_TMPDIR/cap.zsh
  complete_cases 'vocab ' 'vocab fa' 'vocab search la' 'vocab search -' \
    'vocab fav Ze' 'vocab fav bê' 'vocab unfav ' 'vocab next ' 'vocab history '

  local w
  for w in next search fav unfav favs history help; do
    [[ "|$CAND_1|" == *"|$w|"* ]] || fail "vocab <TAB> lacks $w: $CAND_1"
  done
  assert_equal "$CAND_2" 'fav|favs' 'vocab fa'
  assert_contains "|$CAND_3|" '|lac|' 'vocab search la'
  assert_contains "|$CAND_3|" '|laconic|' 'vocab search la'
  assert_not_contains "$CAND_3" ephemeral 'vocab search la'
  assert_contains "|$CAND_4|" '|-d|' 'vocab search -'
  assert_equal "$CAND_5" Zeitgeist 'vocab fav Ze'
  assert_equal "$CAND_6" 'bête\ noire' 'vocab fav bê'
  local -a want
  want=( laconic Zeitgeist )
  assert_equal "$CAND_7" "${(j:|:)${(@o)want}}" 'vocab unfav'
  assert_empty "$CAND_8" 'vocab next'
  assert_empty "$CAND_9" 'vocab history (a number: no candidates)'
}

# ---- 12. hygiene ---------------------------------------------------------

test_hygiene_user_options() {
  mkhist 5
  run zsh -f -c '
    fpath=($ZEV_ROOT/functions $fpath)
    autoload -Uz vocab $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
    setopt ksh_arrays sh_word_split no_multibyte
    before="$(setopt)"
    vocab search BÊTE
    vocab history 3
    vocab fav bête noire
    vocab unfav BÊTE NOIRE
    [[ "$(setopt)" == "$before" ]] && print options-unchanged'
  assert_empty "$stderr"
  assert_match "$lines[1]" '^bête noire '
  assert_match "$lines[2]" '  word3 '
  assert_match "$lines[4]" '  word5 '
  assert_equal "$lines[5]" 'Added to favorites: bête noire'
  assert_equal "$lines[6]" 'Removed from favorites: bête noire'
  assert_equal "$lines[7]" options-unchanged
}

test_hygiene_no_new_globals() {
  run zsh -f -c '
    fpath=($ZEV_ROOT/functions $fpath)
    autoload -Uz vocab $ZEV_ROOT/functions/_zev_vocab_*(N.:t)
    zmodload zsh/system zsh/files zsh/datetime zsh/zselect
    typeset -a before after new
    before=( ${(k)parameters} )
    {
      vocab next; vocab; vocab fav; vocab favs; vocab search la; vocab history
      vocab search -d zzz; vocab bogus; vocab history 0
      vocab unfav "$(<$XDG_STATE_HOME/zsh-english-vocab/current)"
    } >/dev/null 2>&1
    after=( ${(k)parameters} )
    new=( ${after:|before} )
    print -r -- "new=${(j: :)${(@o)new}}"'
  assert_empty "$stderr"
  assert_equal "$output" new=
}

test_hygiene_no_path_needed() {
  mkhist 2
  run eval 'path=(/nonexistent)
    vocab next && vocab && vocab fav && vocab favs && vocab search -d la &&
    vocab history && vocab unfav "$(<$S/current)" && vocab help'
  assert_status 0
  assert_empty "$stderr"
  assert_contains "$output" 'Added to favorites: '
  assert_contains "$output" 'Removed from favorites: '
  assert_contains "$output" 'usage: vocab'
}

test_hygiene_no_command_substitution() {
  run grep -nE '\$\([^(<]|`' $ZEV_ROOT/functions/vocab $ZEV_ROOT/functions/_vocab \
    $ZEV_ROOT/functions/_zev_vocab_cmd_*
  assert_empty "$output"
  assert_status 1
}

# ---- 13. performance -----------------------------------------------------

test_search_performance_1200() {
  local list=$ZEV_TEST_TMPDIR/w1200.tsv
  integer i
  for (( i = 1; i <= 1200; i++ )); do
    print -r -- "w$i${TAB}n.${TAB}synthetic definition number $i${TAB}from the test suite"
  done >| $list
  export ZEV_VOCAB_WORDS=$list
  zmodload zsh/datetime
  vocab search -d e >/dev/null
  float t0=$EPOCHREALTIME ms
  vocab search -d e >/dev/null
  (( ms = (EPOCHREALTIME - t0) * 1000 ))
  print -r -- "search -d e on 1200 entries: $ms ms"
  (( ms < 100 )) || fail "search took $ms ms"
}
