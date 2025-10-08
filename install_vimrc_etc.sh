#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Dev Bootstrap (Append-only, No EPEL)
# - Runs for the CURRENT USER only; fixes ownership of created files/dirs
# - Prompts for sudo ONLY when needed (system packages, /usr/local/bin installs)
# - Vim + Pathogen + plugins
# - bashrc blocks (history/prompt, ble.sh), fzf user fallback, argcomplete
# - Linters: yamllint (pip fallback), shellcheck, shfmt, ruff, pylint
# - kubectl + oc (+ completions)
# - Ghostty (Fedora COPR) + Dracula theme (idempotent, cached failures) [DISABLED by default]
# - tmux + TPM + Dracula + menus/tabs
# - pbcopy/pbpaste (Linux-only shims) + bashrc integration
# - Repo tooling (Makefile, .shellcheckrc)
# ==============================================================================

# --------------------------- CONFIG ------------------------------------------
ENABLE_PACKAGES=1
ENABLE_VIM_PLUGINS=1
ENABLE_VIMRC=1
ENABLE_YAMLLINT=1
ENABLE_BASHRC=1
ENABLE_BLE=1
ENABLE_ARGCOMPLETE=1
ENABLE_BASH_LINTERS=1
ENABLE_PY_LINTERS=1
ENABLE_KUBECTL_OC=1
ENABLE_REPO_TOOLING=1
ENABLE_GHOSTTY=0              # disabled by default (requires GUI WM)
ENABLE_GHOSTTY_DRACULA=0
ENABLE_TMUX=0
ENABLE_TMUX_DRACULA=0
ENABLE_PBCOPY_PBPASTE=1       # install Linux pbcopy/pbpaste shims

CLEAN_OUTPUT=1
LOG_FILE=""   # e.g. /tmp/bootstrap.log

VIM_DIR="$HOME/.vim"
YAMLLINT_CONF="$HOME/.config/yamllint/config"
BLE_BUILD_DIR="$HOME/.local/src/ble.sh"
USER_BASH_COMPLETION_DIR="$HOME/.bash_completion.d"
TMUX_TPM_DIR="$HOME/.tmux/plugins/tpm"
TMUX_CONF="$HOME/.tmux.conf"

PACKAGES_RHEL_BASE=(vim-enhanced git powerline-fonts yamllint curl make gawk bash-completion python3 python3-pip unzip tmux)
PACKAGES_DEBIAN_BASE=(vim git fonts-powerline fzf yamllint curl make gawk bash-completion python3 python3-pip unzip tmux)

# Python linters
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"

# kubectl/oc
KUBECTL_VERSION="v1.31.1"
OC_CHANNEL="stable"

# Ghostty
GHOSTTY_COPR_SHORTHAND="alternateved/ghostty"
GHOSTTY_DEB_URL=""
USE_UNOFFICIAL_GHOSTTY_UBUNTU=0
GHOSTTY_DRACULA_ZIP="https://github.com/dracula/ghostty/archive/refs/heads/main.zip"
# Force re-download of Dracula theme even if a recent failure is cached:
#   GHOSTTY_DRACULA_FORCE=1 ./install_vimrc_etc.sh

# Vim plugins (name=url)
VIM_PLUGIN_LIST="$(cat <<'EOF'
vim-airline=https://github.com/vim-airline/vim-airline
indentLine=https://github.com/Yggdroot/indentLine
nerdtree=https://github.com/preservim/nerdtree
fzf-vim=https://github.com/junegunn/fzf.vim
vim-gitgutter=https://github.com/airblade/vim-gitgutter
vim-fugitive=https://github.com/tpope/vim-fugitive
vim-floaterm=https://github.com/voldikss/vim-floaterm
shades-of-purple=https://github.com/Rigellute/shades-of-purple.vim.git
jinja-4-vim=https://github.com/lepture/vim-jinja.git
ale=https://github.com/dense-analysis/ale
EOF
)"

# ==============================================================================
# Logging (-e safe; stdout + optional file)
[[ -n "$LOG_FILE" ]] && mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
_logfile(){ [[ -n "$LOG_FILE" ]] && printf "%b" "$*" >>"$LOG_FILE" || :; }  # ALWAYS return 0
_log(){ printf "%b" "$*"; _logfile "$*"; }
info(){ _log "\033[1;34m[INFO]\033[0m $*\n"; }
warn(){ _log "\033[1;33m[WARN]\033[0m $*\n"; }
ok(){   _log "\033[1;32m[ OK ]\033[0m $*\n"; }
err(){  _log "\033[1;31m[ERR ]\033[0m $*\n"; }

trap 'err "Failed: \"$BASH_COMMAND\" at ${BASH_SOURCE[0]}:${LINENO}"' ERR

SUDO(){ if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; elif command -v sudo >/dev/null; then sudo "$@"; else err "Need root for: $*"; return 1; fi; }

exec_run(){
  if [[ -n "$LOG_FILE" ]]; then
    (( CLEAN_OUTPUT )) && "$@" >>"$LOG_FILE" 2>&1 || "$@" 2>&1 | tee -a "$LOG_FILE"
  else
    (( CLEAN_OUTPUT )) && "$@" >/dev/null 2>&1 || "$@"
  fi
}

TMPFILES=()
mktempf(){ local t; t="$(mktemp)"; TMPFILES+=("$t"); printf '%s' "$t"; }
cleanup(){ for f in "${TMPFILES[@]:-}"; do [[ -n "$f" ]] && rm -f "$f" 2>/dev/null || true; done
           rm -f /tmp/{kubectl,kubectl.sha256,oc.tar.gz,oc,ghostty.deb,ghostty-dracula.zip} 2>/dev/null || true; }
