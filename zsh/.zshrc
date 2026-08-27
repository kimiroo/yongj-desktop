if [[ -n "$ZPROF" ]]; then zmodload zsh/zprof; fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Using Starship for the prompt instead of an omz theme.
ZSH_THEME=""

# --- perf: skip omz's compaudit security scan (single-user workstation) ---
ZSH_DISABLE_COMPFIX=true
DISABLE_MAGIC_FUNCTIONS=true
zstyle ':omz:update' mode disabled

# --- perf: compinit ---
# omz (this version) always calls `compinit -u -d $ZSH_COMPDUMP` itself,
# unconditionally, further down in oh-my-zsh.sh. `-u` only changes what
# happens with insecure dirs it finds -- it does NOT skip the compaudit
# call itself (only -C does that; see /usr/share/zsh/*/functions/compinit
# comments). So ZSH_DISABLE_COMPFIX=true alone does not remove compaudit
# here, verified with zprof.
#
# Fix: pre-define compinit as a real function. `autoload -U compinit`
# (which omz runs right before calling it) does NOT clobber an
# already-defined function body -- only replaces it on the next call if
# it was still in autoload-pending state. So omz's own hardcoded call
# below ends up running *this* definition instead, taking the -C fast
# path (trust the dump unless it's missing/>24h old) and skipping
# compaudit entirely. Verified with hyperfine: this is the version that's
# actually faster than stock, see ZSH.md.
SHORT_HOST="${HOST/.*/}"
ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"
compinit() {
  emulate -L zsh -o extended_glob
  unfunction compinit
  autoload -Uz compinit
  if [[ -n ${ZSH_COMPDUMP}(#qN.mh+24) ]]; then
    compinit -d "$ZSH_COMPDUMP"
  else
    compinit -C -d "$ZSH_COMPDUMP"
  fi
}

# Which plugins would you like to load?
# zsh-defer must load synchronously (it's what makes everything else lazy).
# zsh-syntax-highlighting is deferred separately below, always last.
plugins=(git zsh-defer)

source $ZSH/oh-my-zsh.sh

# Legacy terminal detection and fallback
_use_plain_prompt() {
  emulate -L zsh
  case "$TERM" in
    linux|dumb|vt100|vt220|ansi|xterm) return 0 ;;
  esac
  return 1
}

if _use_plain_prompt; then
  export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship-plain.toml"
fi

# Manual override
if [[ -n "$FORCE_PLAIN_PROMPT" ]]; then
  export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship-plain.toml"
elif [[ -n "$FORCE_NERD_PROMPT" ]]; then
  unset STARSHIP_CONFIG
fi

# User configuration

eval "$(starship init zsh)"

# --- auto-activate/deactivate python venv based on cwd ---
# Walks up from $PWD (stopping at $HOME or /) looking for .venv/ or venv/;
# activates it if found and not already active, deactivates if you cd out
# of it. No new dependency (no direnv/autoenv) -- starship's own [python]
# module just displays $VIRTUAL_ENV, this is what actually sets it.
# starship's init above already sets VIRTUAL_ENV_DISABLE_PROMPT=1, so the
# venv's own activate script won't also try to touch the prompt.
_auto_venv() {
  emulate -L zsh
  local dir="$PWD" venv=""
  while true; do
    if [[ -f "$dir/.venv/bin/activate" ]]; then venv="$dir/.venv"; break; fi
    if [[ -f "$dir/venv/bin/activate" ]]; then venv="$dir/venv"; break; fi
    [[ "$dir" == "/" || "$dir" == "$HOME" ]] && break
    dir="${dir:h}"
  done
  if [[ -n "$venv" ]]; then
    [[ "$VIRTUAL_ENV" != "$venv" ]] && source "$venv/bin/activate"
  elif [[ -n "$VIRTUAL_ENV" ]]; then
    (( $+functions[deactivate] )) && deactivate
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _auto_venv
zsh-defer _auto_venv

# --- perf: cache completion scripts for CLIs with their own generator ---
# (kubectl/helm/docker/flux/pip completion zsh forks a subprocess every
# time it's called; cache to ~/.cache/zsh and regenerate at most daily)
_gen_completion_cache() {
  emulate -L zsh -o extended_glob
  local cache_file="$HOME/.cache/zsh/$1"
  shift
  if [[ ! -s "$cache_file" || -n ${cache_file}(#qN.mh+24) ]]; then
    mkdir -p "$HOME/.cache/zsh"
    "$@" >| "$cache_file" 2>/dev/null
  fi
  [[ -s "$cache_file" ]] && source "$cache_file"
}

command -v kubectl >/dev/null && zsh-defer _gen_completion_cache kubectl.zsh kubectl completion zsh
command -v helm    >/dev/null && zsh-defer _gen_completion_cache helm.zsh    helm completion zsh
command -v docker  >/dev/null && zsh-defer _gen_completion_cache docker.zsh  docker completion zsh
command -v flux    >/dev/null && zsh-defer _gen_completion_cache flux.zsh    flux completion zsh
command -v pip     >/dev/null && zsh-defer _gen_completion_cache pip.zsh     pip completion --zsh

# --- perf: zcompile .zshrc when it's changed ---
# (the completion dump is already zrecompiled by omz itself, see above)
_zcompile_if_stale() {
  local src=$1
  [[ -s "$src" && ( ! -s "$src.zwc" || "$src" -nt "$src.zwc" ) ]] && zcompile -R "$src" &>/dev/null
}
zsh-defer _zcompile_if_stale "$HOME/.zshrc"

# zsh-syntax-highlighting must always load last (after all widgets/plugins
# are set up), so keep this the final zsh-defer call in the file.
zsh-defer source "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

if [[ -n "$ZPROF" ]]; then zprof; fi
export PATH="$HOME/.local/bin:$PATH"
