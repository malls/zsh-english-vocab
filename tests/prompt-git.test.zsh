# Tests for the theme's async git segment (ZEV-8): functions/_zev_prompt_git*.

typeset -g THEME=$ZEV_ROOT/zsh-english-vocab.zsh-theme
typeset -g FIX=$ZEV_FIXTURES/git
typeset -g H=d3541cdf6b285c27d5216c1c867e1ffd0a9cbb7b
typeset -g REALGIT=${commands[git]-}
typeset -ga GIT_FUNCS
GIT_FUNCS=(_zev_prompt_git_setup _zev_prompt_git_precmd _zev_prompt_git_update
  _zev_prompt_git_root _zev_prompt_git_start _zev_prompt_git_handler
  _zev_prompt_git_worker _zev_prompt_git_parse _zev_prompt_git_format)

# The tests below were written for the counts style; pin it (exported so the
# interactive zpty shells inherit it). Dot-style tests set ZEV_GIT_STYLE=dots.
export ZEV_GIT_STYLE=counts

autoload -Uz add-zsh-hook
autoload -Uz +X $GIT_FUNCS _zev_prompt_escape _zev_prompt_render
zmodload zsh/datetime zsh/system

setup() {
  typeset -g _zev_prompt_opt_bang=0 _zev_prompt_opt_subst=0
  typeset -g _zev_prompt_git= _zev_prompt_git_key= _zev_prompt_git_fd=
  typeset -gi _zev_prompt_git_gen=0 _zev_prompt_git_pending=0
  typeset -ga _zev_prompt_git_fields
  _zev_prompt_git_fields=()
}

# nocolor -- every ZEV_GIT_*_COLOR set to empty.
nocolor() {
  local k
  for k in AHEAD BEHIND CONFLICTED STAGED UNSTAGED UNTRACKED STASH CLEAN BRANCH DETACHED \
      DOT_STAGED DOT_DIRTY; do
    typeset -g ZEV_GIT_${k}_COLOR=
  done
}

needgit() {
  [[ -n $REALGIT ]] || skip "git not found"
}

# mkrepo DIR BRANCH -- a repo with one commit (file f).
mkrepo() {
  git init -q -b "$2" "$1" || fail "git init $1"
  print one > "$1/f"
  git -C "$1" add f
  git -C "$1" commit -q -m init || fail "git commit in $1"
}

# fakegit DIR -- DIR/git logs "$GIT_OPTIONAL_LOCKS $LC_ALL $*" to DIR/calls,
# sleeps 1s if DIR/slow exists, exits 129 for --show-stash if DIR/old exists,
# and otherwise runs the real git.
fakegit() {
  mkdir -p -- "$1"
  cat > "$1/git" <<EOF
#!/bin/sh
d=${(qq)1}
echo "\$GIT_OPTIONAL_LOCKS \$LC_ALL \$*" >> "\$d/calls"
[ -e "\$d/slow" ] && sleep 1
if [ -e "\$d/old" ]; then
  for a in "\$@"; do
    [ "\$a" = --show-stash ] && exit 129
  done
fi
exec ${(qq)REALGIT} "\$@"
EOF
  chmod +x "$1/git"
}

# ---- parse ---------------------------------------------------------------

# pchk FIXTURE EXPECTED_CSV
pchk() {
  local -a reply
  _zev_prompt_git_parse "$(<$FIX/$1.txt)"
  local -i r=$?
  assert_equal "$r" 0 "parse $1 status"
  assert_equal "${(j:,:)reply}" "$2" "parse $1"
}

test_parse_fixtures() {
  pchk clean "main,$H,0,0,0,0,0,0,0"
  pchk mixed "main,$H,1,0,2,1,3,0,1"
  pchk both "main,$H,0,0,3,4,0,0,0"
  pchk detached "(detached),92fb3b15c1e7f7e0f5f6a4c0a0e3b9a8d7c6b5a4,0,0,0,0,1,0,0"
  pchk initial "main,(initial),0,0,1,0,1,0,0"
  pchk initial-empty "main,(initial),0,0,0,0,0,0,0"
  pchk ahead-behind "main,$H,3,12,0,0,0,0,0"
  pchk no-upstream "main,$H,0,0,0,1,0,0,0"
  pchk upstream-gone "main,$H,0,0,0,0,0,0,0"
  pchk stash "main,$H,0,0,0,0,0,0,4"
  pchk conflict "main,$H,0,0,1,0,1,2,0"
  pchk special-branch 'we%ird!$(id)`id`%F{red},'"$H,0,0,0,0,0,0,0"
  pchk unicode-branch "фича/тест,$H,0,0,0,0,0,0,0"
}