trap cleanup EXIT

# ==============================================================================
# Ownership & permissions helpers (ABSOLUTE PATHS for chown/chmod)
USER_UID="$(id -u)"
USER_GID="$(id -g)"

_abs_path() {
  local p="$1"
  [[ -n "$p" ]] || return 1
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "$p"
  elif command -v readlink >/dev/null 2>&1; then
    readlink -m -- "$p" 2>/dev/null || { ( cd "$(dirname -- "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename -- "$p")" ); }
  else
    ( cd "$(dirname -- "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename -- "$p")" )
  fi
}

ensure_user_ownership() {
  local p abs
  for p in "$@"; do
    [[ -e "$p" ]] || continue
    abs="$(_abs_path "$p")" || continue
    local owner_uid; owner_uid="$(stat -c '%u' "$abs" 2>/dev/null || echo "$USER_UID")"
    if [[ "$owner_uid" != "$USER_UID" ]]; then
      info "Fixing ownership: $abs -> $(whoami):$(id -gn)"
      SUDO chown -R "$USER_UID:$USER_GID" -- "$abs"
    fi
  done
}

mkuserdir() {
  local mode="$1"; shift
  local d abs
  for d in "$@"; do
    mkdir -p -- "$d"
    abs="$(_abs_path "$d" 2>/dev/null || echo "$d")"
    chmod "$mode" -- "$abs" 2>/dev/null || true
    ensure_user_ownership "$abs"
  done
}

setperms() {
  local mode="$1"; shift
  local f abs
  for f in "$@"; do
    [[ -e "$f" ]] || continue
    abs="$(_abs_path "$f")" || continue
    chmod "$mode" -- "$abs" 2>/dev/null || true
    ensure_user_ownership "$abs"
  done
}

repair_user_tree() {
  mkuserdir 0755 "$HOME/.config" "$HOME/.local" "$HOME/.local/share" "$HOME/.local/bin"
  mkuserdir 0750 "$VIM_DIR" "$VIM_DIR/autoload" "$VIM_DIR/bundle"
  mkuserdir 0755 "$(dirname "$YAMLLINT_CONF")" "$USER_BASH_COMPLETION_DIR"
  mkuserdir 0755 "$HOME/.tmux" "$HOME/.tmux/plugins"
  setperms 0644 "$HOME/.bashrc" "$HOME/.vimrc" "$TMUX_CONF"
  setperms 0640 "$YAMLLINT_CONF"
  ensure_local_bin_path
}

backup_file(){ local f="$1"; if [[ -f "$f" || -L "$f" ]]; then local ts; ts="$(date +%Y%m%d_%H%M%S)"
  exec_run cp -a "$f" "${f}.bak.${ts}"; info "Backed up $f -> ${f}.bak.${ts}"; fi; }

# Greedy token upsert + newline hygiene
upsert_greedy(){ # $1=file $2=start_token $3=end_token $4=start_line $5=end_line $6=body
  local file="$1" s="$2" e="$3" sl="$4" el="$5" body="$6"
  [[ -f "$file" ]] || : >"$file"; backup_file "$file"
  local tmp; tmp="$(mktempf)"
  awk -v s="$s" -v e="$e" '{a[NR]=$0} {if(index($0,s)&&!f)f=NR; if(index($0,e))l=NR}
       END{for(i=1;i<=NR;i++){if(f&&l&&i>=f&&i<=l)continue; else if(f&&!l&&i>=f)continue; print a[i]}}' "$file" >"$tmp"
  local s1; s1="$(printf '%s' "$sl" | sed 's/[\/&.^$*[]/\\&/g')"; local e1; e1="$(printf '%s' "$el" | sed 's/[\/&.^$*[]/\\&/g')"
  sed -e "/^${s1}\$/d" -e "/^${e1}\$/d" "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"
  { [[ -s "$tmp" ]] && cat "$tmp" && printf '\n' || cat "$tmp"; printf '%s\n%s\n%s\n\n' "$sl" "$body" "$el"; } >"$file"
  local t2; t2="$(mktempf)"; awk 'BEGIN{n=0} {if(!n&&$0~/^[[:space:]]*$/)next; n=1; print}' "$file" >"$t2" && mv "$t2" "$file"
  ensure_user_ownership "$file"
  ok "Updated $file (${s}…${e})"
}

detect_os(){
  . /etc/os-release 2>/dev/null || { err "Missing /etc/os-release"; exit 1; }
  local like="${ID_LIKE:-}"
  if   [[ "$ID" =~ (rhel|rocky|almalinux|centos|fedora) ]] || [[ "$like" =~ (rhel|fedora) ]]; then OS_FAMILY="redhat"
  elif [[ "$ID" =~ (debian|ubuntu|raspbian|linuxmint) ]] || [[ "$like" =~ (debian|ubuntu) ]]; then OS_FAMILY="debian"
  else OS_FAMILY="debian"; warn "Unknown distro; assuming Debian-like."; fi
  info "OS family: $OS_FAMILY (ID=${ID})"
}

ensure_local_bin_path(){
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
    export PATH="$HOME/.local/bin:$PATH"
    [[ -f "$HOME/.bashrc" ]] || : >"$HOME/.bashrc"
    grep -qE '(^|:)\$HOME/\.local/bin(:|$)|(^|:)~/.local/bin(:|$)' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.bashrc"
    info "Ensured ~/.local/bin on PATH"
  esac
}

run_if(){ local var="$1"; shift; [[ "${!var:-0}" -eq 1 ]] && { for f in "$@"; do "$f"; done; } || info "Skipping ${*%% *} (disabled)"; }

# ==============================================================================
# Packages & fallbacks
install_packages_common(){
  mkuserdir 0755 "$HOME/.config/yamllint" "$HOME/.local/share" "$USER_BASH_COMPLETION_DIR"
  mkuserdir 0750 "$VIM_DIR" "$VIM_DIR/autoload" "$VIM_DIR/bundle" "$BLE_BUILD_DIR"
}

install_packages(){
  install_packages_common
  if [[ "$OS_FAMILY" == "redhat" ]]; then
    if command -v dnf >/dev/null; then exec_run SUDO dnf -y -q install "${PACKAGES_RHEL_BASE[@]}" || warn "Some pkgs not in base repos."
    else exec_run SUDO yum -y -q install "${PACKAGES_RHEL_BASE[@]}" || warn "Some pkgs not in base repos."; fi
  else
    if (( CLEAN_OUTPUT )); then exec_run SUDO apt-get -qq update; exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install "${PACKAGES_DEBIAN_BASE[@]}"
    else exec_run SUDO apt-get update -y -o Dpkg::Progress-Fancy=1; exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Progress-Fancy=1 "${PACKAGES_DEBIAN_BASE[@]}"; fi
  fi
  ok "Packages installed."
}

ensure_fzf_user(){
  command -v fzf >/dev/null && return 0
  [[ -d "$HOME/.fzf" ]] && return 0
  command -v git >/dev/null || { warn "git missing; cannot install fzf user-scope"; return 0; }
  info "Installing fzf to ~/.fzf (user)"
  exec_run git clone -q --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  exec_run "$HOME/.fzf/install" --key-bindings --completion --no-update-rc
  ensure_user_ownership "$HOME/.fzf"
}

ensure_pip(){
  python3 -m pip --version >/dev/null 2>&1 && return 0
  python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
  if ! python3 -m pip --version >/dev/null 2>&1; then
    if [[ "$OS_FAMILY" == "redhat" ]]; then
      if command -v dnf >/dev/null; then exec_run SUDO dnf -y -q install python3-pip || true
      else exec_run SUDO yum -y -q install python3-pip || true; fi
    else exec_run SUDO apt-get -qq -y install python3-pip; fi
  fi
  python3 -m pip --version >/dev/null 2>&1 || { err "pip not available"; return 1; }
}

ensure_yamllint_user(){
  command -v yamllint >/dev/null && { ok "yamllint present"; return 0; }
  ensure_pip || { warn "pip unavailable; skip yamllint user install"; return 1; }
  exec_run python3 -m pip install --user --upgrade yamllint || warn "yamllint pip install failed"
  ensure_local_bin_path
  command -v yamllint >/dev/null && ok "yamllint installed (user)"
}

# Fonts (Nerd Font fallback)
font_installed(){
  local family="${1:-FiraCode Nerd Font}"
  command -v fc-list >/dev/null 2>&1 && fc-list : family | grep -iFq "$family" && return 0
  find "$HOME/.local/share/fonts" -type f -iname "*FiraCode*.ttf" 2>/dev/null | grep -q . && return 0
  return 1
}
install_nerd_fonts_user(){
  local family="${1:-FiraCode Nerd Font}" zip="${2:-FiraCode.zip}"
  font_installed "$family" && { info "Nerd Font present"; return 0; }
  info "Installing Nerd Font (user): $family"
  local dest="$HOME/.local/share/fonts"; mkuserdir 0755 "$dest"
  local d; d="$(mktemp -d)"
  ( set -e; cd "$d"; curl -fL --retry 3 -O "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${zip}"
    unzip -oq "$zip"; find . -type f -iname "*.ttf" -exec mv -f {} "$dest"/ \; )
  rm -rf "$d"; command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$dest" >/dev/null 2>&1 || true
  font_installed "$family" && ok "Installed Nerd Font: $family" || warn "Font not visible yet"
  ensure_user_ownership "$dest"
}
ensure_powerline_glyphs(){
  command -v fc-list >/dev/null 2>&1 && fc-list : family | grep -qiE 'Nerd Font|Powerline' && return 0
  install_nerd_fonts_user "FiraCode Nerd Font" "FiraCode.zip"
}

# ==============================================================================
# Vim
ensure_pathogen(){
  local dest="$VIM_DIR/autoload/pathogen.vim"
  [[ -f "$dest" ]] && { info "Pathogen present"; return 0; }
  command -v curl >/dev/null || { err "curl required"; exit 1; }
  mkuserdir 0750 "$VIM_DIR/autoload"
  exec_run curl -fsSL -o "$dest" https://tpo.pe/pathogen.vim
  setperms 0644 "$dest"
  ok "Pathogen installed"
}
deploy_plugins(){
  command -v git >/dev/null || { err "git required"; exit 1; }
  local line name url dest
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *"="* ]] && continue
    name="${line%%=*}"; url="${line#*=}"; dest="$VIM_DIR/bundle/$name"
    if [[ -d "$dest/.git" ]]; then exec_run git -C "$dest" pull -q --ff-only || true
    else mkuserdir 0750 "$(dirname "$dest")"; exec_run git clone -q --depth 1 "$url" "$dest"; fi
    ensure_user_ownership "$dest"
  done <<< "$VIM_PLUGIN_LIST"
  ok "Vim plugins ready"
}
vimrc_body_block(){ cat <<'EOF'
" Managed by install_vimrc_etc.sh
execute pathogen#infect()
syntax on
filetype plugin indent on
set number
set norelativenumber
set tabstop=2 shiftwidth=2 expandtab
set cursorline
set termguicolors
set background=dark
silent! colorscheme shades_of_purple
let mapleader=","
let g:airline#extensions#tabline#enabled = 1
let g:airline_powerline_fonts = 1
nnoremap <leader>n :NERDTreeToggle<CR>
set rtp+=~/.fzf
nnoremap <C-p> :Files<CR>
let g:ale_sign_column_always = 1
let g:indentLine_char = '│'
EOF
}
install_vimrc_block(){
  upsert_greedy "$HOME/.vimrc" "DEV_BOOTSTRAP_VIM_START" "DEV_BOOTSTRAP_VIM_END" \
    '" >>> DEV_BOOTSTRAP_VIM_START >>>' '" <<< DEV_BOOTSTRAP_VIM_END <<<' "$(vimrc_body_block)"
}

