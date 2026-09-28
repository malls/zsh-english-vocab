# zsh-english-vocab plugin entry (oh-my-zsh: plugins=(... zsh-english-vocab)).
#
# Generic loader: puts functions/ on fpath and autoloads the plugin's functions
# (vocab, _vocab, _zev_vocab_*). Features are added as files under functions/;
# this file does not change. No output, no subprocesses, idempotent, and correct
# when sourced from inside a function or through a symlink.

() {
  emulate -L zsh
  setopt extended_glob
  typeset -g ZEV_ROOT=${${(%):-%x}:A:h}
  fpath=("$ZEV_ROOT/functions" ${fpath:#$ZEV_ROOT/functions})
  local f
  for f in "$ZEV_ROOT"/functions/(vocab|_vocab|_zev_vocab_*)(N.:t); do
    autoload -Uz -- "$f"
  done
  # Completion (functions/_vocab). oh-my-zsh has already run compinit.
  if (( $+functions[_vocab] && $+functions[compdef] )); then
    compdef _vocab vocab
  fi
}

# Startup word (functions/_zev_vocab_startup owns all suppression logic). Called
# outside the emulate -L block so it runs with the user's options.
if (( ${+functions[_zev_vocab_startup]} )); then
  _zev_vocab_startup
fi
# A hook's status must never become the status of `source`.
return 0