test_parse_failures() {
  local -a reply
  reply=(x)
  assert_status 1 _zev_prompt_git_parse "$(<$FIX/garbage.txt)"
  assert_equal "${#reply}" 0
  reply=(x)
  assert_status 1 _zev_prompt_git_parse ''
  assert_equal "${#reply}" 0
  assert_status -m "head without oid" 1 _zev_prompt_git_parse '# branch.head main'
  assert_status -m "oid without head" 1 _zev_prompt_git_parse "# branch.oid $H"
}

test_parse_large_output_is_fast() {
  local -a l reply
  local i
  for (( i = 1; i <= 5000; i++ )); do
    l+=("? f$i")
  done
  local text="# branch.oid $H"$'\n''# branch.head main'$'\n'${(F)l}
  typeset -F t=$EPOCHREALTIME
  _zev_prompt_git_parse "$text"
  (( t = EPOCHREALTIME - t ))
  assert_equal "${(j:,:)reply}" "main,$H,0,0,0,0,5000,0,0"
  assert_true -m "5000 lines took ${t}s" test $(( t < 1 )) -eq 1
}

# ---- format --------------------------------------------------------------

# fmt FIXTURE -- parse + format; REPLY = segment.
fmt() {
  local -a reply
  _zev_prompt_git_parse "$(<$FIX/$1.txt)" || fail "parse $1"
  _zev_prompt_git_format "${reply[@]}"
}

test_format_fixtures_plain() {
  local REPLY name want
  nocolor
  for name want in \
    clean 'main ✓' \
    mixed 'main ⇡1 +2 !1 ?3 ≡1' \
    both 'main +3 !4' \
    detached '92fb3b1 ?1' \
    initial 'main +1 ?1' \
    initial-empty 'main ✓' \
    ahead-behind 'main ⇡3 ⇣12 ✓' \
    no-upstream 'main !1' \
    upstream-gone 'main ✓' \
    stash 'main ✓ ≡4' \
    conflict 'main ~2 +1 ?1' \
    special-branch 'we%ird!$(id)`id`%F{red} ✓' \
    unicode-branch 'фича/тест ✓'
  do
    fmt $name
    assert_equal "${(%)REPLY}" "$want" "format $name"
    assert_true -m "no surrounding space/newline in $name" \
      test "$REPLY" = "${${REPLY# }% }"
    assert_not_contains "$REPLY" $'\n' "$name"
  done
}

test_format_default_colors() {
  local REPLY
  fmt mixed
  assert_equal "$REPLY" '%F{magenta}main%f %F{cyan}⇡1%f %F{green}+2%f %F{yellow}!1%f %F{blue}?3%f %F{8}≡1%f'
  fmt detached
  assert_equal "$REPLY" '%F{yellow}92fb3b1%f %F{blue}?1%f'
  fmt conflict
  assert_equal "$REPLY" '%F{magenta}main%f %F{red}~2%f %F{green}+1%f %F{blue}?1%f'
  fmt ahead-behind
  assert_equal "$REPLY" '%F{magenta}main%f %F{cyan}⇡3%f %F{cyan}⇣12%f %F{green}✓%f'
}

test_format_special_branch_round_trips() {
  local REPLY name='we%ird!$(id)`id`%F{red}'
  nocolor
  _zev_prompt_opt_bang=0
  fmt special-branch
  assert_equal "${(%)REPLY}" "$name ✓"
  _zev_prompt_opt_bang=1
  fmt special-branch
  assert_contains "$REPLY" '!!'
  run zsh -f -c 'setopt prompt_bang; print -rP -- "$1"' zsh "$REPLY"
  assert_equal "$output" "$name ✓"
  assert_empty "$stderr"
}

test_format_overrides() {
  local REPLY
  nocolor
  ZEV_GIT_STAGED_MARKER=S
  fmt mixed
  assert_equal "${(%)REPLY}" 'main ⇡1 S2 !1 ?3 ≡1'
  ZEV_GIT_STASH_MARKER=
  fmt mixed
  assert_equal "${(%)REPLY}" 'main ⇡1 S2 !1 ?3'
  ZEV_GIT_CLEAN_MARKER=
  fmt clean
  assert_equal "$REPLY" main
  ZEV_GIT_UNSTAGED_MARKER='%!'
  fmt no-upstream
  assert_equal "$REPLY" 'main %%!1'
  assert_equal "${(%)REPLY}" 'main %!1'
  unset ZEV_GIT_BRANCH_COLOR ZEV_GIT_AHEAD_COLOR
  ZEV_GIT_BRANCH_COLOR='red}%F{x' ZEV_GIT_AHEAD_COLOR=208
  fmt ahead-behind
  assert_equal "$REPLY" 'main %F{208}⇡3%f ⇣12'
}