# ==============================================================================
# yamllint
install_yamllint_conf(){
  [[ -f "$YAMLLINT_CONF" ]] && { info "yamllint config exists"; return 0; }
  mkuserdir 0755 "$(dirname "$YAMLLINT_CONF")"
  cat >"$YAMLLINT_CONF" <<'EOF'
extends: default
rules: {line-length: {max: 120, allow-non-breakable-words: true}, truthy: {allowed-values: ['true','false','on','off','yes','no']}, indentation: {spaces: 2}, document-start: disable}
EOF
  chmod 0640 "$YAMLLINT_CONF" || true
  ensure_user_ownership "$YAMLLINT_CONF"
  ok "Yamllint config at $YAMLLINT_CONF"
}

# ==============================================================================
# Bashrc blocks
eternal_history_block(){ cat <<'EOF'
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE=~/.bash_eternal_history
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
HISTCONTROL=erasedups
if declare -F __git_ps1 >/dev/null 2>&1; then
  export PS1='╭─╼[\[\e[1;36m\]\w\[\e[0m\]] \[\e[1;34m\]$(__git_ps1 "[%s]")\[\e[0m\]\n╰─ \u@\h >> '
else
  parse_git_branch(){ git branch --no-color 2>/dev/null | sed -n "s/^\* //p"; }
  export PS1='╭─╼[\[\e[1;36m\]\w\[\e[0m\]] \[\e[1;34m\]$(parse_git_branch)\[\e[0m\]\n╰─ \u@\h >> '
fi
PROMPT_DIRTRIM=2
EOF
}
ble_bashrc_block(){ cat <<'EOF'
# ble.sh (interactive only)
if [[ $- == *i* ]] && [[ -r "$HOME/.local/share/blesh/ble.sh" ]]; then
  source "$HOME/.local/share/blesh/ble.sh" --noattach
  ble-attach >/dev/null 2>&1
  if [[ -z "${BLESH_TUNED:-}" ]]; then
    bleopt accept-line:char=^M >/dev/null 2>&1 || true
    bleopt edit_abell=1 >/dev/null 2>&1 || true
    bleopt complete_menu_style=desc >/dev/null 2>&1 || true
    bleopt highlight_syntax=always >/dev/null 2>&1 || true
    ble-face -s autosuggest=fg=242 >/dev/null 2>&1 || true
    BLESH_TUNED=1
  fi
fi
# bash-completion (system)
[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
# fzf bindings (system or user)
for p in /usr/share/fzf/completion.bash /usr/share/fzf/shell/completion.bash "$HOME/.fzf/shell/completion.bash"; do [[ -r "$p" ]] && source "$p"; done
for p in /usr/share/fzf/key-bindings.bash /usr/share/fzf/shell/key-bindings.bash "$HOME/.fzf/shell/key-bindings.bash"; do [[ -r "$p" ]] && source "$p"; done
# user argcomplete loaders
if [[ $- == *i* ]] && [[ -d "$HOME/.bash_completion.d" ]]; then
  for f in "$HOME"/.bash_completion.d/*; do [[ -r "$f" ]] && . "$f"; done
fi
command -v carapace >/dev/null && eval "$(carapace _carapace)"
EOF
}
# pbcopy/pbpaste shims + PATH export
pbcopy_pbpaste_bashrc_block(){ cat <<'EOF'
# pbcopy/pbpaste (Linux shim)
export PATH="$HOME/.local/bin:$PATH"
if command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1 || command -v wl-copy >/dev/null 2>&1; then
  :
fi
EOF
}

install_bashrc_block(){
  upsert_greedy "$HOME/.bashrc" "ETERNAL_HISTORY_AND_GIT_PROMPT_START" "ETERNAL_HISTORY_AND_GIT_PROMPT_END" \
    "# >>> ETERNAL_HISTORY_AND_GIT_PROMPT_START >>>" "# <<< ETERNAL_HISTORY_AND_GIT_PROMPT_END <<<" "$(eternal_history_block)"
}
install_ble_bashrc_block(){
  upsert_greedy "$HOME/.bashrc" "BLE_SH_START" "BLE_SH_END" \
    "# >>> BLE_SH_START >>>" "# <<< BLE_SH_END <<<" "$(ble_bashrc_block)"
}
install_pb_bashrc_block(){
  upsert_greedy "$HOME/.bashrc" "PBCLIP_PATH_START" "PBCLIP_PATH_END" \
    "# >>> PBCLIP_PATH_START >>>" "# <<< PBCLIP_PATH_END <<<" "$(pbcopy_pbpaste_bashrc_block)"
}

# ==============================================================================
# pbcopy/pbpaste installers (Linux shims)
install_pbcopy_pbpaste() {
  mkuserdir 0755 "$HOME/.local/bin"
  cat > "$HOME/.local/bin/pbcopy" <<'PB'
#!/usr/bin/env bash
set -euo pipefail
if command -v wl-copy >/dev/null 2>&1; then exec wl-copy; fi
if command -v xclip   >/dev/null 2>&1; then exec xclip -selection clipboard; fi
if command -v xsel    >/dev/null 2>&1; then exec xsel --clipboard --input; fi
cat >/dev/null
PB
  cat > "$HOME/.local/bin/pbpaste" <<'PB'
#!/usr/bin/env bash
set -euo pipefail
if command -v wl-paste >/dev/null 2>&1; then exec wl-paste; fi
if command -v xclip    >/dev/null 2>&1; then exec xclip -selection clipboard -o; fi
if command -v xsel     >/dev/null 2>&1; then exec xsel --clipboard --output; fi
exit 0
PB
  chmod 0755 "$HOME/.local/bin/pbcopy" "$HOME/.local/bin/pbpaste"
  ensure_user_ownership "$HOME/.local/bin/pbcopy" "$HOME/.local/bin/pbpaste"
  ensure_local_bin_path
  ok "pbcopy/pbpaste installed to ~/.local/bin"
}

# ==============================================================================
# ble.sh
install_ble(){
  command -v git >/dev/null || { err "git required"; exit 1; }
  (command -v gawk >/dev/null || command -v awk >/dev/null) || { err "gawk/awk required"; exit 1; }
  command -v make >/dev/null || { err "make required"; exit 1; }
  if [[ -d "$BLE_BUILD_DIR/.git" ]]; then info "Updating ble.sh"; exec_run git -C "$BLE_BUILD_DIR" pull -q --ff-only || true
  else mkuserdir 0750 "$(dirname "$BLE_BUILD_DIR")"; info "Cloning ble.sh"; exec_run git clone -q --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git "$BLE_BUILD_DIR"; fi
  exec_run make -s -C "$BLE_BUILD_DIR" install PREFIX="$HOME/.local"
  [[ -r "$HOME/.local/share/blesh/ble.sh" ]] || { err "ble.sh install failed"; exit 1; }
  ensure_user_ownership "$HOME/.local/share/blesh"
  ok "ble.sh installed"
}

# ==============================================================================
# Python linters
install_python_linters(){
  ensure_pip || return 1; ensure_local_bin_path
  local ruff_spec="${RUFF_VERSION:+ruff==$RUFF_VERSION}"; [[ -z "$ruff_spec" ]] && ruff_spec="ruff"
  local pyl_spec="${PYLINT_VERSION:+pylint==$PYLINT_VERSION}"; [[ -z "$pyl_spec" ]] && pyl_spec="pylint"
  info "Installing Python linters (user): $ruff_spec $pyl_spec"
  exec_run python3 -m pip install --user --upgrade "$ruff_spec" "$pyl_spec"
  hash -r || true
  command -v ruff >/dev/null 2>&1 && ok "ruff installed ($(ruff --version 2>/dev/null | awk '{print $2}'))" || warn "ruff missing"
  command -v pylint >/dev/null 2>&1 && ok "pylint installed ($(pylint --version 2>/dev/null | awk 'NR==1{print $2}'))" || warn "pylint missing"
}

# ==============================================================================
# Bash linters
install_bash_linters(){
  info "Installing Bash linters (shellcheck, shfmt)"
  if [[ "$OS_FAMILY" == "redhat" ]]; then
    if command -v dnf >/dev/null; then exec_run SUDO dnf -y -q install shellcheck || warn "shellcheck unavailable"; exec_run SUDO dnf -y -q install shfmt || warn "shfmt unavailable"
    else exec_run SUDO yum -y -q install shellcheck || warn "shellcheck unavailable"; exec_run SUDO yum -y -q install shfmt || warn "shfmt unavailable"; fi
  else
    exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install shellcheck || warn "shellcheck unavailable"
    exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install shfmt || warn "shfmt unavailable"
  fi
  command -v shellcheck >/dev/null && ok "shellcheck installed" || warn "shellcheck missing"
  command -v shfmt >/dev/null && ok "shfmt installed" || warn "shfmt missing"
}

# ==============================================================================
# kubectl + oc
K_ARCH="amd64"
detect_arch(){
  case "$(uname -m)" in
    x86_64|amd64) K_ARCH="amd64" ;;
    aarch64|arm64) K_ARCH="arm64" ;;
    armv7l) K_ARCH="arm" ;;
    ppc64le) K_ARCH="ppc64le" ;;
    s390x) K_ARCH="s390x" ;;
    *) K_ARCH="amd64"; warn "Unknown arch; defaulting to amd64" ;;
  esac
}
fetch(){ curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 -H 'User-Agent: dev-bootstrap/1.0' -o "$2" "$1"; }
install_oc_kubectl(){
  detect_arch
  local sysbindir="/usr/local/bin"
  local userbindir="$HOME/.local/bin"
  local bindir="$sysbindir"
  if ! SUDO test -w "$sysbindir" >/dev/null 2>&1; then bindir="$userbindir"; mkuserdir 0755 "$bindir"; warn "Add $bindir to PATH if needed"; fi
  local kubectl_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K_ARCH}/kubectl"
  local oc_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_CHANNEL}/openshift-client-linux.tar.gz"

  if ! command -v kubectl >/dev/null; then
    fetch "$kubectl_url" /tmp/kubectl; chmod +x /tmp/kubectl; SUDO mv /tmp/kubectl "$bindir/kubectl"; ok "kubectl -> $bindir/kubectl"
    if curl -fsSL "https://dl.k8s.io/${KUBECTL_VERSION}/bin/linux/${K_ARCH}/kubectl.sha256" -o /tmp/kubectl.sha256; then
      (cd /tmp && sha256sum -c --status kubectl.sha256 2>/dev/null) || warn "kubectl checksum mismatch."
    fi
  else ok "kubectl already present"; fi

  if ! command -v oc >/dev/null; then
    fetch "$oc_url" /tmp/oc.tar.gz; tar -xzf /tmp/oc.tar.gz -C /tmp oc 2>/dev/null || true
    [[ -f /tmp/oc ]] && { chmod +x /tmp/oc; SUDO mv /tmp/oc "$bindir/oc"; ok "oc -> $bindir/oc"; } || warn "oc not found in archive"
  else ok "oc already present"; fi

  mkuserdir 0755 "$USER_BASH_COMPLETION_DIR"
  command -v kubectl >/dev/null && kubectl completion bash >"$USER_BASH_COMPLETION_DIR/kubectl" || true
  command -v oc >/dev/null && oc completion bash >"$USER_BASH_COMPLETION_DIR/oc" || true
  ensure_user_ownership "$USER_BASH_COMPLETION_DIR"
  ok "kubectl/oc completions saved"
}

# ==============================================================================
# Ghostty + Dracula
enable_copr_ghostty(){
  command -v dnf >/dev/null || return 1
  exec_run SUDO dnf -y -q install dnf-plugins-core || true
  exec_run SUDO dnf -y copr enable "$GHOSTTY_COPR_SHORTHAND" || exec_run SUDO dnf -y copr enable "copr:copr.fedorainfracloud.org:${GHOSTTY_COPR_SHORTHAND/:/:}"
}
install_ghostty_repo_redhat(){
  info "Enabling Ghostty COPR: $GHOSTTY_COPR_SHORTHAND"
  enable_copr_ghostty && exec_run SUDO dnf -y --setopt=tsflags=nodocs install ghostty || err "Failed to enable/install Ghostty"
  command -v ghostty >/dev/null && ok "ghostty installed" || err "ghostty install failed"
}
install_ghostty_debian(){
  if [[ -n "$GHOSTTY_DEB_URL" ]]; then
    info "Installing ghostty from .deb"; fetch "$GHOSTTY_DEB_URL" /tmp/ghostty.deb
    exec_run SUDO apt-get -qq -y install /tmp/ghostty.deb || exec_run SUDO dpkg -i /tmp/ghostty.deb
    command -v ghostty >/dev/null && ok "ghostty installed (.deb)" || err "ghostty .deb install failed"
  elif [[ "${USE_UNOFFICIAL_GHOSTTY_UBUNTU:-0}" -eq 1 ]]; then
    warn "Using community installer for ghostty (Ubuntu/Debian)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)" || warn "ghostty unofficial install failed"
    command -v ghostty >/devNull && ok "ghostty installed (community)" || err "ghostty community install failed"
  else
    warn "No official ghostty path for Debian/Ubuntu in this script."
  fi
}
ensure_ghostty_dracula_theme(){
  # split locals to avoid set -u “unbound” during same-line expansions
  local cfgdir;      cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
  local themes_dir;  themes_dir="$cfgdir/themes"
  local stamp;       stamp="$themes_dir/.dracula_not_found"

  mkuserdir 0755 "$themes_dir"
  # Already installed? Accept either a 'dracula' file or a directory.
  if [[ -f "$themes_dir/dracula" ]] || [[ -d "$themes_dir/dracula" ]]; then
    :
  else
    # Recent failure? skip for 7 days unless forced
    if [[ -f "$stamp" && "${GHOSTTY_DRACULA_FORCE:-0}" -ne 1 ]] && find "$stamp" -mtime -7 | grep -q .; then
      info "Ghostty Dracula previously not found; skipping (force with GHOSTTY_DRACULA_FORCE=1)."
    else
      rm -f "$stamp" || true
      info "Installing Ghostty Dracula theme"
      local zip="/tmp/ghostty-dracula.zip"
      local tmp; tmp="$(mktemp -d)"
      if curl -fL --retry 3 --retry-delay 2 -o "$zip" "$GHOSTTY_DRACULA_ZIP"; then
        unzip -oq "$zip" -d "$tmp"
        local src_dir="" src_file="" copied=0
        src_dir="$(find "$tmp" -type d -iname dracula | head -n1 || true)"
        if [[ -n "$src_dir" ]]; then
          # Nested "themes/dracula.conf"? Flatten to a single file called "dracula"
          if [[ -f "$src_dir/themes/dracula.conf" ]]; then
            cp -f "$src_dir/themes/dracula.conf" "$themes_dir/dracula"
            copied=1
          else
            # If it’s a directory of theme assets, copy the folder as "dracula"
            rm -rf "$themes_dir/dracula"
            cp -a "$src_dir" "$themes_dir/dracula"
            copied=1
          fi
        else
          src_file="$(find "$tmp" -type f \( -iname 'dracula*.conf' -o -iname 'dracula*.toml' -o -iname 'dracula' \) | head -n1 || true)"
          if [[ -n "$src_file" ]]; then
            cp -f "$src_file" "$themes_dir/dracula"
            copied=1
          fi
        fi
        rm -rf "$zip" "$tmp"
        if [[ $copied -eq 1 ]]; then
          ok "Dracula theme installed to $themes_dir"
          ensure_user_ownership "$themes_dir"
        else
          warn "Dracula not found in archive; caching failure."; : >"$stamp"
        fi
      else
        warn "Failed to download Dracula archive"
      fi
    fi
  fi
  # Ensure config points at theme
  local cfg="$cfgdir/config"; mkuserdir 0755 "$cfgdir"; : > /dev/null
  touch "$cfg"
  if grep -qE '^\s*theme\s*=\s*dracula\s*$' "$cfg"; then
    info "Ghostty config already selects Dracula theme"
  else
    echo "theme = dracula" >>"$cfg"
    ok "Added 'theme = dracula' to $cfg"
  fi
  ensure_user_ownership "$cfg"
}

install_ghostty(){
  if [[ "$OS_FAMILY" == "redhat" ]]; then install_ghostty_repo_redhat; else install_ghostty_debian; fi
  if [[ "${ENABLE_GHOSTTY_DRACULA:-1}" -eq 1 ]] && command -v ghostty >/dev/null; then ensure_ghostty_dracula_theme; fi
}

# ==============================================================================
# tmux + TPM + Dracula + Menus/Tabs
ensure_tpm(){
  if [[ -d "$TMUX_TPM_DIR/.git" ]]; then exec_run git -C "$TMUX_TPM_DIR" pull -q --ff-only || true
  else command -v git >/dev/null || { warn "git missing; cannot install TPM"; return 1; }
       mkuserdir 0755 "$TMUX_TPM_DIR"
       exec_run git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$TMUX_TPM_DIR"; fi
  ensure_user_ownership "$TMUX_TPM_DIR"
  ok "TPM ready"
}
tmux_conf_body_block(){ cat <<'EOF'
# Managed by install_vimrc_etc.sh — safe to edit/move or remove the whole block.
#
# TMUX QUICK INSTRUCTIONS (tabs + menus)
# - New tab (window): Prefix + c
# - Rename tab:       Prefix + ,
# - Next/Prev tab:    Alt+Right / Alt+Left  (also: C-NPage / C-PPage)
# - Session/window tree: Prefix + w
# - Mega-menu:        Prefix + m
# - Mouse menus:      Right-click on status bar (tab) or inside a pane
# - Reload config:    Prefix + m → R
# - Toggle sync:      Prefix + m → s
##### Basics
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:RGB,tmux-256color:RGB"
set -g mouse on
set -g history-limit 100000
set -g status-interval 5
set -g renumber-windows on

# Vi copy-mode + quick copy
setw -g mode-keys vi
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel

##### “Tabs” (windows) look & feel
set -g status on
set -g status-position top
set -g status-style fg=default,bg=default
set -g window-status-style fg=colour245,bg=default
set -g window-status-format " #I:#W "
set -g window-status-current-style fg=colour231,bg=colour61,bold
set -g window-status-current-format " #I:#W "
set -g window-status-separator ""

# Navigate tabs (windows)
bind -n M-Left  previous-window
bind -n M-Right next-window
bind C-PPage    previous-window
bind C-NPage    next-window

# New/rename/move tabs
bind c new-window
bind , command-prompt -I "#W" "rename-window '%%'"
bind < swap-window -t -1 \; select-window -t -1
bind > swap-window -t +1 \; select-window -t +1

##### Quick session/window “tree” chooser
bind w choose-tree -Zw

##### Mega-menu (Prefix + m)
bind m display-menu -T "#[align=centre]TMUX MENU" \
  "New tab (window)"      c  new-window \
  "Split ─ horizontally"  "-" split-window -v \
  "Split │ vertically"    "|" split-window -h \
  "" \
  "Next tab →"            n  next-window \
  "Prev tab ←"            p  previous-window \
  "Rename tab…"           r  command-prompt -I "#W" "rename-window '%%'" \
  "" \
  "Toggle sync panes"     s  "run-shell 'tmux set -g synchronize-panes; tmux display-message \"sync-panes: #{?synchronize-panes,on,off}\"'" \
  "Choose session/tree"   w  "choose-tree -Zw" \
  "" \
  "Reload ~/.tmux.conf"   R  "source-file ~/.tmux.conf \; display-message \"reloaded tmux.conf\"" \
  "Kill pane"             x  kill-pane \
  "Kill tab (window)"     X  kill-window

##### Mouse right-click menus
# Status bar (on a tab)
bind -n MouseDown3Status display-menu -T "#[align=centre]Tab: #I #W" -x W -y S \
  "New tab"         c  new-window \
  "Rename tab…"     r  command-prompt -I "#W" "rename-window '%%'" \
  "Move tab left"   <  "swap-window -t -1 \; select-window -t -1" \
  "Move tab right"  >  "swap-window -t +1 \; select-window -t +1" \
  "" \
  "Close tab"       X  kill-window

# In a pane
bind -n MouseDown3Pane display-menu -T "#[align=centre]Pane • #{pane_index}" \
  "Split ─ horizontally"    "-" split-window -v \
  "Split │ vertically"      "|" split-window -h \
  "Toggle sync panes"       s  "run-shell 'tmux set -g synchronize-panes; tmux display-message \"sync-panes: #{?synchronize-panes,on,off}\"'" \
  "" \
  "Zoom pane"               z  resize-pane -Z \
  "Kill pane"               x  kill-pane

##### Plugins (TPM + Dracula theme)
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'dracula/tmux'
set -g @dracula-show-network false
set -g @dracula-plugins "battery,cpu,ram,git"
set -g @dracula-refresh-rate 5
set -g @dracula-fixed_location_status false
set -g @dracula-show-powerline true

# Initialize TPM (keep at end of plugin list)
run '~/.tmux/plugins/tpm/tpm'
EOF
}
install_tmux_conf_block(){
  upsert_greedy "$TMUX_CONF" "DEV_BOOTSTRAP_TMUX_START" "DEV_BOOTSTRAP_TMUX_END" \
    "# >>> DEV_BOOTSTRAP_TMUX_START >>>" "# <<< DEV_BOOTSTRAP_TMUX_END <<<" "$(tmux_conf_body_block)"
}
install_tmux_plugins_quiet(){
  [[ -x "$TMUX_TPM_DIR/bin/install_plugins" ]] || { warn "TPM installer missing"; return 0; }
  (( CLEAN_OUTPUT )) && "$TMUX_TPM_DIR/bin/install_plugins" >/dev/null 2>&1 || "$TMUX_TPM_DIR/bin/install_plugins" || true
  ok "tmux plugins installed/updated"
}
install_tmux(){
  command -v tmux >/dev/null || warn "tmux binary not found after package step"
  ensure_tpm; install_tmux_conf_block
  [[ "${ENABLE_TMUX_DRACULA:-1}" -eq 1 ]] && install_tmux_plugins_quiet
  ok "tmux configured. Start with: tmux"
}

# ==============================================================================
# Repo tooling
write_repo_tooling(){
  local script_path="${BASH_SOURCE[0]:-$(pwd)/install_vimrc_etc.sh}" script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  cat > "${script_dir}/Makefile" <<'MK'
SHELL := /usr/bin/env bash
SHELLCHECK ?= shellcheck
SH_SOURCES := install_vimrc_etc.sh
.PHONY: check-sh lint-sh fmt-sh
check-sh: ; @bash -n $(SH_SOURCES)
lint-sh:  ; @$(SHELLCHECK) -x -S style -s bash $(SH_SOURCES)
fmt-sh:   ; @command -v shfmt >/dev/null 2>&1 && shfmt -w -i 2 -ci -bn $(SH_SOURCES) || { echo "shfmt not installed; skipping."; }
MK
  echo "external-sources=true" > "${script_dir}/.shellcheckrc"
  ensure_user_ownership "${script_dir}/Makefile" "${script_dir}/.shellcheckrc"
  ok "Repo tooling written"
}

safe_source_bashrc(){ [[ -r "$HOME/.bashrc" ]] && { set +u; . "$HOME/.bashrc" || true; set -u; } || warn "~/.bashrc missing"; }

# ------------------------------------------------------------------------------
# argcomplete (kept last)
install_argcomplete(){
  ensure_pip || { warn "pip unavailable; cannot install argcomplete"; return 1; }
  export PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_ROOT_USER_ACTION=ignore
  info "Installing argcomplete (user)"
  exec_run python3 -m pip install --user --upgrade --upgrade-strategy only-if-needed argcomplete
  mkuserdir 0755 "$USER_BASH_COMPLETION_DIR"
  if command -v activate-global-python-argcomplete >/dev/null; then
    exec_run activate-global-python-argcomplete --dest "$USER_BASH_COMPLETION_DIR"
  else
    python3 - <<'PY' 2>/dev/null || true
import importlib, sys
sys.exit(0 if importlib.util.find_spec("argcomplete") else 1)
PY
    cat > "$USER_BASH_COMPLETION_DIR/python-argcomplete.sh" <<'EOS'
if command -v register-python-argcomplete >/dev/null 2>&1; then
  for cmd in pip pip3 python3 git kubectl oc terraform ansible ansible-playbook; do
    command -v "$cmd" >/dev/null 2>&1 && eval "$(register-python-argcomplete "$cmd")"
  done
fi
EOS
  fi
  ensure_user_ownership "$USER_BASH_COMPLETION_DIR"
  ok "argcomplete set up"
}

# ==============================================================================
# Main
main(){
  info "Dev Bootstrap starting"
  detect_os
  repair_user_tree

  run_if ENABLE_PACKAGES install_packages

  # Fallbacks
  ensure_powerline_glyphs
  [[ "$ENABLE_YAMLLINT" -eq 1 ]] && ! command -v yamllint >/dev/null 2>&1 && ensure_yamllint_user
  ensure_fzf_user

  # Editors & configs
  run_if ENABLE_VIM_PLUGINS ensure_pathogen deploy_plugins
  run_if ENABLE_VIMRC install_vimrc_block
  run_if ENABLE_YAMLLINT install_yamllint_conf

  # Shell enhancements
  run_if ENABLE_BASHRC install_bashrc_block
  if [[ "$ENABLE_BLE" -eq 1 ]]; then install_ble; install_ble_bashrc_block; fi
  [[ "$ENABLE_ARGCOMPLETE" -eq 1 ]] && install_argcomplete || info "Skipping argcomplete (disabled)"

  # pbcopy/pbpaste
  if [[ "$ENABLE_PBCOPY_PBPASTE" -eq 1 ]]; then install_pbcopy_pbpaste; install_pb_bashrc_block; fi

  # Linters & CLIs
  run_if ENABLE_BASH_LINTERS install_bash_linters
  run_if ENABLE_PY_LINTERS install_python_linters
  run_if ENABLE_KUBECTL_OC install_oc_kubectl

  # Terminals
  run_if ENABLE_GHOSTTY install_ghostty
  run_if ENABLE_TMUX install_tmux

  run_if ENABLE_REPO_TOOLING write_repo_tooling

  repair_user_tree

  ok "All done. Sourcing ~/.bashrc now (safe)."
  safe_source_bashrc
  ok "Done. For a fresh session, run: exec bash -l"
}
main
