# Tests for tools/lint-words (the word-list linter) and its check wrapper.

# Multibyte fixtures and character classes need a UTF-8 locale (the linter
# forces its own; this is for building fixtures here).
export LC_ALL=C.UTF-8
if (( ${#${:-é}} != 1 )); then
  LC_ALL=en_US.UTF-8
fi
(( ${#${:-é}} == 1 )) || skip "no UTF-8 locale available"

LINT=$ZEV_ROOT/tools/lint-words

# mkw NAME LINE... -- write the lines (each followed by \n) to
# $ZEV_TEST_TMPDIR/NAME; REPLY is the path.
mkw() {
  REPLY=$ZEV_TEST_TMPDIR/$1
  shift
  print -rn -- "${(pj:\n:)@}"$'\n' > $REPLY
}

# mkraw NAME CONTENT -- write CONTENT byte-for-byte; REPLY is the path.
mkraw() {
  REPLY=$ZEV_TEST_TMPDIR/$1
  print -rn -- "$2" > $REPLY
}

# row F1 F2 F3 F4 -- print the arguments joined by TABs.
row() {
  print -rn -- "${(pj:\t:)@}"
}

# ---- the real list ---------------------------------------------------------

test_real_list_passes() {
  run $LINT --min 20 $ZEV_ROOT/data/words.tsv
  assert_status 0
  assert_match "$output" ': [0-9]+ entries OK$'
  assert_empty "$stderr"
}

test_default_path_is_repo_word_list() {
  run $LINT
  assert_status 0
  assert_match "$output" '^.*/data/words\.tsv: [0-9]+ entries OK$'
  assert_equal "${output%%: *}" "$ZEV_ROOT/data/words.tsv"
}

test_tricky_valid_file_passes() {
  mkw ok.tsv \
    "$(row 'sine qua non' n. 'an essential condition' 'from Latin, literally "without which not"')" \
    "$(row willy-nilly adv. 'whether one likes it or not' 'from "will I, nill I"')" \
    "$(row "hors d'oeuvre" n. 'a small savory dish served before a meal' 'from French, "outside the work"')" \
    "$(row élan n. 'energetic style — and flair' 'from French élan')" \
    "$(row ichor n. 'the ethereal fluid in the veins of the gods' 'from Greek ἰχώρ, via Latin; cf. Lakōnikos')" \
    "$(row quip n. 'a witty “remark” or ‘retort’' 'of uncertain origin')"
  run $LINT $REPLY
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" "$REPLY: 6 entries OK"
}

# ---- structure ---------------------------------------------------------------

test_field_count_errors() {
  local f
  mkw fc.tsv \
    "$(row word n. definition)" \
    "$(row word2 n. definition etymology)"$'\t' \
    "wordonly" \
    "$(row a b c d e)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: expected 4 tab-separated fields, found 3"
  assert_contains "$stderr" "$f:2: trailing whitespace"
  assert_contains "$stderr" "$f:2: expected 4 tab-separated fields, found 5"
  assert_contains "$stderr" "$f:3: expected 4 tab-separated fields, found 1"
  assert_contains "$stderr" "$f:4: expected 4 tab-separated fields, found 5"
}

test_empty_field_messages() {
  local f
  mkw ef.tsv \
    "$(row '' n. def ety)" \
    "$(row word '' def ety)" \
    "$(row wordb n. '' ety)" \
    "$(row wordc n. def '')"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: empty word"
  assert_contains "$stderr" "$f:2: empty pos"
  assert_contains "$stderr" "$f:3: empty definition"
  assert_contains "$stderr" "$f:4: empty etymology"
  # An empty first or last field also leaves a TAB at the edge of the line.
  assert_contains "$stderr" "$f:1: leading whitespace"
  assert_contains "$stderr" "$f:4: trailing whitespace"
  assert_contains "$stderr" "$f: 6 errors"
}

test_empty_lines() {
  local f
  mkw el.tsv "$(row one n. def ety)" "" "$(row two n. def ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:2: empty line"
  assert_contains "$stderr" "$f: 1 error"

  mkraw el2.tsv "$(row one n. def ety)"$'\n\n'
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_equal "$stderr" "$f:2: empty line"$'\n'"$f: 1 error"
}

test_duplicates() {
  local f
  mkw dup.tsv \
    "$(row laconic adj. terse 'from Greek')" \
    "$(row élan n. flair 'from French')" \
    "$(row laconic adj. terse 'from Greek')" \
    "$(row LACONIC adj. terse 'from Greek')" \
    "$(row Élan n. flair 'from French')"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:3: duplicate word \"laconic\" (first on line 1)"
  assert_contains "$stderr" "$f:4: duplicate word \"LACONIC\" (first on line 1)"
  assert_contains "$stderr" "$f:5: duplicate word \"Élan\" (first on line 2)"
}

test_pos_values() {
  local f p
  mkw pos-bad.tsv \
    "$(row one noun def ety)" \
    "$(row two adj def ety)" \
    "$(row three Adj. def ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: part of speech \"noun\" is not one of: n. v. adj. adv. prep. conj. interj. pron."
  assert_contains "$stderr" "$f:2: part of speech \"adj\" is not one of:"
  assert_contains "$stderr" "$f:3: part of speech \"Adj.\" is not one of:"

  local -a rows
  local -a words=(alpha beta gamma delta epsilon zeta eta theta)
  local i=0
  for p in n. v. adj. adv. prep. conj. interj. pron.; do
    (( i++ ))
    rows+=("$(row $words[i] $p def ety)")
  done
  mkw pos-ok.tsv $rows
  run $LINT $REPLY
  assert_status 0
  assert_empty "$stderr"
}

# ---- whitespace --------------------------------------------------------------

test_whitespace_errors() {
  local f
  mkw ws.tsv \
    " $(row one n. def ety)" \
    "$(row two n. def ety) " \
    "$(row three n. def ety)"$'\t' \
    "$(row 'four ' adj. def ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: leading whitespace"
  assert_contains "$stderr" "$f:2: trailing whitespace"
  assert_contains "$stderr" "$f:3: trailing whitespace"
  assert_contains "$stderr" "$f:4: whitespace next to a tab"
}

test_tab_space_adjacency_both_directions_reported_once() {
  local f
  mkw adj.tsv "$(row five n. ' def ' ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: whitespace next to a tab"
  assert_equal "${#${(@M)${(f)stderr}:#*whitespace next to a tab}}" 1
}

test_crlf_reports_once_per_line() {
  local f
  mkraw crlf.tsv "$(row one n. def ety)"$'\r\n'"$(row two n. def ety)"$'\r\n'
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_equal "$stderr" \
    "$f:1: carriage return (CRLF line ending?)"$'\n'"$f:2: carriage return (CRLF line ending?)"$'\n'"$f: 2 errors"
}

test_lone_cr_mid_line() {
  local f
  mkw cr.tsv "$(row one n. $'de\rf' ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: carriage return (CRLF line ending?)"
}

test_control_character() {
  local f
  mkw esc.tsv "$(row one n. $'a \e[1m bold' ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: control character U+001B"
}

test_invalid_utf8_and_nonprintables() {
  local f
  # \xff at column 9: "one<TAB>n.<TAB>d" is 8 characters.
  mkw bad.tsv \
    "$(row one n. $'d\xffef' ety)" \
    "$(row two n. def $'ety\xc3')" \
    "$(row three n. $'zero​width' ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: invalid UTF-8 or non-printable character at column 9"
  assert_contains "$stderr" "$f:2: invalid UTF-8 or non-printable character at column 15"
  # macOS classifies U+200B as [[:cntrl:]], so check 3 reports it first.
  assert_match "$stderr" ':3: (control character U\+200B|invalid UTF-8 or non-printable character at column 14)'
  assert_contains "$stderr" "$f: 3 errors"

  mkw bom.tsv $'\xef\xbb\xbf'"$(row one n. def ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: invalid UTF-8 or non-printable character at column 1"
}

test_double_and_nonbreaking_spaces() {
  local f
  mkw sp.tsv \
    "$(row one n. 'two  spaces' ety)" \
    "$(row two n. $'no\xc2\xa0break' ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: consecutive spaces"
  assert_contains "$stderr" "$f:2: non-breaking space (U+00A0)"
}

# ---- end of file ---------------------------------------------------------------

test_missing_final_newline() {
  local f
  mkraw nf2.tsv "$(row one n. def ety)"$'\n'"$(row two n. def ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:2: missing final newline"

  mkraw nf1.tsv "$(row one n. def ety)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_equal "$stderr" "$f:1: missing final newline"$'\n'"$f: 1 error"
}

test_empty_file() {
  local f
  mkraw empty.tsv ""
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_equal "$stderr" "$f: file is empty"$'\n'"$f: 1 error"

  run $LINT --min 5 $f
  assert_status 1
  assert_equal "$stderr" \
    "$f: file is empty"$'\n'"$f: 0 entries, fewer than --min 5"$'\n'"$f: 2 errors"
}

test_min_entries() {
  local f
  mkw three.tsv "$(row one n. def ety)" "$(row two n. def ety)" "$(row three n. def ety)"
  f=$REPLY
  run $LINT --min 3 $f
  assert_status 0
  assert_equal "$output" "$f: 3 entries OK"

  run $LINT --min 4 $f
  assert_status 1
  assert_contains "$stderr" "$f: 3 entries, fewer than --min 4"
  assert_contains "$stderr" "$f: 1 error"

  run $LINT $f
  assert_status 0
}

# ---- field rules ---------------------------------------------------------------

test_word_rule_rejections() {
  local f w i=0
  local -a bad=(Paris 'two  words' trail- -lead a_b x9)
  local -a rows
  for w in $bad; do rows+=("$(row $w n. def ety)"); done
  mkw words.tsv $rows
  f=$REPLY
  run $LINT $f
  assert_status 1
  for w in $bad; do
    (( i++ ))
    assert_contains "$stderr" "$f:$i: word \"$w\" must be lowercase letters joined by single spaces, hyphens or apostrophes"
  done
}

test_length_limits() {
  local f d120= d121 e100= e101 accents=
  repeat 120 d120+=x
  d121=${d120}x
  repeat 100 e100+=y
  e101=${e100}y
  repeat 120 accents+=$'\xc3\xa9'

  mkw len-ok.tsv "$(row one n. $d120 $e100)" "$(row two n. $accents ety)"
  run $LINT $REPLY
  assert_status 0
  assert_empty "$stderr"

  mkw len-bad.tsv "$(row one n. $d121 ety)" "$(row two n. def $e101)"
  f=$REPLY
  run $LINT $f
  assert_status 1
  assert_contains "$stderr" "$f:1: definition is 121 characters (max 120)"
  assert_contains "$stderr" "$f:2: etymology is 101 characters (max 100)"
}

test_golden_multi_error_fixture() {
  local f=$ZEV_FIXTURES/words/multi-error.tsv
  run $LINT $f
  assert_status 1
  assert_empty "$output"
  assert_equal "$stderr" "\
$f:2: word \"Laconic\" must be lowercase letters joined by single spaces, hyphens or apostrophes
$f:2: duplicate word \"Laconic\" (first on line 1)
$f:3: part of speech \"noun\" is not one of: n. v. adj. adv. prep. conj. interj. pron.
$f:4: expected 4 tab-separated fields, found 3
$f:5: empty definition
$f:6: trailing whitespace
$f:7: empty line
$f: 7 errors"
}

# ---- usage ---------------------------------------------------------------------

test_usage_errors() {
  local f
  mkw a.tsv "$(row one n. def ety)"
  f=$REPLY
  mkdir -p $ZEV_TEST_TMPDIR/dir

  run $LINT --min abc $f
  assert_status 2
  assert_contains "$stderr" "lint-words: "
  run $LINT $f --min
  assert_status 2
  run $LINT --bogus $f
  assert_status 2
  assert_contains "$stderr" "lint-words: unknown option"
  run $LINT $f $f
  assert_status 2
  run $LINT $ZEV_TEST_TMPDIR/missing.tsv
  assert_status 2
  assert_contains "$stderr" "lint-words: cannot read $ZEV_TEST_TMPDIR/missing.tsv"
  run $LINT $ZEV_TEST_TMPDIR/dir
  assert_status 2
  assert_contains "$stderr" "lint-words: cannot read"
}

test_help() {
  local p
  run $LINT --help
  assert_status 0
  assert_contains "$output" "word<TAB>pos<TAB>definition<TAB>etymology"
  for p in n. v. adj. adv. prep. conj. interj. pron.; do
    assert_contains "$output" " $p"
  done
  run $LINT -h
  assert_status 0
}

# ---- wrapper and runner ----------------------------------------------------------

test_check_wrapper_from_root_dir() {
  cd / || fail "cd /"
  run $ZEV_ROOT/tests/checks/lint-words
  assert_status 0
  assert_contains "$output" "entries OK"
}

test_runner_runs_lint_check() {
  run $ZEV_ROOT/tests/run --checks-only
  assert_contains "$output" "ok    lint-words"
}