test_format_bad_counts_are_zero() {
  local REPLY
  nocolor
  _zev_prompt_git_format main $H 'a[$(touch pwned)]' 2 x '' -1 1.5 3
  assert_equal "$REPLY" 'main ⇣2 ✓ ≡3'
  assert_file_not_exists pwned
}

test_format_dots_fixtures_plain() {
  local REPLY name want
  nocolor
  ZEV_GIT_STYLE=dots
  for name want in \
    clean 'main' \
    mixed 'main ⇡1 ● ● ≡1' \
    both 'main ● ●' \
    detached '92fb3b1 ●' \
    initial 'main ● ●' \
    initial-empty 'main' \
    ahead-behind 'main ⇡3 ⇣12' \
    no-upstream 'main ●' \
    stash 'main ≡4' \
    conflict 'main ● ●'
  do
    fmt $name
    assert_equal "${(%)REPLY}" "$want" "dots $name"
  done
}

test_format_dots_is_default_and_colored() {
  local REPLY
  unset ZEV_GIT_STYLE
  fmt mixed
  assert_equal "$REPLY" '%F{magenta}main%f %F{cyan}⇡1%f %F{green}●%f %F{red}●%f %F{8}≡1%f'
  fmt detached
  assert_equal "$REPLY" '%F{yellow}92fb3b1%f %F{red}●%f'
  fmt clean
  assert_equal "$REPLY" '%F{magenta}main%f'
  ZEV_GIT_STYLE=bogus
  fmt both
  assert_equal "$REPLY" '%F{magenta}main%f %F{green}●%f %F{red}●%f'
}

test_format_dots_staged_only_and_overrides() {
  local REPLY
  unset ZEV_GIT_STYLE
  nocolor
  _zev_prompt_git_format main $H 0 0 5 0 0 0 0
  assert_equal "$REPLY" 'main ●' "staged only"
  _zev_prompt_git_format main $H 0 0 0 0 0 1 0
  assert_equal "$REPLY" 'main ●' "conflict only counts as dirty"
  ZEV_GIT_DOT_STAGED_MARKER=S ZEV_GIT_DOT_DIRTY_MARKER='%'
  _zev_prompt_git_format main $H 0 0 1 1 0 0 0
  assert_equal "$REPLY" 'main S %%'
  ZEV_GIT_DOT_DIRTY_MARKER=
  _zev_prompt_git_format main $H 0 0 1 1 0 0 0
  assert_equal "$REPLY" 'main S' "empty marker hides the dot"
  unset ZEV_GIT_DOT_STAGED_COLOR
  ZEV_GIT_DOT_STAGED_MARKER=
  ZEV_GIT_DOT_DIRTY_MARKER=●
  ZEV_GIT_DOT_DIRTY_COLOR=208
  _zev_prompt_git_format main $H 0 0 1 1 0 0 0
  assert_equal "$REPLY" 'main %F{208}●%f'
}

# ---- root ----------------------------------------------------------------

# rootis DIR EXPECTED
rootis() {
  local REPLY
  cd -- "$1" || fail "cd $1"
  _zev_prompt_git_root
  assert_equal "$REPLY" "$2" "root in $1"
}

test_root_repo_subdir_nested() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A}
  mkrepo $T/a main
  mkdir -p $T/a/sub/deep $T/plain
  mkrepo $T/a/sub/nested main
  rootis $T/a $T/a
  rootis $T/a/sub/deep $T/a
  rootis $T/a/sub/nested $T/a/sub/nested
  rootis $T/a/.git/refs $T/a
  rootis $T/plain ''
}

test_root_worktree_and_symlink() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A}
  mkrepo $T/a main
  mkdir -p $T/a/sub
  git -C $T/a worktree add -q -b wtb $T/wt 2>/dev/null || fail "worktree add"
  assert_true -m ".git is a file in a worktree" test -f $T/wt/.git
  rootis $T/wt $T/wt
  ln -s $T/a/sub $T/link
  rootis $T/link $T/a
}

test_root_glob_chars_in_path() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A}
  mkrepo "$T/a[1]*" main
  mkdir -p "$T/a[1]*/x"
  rootis "$T/a[1]*/x" "$T/a[1]*"
}

test_root_git_dir() {
  local REPLY k1 T=${ZEV_TEST_TMPDIR:A}
  mkdir -p $T/p $T/q
  cd $T/p
  GIT_DIR=x
  _zev_prompt_git_root
  k1=$REPLY
  assert_match "$k1" '^gitdir:x::'
  cd $T/q
  _zev_prompt_git_root
  assert_not_equal "$REPLY" "$k1"
}

