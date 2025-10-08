#!/usr/bin/env bash
set -euo pipefail

# Dev Bootstrap (append-only; user-scope by default; minimal sudo use)
# - Vim + Pathogen + plugins
# - Bashrc blocks (history/prompt, ble.sh), fzf user fallback, argcomplete
# - Linters: yamllint (pip fallback), shellcheck, shfmt, ruff, pylint
# - kubectl + oc (+ completions)
# - Ghostty (optional, OFF by default) + Dracula theme (cached, flattened)
# - tmux + TPM + Dracula + menus/tabs (OFF by default)
# - Clipboard helpers: pbcopy/pbpaste into ~/.local/bin
# - Idempotent upserts + compaction (no duplicate PATH lines, no blank spam)

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
ENABLE_GHOSTTY=0
ENABLE_GHOSTTY_DRACULA=0
ENABLE_TMUX=0
ENABLE_TMUX_DRACULA=0
ENABLE_PBTOOLS=1

CLEAN_OUTPUT=1
LOG_FILE=""

VIM_DIR="$HOME/.vim"
YAMLLINT_CONF="$HOME/.config/yamllint/config"
BLE_BUILD_DIR="$HOME/.local/src/ble.sh"
USER_BASH_COMPLETION_DIR="$HOME/.bash_completion.d"
TMUX_TPM_DIR="$HOME/.tmux/plugins/tpm"
TMUX_CONF="$HOME/.tmux.conf"

PACKAGES_RHEL_BASE=(vim-enhanced git powerline-fonts yamllint curl make gawk bash-completion python3 python3-pip unzip tmux)
PACKAGES_DEBIAN_BASE=(vim git fonts-powerline fzf yamllint curl make gawk bash-completion python3 python3-pip unzip tmux)

RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"

KUBECTL_VERSION="v1.31.1"
OC_CHANNEL="stable"

GHOSTTY_COPR_SHORTHAND="alternateved/ghostty"
GHOSTTY_DEB_URL=""
USE_UNOFFICIAL_GHOSTTY_UBUNTU=0
GHOSTTY_DRACULA_ZIP="https://github.com/dracula/ghostty/archive/refs/heads/main.zip"

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

# --------------------------- Logging & helpers --------------------------------
[[ -n "$LOG_FILE" ]] && mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
_logfile(){ [[ -n "$LOG_FILE" ]] && printf "%b" "$*" >>"$LOG_FILE" || :; }
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
cleanup(){
  for f in "${TMPFILES[@]:-}"; do [[ -n "$f" ]] && rm -f "$f" 2>/dev/null || true; done
  rm -f /tmp/{kubectl,kubectl.sha256,oc.tar.gz,oc,ghostty.deb,ghostty-dracula.zip} 2>/dev/null || true
}
trap cleanup EXIT

backup_file(){ local f="$1"; if [[ -f "$f" || -L "$f" ]]; then local ts; ts="$(date +%Y%m%d_%H%M%S)"; exec_run cp -a "$f" "${f}.bak.${ts}"; info "Backed up $f -> ${f}.bak.${ts}"; fi; }

# Remove leading blanks, collapse multiple blank lines, ensure trailing newline.
compact_file(){
  local f="$1"
  [[ -r "$f" ]] || return 0
  local t; t="$(mktemp)"
  awk '
    { sub(/\r$/,"") }
    !started && $0 ~ /^[[:space:]]*$/ { next }
    { started=1 }
    $0 ~ /^[[:space:]]*$/ { if(blank) next; blank=1; print ""; next }
    { blank=0; print }
    END{ print "" }
  ' "$f" >"$t" && mv "$t" "$f"
}

# Keep only the first exact occurrence of a given literal line, drop the rest
dedupe_literal_line(){
  local f="$1" line="$2"
  [[ -r "$f" ]] || return 0
  local t; t="$(mktemp)"
  awk -v LIT="$line" '{ if ($0 == LIT) { if (seen) next; seen=1 } print }' "$f" >"$t" && mv "$t" "$f"
}

