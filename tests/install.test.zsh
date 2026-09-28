# Tests for the entry files: zsh-english-vocab.plugin.zsh and
# zsh-english-vocab.zsh-theme (fpath setup, extension hooks, symlinked theme,
# and an optional oh-my-zsh smoke test).

typeset -g PLUGIN=$ZEV_ROOT/zsh-english-vocab.plugin.zsh
typeset -g THEME=$ZEV_ROOT/zsh-english-vocab.zsh-theme

# make_copy DIR FILE -- copy an entry file into DIR (with an empty functions/)
make_copy() {
  mkdir -p -- "$1/functions"
  cp -- "$2" "$1/"
}

# ---- plugin --------------------------------------------------------------

test_plugin_sources_silently_and_sets_fpath() {
  run zsh -f -c 'source "$1"' zsh "$PLUGIN"
  assert_status 0
  assert_empty "$output"
  assert_empty "$stderr"
  run zsh -f -c 'source "$1" && print -r -- "$fpath[1]" && print -r -- "$ZEV_ROOT"' zsh "$PLUGIN"
  assert_status 0
  assert_equal "$output" "$ZEV_ROOT/functions"$'\n'"$ZEV_ROOT"
}

test_plugin_is_idempotent() {
  run zsh -f -c '
    source "$1"; source "$1"
    print -r -- ${#${(M)fpath:#$ZEV_ROOT/functions}}' zsh "$PLUGIN"
  assert_status 0
  assert_equal "$output" 1
}

test_plugin_sourced_inside_function() {
  run zsh -f -c 'f() { source "$1" }; f "$1"; print -r -- "$ZEV_ROOT|$fpath[1]"' zsh "$PLUGIN"
  assert_status 0
  assert_equal "$output" "$ZEV_ROOT|$ZEV_ROOT/functions"
}

test_plugin_idempotent_in_dir_with_glob_chars() {
  local d="$ZEV_TEST_TMPDIR/p[1]*"
  make_copy "$d" "$PLUGIN"
  run zsh -f -c '
    source "$1"; source "$1"
    print -r -- "$ZEV_ROOT"
    print -r -- ${#${(M)fpath:#$ZEV_ROOT/functions}}' zsh "$d/zsh-english-vocab.plugin.zsh"
  assert_status 0
  assert_equal "$lines[1]" "${d:A}"
  assert_equal "$lines[2]" 1
}

test_plugin_calls_startup_hook_and_autoloads_vocab() {
  local p=$ZEV_TEST_TMPDIR/p
  make_copy "$p" "$PLUGIN"
  print -r -- 'print started' > "$p/functions/_zev_vocab_startup"
  print -r -- 'print vocab-ran' > "$p/functions/vocab"
  print -r -- 'print not-autoloaded' > "$p/functions/other_name"
  run zsh -f -c 'source "$1"; print -r -- "rc=$?"; whence -w vocab other_name' \
    zsh "$p/zsh-english-vocab.plugin.zsh"
  assert_equal "$lines[1]" started
  assert_equal "$lines[2]" "rc=0"
  assert_equal "$lines[3]" "vocab: function"
  assert_equal "$lines[4]" "other_name: none"
}

test_plugin_registers_completion_after_compinit() {
  local p=$ZEV_TEST_TMPDIR/p
  make_copy "$p" "$PLUGIN"
  print -r -- 'print vocab-ran' > "$p/functions/vocab"
  printf '#compdef vocab\n_arguments "1:cmd:(next help)"\n' > "$p/functions/_vocab"
  run zsh -f -c '
    autoload -Uz compinit; compinit -D
    source "$1"; print -r -- "rc=$?"
    print -r -- "comp=$_comps[vocab]"' zsh "$p/zsh-english-vocab.plugin.zsh"
  assert_contains "$output" "rc=0"
  assert_contains "$output" "comp=_vocab"
}

test_plugin_without_compinit_returns_0() {
  local p=$ZEV_TEST_TMPDIR/p
  make_copy "$p" "$PLUGIN"
  printf '#compdef vocab\n' > "$p/functions/_vocab"
  run zsh -f -c 'source "$1"' zsh "$p/zsh-english-vocab.plugin.zsh"
  assert_status 0
  assert_empty "$output$stderr"
}

# ---- theme ---------------------------------------------------------------

test_theme_sources_silently_and_sets_prompt() {
  run zsh -f -c 'source "$1"' zsh "$THEME"
  assert_status 0
  assert_empty "$output"
  assert_empty "$stderr"
  run zsh -f -c 'source "$1"; print -r -- "${#PROMPT}|$fpath[1]"' zsh "$THEME"
  assert_status 0
  assert_match "$output" "^[1-9][0-9]*\\|$ZEV_ROOT/functions\$"
}

test_theme_is_idempotent() {
  run zsh -f -c '
    source "$1"; source "$1"
    print -r -- ${#${(M)fpath:#$ZEV_ROOT/functions}}' zsh "$THEME"
  assert_status 0
  assert_equal "$output" 1
}

test_theme_via_symlink_resolves_real_root() {
  mkdir -p "$HOME/themes"
  ln -s "$THEME" "$HOME/themes/zsh-english-vocab.zsh-theme"
  run env -u ZEV_ROOT zsh -f -c 'source "$1"; print -r -- "$fpath[1]"' zsh "$HOME/themes/zsh-english-vocab.zsh-theme"
  assert_status 0
  assert_equal "$output" "$ZEV_ROOT/functions"
}

test_theme_leaves_plugin_zev_root_alone() {
  local p=$ZEV_TEST_TMPDIR/t
  make_copy "$p" "$THEME"
  run zsh -f -c 'ZEV_ROOT=/plugin/root; source "$1"; print -r -- "$ZEV_ROOT"' zsh "$p/zsh-english-vocab.zsh-theme"
  assert_status 0
  assert_equal "$output" /plugin/root
}

test_hooks_returning_nonzero_still_source_with_rc_0() {
  local p=$ZEV_TEST_TMPDIR/p t=$ZEV_TEST_TMPDIR/t
  make_copy "$p" "$PLUGIN"
  make_copy "$t" "$THEME"
  print -r -- 'return 1' > "$p/functions/_zev_vocab_startup"
  print -r -- 'return 1' > "$t/functions/_zev_prompt_setup"
  run zsh -f -c 'source "$1"; print -r -- "plugin=$?"; source "$2"; print -r -- "theme=$?"' \
    zsh "$p/zsh-english-vocab.plugin.zsh" "$t/zsh-english-vocab.zsh-theme"
  assert_equal "$output" $'plugin=0\ntheme=0'
}

test_theme_calls_prompt_setup_hook() {
  local p=$ZEV_TEST_TMPDIR/t
  make_copy "$p" "$THEME"
  printf 'setopt prompt_subst\nPROMPT=HOOKED\n' > "$p/functions/_zev_prompt_setup"
  run zsh -f -c '
    source "$1"; print -r -- "rc=$?"
    print -r -- "PROMPT=$PROMPT"
    [[ -o prompt_subst ]] && print prompt_subst=on' zsh "$p/zsh-english-vocab.zsh-theme"
  assert_status 0
  assert_equal "$output" $'rc=0\nPROMPT=HOOKED\nprompt_subst=on'
}

test_theme_does_not_autoload_plugin_functions() {
  local p=$ZEV_TEST_TMPDIR/t
  make_copy "$p" "$THEME"
  print -r -- 'print started' > "$p/functions/_zev_vocab_startup"
  run zsh -f -c 'source "$1"; whence -w _zev_vocab_startup' zsh "$p/zsh-english-vocab.zsh-theme"
  assert_equal "$output" "_zev_vocab_startup: none"
}

# ---- oh-my-zsh smoke test ------------------------------------------------

test_ohmyzsh_loads_plugin_and_theme() {
  [[ -n ${ZEV_OMZ_DIR-} && -f $ZEV_OMZ_DIR/oh-my-zsh.sh ]] || skip "oh-my-zsh not found"
  local custom=$HOME/custom
  mkdir -p "$custom/plugins" "$custom/themes" "$HOME/.cache/omz"
  ln -s "$ZEV_ROOT" "$custom/plugins/zsh-english-vocab"
  ln -s "$ZEV_ROOT/zsh-english-vocab.zsh-theme" "$custom/themes/zsh-english-vocab.zsh-theme"
  cat > "$ZDOTDIR/.zshrc" <<EOF
ZSH=${(q)ZEV_OMZ_DIR}
ZSH_CUSTOM=\$HOME/custom
ZSH_CACHE_DIR=\$HOME/.cache/omz
ZSH_COMPDUMP=\$HOME/.zcompdump
DISABLE_AUTO_UPDATE=true
zstyle ':omz:update' mode disabled
ZSH_DISABLE_COMPFIX=true
ZEV_VOCAB_DISABLE=1
ZSH_THEME=zsh-english-vocab
plugins=(git zsh-english-vocab)
source \$ZSH/oh-my-zsh.sh
EOF
  # ZEV_ROOT is exported by the runner; unset it so only the plugin can set it.
  run env -u ZEV_ROOT zsh -i -c 'print -r -- "ROOT=$ZEV_ROOT"; print -r -- "PROMPT=$PROMPT"'
  assert_contains "$output" "ROOT=$ZEV_ROOT"
  assert_match "$output" "(^|"$'\n'")PROMPT=[^"$'\n'"]"
  assert_not_contains "$output$stderr" "theme 'zsh-english-vocab' not found"
  assert_not_contains "$output$stderr" "plugin 'zsh-english-vocab' not found"
}

test_entry_hooks_run_under_ksh_arrays() {
  local p=$ZEV_TEST_TMPDIR/p t=$ZEV_TEST_TMPDIR/t
  make_copy "$p" "$PLUGIN"
  make_copy "$t" "$THEME"
  print -r -- 'print startup-ran' > "$p/functions/_zev_vocab_startup"
  print -r -- 'print setup-ran' > "$t/functions/_zev_prompt_setup"
  run zsh -f -c 'setopt ksh_arrays; source "$1"; source "$2"' \
    zsh "$p/zsh-english-vocab.plugin.zsh" "$t/zsh-english-vocab.zsh-theme"
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" $'startup-ran\nsetup-ran'
}