# ---- worker --------------------------------------------------------------

# wexp FIELD... -- REPLY = expected worker line for generation 7.
wexp() {
  REPLY=7$'\t'${(pj:\t:)@}
}

test_worker_git_failures_print_gen_only() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A}
  mkdir -p $T/plain
  mkrepo $T/a main
  git init -q --bare -b main $T/bare.git
  local d
  for d in $T/plain $T/a/.git $T/a/.git/refs $T/bare.git; do
    cd $d
    run _zev_prompt_git_worker 7
    assert_equal "$output" 7 "worker in $d"
    assert_empty "$stderr" "worker in $d"
  done
}

test_worker_noisy_traps_neutralized() {
  local T=${ZEV_TEST_TMPDIR:A}
  mkdir -p $T/plain
  cd $T/plain
  TRAPZERR() { print ZERR-NOISE }
  TRAPDEBUG() { : }
  zshexit() { print EXIT-NOISE }
  run _zev_prompt_git_worker 7
  assert_equal "$output" 7
}

test_worker_initial_repo() {
  needgit
  local REPLY
  git init -q -b main $ZEV_TEST_TMPDIR/e
  cd $ZEV_TEST_TMPDIR/e
  run _zev_prompt_git_worker 7
  wexp main '(initial)' 0 0 0 0 0 0 0
  assert_equal "$output" "$REPLY"
}

test_worker_counts() {
  needgit
  local REPLY A=$ZEV_TEST_TMPDIR/a
  mkrepo $A main
  cd $A
  print stash >> f
  git stash -q || fail "git stash"
  print new > g
  git add g
  print more >> f
  touch u1 u2
  run _zev_prompt_git_worker 7
  wexp main "$(git rev-parse HEAD)" 0 0 1 1 2 0 1
  assert_equal "$output" "$REPLY"
}

test_worker_ahead_behind_without_network() {
  needgit
  local REPLY A=$ZEV_TEST_TMPDIR/a c1 c3
  mkrepo $A main
  cd $A
  c1=$(git rev-parse HEAD)
  print two >> f
  git commit -q -am c2
  c3=$(git commit-tree -p $c1 -m x "$c1^{tree}")
  git remote add origin /nonexistent
  git update-ref refs/remotes/origin/main $c3
  git config branch.main.remote origin
  git config branch.main.merge refs/heads/main
  run _zev_prompt_git_worker 7
  wexp main "$(git rev-parse HEAD)" 1 1 0 0 0 0 0
  assert_equal "$output" "$REPLY"
}

test_worker_conflict_detached_worktree() {
  needgit
  local REPLY A=$ZEV_TEST_TMPDIR/a
  mkrepo $A main
  cd $A
  git checkout -q -b o
  print theirs > f
  git commit -q -am o
  git checkout -q main
  print ours > f
  git commit -q -am m
  git merge o >/dev/null 2>&1
  run _zev_prompt_git_worker 7
  wexp main "$(git rev-parse HEAD)" 0 0 0 0 0 1 0
  assert_equal "$output" "$REPLY" "conflict"
  git merge --abort
  git checkout -q --detach
  run _zev_prompt_git_worker 7
  wexp '(detached)' "$(git rev-parse HEAD)" 0 0 0 0 0 0 0
  assert_equal "$output" "$REPLY" "detached"
  git worktree add -q -b wtb $ZEV_TEST_TMPDIR/wt 2>/dev/null
  cd $ZEV_TEST_TMPDIR/wt
  run _zev_prompt_git_worker 7
  wexp wtb "$(git rev-parse HEAD)" 0 0 0 0 0 0 0
  assert_equal "$output" "$REPLY" "worktree"
}

test_worker_special_branch_is_literal() {
  needgit
  local REPLY T=$ZEV_TEST_TMPDIR b='x$(touch${IFS}pwned)'
  git init -q -b "$b" $T/s
  cd $T/s
  run _zev_prompt_git_worker 7
  wexp "$b" '(initial)' 0 0 0 0 0 0 0
  assert_equal "$output" "$REPLY"
  local -a pwned
  pwned=($T/**/pwned*(N))
  assert_equal "${#pwned}" 0 "injected command ran: $pwned"
}