# Strip duplicate managed blocks by greedy token; newline-safe reinsert
upsert_greedy(){ # $1=file $2=start_token $3=end_token $4=start_line $5=end_line $6=body
  local file="$1" s="$2" e="$3" sl="$4" el="$5" body="$6"
  [[ -f "$file" ]] || : >"$file"; backup_file "$file"
  local tmp; tmp="$(mktempf)"
  awk -v s="$s" -v e="$e" '
    {a[NR]=$0} {if(index($0,s)&&!f)f=NR; if(index($0,e))l=NR}
    END{for(i=1;i<=NR;i++){if(f&&l&&i>=f&&i<=l)continue; else if(f&&!l&&i>=f)continue; print a[i]}}
  ' "$file" >"$tmp"
  # drop any exact marker lines that may linger
  local t2; t2="$(mktempf)"
  awk -v SL="$sl" -v EL="$el" '{if($0==SL||$0==EL)next; print}' "$tmp" >"$t2" && mv "$t2" "$tmp"
  # append managed block
  { [[ -s "$tmp" ]] && cat "$tmp" && printf '\n' || cat "$tmp"; printf '%s\n%s\n%s\n' "$sl" "$body" "$el"; } >"$file"
  compact_file "$file"
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
    grep -qE '(^|:)\$HOME/\.local/bin(:|$)|(^|:)~/.local/bin(:|$)' "$HOME/.bashrc" 2>/dev/null \
      || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.bashrc"
    if [[ -f "$HOME/.profile" ]] && ! grep -qE 'export PATH="\$HOME/\.local/bin:\$PATH"' "$HOME/.profile" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
    fi
    compact_bashrc
    info "Ensured ~/.local/bin on PATH"
  esac
}

run_if(){ local var="$1"; shift; [[ "${!var:-0}" -eq 1 ]] && { for f in "$@"; do "$f"; done; } || info "Skipping ${*%% *} (disabled)"; }

# Compactors per dotfile
compact_bashrc(){ dedupe_literal_line "$HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'; compact_file "$HOME/.bashrc"; }
compact_vimrc(){ compact_file "$HOME/.vimrc"; }
compact_tmux(){ compact_file "$TMUX_CONF"; }

# Enforce user ownership for created dirs/files (absolute path chown only)
ensure_user_ownership(){
  local u; u="$(id -un)"
  local g; g="$(id -gn)"
  local targets=(
    "$HOME/.vim" "$HOME/.vimrc"
    "$HOME/.config" "$HOME/.config/yamllint" "$YAMLLINT_CONF"
    "$HOME/.local" "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.local/share/blesh"
    "$HOME/.bash_completion.d" "$HOME/.bashrc" "$HOME/.profile"
    "$HOME/.tmux" "$TMUX_TPM_DIR" "$TMUX_CONF"
    "$HOME/.config/ghostty" "$HOME/.config/ghostty/themes"
  )
  for p in "${targets[@]}"; do
    [[ -e "$p" || -L "$p" ]] || continue
    SUDO chown -h -- "$u:$g" "$p" || true
    if [[ -d "$p" ]]; then
      SUDO chown -R -- "$u:$g" "$p" || true
    fi
  done
}

# ----------------------------- Packages & fallbacks ---------------------------
install_packages_common(){
  mkdir -p "$HOME/.config/yamllint" "$VIM_DIR"/{autoload,bundle} "$HOME/.local/share" "$BLE_BUILD_DIR" "$USER_BASH_COMPLETION_DIR" || true
  chmod 0755 "$HOME/.config" "$HOME/.config/yamllint" "$HOME/.local/share" || true
  chmod 0750 "$VIM_DIR" "$VIM_DIR"/{autoload,bundle} || true
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
  local dest="$HOME/.local/share/fonts"; mkdir -p "$dest"
  local d; d="$(mktemp -d)"
  ( set -e; cd "$d"; curl -fL --retry 3 -O "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${zip}"
    unzip -oq "$zip"; find . -type f -iname "*.ttf" -exec mv -f {} "$dest"/ \; )
  rm -rf "$d"; command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$dest" >/dev/null 2>&1 || true
  font_installed "$family" && ok "Installed Nerd Font: $family" || warn "Font not visible yet"
}
ensure_powerline_glyphs(){
  command -v fc-list >/dev/null 2>&1 && fc-list : family | grep -qiE 'Nerd Font|Powerline' && return 0
  install_nerd_fonts_user "FiraCode Nerd Font" "FiraCode.zip"
}

# ----------------------------------- Vim --------------------------------------
ensure_pathogen(){
  local dest="$VIM_DIR/autoload/pathogen.vim"
  [[ -f "$dest" ]] && { info "Pathogen present"; return 0; }
  command -v curl >/dev/null || { err "curl required"; exit 1; }
  exec_run curl -fsSL -o "$dest" https://tpo.pe/pathogen.vim
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
    else exec_run git clone -q --depth 1 "$url" "$dest"; fi
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
  compact_vimrc
}

# --------------------------------- yamllint -----------------------------------
install_yamllint_conf(){
  [[ -f "$YAMLLINT_CONF" ]] && { info "yamllint config exists"; return 0; }
  mkdir -p "$(dirname "$YAMLLINT_CONF")"
  cat >"$YAMLLINT_CONF" <<'EOF'
extends: default
rules: {line-length: {max: 120, allow-non-breakable-words: true}, truthy: {allowed-values: ['true','false','on','off','yes','no']}, indentation: {spaces: 2}, document-start: disable}
EOF
  chmod 0640 "$YAMLLINT_CONF" || true
  ok "Yamllint config at $YAMLLINT_CONF"
}

# --------------------------------- Bashrc -------------------------------------
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
install_bashrc_block(){
  upsert_greedy "$HOME/.bashrc" "ETERNAL_HISTORY_AND_GIT_PROMPT_START" "ETERNAL_HISTORY_AND_GIT_PROMPT_END" \
    "# >>> ETERNAL_HISTORY_AND_GIT_PROMPT_START >>>" "# <<< ETERNAL_HISTORY_AND_GIT_PROMPT_END <<<" "$(eternal_history_block)"
  compact_bashrc
}
install_ble_bashrc_block(){
  upsert_greedy "$HOME/.bashrc" "BLE_SH_START" "BLE_SH_END" \
    "# >>> BLE_SH_START >>>" "# <<< BLE_SH_END <<<" "$(ble_bashrc_block)"
  compact_bashrc
}

# --------------------------------- ble.sh -------------------------------------
install_ble(){
  command -v git >/dev/null || { err "git required"; exit 1; }
  (command -v gawk >/dev/null || command -v awk >/dev/null) || { err "gawk/awk required"; exit 1; }
  command -v make >/dev/null || { err "make required"; exit 1; }
  if [[ -d "$BLE_BUILD_DIR/.git" ]]; then info "Updating ble.sh"; exec_run git -C "$BLE_BUILD_DIR" pull -q --ff-only || true
  else exec_run mkdir -p "$(dirname "$BLE_BUILD_DIR")"; info "Cloning ble.sh"; exec_run git clone -q --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git "$BLE_BUILD_DIR"; fi
  exec_run make -s -C "$BLE_BUILD_DIR" install PREFIX="$HOME/.local"
  [[ -r "$HOME/.local/share/blesh/ble.sh" ]] || { err "ble.sh install failed"; exit 1; }
  ok "ble.sh installed"
}

# -------------------------------- Python lints --------------------------------
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

# -------------------------------- Bash lints ----------------------------------
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

# -------------------------------- kubectl/oc ----------------------------------
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
  if ! SUDO test -w "$sysbindir" >/dev/null 2>&1; then bindir="$userbindir"; mkdir -p "$bindir"; warn "Add $bindir to PATH if needed"; fi
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

  mkdir -p "$USER_BASH_COMPLETION_DIR"
  command -v kubectl >/dev/null && kubectl completion bash >"$USER_BASH_COMPLETION_DIR/kubectl" || true
  command -v oc >/dev/null && oc completion bash >"$USER_BASH_COMPLETION_DIR/oc" || true
  ok "kubectl/oc completions saved"
}

