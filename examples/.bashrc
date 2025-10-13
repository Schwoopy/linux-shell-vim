export PATH="$HOME/.local/bin:$PATH"

# <<< COMPLETIONS_AND_FZF_END <<<

# >>> ETERNAL_HISTORY_AND_GIT_PROMPT_START >>>
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE="$HOME/.bash_eternal_history"
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
HISTCONTROL=erasedups
PROMPT_DIRTRIM=2

# Simple prompt (UTF-8 friendly)
if declare -F __git_ps1 >/dev/null 2>&1; then
  export PS1='╭─╼[\[\e[1;36m\]\w\[\e[0m\]] \[\e[1;34m\]$(__git_ps1 "[%s]")\[\e[0m\]\n╰─ \u@\h >> '
else
  parse_git_branch(){ git branch --no-color 2>/dev/null | sed -n "s/^\* //p"; }
  export PS1='╭─╼[\[\e[1;36m\]\w\[\e[0m\]] \[\e[1;34m\]$(parse_git_branch)\[\e[0m\]\n╰─ \u@\h >> '
fi
# <<< ETERNAL_HISTORY_AND_GIT_PROMPT_END <<<

# >>> COMPLETIONS_AND_FZF_START >>>
# bash-completion + user completions + fzf (interactive only)
case $- in
  *i*)
    [[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion

    for p in \
      /usr/share/fzf/completion.bash \
      /usr/share/fzf/shell/completion.bash \
      "$HOME/.fzf/shell/completion.bash"
    do [[ -r "$p" ]] && source "$p"; done

    for p in \
      /usr/share/fzf/key-bindings.bash \
      /usr/share/fzf/shell/key-bindings.bash \
      "$HOME/.fzf/shell/key-bindings.bash"
    do [[ -r "$p" ]] && source "$p"; done

    if [[ -d "$HOME/.bash_completion.d" ]]; then
      for f in "$HOME"/.bash_completion.d/*; do [[ -r "$f" ]] && . "$f"; done
    fi

    command -v carapace >/dev/null && eval "$(carapace _carapace)"
  ;;
esac
# <<< COMPLETIONS_AND_FZF_END <<<

# >>> PBCLIP_PATH_START >>>
# pbcopy/pbpaste shims installed in ~/.local/bin (PATH ensured by installer)
# Backends: wl-clipboard (Wayland), xclip/xsel (X11), clip.exe (WSL: pbcopy only)
# <<< PBCLIP_PATH_END <<<