test_worker_git_invocation() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A} REPLY
  fakegit $T/bin
  mkrepo $T/a main
  cd $T/a
  wexp main "$(git rev-parse HEAD)" 0 0 0 0 0 0 0
  PATH=$T/bin:$PATH
  run _zev_prompt_git_worker 7
  assert_equal "$output" "$REPLY"
  assert_file_contents $T/bin/calls '0 C status --porcelain=v2 --branch --show-stash --ignore-submodules=dirty'
  : > $T/bin/calls
  ZEV_GIT_IGNORE_SUBMODULES=all run _zev_prompt_git_worker 7
  assert_file_contents $T/bin/calls '0 C status --porcelain=v2 --branch --show-stash --ignore-submodules=all'
  : > $T/bin/calls
  ZEV_GIT_IGNORE_SUBMODULES=bogus run _zev_prompt_git_worker 7
  assert_file_contents $T/bin/calls '0 C status --porcelain=v2 --branch --show-stash --ignore-submodules=dirty'
}

test_worker_old_git_retries_without_show_stash() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A} REPLY
  fakegit $T/bin
  mkrepo $T/a main
  cd $T/a
  print stash >> f
  git stash -q
  touch u1
  wexp main "$(git rev-parse HEAD)" 0 0 0 0 1 0 0
  PATH=$T/bin:$PATH
  touch $T/bin/old
  run _zev_prompt_git_worker 7
  assert_equal "$output" "$REPLY"
  assert_file_contents $T/bin/calls \
    '0 C status --porcelain=v2 --branch --show-stash --ignore-submodules=dirty'$'\n''0 C status --porcelain=v2 --branch --ignore-submodules=dirty'
}

# ---- async flow (no pty: the handler is called by hand) -------------------

fdopen() {
  { : <&$1 } 2>/dev/null
}

# two repos A (zevtrunk, one staged file) and B (zevother, clean)
tworepos() {
  typeset -g A=${ZEV_TEST_TMPDIR:A}/a B=${ZEV_TEST_TMPDIR:A}/b NR=${ZEV_TEST_TMPDIR:A}/nr
  mkrepo $A zevtrunk
  print n > $A/n
  git -C $A add n
  mkrepo $B zevother
  mkdir -p $A/sub $NR
  nocolor
}

test_async_spawn_and_deliver() {
  needgit
  tworepos
  cd $A
  _zev_prompt_git_update
  local fd=$_zev_prompt_git_fd
  assert_match "$fd" '^[0-9]+$'
  assert_empty "$_zev_prompt_git"
  assert_equal "$_zev_prompt_git_key" $A
  assert_status 0 _zev_prompt_git_handler $fd
  assert_equal "${(%)_zev_prompt_git}" 'zevtrunk +1'
  assert_empty "$_zev_prompt_git_fd"
  assert_false -m "fd closed" fdopen $fd
  assert_contains "$_zev_prompt" 'zevtrunk +1' "rendered"
}

test_async_default_style_renders_dots() {
  needgit
  tworepos
  unset ZEV_GIT_STYLE
  print x >> $A/f                      # staged n + unstaged f
  cd $A
  _zev_prompt_git_update
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_equal "${(%)_zev_prompt_git}" 'zevtrunk ● ●'
  assert_contains "$_zev_prompt" 'zevtrunk ● ●' "rendered"
  cd $B
  _zev_prompt_git_update
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_equal "${(%)_zev_prompt_git}" 'zevother' "clean repo: no dot, no check mark"
}

test_async_coalesce() {
  needgit
  tworepos
  cd $A
  _zev_prompt_git_update
  local fd=$_zev_prompt_git_fd gen=$_zev_prompt_git_gen
  _zev_prompt_git_update
  assert_equal "$_zev_prompt_git_fd" "$fd" "no second job"
  assert_equal "$_zev_prompt_git_pending" 1
  assert_equal "$_zev_prompt_git_gen" "$gen"
  _zev_prompt_git_handler $fd
  assert_equal "${(%)_zev_prompt_git}" 'zevtrunk +1'
  assert_not_empty "$_zev_prompt_git_fd" "pending job started"
  assert_equal "$_zev_prompt_git_pending" 0
  assert_equal "$_zev_prompt_git_gen" $(( gen + 1 ))
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_equal "${(%)_zev_prompt_git}" 'zevtrunk +1'
  assert_empty "$_zev_prompt_git_fd"
  assert_equal "$_zev_prompt_git_pending" 0
}

test_async_key_change_discards_job() {
  needgit
  tworepos
  cd $A
  _zev_prompt_git_update
  local fda=$_zev_prompt_git_fd gen=$_zev_prompt_git_gen
  cd $B
  _zev_prompt_git_update
  assert_empty "$_zev_prompt_git"
  assert_equal "$_zev_prompt_git_key" $B
  assert_equal "$_zev_prompt_git_pending" 0
  assert_equal "$_zev_prompt_git_gen" $(( gen + 2 )) "discard bump + new job"
  assert_not_empty "$_zev_prompt_git_fd"
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_equal "${(%)_zev_prompt_git}" 'zevother ✓'
  assert_not_contains "$_zev_prompt" zevtrunk
  # Back to A with a result shown, then away: blanked at once.
  cd $A
  _zev_prompt_git_update
  assert_empty "$_zev_prompt_git" "never B's status in A"
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_equal "${(%)_zev_prompt_git}" 'zevtrunk +1'
}