# -------------------------------- Ghostty -------------------------------------
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
  local cfgdir;      cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
  local themes_dir;  themes_dir="$cfgdir/themes"
  local stamp;       stamp="$themes_dir/.dracula_not_found"
  mkdir -p "$themes_dir"

  if [[ -d "$themes_dir/dracula" ]] || [[ -f "$themes_dir/dracula" ]] || [[ -f "$themes_dir/dracula.conf" ]] || [[ -f "$themes_dir/dracula.toml" ]]; then
    :
  else
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
          if [[ -f "$src_dir/themes/dracula.conf" ]]; then
            cp -f "$src_dir/themes/dracula.conf" "$themes_dir/dracula"   # <— write exact filename "dracula"
            copied=1
          else
            rm -rf "$themes_dir/dracula"
            cp -a "$src_dir" "$themes_dir/dracula"
            copied=1
          fi
        else
          src_file="$(find "$tmp" -type f \( -iname 'dracula' -o -iname 'dracula*.conf' -o -iname 'dracula*.toml' \) | head -n1 || true)"
          if [[ -n "$src_file" ]]; then
            if [[ "$src_file" =~ \.toml$ ]]; then
              cp -f "$src_file" "$themes_dir/dracula.toml"
            elif [[ "$src_file" =~ \.conf$ ]]; then
              cp -f "$src_file" "$themes_dir/dracula"
            else
              cp -f "$src_file" "$themes_dir/dracula"
            fi
            copied=1
          fi
        fi
        rm -rf "$zip" "$tmp"
        [[ $copied -eq 1 ]] && ok "Dracula theme installed to $themes_dir" || { warn "Dracula not found in archive; caching failure."; : >"$stamp"; }
      else
        warn "Failed to download Dracula archive"
      fi
    fi
  fi

  local cfg="$cfgdir/config"; mkdir -p "$cfgdir"; touch "$cfg"
  # normalize legacy names -> config
  for legacy in "$cfgdir/config.conf" "$cfgdir/config.toml"; do
    [[ -f "$legacy" ]] && { mv -f -- "$legacy" "$cfg"; ok "Renamed $(basename "$legacy") -> config"; }
  done
  grep -qE '^\s*theme\s*=\s*dracula\s*$' "$cfg" || { echo "theme = dracula" >>"$cfg"; ok "Added 'theme = dracula' to $cfg"; }
}

