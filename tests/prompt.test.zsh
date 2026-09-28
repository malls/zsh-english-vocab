# Tests for the theme's synchronous prompt (ZEV-7): functions/_zev_prompt_*
# except the git segment (_zev_prompt_git*, ZEV-8).

typeset -g THEME=$ZEV_ROOT/zsh-english-vocab.zsh-theme
typeset -ga ZEV7_FUNCS
ZEV7_FUNCS=(_zev_prompt_setup _zev_prompt_preexec _zev_prompt_precmd
  _zev_prompt_render _zev_prompt_escape _zev_prompt_path_format
  _zev_prompt_duration_format)

autoload -Uz add-zsh-hook
autoload -Uz +X $ZEV7_FUNCS
zmodload zsh/datetime

# state PATH GIT DURATION CLOCK EXIT -- set every render global by hand.
state() {
  typeset -g _zev_prompt_path=$1 _zev_prompt_git=$2 _zev_prompt_duration=$3 \
    _zev_prompt_clock=$4 _zev_prompt_exit=$5
  typeset -g _zev_prompt_opt_subst=0 _zev_prompt_opt_bang=0 _zev_prompt_cmd_start=
}

# line1 / line2 -- the two lines of $_zev_prompt (in REPLY).
line1() { REPLY=${_zev_prompt%%$'\n'*} }
line2() { REPLY=${_zev_prompt#*$'\n'} }

# ---- path_format ---------------------------------------------------------

# pf PWD HOME STYLE EXPECTED
pf() {
  local REPLY
  _zev_prompt_path_format "$1" "$2" "$3"
  assert_equal "$REPLY" "$4" "path_format ${(qq)1} ${(qq)2} ${(qq)3}"
}

test_path_format_short() {
  local h=/Users/f
  pf / $h short /
  pf /usr $h short /usr
  pf /usr/local/bin $h short /u/l/bin
  pf /Users/f $h short '~'
  pf /Users/f/Code/zsh-english-vocab $h short '~/C/zsh-english-vocab'
  pf /Users/f/.config/zsh/plugins $h short '~/.c/z/plugins'
  pf /Users/f/.config $h short '~/.config'
  pf /Users/fo/x/y $h short /U/f/x/y
  pf /Users/f/Документы/x $h short '~/Д/x'
  pf /Users/f/.Ёлка/x $h short '~/.Ё/x'
  pf '/Users/f/My Docs/x' $h short '~/M/x'
  pf '/Users/f/a%b/$(x)' $h short '~/a/$(x)'
  pf /Users/f/..foo/x $h short '~/../x'
}

test_path_format_full() {
  local h=/Users/f
  pf / $h full /
  pf /usr $h full /usr
  pf /usr/local/bin $h full /usr/local/bin
  pf /Users/f $h full '~'
  pf /Users/f/Code/zsh-english-vocab $h full '~/Code/zsh-english-vocab'
}

test_path_format_home_edge_cases() {
  pf /usr/local / short /u/local
  pf /usr/local '' short /u/local
  pf / / short /
  pf '/tmp/a[1]/b/c' '/tmp/a[1]' short '~/b/c'
  pf /tmp/a1/b '/tmp/a[1]' short /t/a/b
  # Trailing slash on HOME gives the same result.
  pf /Users/f/Code/zsh-english-vocab /Users/f/ short '~/C/zsh-english-vocab'
  pf /Users/f /Users/f/ short '~'
  pf /Users/fo/x /Users/f/ short /U/f/x
}

test_path_format_unknown_style_is_short() {
  pf /usr/local/bin /Users/f bogus /u/l/bin
  pf /Users/f/Code/proj /Users/f '' '~/C/proj'
}

# ---- duration_format -----------------------------------------------------

test_duration_format() {
  local REPLY in want
  for in want in 0 0s 3 3s 59 59s 60 1m0s 64 1m4s 3599 59m59s 3600 1h0m0s \
    3661 1h1m1s 86400 1d0h0m0s 90061 1d1h1m1s; do
    _zev_prompt_duration_format $in
    assert_equal "$REPLY" "$want" "duration_format $in"
  done
}

# ---- escape --------------------------------------------------------------

# esc BANG IN EXPECTED
esc() {
  local REPLY
  typeset -g _zev_prompt_opt_bang=$1
  _zev_prompt_escape "$2"
  assert_equal "$REPLY" "$3" "escape (bang=$1) ${(qqqq)2}"
}

test_escape_percent_and_bang() {
  esc 0 'a%b' 'a%%b'
  esc 0 '%%' '%%%%'
  esc 0 'a!b' 'a!b'
  esc 1 'a!b' 'a!!b'
  esc 1 '%!' '%%!!'
}

test_escape_control_chars() {
  esc 0 $'a\e[31mb\nc' 'a?[31mb?c'
  esc 0 $'x\x7fy\tz' 'x?y?z'
}

test_escape_leaves_substitutions_alone() {
  esc 0 '$(rm -rf /)' '$(rm -rf /)'
  esc 1 '`x`' '`x`'
  esc 0 '${HOME}\n' '${HOME}\n'
}

test_escape_empty() {
  esc 0 '' ''
  esc 1 '' ''
}

# ---- render --------------------------------------------------------------

test_render_default_example() {
  state '~/C/zsh-english-vocab' '' 4s 14:32 1
  _zev_prompt_render
  assert_status 0 _zev_prompt_render
  assert_equal "$_zev_prompt" \
    '%F{blue}~/C/zsh-english-vocab%f  %F{yellow}took 4s%f  %F{8}14:32%f'$'\n''%F{red}[1]%f %F{red}❯%f '
  assert_equal "$PROMPT" "$_zev_prompt"
}

test_render_exit_zero() {
  state '~' '' '' 14:32 0
  _zev_prompt_render
  local REPLY
  line2
  assert_equal "$REPLY" '%F{green}❯%f '
  assert_not_contains "$_zev_prompt" '['
}

test_render_git_segment_verbatim_between_two_space_separators() {
  state '~/C/zev' '%F{magenta}main%f' 4s 14:32 1
  _zev_prompt_render
  local REPLY
  line1
  assert_equal "$REPLY" '%F{blue}~/C/zev%f  %F{magenta}main%f  %F{yellow}took 4s%f  %F{8}14:32%f'
}

test_render_empty_optional_segments() {
  local REPLY
  state '~/C/zev' '' 4s '' 0
  _zev_prompt_render
  line1
  assert_equal "$REPLY" '%F{blue}~/C/zev%f  %F{yellow}took 4s%f' "no trailing space without clock"
  state '~/C/zev' '' '' 14:32 0
  _zev_prompt_render
  line1
  assert_equal "$REPLY" '%F{blue}~/C/zev%f  %F{8}14:32%f'
  assert_not_contains "$_zev_prompt" took
  state '~/C/zev' '' '' '' 0
  _zev_prompt_render
  line1
  assert_equal "$REPLY" '%F{blue}~/C/zev%f'
}

test_render_all_colors_empty() {
  ZEV_PATH_COLOR= ZEV_DURATION_COLOR= ZEV_CLOCK_COLOR= ZEV_EXIT_COLOR=
  ZEV_PROMPT_CHAR_OK_COLOR= ZEV_PROMPT_CHAR_ERR_COLOR=
  state '~/C/zev' main 4s 14:32 1
  _zev_prompt_render
  assert_equal "${(%)_zev_prompt}" '~/C/zev  main  took 4s  14:32'$'\n''[1] ❯ '
  assert_not_contains "$_zev_prompt" '%F'
}

test_render_overrides() {
  ZEV_PROMPT_CHAR='>' ZEV_DURATION_PREFIX='⏱ ' ZEV_CLOCK_COLOR=244
  state '~' '' 4s 14:32 0
  _zev_prompt_render
  assert_equal "$_zev_prompt" '%F{blue}~%f  %F{yellow}⏱ 4s%f  %F{244}14:32%f'$'\n''%F{green}>%f '
  ZEV_PATH_COLOR='#ff0088' ZEV_PROMPT_CHAR_ERR_COLOR=magenta ZEV_EXIT_COLOR=1
  state '~' '' '' '' 2
  _zev_prompt_render
  assert_equal "$_zev_prompt" '%F{#ff0088}~%f'$'\n''%F{1}[2]%f %F{magenta}>%f '
}

test_render_prompt_char_is_escaped() {
  ZEV_PROMPT_CHAR='%#'
  state '~' '' '' '' 0
  _zev_prompt_render
  local REPLY
  line2
  assert_equal "$REPLY" '%F{green}%%#%f '
}

test_render_invalid_color_is_no_color() {
  ZEV_PATH_COLOR='red}%F{x' ZEV_CLOCK_COLOR='1 2'
  state '~/C/zev' '' '' 14:32 0
  _zev_prompt_render
  local REPLY
  line1
  assert_equal "$REPLY" '~/C/zev  14:32'
}

test_render_escapes_path() {
  local REPLY
  state '~/a%b!c' '' '' '' 0
  _zev_prompt_render
  line1
  assert_equal "$REPLY" '%F{blue}~/a%%b!c%f'
  state '~/a%b!c' '' '' '' 0
  _zev_prompt_opt_bang=1
  _zev_prompt_render
  line1
  assert_equal "$REPLY" '%F{blue}~/a%%b!!c%f'
  state $'~/a\nb\e' '' '' '' 0
  _zev_prompt_render
  line1
  assert_equal "$REPLY" '%F{blue}~/a?b?%f'
}

test_render_prompt_subst_uses_reference() {
  state '~' '' '' '' 0
  _zev_prompt_opt_subst=1
  _zev_prompt_render
  assert_equal "$PROMPT" '${_zev_prompt}'
  _zev_prompt_opt_subst=0
  _zev_prompt_render
  assert_equal "$PROMPT" "$_zev_prompt"
}

# ---- flow (preexec/precmd) -----------------------------------------------

test_flow_no_preexec_means_exit_0() {
  state '' '' '' '' 0
  (exit 5)
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_exit" 0
  assert_empty "$_zev_prompt_duration"
  local REPLY
  line2
  assert_equal "$REPLY" '%F{green}❯%f '
}

test_flow_command_exit_status() {
  state '' '' '' '' 0
  _zev_prompt_preexec x
  (exit 2)
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_exit" 2
  assert_empty "$_zev_prompt_duration"
  assert_empty "$_zev_prompt_cmd_start"
  local REPLY
  line2
  assert_equal "$REPLY" '%F{red}[2]%f %F{red}❯%f '
}

test_flow_duration_then_cleared() {
  state '' '' '' '' 0
  typeset -F st
  (( st = EPOCHREALTIME - 65 ))
  _zev_prompt_cmd_start=$st
  (exit 1)
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_duration" 1m5s
  assert_equal "$_zev_prompt_exit" 1
  assert_contains "$_zev_prompt" '%F{yellow}took 1m5s%f'
  _zev_prompt_precmd
  assert_empty "$_zev_prompt_duration"
  assert_equal "$_zev_prompt_exit" 0
  assert_not_contains "$_zev_prompt" took
}

# start_ago SECS -- pretend a command started SECS seconds ago.
start_ago() {
  typeset -F st
  (( st = EPOCHREALTIME - $1 ))
  typeset -g _zev_prompt_cmd_start=$st
}

test_flow_duration_threshold() {
  state '' '' '' '' 0
  start_ago 2.5; _zev_prompt_precmd
  assert_empty "$_zev_prompt_duration" "2.5s is below the default 3"
  ZEV_DURATION_THRESHOLD=2
  start_ago 2.5; _zev_prompt_precmd
  assert_equal "$_zev_prompt_duration" 2s
  ZEV_DURATION_THRESHOLD=2.4
  start_ago 2.5; _zev_prompt_precmd
  assert_equal "$_zev_prompt_duration" 2s "decimal threshold"
  ZEV_DURATION_THRESHOLD=0
  _zev_prompt_preexec x; _zev_prompt_precmd
  assert_equal "$_zev_prompt_duration" 0s
  ZEV_DURATION_THRESHOLD=abc
  start_ago 2.5; _zev_prompt_precmd
  assert_empty "$_zev_prompt_duration" "invalid threshold falls back to 3"
  start_ago 3.5; _zev_prompt_precmd
  assert_equal "$_zev_prompt_duration" 3s
  ZEV_DURATION_THRESHOLD=
  start_ago 2.5; _zev_prompt_precmd
  assert_empty "$_zev_prompt_duration" "empty threshold falls back to 3"
}

test_flow_start_without_datetime_shows_status_only() {
  state '' '' '' '' 0
  _zev_prompt_cmd_start=-
  (exit 4)
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_exit" 4
  assert_empty "$_zev_prompt_duration"
  assert_empty "$_zev_prompt_cmd_start"
}

test_flow_clock() {
  local REPLY
  state '' '' '' '' 0
  _zev_prompt_precmd
  assert_match "$_zev_prompt_clock" '^[0-2][0-9]:[0-5][0-9]$'
  ZEV_CLOCK_FORMAT='%H:%M:%S'
  _zev_prompt_precmd
  assert_equal "${#_zev_prompt_clock}" 8
  ZEV_CLOCK_FORMAT=''
  _zev_prompt_precmd
  assert_empty "$_zev_prompt_clock"
  line1
  assert_equal "$REPLY" '%F{blue}~%f'
}

test_flow_path_from_pwd_and_home() {
  HOME=$ZEV_TEST_TMPDIR/home
  mkdir -p "$HOME/Code/proj"
  cd "$HOME/Code/proj"
  state '' '' '' '' 0
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_path" '~/C/proj'
  ZEV_PATH_STYLE=full
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_path" '~/Code/proj'
  cd /
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_path" /
}

test_flow_first_call_captures_status() {
  run zsh -f -c 'source "$1"; _zev_prompt_preexec x; (exit 3); _zev_prompt_precmd
    print -r -- $_zev_prompt_exit' zsh "$THEME"
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" 3
}

test_flow_resource_during_command_keeps_status() {
  state '' '' '' '' 0
  start_ago 65
  _zev_prompt_setup
  (exit 4)
  _zev_prompt_precmd
  assert_equal "$_zev_prompt_exit" 4
  assert_equal "$_zev_prompt_duration" 1m5s
}

# ---- setup ---------------------------------------------------------------

test_setup_is_idempotent() {
  RPROMPT=something
  _zev_prompt_setup
  assert_status 0 _zev_prompt_setup
  assert_equal "${#${(@M)precmd_functions:#_zev_prompt_precmd}}" 1
  assert_equal "${#${(@M)preexec_functions:#_zev_prompt_preexec}}" 1
  assert_empty "$RPROMPT"
  assert_equal "$_zev_prompt_exit" 0
  assert_empty "$_zev_prompt_cmd_start"
}

test_setup_via_theme_sets_prompt_immediately() {
  run zsh -f -c 'source "$1"; print -r -- "$PROMPT"; print -r -- "[$RPROMPT]"
    print -rl -- $precmd_functions $preexec_functions' zsh "$THEME"
  assert_status 0
  assert_empty "$stderr"
  assert_equal "${#lines}" 5
  assert_match "$lines[1]" '^%F\{blue\}~%f  %F\{8\}[0-2][0-9]:[0-5][0-9]%f$'
  assert_equal "${(F)lines[2,5]}" '%F{green}❯%f '$'\n''[]'$'\n''_zev_prompt_precmd'$'\n''_zev_prompt_preexec'
}

test_setup_with_prompt_subst_sets_reference() {
  run zsh -f -c 'setopt prompt_subst; source "$1"; print -r -- "$PROMPT"
    [[ -o prompt_subst ]] && print still-on' zsh "$THEME"
  assert_status 0
  assert_equal "$output" '${_zev_prompt}'$'\n''still-on'
}

# ---- ZEV-8 seam ----------------------------------------------------------

test_seam_git_setup_called_once_and_segment_rendered() {
  typeset -gi calls=0
  _zev_prompt_git_setup() {
    (( calls++ ))
    _zev_prompt_git=GIT
    add-zsh-hook precmd fakegit
  }
  fakegit() { : }
  _zev_prompt_setup
  assert_equal "$calls" 1
  assert_true -m "our precmd runs before the git hook" \
    test ${precmd_functions[(i)_zev_prompt_precmd]} -lt ${precmd_functions[(i)fakegit]}
  assert_contains "$_zev_prompt" '%F{blue}~%f  GIT  %F{8}'
  _zev_prompt_git=
  _zev_prompt_render
  assert_not_contains "$_zev_prompt" GIT
  local REPLY
  line1
  assert_match "$REPLY" '^%F\{blue\}~%f  %F\{8\}[^ ]+%f$'
}

# ---- injection -----------------------------------------------------------

# inject OPTS DIRNAME -- print the expanded prompt of a shell in DIRNAME.
inject() {
  local d=$ZEV_TEST_TMPDIR/inj/$2
  mkdir -p -- "$d"
  run zsh -f -c 'cd -- "$3" || exit 9; [[ -n $2 ]] && setopt ${=2}; source "$1"
    print -rP -- "$PROMPT"' zsh "$THEME" "$1" "$d"
  assert_status 0
  assert_empty "$stderr"
  local -a pwned
  pwned=($ZEV_TEST_TMPDIR/**/pwned*(N))
  assert_equal "${#pwned}" 0 "injected command ran: $pwned"
}

test_injection_dirnames_are_inert() {
  local opts
  for opts in 'prompt_subst prompt_bang' ''; do
    inject "$opts" '%F{red}!x$(touch pwned1)'
    assert_contains "$output" '$(touch' "opts=$opts"
    assert_contains "$output" '%F{red}!x$(touch pwned1)' "opts=$opts"
    inject "$opts" '%F{red}!x`touch pwned2`'
    assert_contains "$output" '%F{red}!x`touch pwned2`' "opts=$opts"
    inject "$opts" '${HOME}%~'
    assert_contains "$output" '${HOME}%~' "opts=$opts"
  done
}

# ---- robustness ----------------------------------------------------------

# Loads the functions the way the entry file does, then runs setup under the
# given options (ksh_arrays breaks the entry file's own $+functions[...] test,
# so setup is called directly here).
test_robust_under_hostile_options() {
  local script='fpath=("$1/functions" $fpath)
    autoload -Uz $1/functions/_zev_prompt_*(N:t)
    [[ -n $2 ]] && setopt ${=2}
    ZEV_CLOCK_FORMAT=CLK
    _zev_prompt_setup
    print -r -- "$_zev_prompt"
    _zev_prompt_preexec x; (exit 3); _zev_prompt_precmd
    print -r -- "$_zev_prompt"'
  run zsh -f -c "$script" zsh "$ZEV_ROOT" ''
  assert_status 0
  local want=$output
  assert_equal "$want" '%F{blue}~%f  %F{8}CLK%f'$'\n''%F{green}❯%f '$'\n''%F{blue}~%f  %F{8}CLK%f'$'\n''%F{red}[3]%f %F{red}❯%f '
  run zsh -f -c "$script" zsh "$ZEV_ROOT" 'ksh_arrays sh_word_split warn_create_global nounset'
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" "$want"
}

test_resource_under_err_exit_survives() {
  run zsh -f -c 'source "$1"; setopt err_exit err_return; source "$1"; print -r -- "survived rc=$?"' zsh "$THEME"
  assert_status 0
  assert_equal "$output" 'survived rc=0'
}

test_escape_replaces_invalid_bytes_in_utf8_locale() {
  LC_ALL=en_US.UTF-8
  _zev_prompt_opt_bang=0
  _zev_prompt_escape $'br\x9banch-é'
  assert_equal "$REPLY" 'br?anch-é'
}

test_robust_theme_source_with_warn_create_global() {
  run zsh -f -c 'setopt sh_word_split warn_create_global nounset; ZEV_CLOCK_FORMAT=
    source "$1"; print -r -- "$_zev_prompt"' zsh "$THEME"
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" '%F{blue}~%f'$'\n''%F{green}❯%f '
}

test_robust_empty_path() {
  run zsh -f -c 'source "$1"; PATH=; _zev_prompt_preexec x; _zev_prompt_precmd
    _zev_prompt_render; print ok' zsh "$THEME"
  assert_status 0
  assert_empty "$stderr"
  assert_equal "$output" ok
}

test_static_no_forks() {
  setopt local_options extended_glob
  local f line
  local -a files hits
  files=($ZEV_ROOT/functions/_zev_prompt_*~*/_zev_prompt_git*(N))
  assert_true -m "at least the 7 ZEV-7 files" test ${#files} -ge 7
  for f in $files; do
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line == [[:space:]]#\#* ]] && continue
      if [[ $line =~ '\$\([^(]|`|[<>]\(' ]]; then
        hits+=("${f:t}: $line")
      fi
    done < $f
  done
  assert_equal "${(F)hits}" ''
}

# ---- oh-my-zsh -----------------------------------------------------------

test_ohmyzsh_prompt() {
  [[ -n ${ZEV_OMZ_DIR-} && -f $ZEV_OMZ_DIR/oh-my-zsh.sh ]] || skip "oh-my-zsh not found"
  local custom=$HOME/custom
  mkdir -p "$custom/plugins" "$custom/themes" "$HOME/.cache/omz"
  ln -s "$ZEV_ROOT/zsh-english-vocab.zsh-theme" "$custom/themes/zsh-english-vocab.zsh-theme"
  cat > "$ZDOTDIR/.zshrc" <<EOF
ZSH=${(q)ZEV_OMZ_DIR}
ZSH_CUSTOM=\$HOME/custom
ZSH_CACHE_DIR=\$HOME/.cache/omz
ZSH_COMPDUMP=\$HOME/.zcompdump
DISABLE_AUTO_UPDATE=true
zstyle ':omz:update' mode disabled
ZSH_DISABLE_COMPFIX=true
ZSH_THEME=zsh-english-vocab
plugins=(git)
source \$ZSH/oh-my-zsh.sh
EOF
  run zsh -i -c 'print -r -- "P=$PROMPT"; print -r -- "R=[$RPROMPT]"; print -r -- ${(%)_zev_prompt}'
  assert_contains "$output" 'P=${_zev_prompt}'
  assert_contains "$output" 'R=[]'
  assert_contains "$output" '❯'
  assert_not_contains "$output$stderr" "theme 'zsh-english-vocab' not found"
}