test_async_same_repo_reformats_and_restarts() {
  needgit
  tworepos
  cd $A
  _zev_prompt_git_update
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_equal "${(%)_zev_prompt_git}" 'zevtrunk +1'
  _zev_prompt_git_start() { touch $ZEV_TEST_TMPDIR/started }
  cd $A/sub
  ZEV_GIT_STAGED_MARKER=S
  _zev_prompt_git_update
  assert_equal "${(%)_zev_prompt_git}" 'zevtrunk S1'
  assert_file_exists $ZEV_TEST_TMPDIR/started
}

test_async_no_repo_disable_no_git() {
  needgit
  tworepos
  local err=$ZEV_TEST_TMPDIR/err
  _zev_prompt_git_start() { touch $ZEV_TEST_TMPDIR/started }
  # Non-repo after a result: blanked, nothing started.
  _zev_prompt_git_key=$A _zev_prompt_git=X _zev_prompt_git_fields=(zevtrunk $H 0 0 1 0 0 0 0)
  cd $NR
  _zev_prompt_git_update 2>>$err
  assert_empty "$_zev_prompt_git"
  assert_empty "$_zev_prompt_git_key"
  assert_equal "${#_zev_prompt_git_fields}" 0
  cd $A
  ZEV_GIT_DISABLE=1
  _zev_prompt_git_update 2>>$err
  assert_empty "$_zev_prompt_git"
  unset ZEV_GIT_DISABLE
  PATH=
  _zev_prompt_git_update 2>>$err
  assert_empty "$_zev_prompt_git"
  assert_file_not_exists $ZEV_TEST_TMPDIR/started
  assert_file_contents $err ''
}

test_async_stale_generation_ignored() {
  needgit
  tworepos
  cd $A
  _zev_prompt_git_update
  (( _zev_prompt_git_gen++ ))
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_empty "$_zev_prompt_git"
  assert_equal "${#_zev_prompt_git_fields}" 0
  assert_empty "$_zev_prompt_git_fd"
}

test_async_widget_cd_discards_result() {
  needgit
  tworepos
  cd $A
  _zev_prompt_git_update
  cd $NR
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_empty "$_zev_prompt_git"
  assert_equal "${#_zev_prompt_git_fields}" 0
}

test_async_git_failure_hides_segment() {
  needgit
  tworepos
  cd $A
  _zev_prompt_git_update
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_not_empty "$_zev_prompt_git"
  rm -f $A/.git/HEAD
  _zev_prompt_git_update
  assert_not_empty "$_zev_prompt_git" "kept until the result arrives"
  _zev_prompt_git_handler $_zev_prompt_git_fd
  assert_empty "$_zev_prompt_git"
  assert_equal "${#_zev_prompt_git_fields}" 0
}

test_async_eof_leaves_state() {
  local fd
  exec {fd}< <(:)
  _zev_prompt_git_fd=$fd _zev_prompt_git=X
  assert_status 0 _zev_prompt_git_handler $fd hup
  assert_equal "$_zev_prompt_git" X
  assert_empty "$_zev_prompt_git_fd"
  assert_false -m "fd closed" fdopen $fd
  assert_status -m "stray fd" 0 _zev_prompt_git_handler 99 err
  assert_status -m "bad fd" 0 _zev_prompt_git_handler '' err
}