install_ghostty(){
  if [[ "$OS_FAMILY" == "redhat" ]]; then install_ghostty_repo_redhat; else install_ghostty_debian; fi
  if [[ "${ENABLE_GHOSTTY_DRACULA:-1}" -eq 1 ]] && command -v ghostty >/dev/null; then ensure_ghostty_dracula_theme; fi
}

# ---------------------------------- tmux --------------------------------------
ensure_tpm(){
  if [[ -d "$TMUX_TPM_DIR/.git" ]]; then exec_run git -C "$TMUX_TPM_DIR" pull -q --ff-only || true
  else command -v git >/dev/null || { warn "git missing; cannot install TPM"; return 1; }
       exec_run mkdir -p "$TMUX_TPM_DIR"
       exec_run git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$TMUX_TPM_DIR"; fi
  ok "TPM ready"
}
tmux_conf_body_block(){ cat <<'EOF'
# Managed by install_vimrc_etc.sh
# Tabs/menus quick keys: Prefix+m (menu), Prefix+c (new), Prefix+, (rename)
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:RGB,tmux-256color:RGB"
set -g mouse on
set -g history-limit 100000
set -g status-interval 5
set -g renumber-windows on
setw -g mode-keys vi
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
set -g status on
set -g status-position top
set -g status-style fg=default,bg=default
set -g window-status-style fg=colour245,bg=default
set -g window-status-format " #I:#W "
set -g window-status-current-style fg=colour231,bg=colour61,bold
set -g window-status-current-format " #I:#W "
set -g window-status-separator ""
bind -n M-Left  previous-window
bind -n M-Right next-window
bind C-PPage    previous-window
bind C-NPage    next-window
bind c new-window
bind , command-prompt -I "#W" "rename-window '%%'"
bind < swap-window -t -1 \; select-window -t -1
bind > swap-window -t +1 \; select-window -t +1
bind w choose-tree -Zw
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
bind -n MouseDown3Status display-menu -T "#[align=centre]Tab: #I #W" -x W -y S \
  "New tab"         c  new-window \
  "Rename tab…"     r  command-prompt -I "#W" "rename-window '%%'" \
  "Move tab left"   <  "swap-window -t -1 \; select-window -t -1" \
  "Move tab right"  >  "swap-window -t +1 \; select-window -t +1" \
  "" \
  "Close tab"       X  kill-window
bind -n MouseDown3Pane display-menu -T "#[align=centre]Pane • #{pane_index}" \
  "Split ─ horizontally"    "-" split-window -v \
  "Split │ vertically"      "|" split-window -h \
  "Toggle sync panes"       s  "run-shell 'tmux set -g synchronize-panes; tmux display-message \"sync-panes: #{?synchronize-panes,on,off}\"'" \
  "" \
  "Zoom pane"               z  resize-pane -Z \
  "Kill pane"               x  kill-pane
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'dracula/tmux'
set -g @dracula-show-network false
set -g @dracula-plugins "battery,cpu,ram,git"
set -g @dracula-refresh-rate 5
set -g @dracula-fixed_location_status false
set -g @dracula-show-powerline true
run '~/.tmux/plugins/tpm/tpm'
EOF
}
install_tmux_conf_block(){
  upsert_greedy "$TMUX_CONF" "DEV_BOOTSTRAP_TMUX_START" "DEV_BOOTSTRAP_TMUX_END" \
    "# >>> DEV_BOOTSTRAP_TMUX_START >>>" "# <<< DEV_BOOTSTRAP_TMUX_END <<<" "$(tmux_conf_body_block)"
  compact_tmux
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

# ------------------------------ Clipboard tools -------------------------------
install_pbtools(){
  [[ "${ENABLE_PBTOOLS:-1}" -eq 1 ]] || { info "Skipping pbcopy/pbpaste (disabled)"; return 0; }
  ensure_local_bin_path
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/pbcopy" <<'PB'
#!/usr/bin/env bash
set -euo pipefail
if command -v pbcopy >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then exec /usr/bin/pbcopy; fi
if command -v wl-copy >/dev/null 2>&1; then exec wl-copy; fi
if command -v xclip >/dev/null 2>&1; then exec xclip -selection clipboard; fi
if command -v xsel >/dev/null 2>&1; then exec xsel --clipboard --input; fi
if grep -qi microsoft /proc/version 2>/dev/null && command -v clip.exe >/dev/null 2>&1; then exec clip.exe; fi
echo "pbcopy: no clipboard backend found (install wl-clipboard or xclip/xsel)" >&2; exit 1
PB
  cat > "$HOME/.local/bin/pbpaste" <<'PB'
#!/usr/bin/env bash
set -euo pipefail
if command -v pbpaste >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then exec /usr/bin/pbpaste; fi
if command -v wl-paste >/dev/null 2>&1; then exec wl-paste; fi
if command -v xclip >/dev/null 2>&1; then exec xclip -selection clipboard -o; fi
if command -v xsel  >/dev/null 2>&1; then exec xsel --clipboard --output; fi
# WSL paste intentionally disabled (PowerShell backend omitted)
echo "pbpaste: no clipboard backend found (install wl-clipboard or xclip/xsel)" >&2; exit 1
PB
  chmod +x "$HOME/.local/bin/pbcopy" "$HOME/.local/bin/pbpaste"
  # Minimal comment block in .bashrc (no PATH duplication)
  upsert_greedy "$HOME/.bashrc" "PBCLIP_PATH_START" "PBCLIP_PATH_END" \
    "# >>> PBCLIP_PATH_START >>>" "# <<< PBCLIP_PATH_END <<<" \
    "# pbcopy/pbpaste shims installed in ~/.local/bin (PATH ensured by installer)\n# Backends: wl-clipboard (Wayland), xclip/xsel (X11), clip.exe (WSL for pbcopy)"
  compact_bashrc
  ok "Installed pbcopy/pbpaste to ~/.local/bin"
}

# ------------------------------- Repo tooling ---------------------------------
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
  ok "Repo tooling written"
}

