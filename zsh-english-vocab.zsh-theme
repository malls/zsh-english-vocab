# zsh-english-vocab theme entry (oh-my-zsh: ZSH_THEME="zsh-english-vocab").
#
# Generic loader: puts functions/ on fpath, autoloads the theme's functions
# (_zev_prompt_*), then calls _zev_prompt_setup if it exists; otherwise sets a
# plain two-line stub prompt. Independent of the plugin. No output, no
# subprocesses, idempotent, and correct when sourced through a symlink (the
# usual install symlinks this file into $ZSH_CUSTOM/themes/).

() {
  emulate -L zsh
  setopt extended_glob
  # The theme keeps its own root: ZEV_ROOT belongs to the plugin, and a copied
  # (not symlinked) theme file must not repoint it.
  local root=${${(%):-%x}:A:h}
  fpath=("$root/functions" ${fpath:#$root/functions})
  local f
  for f in "$root"/functions/_zev_prompt_*(N.:t); do
    autoload -Uz -- "$f"
  done
}

# Called outside the emulate -L block so options it sets (e.g. prompt_subst)
# and hooks it adds persist in the user's shell.
if (( ${+functions[_zev_prompt_setup]} )); then
  _zev_prompt_setup
else
  PROMPT='%F{blue}%~%f'$'\n''%(?.%F{green}.%F{red})❯%f '
fi
# A hook's status must never become the status of `source`.
return 0