test_async_no_fd_leak() {
  needgit
  tworepos
  local -a before after
  before=(/dev/fd/*(N))
  repeat 10; do
    cd $A
    _zev_prompt_git_update
    _zev_prompt_git_update
    _zev_prompt_git_handler $_zev_prompt_git_fd
    _zev_prompt_git_handler $_zev_prompt_git_fd
    cd $B
    _zev_prompt_git_update
    cd $A
    _zev_prompt_git_update
    _zev_prompt_git_handler $_zev_prompt_git_fd
  done
  cd $NR
  _zev_prompt_git_update
  after=(/dev/fd/*(N))
  assert_equal "${#after}" "${#before}" "open fds: ${after:t} vs ${before:t}"
}

test_async_render_integration() {
  needgit
  local A=${ZEV_TEST_TMPDIR:A}/a
  mkrepo $A zevtrunk
  cd $A
  run zsh -f -c 'for k in AHEAD BEHIND CONFLICTED STAGED UNSTAGED UNTRACKED STASH CLEAN BRANCH DETACHED; do
      typeset -g ZEV_GIT_${k}_COLOR=
    done
    ZEV_PATH_COLOR= ZEV_CLOCK_COLOR= ZEV_DURATION_COLOR=
    source "$1"
    _zev_prompt_git_update; _zev_prompt_git_handler $_zev_prompt_git_fd
    print -r -- "${(%)_zev_prompt}"' zsh "$THEME"
  assert_status 0
  assert_empty "$stderr"
  assert_match "$lines[1]" '^.*  zevtrunk ✓  [0-2][0-9]:[0-5][0-9]$'
}

test_async_injection() {
  needgit
  setopt local_options extended_glob
  local T=${ZEV_TEST_TMPDIR:A} b='x$(touch${IFS}pwned)%F{red}!' opts
  local -a pwned
  git init -q -b "$b" $T/r
  cd $T/r
  for opts in 'prompt_subst prompt_bang' ''; do
    run zsh -f -c '[[ -n $2 ]] && setopt ${=2}; source "$1"; _zev_prompt_precmd
      _zev_prompt_git_update; _zev_prompt_git_handler $_zev_prompt_git_fd
      print -rP -- "$PROMPT"' zsh "$THEME" "$opts"
    assert_status 0
    assert_empty "$stderr"
    assert_contains "${output//$'\e'\[[0-9;]#m/}" "$b ✓" "opts=$opts"
    pwned=($T/**/pwned*(N))
    assert_equal "${#pwned}" 0 "injected command ran: $pwned"
  done
}

# ---- setup ---------------------------------------------------------------

test_setup_non_interactive() {
  needgit
  local A=${ZEV_TEST_TMPDIR:A}/a
  mkrepo $A main
  cd $A
  run zsh -f -c 'source "$1"; source "$1"
    print -r -- "H=${(j:,:)precmd_functions}"
    print -r -- "G=[$_zev_prompt_git]"
    for f in ${=3}; do [[ $functions[$f] == *"autoload -X"* ]] && print -r -- "STUB $f"; done
    _zev_prompt_git_precmd
    print -r -- "FD=[$_zev_prompt_git_fd]"' zsh "$THEME" "$A" "${(j: :)GIT_FUNCS}"
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" 'H=_zev_prompt_precmd'$'\n''G=[]'$'\n''FD=[]'
}

test_setup_hostile_options() {
  needgit
  local A=${ZEV_TEST_TMPDIR:A}/a want
  mkrepo $A main
  cd $A
  local script='fpath=("$1/functions" $fpath)
    autoload -Uz $1/functions/_zev_prompt_*(N:t)
    [[ -n $2 ]] && setopt ${=2}
    _zev_prompt_setup
    _zev_prompt_git_update
    _zev_prompt_git_handler $_zev_prompt_git_fd
    print -r -- "$_zev_prompt_git"'
  run zsh -f -c "$script" zsh "$ZEV_ROOT" ''
  assert_status 0
  assert_empty "$stderr"
  want=$output
  assert_equal "$want" '%F{magenta}main%f %F{green}✓%f'
  run zsh -f -c "$script" zsh "$ZEV_ROOT" 'ksh_arrays sh_word_split warn_create_global nounset'
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" "$want"
}

test_static_single_fork_site() {
  setopt local_options extended_glob
  local f line re
  local -a files hits
  re='\$\([^(]|`|[<>]\(|&[!|]|(^|[^|])\|([^|]|$)|^[[:space:]]*\([^(]|[^&]&[[:space:]]*$'
  files=($ZEV_ROOT/functions/_zev_prompt_git*~*/_zev_prompt_git_worker(N))
  assert_equal "${#files}" 8
  for f in $files; do
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line == [[:space:]]#\#* ]] && continue
      [[ $line =~ $re ]] && hits+=("${f:t}: $line")
    done < $f
  done
  assert_equal "${#hits}" 1 "hits: ${(F)hits}"
  assert_match "$hits[1]" '^_zev_prompt_git_start: .*<\(_zev_prompt_git_worker '
}

# ---- perf ----------------------------------------------------------------