safe_source_bashrc(){ [[ -r "$HOME/.bashrc" ]] && { set +u; . "$HOME/.bashrc" || true; set -u; } || warn "~/.bashrc missing"; }

# ---------------------------------- argcomplete -------------------------------
install_argcomplete(){
  ensure_pip || { warn "pip unavailable; cannot install argcomplete"; return 1; }
  export PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_ROOT_USER_ACTION=ignore
  info "Installing argcomplete (user)"
  exec_run python3 -m pip install --user --upgrade --upgrade-strategy only-if-needed argcomplete
  mkdir -p "$USER_BASH_COMPLETION_DIR"
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
  ok "argcomplete set up"
}

# ----------------------------------- Main -------------------------------------
main(){
  info "Dev Bootstrap starting"
  detect_os
  run_if ENABLE_PACKAGES install_packages

  # Fallbacks
  ensure_powerline_glyphs
  [[ "$ENABLE_YAMLLINT" -eq 1 ]] && ! command -v yamllint >/dev/null && ensure_yamllint_user
  ensure_fzf_user
  ensure_local_bin_path

  # Editors & configs
  run_if ENABLE_VIM_PLUGINS ensure_pathogen deploy_plugins
  run_if ENABLE_VIMRC install_vimrc_block
  run_if ENABLE_YAMLLINT install_yamllint_conf

  # Shell enhancements
  run_if ENABLE_BASHRC install_bashrc_block
  if [[ "$ENABLE_BLE" -eq 1 ]]; then install_ble; install_ble_bashrc_block; fi
  [[ "$ENABLE_ARGCOMPLETE" -eq 1 ]] && install_argcomplete || info "Skipping argcomplete (disabled)"

  # Clipboard helpers
  run_if ENABLE_PBTOOLS install_pbtools

  # Linters & CLIs
  run_if ENABLE_BASH_LINTERS install_bash_linters
  run_if ENABLE_PY_LINTERS install_python_linters
  run_if ENABLE_KUBECTL_OC install_oc_kubectl

  # Terminals
  run_if ENABLE_GHOSTTY install_ghostty
  run_if ENABLE_TMUX install_tmux

  run_if ENABLE_REPO_TOOLING write_repo_tooling

  # Final tidy, ownership, and source
  compact_bashrc; compact_vimrc; compact_tmux
  ensure_user_ownership

  ok "All done. Sourcing ~/.bashrc now (safe)."
  safe_source_bashrc
  ok "Done. For a fresh session, run: exec bash -l"
}
main