test_perf_update() {
  needgit
  local A=${ZEV_TEST_TMPDIR:A}/a
  mkrepo $A main
  mkdir -p $ZEV_TEST_TMPDIR/nr
  cd $A
  typeset -F t s=0
  repeat 20; do
    t=$EPOCHREALTIME
    _zev_prompt_git_update
    (( s += EPOCHREALTIME - t ))
    _zev_prompt_git_handler $_zev_prompt_git_fd
  done
  assert_equal "$_zev_prompt_git" '%F{magenta}main%f %F{green}✓%f'
  assert_true -m "spawn update avg $(( s * 1000 / 20 )) ms" test $(( s * 1000 / 20 < 10 )) -eq 1
  cd $ZEV_TEST_TMPDIR/nr
  s=0
  t=$EPOCHREALTIME
  repeat 200 _zev_prompt_git_update
  (( s = EPOCHREALTIME - t ))
  assert_true -m "non-repo update avg $(( s * 1000 / 200 )) ms" test $(( s * 1000 / 200 < 1 )) -eq 1
}

# ---- end to end (zpty) ---------------------------------------------------

# expect PATTERN SECS -- read the pty into BUF (CR and CSI sequences stripped)
# until BUF matches PATTERN or SECS pass.
expect() {
  setopt local_options extended_glob
  local chunk
  typeset -F end
  (( end = EPOCHREALTIME + $2 ))
  while :; do
    [[ $BUF == $~1 ]] && return 0
    (( EPOCHREALTIME < end )) || return 1
    chunk=
    if sysread -t 0.05 -i $PFD chunk; then
      RAW+=$chunk
      BUF=${${RAW//$'\r'/}//$'\e'\[[0-9;?]#[a-zA-Z]/}
    fi
  done
}

# send LINE -- type LINE and Enter; resets BUF.
send() {
  RAW= BUF=
  zpty -w -n z "$1"$'\r'
}

zpty_start() {
  zmodload zsh/zpty 2>/dev/null || skip "zsh/zpty unavailable"
  typeset -g RAW= BUF= PFD
  zpty z "PATH=${(q)1}:\$PATH zsh -f -i" || fail "zpty"
  PFD=$REPLY
  expect '*%*' 5 || fail "no initial prompt: $BUF"
}

test_setup_interactive_registers_hook_once() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A}
  mkdir -p $T/bin
  zpty_start $T/bin
  send "source ${(q)THEME}; source ${(q)THEME}; print -r -- H=\${(j:,:)precmd_functions}"
  expect "*H=_zev_prompt_precmd,_zev_prompt_git_precmd"$'\n'"*" 5
  local ok=$?
  zpty -d z
  (( ok == 0 )) || fail "hooks: $BUF"
}

test_e2e_zpty() {
  needgit
  local T=${ZEV_TEST_TMPDIR:A} bin A B NR pre
  bin=$T/bin A=$T/a B=$T/b NR=$T/nr
  fakegit $bin
  mkrepo $A zevtrunk
  print n > $A/n
  git -C $A add n
  print more >> $A/f
  touch $A/u1
  mkrepo $B zevother
  mkdir -p $NR
  zpty_start $bin

  send "source ${(q)THEME}"
  expect '*❯*' 5 || fail "step 1: $BUF"

  touch $bin/slow
  send "cd ${(q)A}"
  expect '*cd*❯*' 0.5 || fail "step 2: prompt not drawn within 0.5s: $BUF"
  assert_not_contains "$BUF" zevtrunk "step 2: segment before git finished"
  expect '*  zevtrunk +1 !1 ?1  *' 5 || fail "step 2: no segment: $BUF"

  rm -f $bin/slow
  send "touch n2"
  expect '*zevtrunk +1 !1 ?2*' 5 || fail "step 3: $BUF"

  touch $bin/slow
  send "cd ${(q)B}"
  expect '*cd*❯*' 2 || fail "step 4: no prompt: $BUF"
  assert_not_contains "$BUF" zevtrunk "step 4: stale segment of A shown in B"
  expect '*zevother ✓*' 5 || fail "step 4: no segment: $BUF"

  rm -f $bin/slow
  send "cd ${(q)NR}"
  expect '*cd*❯*' 2 || fail "step 5: no prompt: $BUF"
  expect '*NEVER-MATCHES*' 1
  pre=${BUF#*cd }
  assert_not_contains "$pre" zevtrunk "step 5"
  assert_not_contains "$pre" zevother "step 5"

  send "cd ${(q)A}"
  expect '*zevtrunk +1 !1 ?2*' 5 || fail "step 6: $BUF"
  touch $bin/slow
  : > $bin/calls
  repeat 5; do
    zpty -w -n z $'\r'
    sleep 0.05
  done
  expect '*NEVER-MATCHES*' 3.5
  local -a calls
  calls=("${(@f)$(<$bin/calls)}")
  print -r -- "coalescing: ${#calls} git calls"
  assert_true -m "coalescing: ${#calls} git calls: ${(F)calls}" test ${#calls} -le 2

  send exit
  zpty -d z 2>/dev/null
  return 0
}
