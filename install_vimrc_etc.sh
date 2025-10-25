#!/usr/bin/env bash
# Dev Bootstrap (No EPEL, append-only configs, quiet logs)
# - Installs base dev packages from system repos
# - Falls back to user-scope installs for yamllint and Nerd Fonts
# - Vim + Pathogen + curated plugins
# - bash-completion, argcomplete (user), bash/python linters
# - kubectl + oc installers (+ bash completions)
# - Adds robust fzf Ctrl-R history support (user-scope ~/.fzf)
# - Idempotent .bashrc/.vimrc upserts with backups

set -euo pipefail

###############################################################################
# CONFIG (edit here)
###############################################################################
ENABLE_PACKAGES=1
ENABLE_VIM_PLUGINS=1
ENABLE_VIMRC=1
ENABLE_YAMLLINT=1
ENABLE_BASHRC=1
ENABLE_ARGCOMPLETE=1
ENABLE_BASH_LINTERS=1
ENABLE_PY_LINTERS=1
ENABLE_KUBECTL_OC=1
ENABLE_REPO_TOOLING=1

CLEAN_OUTPUT=1                # 1 = suppress package manager/git noise
LOG_FILE=""                   # e.g. "/tmp/bootstrap.log" (empty = no file log)

VIM_DIR="$HOME/.vim"
YAMLLINT_CONF="$HOME/.config/yamllint/config"
BLE_BUILD_DIR="$HOME/.local/src/ble.sh"   # unused now (BLE removed)
USER_BASH_COMPLETION_DIR="$HOME/.bash_completion.d"

# Base packages (no EPEL). Add unzip for Nerd Font fallback.
PACKAGES_RHEL_BASE=(vim-enhanced git powerline-fonts curl make gawk bash-completion python3 python3-pip unzip)
PACKAGES_DEBIAN_BASE=(vim git fonts-powerline fzf yamllint curl make gawk bash-completion python3 python3-pip unzip)

# Python linters (pin or leave empty for latest)
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"

# kubectl/oc versions
KUBECTL_VERSION="v1.31.1"
OC_CHANNEL="stable"

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

###############################################################################
# Logging & helpers
###############################################################################
_have_tty() { [[ -t 1 ]] || [[ -w /dev/tty ]]; }
_to_tty()   { if [[ -w /dev/tty ]]; then printf "%b" "$*" > /dev/tty; else printf "%b" "$*"; fi; }
_logfile()  { if [[ -n "$LOG_FILE" ]]; then printf "%b" "$*" >> "$LOG_FILE"; fi; }
log()  { _to_tty "$*"; _logfile "$*"; }
info() { log "\033[1;34m[INFO]\033[0m $*\n"; }
warn() { log "\033[1;33m[WARN]\033[0m $*\n"; }
ok()   { log "\033[1;32m[ OK ]\033[0m $*\n"; }
err()  { log "\033[1;31m[ERR ]\033[0m $*\n"; }

if [[ -n "$LOG_FILE" ]]; then mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true; fi
trap 'err "Failed: \"$BASH_COMMAND\" at ${BASH_SOURCE[0]}:${LINENO}"' ERR

SUDO() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    err "Need root for: $* (sudo not available)"; return 1
  fi
}

exec_run() {
  if [[ -n "$LOG_FILE" ]]; then
    if (( CLEAN_OUTPUT )); then "$@" >>"$LOG_FILE" 2>&1; else "$@" 2>&1 | tee -a "$LOG_FILE"; fi
  else
    if (( CLEAN_OUTPUT )); then "$@" >/dev/null 2>&1; else "$@"; fi
  fi
}

TMPFILES=()
mktempf() { local t; t="$(mktemp)"; TMPFILES+=("$t"); printf '%s' "$t"; }
cleanup() {
  for f in "${TMPFILES[@]:-}"; do [[ -n "$f" ]] && rm -f "$f" 2>/dev/null || true; done
  rm -f /tmp/{kubectl,kubectl.sha256,oc.tar.gz,oc,README.md} 2>/dev/null || true
}
trap cleanup EXIT

backup_file() {
  local f="$1"
  if [[ -f "$f" || -L "$f" ]]; then
    local ts; ts="$(date +%Y%m%d_%H%M%S)"
    exec_run cp -a "$f" "${f}.bak.${ts}"
    info "Backed up $f -> ${f}.bak.${ts}"
  fi
}

_write_block_clean() {
  # $1=file, $2=tmpfile-with-existing-content, $3=start_line, $4=end_line, $5=body
  local file="$1" tmp="$2" start_line="$3" end_line="$4" body="$5"
  local prefix=""
  [[ -s "$tmp" ]] && prefix=$'\n'

  {
    cat "$tmp"
    printf '%s%s\n' "$prefix" "$start_line"
    printf '%s\n' "$body"
    printf '%s\n' "$end_line"
    printf '\n'
  } > "$file"

  # strip only leading blank lines
  local t2; t2="$(mktempf)"
  awk '
    BEGIN { seen_nonblank=0 }
    {
      if (!seen_nonblank) {
        if ($0 ~ /^[[:space:]]*$/) next
        seen_nonblank=1
      }
      print
    }
  ' "$file" > "$t2" && mv "$t2" "$file"
}

upsert_block() {
  local file="$1" start="$2" end="$3" content="$4"
  [[ -f "$file" ]] || : > "$file"
  backup_file "$file"

  _sed_escape() { printf '%s' "$1" | sed -e 's/[\/&[\].*^$\\]/\\&/g'; }
  local s_esc e_esc tmp
  s_esc="$(_sed_escape "$start")"
  e_esc="$(_sed_escape "$end")"

  tmp="$(mktempf)"
  sed -e "/^${s_esc}\$/,/^${e_esc}\$/d" "$file" > "$tmp"
  sed -e "/^${s_esc}\$/d" -e "/^${e_esc}\$/d" "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"

  _write_block_clean "$file" "$tmp" "$start" "$end" "$content"
  ok "Updated $file ($start)"
}

upsert_vim_block() {
  local file="$1" body="$2"
  [[ -f "$file" ]] || : > "$file"
  backup_file "$file"

  local tmp; tmp="$(mktempf)"
  awk -v s="DEV_BOOTSTRAP_VIM_START" -v e="DEV_BOOTSTRAP_VIM_END" '
    { lines[NR]=$0 }
    {
      if (index($0, s) && first==0) first=NR;
      if (index($0, e))            last=NR;
    }
    END {
      for (i=1; i<=NR; i++) {
        if (first && last && i>=first && i<=last) continue;
        else if (first && !last && i>=first)      continue;
        print lines[i];
      }
    }
  ' "$file" > "$tmp"

  _write_block_clean "$file" "$tmp" '" >>> DEV_BOOTSTRAP_VIM_START >>>' '" <<< DEV_BOOTSTRAP_VIM_END <<<' "$body"
  ok "Ensured single managed Vim block in $file"
}

upsert_block_by_token() {
  # $1=file, $2=start_token, $3=end_token, $4=start_line, $5=end_line, $6=body
  local file="$1" s_tok="$2" e_tok="$3" start_line="$4" end_line="$5" body="$6"
  [[ -f "$file" ]] || : > "$file"
  backup_file "$file"

  local tmp; tmp="$(mktempf)"
  awk -v s="$s_tok" -v e="$e_tok" '
    { lines[NR]=$0 }
    {
      if (index($0, s) && first==0) first=NR;
      if (index($0, e))            last=NR;
    }
    END {
      for (i=1; i<=NR; i++) {
        if (first && last && i>=first && i<=last) continue;
        else if (first && !last && i>=first)      continue;
        print lines[i];
      }
    }
  ' "$file" > "$tmp"

  local esc_start esc_end
  esc_start="$(printf '%s' "$start_line" | sed -e 's/[\/&.^$*[]]/\\&/g')"
  esc_end="$(printf   '%s' "$end_line"   | sed -e 's/[\/&.^$*[]]/\\&/g')"
  sed -e "/^${esc_start}\$/d" -e "/^${esc_end}\$/d" "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"

  _write_block_clean "$file" "$tmp" "$start_line" "$end_line" "$body"
  ok "Updated $file (${s_tok}…${e_tok})"
}

###############################################################################
# OS & packages
###############################################################################
detect_os() {
  . /etc/os-release 2>/dev/null || { err "Missing /etc/os-release"; exit 1; }
  local id_like="${ID_LIKE:-}"
  if [[ "$ID" =~ (rhel|rocky|almalinux|centos|fedora) ]] || [[ "$id_like" =~ (rhel|fedora) ]]; then
    OS_FAMILY="redhat"
  elif [[ "$ID" =~ (debian|ubuntu|raspbian|linuxmint) ]] || [[ "$id_like" =~ (debian|ubuntu) ]]; then
    OS_FAMILY="debian"
  else
    OS_FAMILY="debian"; warn "Unknown distro; assuming Debian-like."
  fi
  info "OS family: $OS_FAMILY (ID=${ID})"
}

install_packages_common() {
  mkdir -p "$HOME/.config/yamllint" "$HOME/files" "$VIM_DIR" "$VIM_DIR/autoload" "$VIM_DIR/bundle" \
           "$HOME/.local/share" "$HOME/.local/bin" "$USER_BASH_COMPLETION_DIR" || true
  chmod 0755 "$HOME/.config" "$HOME/.config/yamllint" "$HOME/files" "$VIM_DIR" "$HOME/.local/share" \
             "$USER_BASH_COMPLETION_DIR" || true
  chmod 0750 "$VIM_DIR" "$VIM_DIR/autoload" "$VIM_DIR/bundle" || true
}

install_packages() {
  install_packages_common
  if [[ "$OS_FAMILY" == "redhat" ]]; then
    if command -v dnf >/dev/null 2>&1; then
      exec_run SUDO dnf -y -q install "${PACKAGES_RHEL_BASE[@]}" || warn "Some packages not available in base repos."
    else
      exec_run SUDO yum -y -q install "${PACKAGES_RHEL_BASE[@]}" || warn "Some packages not available in base repos."
    fi
  else
    if (( CLEAN_OUTPUT )); then
      exec_run SUDO apt-get -qq update
      exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install "${PACKAGES_DEBIAN_BASE[@]}"
    else
      exec_run SUDO apt-get update -y -o Dpkg::Progress-Fancy=1
      exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Progress-Fancy=1 "${PACKAGES_DEBIAN_BASE[@]}"
    fi
  fi
  ok "Packages installed (system repos only; no EPEL)."
}

###############################################################################
# Fallbacks: fzf (user), yamllint (user via pip), Nerd Fonts (user)
###############################################################################
ensure_pip() {
  if python3 -m pip --version >/dev/null 2>&1; then return 0; fi
  if python3 -m ensurepip --version >/dev/null 2>&1; then exec_run python3 -m ensurepip --upgrade; fi
  if ! python3 -m pip --version >/dev/null 2>&1; then
    if [[ "$OS_FAMILY" == "redhat" ]]; then
      if command -v dnf >/dev/null 2>&1; then exec_run SUDO dnf -y -q install python3-pip || true
      else exec_run SUDO yum -y -q install python3-pip || true
      fi
    else
      exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install python3-pip
    fi
  fi
  python3 -m pip --version >/dev/null 2>&1 || { err "pip not available"; return 1; }
}

ensure_fzf_user() {
  # If fzf exists anywhere on PATH, keep existing setup.
  if command -v fzf >/dev/null 2>&1; then
    info "fzf found in PATH ($(command -v fzf))"
    return 0
  fi
  # If user install already present, just expose it to PATH and return.
  if [[ -x "$HOME/.fzf/bin/fzf" ]]; then
    info "fzf already installed at ~/.fzf; ensuring PATH"
    if [[ ":$PATH:" != *":$HOME/.fzf/bin:"* ]]; then
      export PATH="$HOME/.fzf/bin:$PATH"
      info "Added ~/.fzf/bin to PATH (current shell)"
    fi
    return 0
  fi
  # Fresh user-scope install (no EPEL needed)
  if ! command -v git >/dev/null 2>&1; then
    warn "git missing; cannot install fzf user-scope"
    return 0
  fi
  info "Installing fzf to ~/.fzf (user-scope; no EPEL)"
  exec_run git clone -q --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  exec_run "$HOME/.fzf/install" --key-bindings --completion --no-update-rc
  # Ensure ~/.fzf/bin on PATH now
  if [[ ":$PATH:" != *":$HOME/.fzf/bin:"* ]]; then
    export PATH="$HOME/.fzf/bin:$PATH"
    info "Added ~/.fzf/bin to PATH (current shell)"
  fi
  ok "fzf installed to ~/.fzf"
}

ensure_yamllint_user() {
  if command -v yamllint >/dev/null 2>&1; then
    ok "yamllint already present: $(command -v yamllint)"
    return 0
  fi
  ensure_pip || { warn "pip unavailable; cannot install yamllint user-scope"; return 1; }
  exec_run python3 -m pip install --user --upgrade yamllint || { warn "Failed installing yamllint via pip"; return 1; }
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/.local/bin:$PATH"
    info "Added ~/.local/bin to PATH"
  fi
  command -v yamllint >/dev/null 2>&1 && ok "yamllint installed (user)" || err "yamllint not found after install"
}

font_installed() {
  local family="${1:-FiraCode Nerd Font}"
  if command -v fc-list >/dev/null 2>&1; then
    fc-list : family | grep -iFq "$family" && return 0
  fi
  local ufonts="$HOME/.local/share/fonts"
  if find "$ufonts" -type f \( -iname "*$(echo "$family" | tr -d ' ')*.ttf" -o -iname "*FiraCodeNerdFont*.ttf" \) 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

install_nerd_fonts_user() {
  local family="${1:-FiraCode Nerd Font}"
  local zip="${2:-FiraCode.zip}"
  local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${zip}"
  local dest="$HOME/.local/share/fonts"

  if font_installed "$family"; then
    info "Nerd Font already present: $family"
    return 0
  fi

  info "Installing Nerd Font (user): $family"
  mkdir -p "$dest"
  local tmpd; tmpd="$(mktemp -d)" || { warn "mktemp failed for fonts"; return 1; }
  (
    set -e
    cd "$tmpd"
    curl -fL --retry 3 --retry-delay 2 -O "$url"
    unzip -oq "$zip"
    find . -type f \( -iname "*.ttf" -o -iname "*.otf" \) -exec mv -f {} "$dest"/ \;
  ) || { warn "Nerd Font download/install failed: ${zip}"; rm -rf "$tmpd"; return 1; }
  rm -rf "$tmpd"
  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$dest" >/dev/null 2>&1 || true; fi
  font_installed "$family" && ok "Installed Nerd Font: $family" || warn "Font not visible yet: $family"
}

ensure_powerline_glyphs() {
  local family="${1:-FiraCode Nerd Font}"
  local zip="${2:-FiraCode.zip}"
  if command -v fc-list >/dev/null 2>&1 && fc-list : family | grep -qiE 'Nerd Font|Powerline'; then
    info "Powerline/Nerd fonts available"
    return 0
  fi
  install_nerd_fonts_user "$family" "$zip"
}

###############################################################################
# Vim
###############################################################################
ensure_pathogen() {
  local dest="$VIM_DIR/autoload/pathogen.vim"
  [[ -f "$dest" ]] && { info "Pathogen present."; return 0; }
  command -v curl >/dev/null 2>&1 || { err "curl is required"; exit 1; }
  exec_run curl -fsSL -o "$dest" https://tpo.pe/pathogen.vim
  ok "Pathogen installed."
}

deploy_plugins() {
  command -v git >/dev/null 2>&1 || { err "git is required"; exit 1; }
  local line name url dest
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" != *"="* ]] && { warn "Skipping malformed plugin line: $line"; continue; }
    name="${line%%=*}"; url="${line#*=}"
    [[ -z "${name:-}" || -z "${url:-}" ]] && { warn "Skipping broken entry: $line"; continue; }
    dest="$VIM_DIR/bundle/$name"
    if [[ -d "$dest/.git" ]]; then
      exec_run git -C "$dest" pull -q --ff-only || true
    else
      exec_run git clone -q --depth 1 "$url" "$dest"
    fi
  done <<< "$VIM_PLUGIN_LIST"
  ok "Vim plugins ready."
}

vimrc_body_block() {
cat <<'EOF'
" Managed by install_vimrc_etc.sh — safe to remove or move as you like.
execute pathogen#infect()
syntax on
filetype plugin indent on

" Line numbers (traditional)
set number
set norelativenumber

set tabstop=2 shiftwidth=2 expandtab
set cursorline
set termguicolors
set background=dark
" colorscheme requires plugin installed; comment out if you prefer another theme
silent! colorscheme shades_of_purple

let mapleader=","
let g:airline#extensions#tabline#enabled = 1
let g:airline_powerline_fonts = 1

" NERDTree toggle
nnoremap <leader>n :NERDTreeToggle<CR>

" fzf integration (works with either system fzf or ~/.fzf)
set rtp+=~/.fzf
nnoremap <C-p> :Files<CR>

" ALE & indent guides
let g:ale_sign_column_always = 1
let g:indentLine_char = '│'
EOF
}

install_vimrc_block() {
  local f="$HOME/.vimrc"
  [[ -f "$f" ]] || : > "$f"
  upsert_vim_block "$f" "$(vimrc_body_block)"
}

###############################################################################
# yamllint config
###############################################################################
write_default_yamllint() {
cat <<'EOF'
# --- Managed by install_vimrc_etc.sh ---
extends: default
rules:
  line-length:
    max: 120
    allow-non-breakable-words: true
  truthy:
    allowed-values: ['true', 'false', 'on', 'off', 'yes', 'no']
  indentation:
    spaces: 2
  document-start: disable
EOF
}

install_yamllint_conf() {
  if [[ -f "$YAMLLINT_CONF" ]]; then
    info "yamllint config exists at $YAMLLINT_CONF — leaving it untouched."
    return 0
  fi
  mkdir -p "$(dirname "$YAMLLINT_CONF")"
  write_default_yamllint > "$YAMLLINT_CONF"
  chmod 0640 "$YAMLLINT_CONF" || true
  ok "Yamllint config created at $YAMLLINT_CONF"
}

###############################################################################
# Bashrc blocks
###############################################################################
eternal_history_block() {
cat <<'EOF'
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE=~/.bash_eternal_history
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
HISTCONTROL=erasedups

# Prefer fast git prompt if available (bash-completion)
if declare -F __git_ps1 >/dev/null 2>&1; then
  # shellcheck disable=SC2016
  export PS1='╭─╼[\[\e[1;36m\]\w\[\e[0m\]] \[\e[1;34m\]$(__git_ps1 "[%s]")\[\e[0m\]\n╰─ \u@\h >> '
else
  parse_git_branch() { git branch --no-color 2>/dev/null | sed -n "s/^\* //p"; }
  # shellcheck disable=SC2016
  export PS1='╭─╼[\[\e[1;36m\]\w\[\e[0m\]] \[\e[1;34m\]$(parse_git_branch)\[\e[0m\]\n╰─ \u@\h >> '
fi

PROMPT_DIRTRIM=2
EOF
}

# NEW: Robust FZF setup (PATH + key-bindings + Ctrl-R fallback)
fzf_bashrc_block() {
cat <<'EOF'
# --- FZF user-scope setup (idempotent) ---
# Ensure ~/.fzf/bin on PATH (once)
if [[ ":$PATH:" != *":$HOME/.fzf/bin:"* ]]; then
  export PATH="$HOME/.fzf/bin:$PATH"
fi

# Load keybindings/completion from common locations
if [[ $- == *i* ]]; then
  # System key-bindings (varies by distro)
  if [[ -r /usr/share/fzf/key-bindings.bash ]]; then
    # shellcheck source=/usr/share/fzf/key-bindings.bash
    source /usr/share/fzf/key-bindings.bash
  elif [[ -r /usr/share/fzf/shell/key-bindings.bash ]]; then
    # shellcheck source=/usr/share/fzf/shell/key-bindings.bash
    source /usr/share/fzf/shell/key-bindings.bash
  fi
  # System completion
  if [[ -r /usr/share/fzf/completion.bash ]]; then
    # shellcheck source=/usr/share/fzf/completion.bash
    source /usr/share/fzf/completion.bash
  elif [[ -r /usr/share/fzf/shell/completion.bash ]]; then
    # shellcheck source=/usr/share/fzf/shell/completion.bash
    source /usr/share/fzf/shell/completion.bash
  fi

  # User-scope (~/.fzf)
  [[ -r "$HOME/.fzf/shell/key-bindings.bash" ]] && source "$HOME/.fzf/shell/key-bindings.bash"
  [[ -r "$HOME/.fzf/shell/completion.bash"   ]] && source "$HOME/.fzf/shell/completion.bash"

  # Nice defaults
  : "${FZF_DEFAULT_OPTS:=--height=40% --layout=reverse --border}"
  : "${FZF_CTRL_R_OPTS:=--sort}"

  # Fallback Ctrl-R widget if official one didn't load
  if ! declare -F __fzf_history__ >/dev/null; then
    fzf_history_widget_fallback() {
      local selected
      selected="$(
        HISTTIMEFORMAT= builtin history \
          | sed 's/^[ ]*[0-9]\+[ ]*//' \
          | tac \
          | fzf ${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS} --tiebreak=index --query="$READLINE_LINE"
      )" || return
      READLINE_LINE="$selected"; READLINE_POINT=${#READLINE_LINE}
    }
    bind -x '"\C-r": fzf_history_widget_fallback'
  fi
fi
# --- end FZF user-scope setup ---
EOF
}

install_bashrc_history_block() {
  local f="$HOME/.bashrc"
  [[ -f "$f" ]] || : > "$f"
  upsert_block_by_token \
    "$f" \
    "ETERNAL_HISTORY_AND_GIT_PROMPT_START" \
    "ETERNAL_HISTORY_AND_GIT_PROMPT_END" \
    "# >>> ETERNAL_HISTORY_AND_GIT_PROMPT_START >>>" \
    "# <<< ETERNAL_HISTORY_AND_GIT_PROMPT_END <<<" \
    "$(eternal_history_block)"
}

install_bashrc_fzf_block() {
  local f="$HOME/.bashrc"
  [[ -f "$f" ]] || : > "$f"
  upsert_block_by_token \
    "$f" \
    "FZF_USER_START" \
    "FZF_USER_END" \
    "# >>> FZF_USER_START >>>" \
    "# <<< FZF_USER_END <<<" \
    "$(fzf_bashrc_block)"
}

###############################################################################
# pip / argcomplete / linters
###############################################################################
install_argcomplete() {
  ensure_pip || { warn "pip unavailable; cannot install argcomplete"; return 1; }
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  export PIP_ROOT_USER_ACTION=ignore

  info "Installing argcomplete (user-scope)"
  exec_run python3 -m pip install --user --upgrade --upgrade-strategy only-if-needed argcomplete

  mkdir -p "$USER_BASH_COMPLETION_DIR"
  if command -v activate-global-python-argcomplete >/dev/null 2>&1; then
    exec_run activate-global-python-argcomplete --dest "$USER_BASH_COMPLETION_DIR"
    ok "argcomplete activated (user-scope)"
  else
    python3 - <<'PY' 2>/dev/null || { warn "argcomplete not importable; skipping user loader"; return 0; }
import importlib, sys
try:
    import importlib; importlib.import_module("argcomplete"); sys.exit(0)
except Exception:
    sys.exit(1)
PY
    cat > "$USER_BASH_COMPLETION_DIR/python-argcomplete.sh" <<'EOS'
# user-scope argcomplete loader
if command -v register-python-argcomplete >/dev/null 2>&1; then
  for cmd in pip pip3 python3 git kubectl oc terraform ansible ansible-playbook; do
    if command -v "$cmd" >/dev/null 2>&1; then
      eval "$(register-python-argcomplete "$cmd")"
    fi
  done
fi
EOS
    ok "argcomplete user loader created at $USER_BASH_COMPLETION_DIR/python-argcomplete.sh"
  fi
}

install_python_linters() {
  ensure_pip || return 1
  local ruff_spec="ruff";   [[ -n "$RUFF_VERSION"   ]] && ruff_spec="ruff==${RUFF_VERSION}"
  local pyl_spec="pylint";  [[ -n "$PYLINT_VERSION" ]] && pyl_spec="pylint==${PYLINT_VERSION}"
  info "Installing Python linters: ${ruff_spec} ${pyl_spec} (user-scope)"
  exec_run python3 -m pip install --user --upgrade ${ruff_spec} ${pyl_spec}

  # Ensure ~/.local/bin on PATH (current + persist)
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    info "Added ~/.local/bin to PATH (current shell)"
    if ! grep -qE '(^|:)\$HOME/\.local/bin(:|$)|(^|:)~/.local/bin(:|$)' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      info "Appended PATH export to ~/.bashrc"
    fi
    hash -r || true
  fi

  # Extra safety: if not visible, reinstall explicitly
  if ! command -v ruff >/dev/null 2>&1 || ! command -v pylint >/dev/null 2>&1; then
    warn "ruff/pylint not visible yet; reinstalling explicitly to user site"
    local re_ruff="ruff"; [[ -n "$RUFF_VERSION" ]] && re_ruff="ruff==${RUFF_VERSION}"
    local re_pyl="pylint"; [[ -n "$PYLINT_VERSION" ]] && re_pyl="pylint==${PYLINT_VERSION}"
    exec_run python3 -m pip install --user --upgrade "$re_ruff" "$re_pyl"
    hash -r || true
  fi

  command -v ruff >/dev/null 2>&1 && ok "ruff installed ($(ruff --version 2>/dev/null | awk '{print $2}'))" || warn "ruff missing"
  command -v pylint >/dev/null 2>&1 && ok "pylint installed ($(pylint --version 2>/dev/null | awk 'NR==1{print $2}'))" || warn "pylint missing"
}

install_bash_linters() {
  info "Installing Bash linters (shellcheck, shfmt)"
  if [[ "$OS_FAMILY" == "redhat" ]]; then
    if command -v dnf >/dev/null 2>&1; then
      exec_run SUDO dnf -y -q install shellcheck || warn "shellcheck not in base repos"
      exec_run SUDO dnf -y -q install shfmt      || warn "shfmt not in base repos"
    else
      exec_run SUDO yum -y -q install shellcheck || warn "shellcheck not in base repos"
      exec_run SUDO yum -y -q install shfmt      || warn "shfmt not in base repos"
    fi
  else
    exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install shellcheck || warn "shellcheck not available"
    exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install shfmt      || warn "shfmt not available"
  fi
  command -v shellcheck >/dev/null 2>&1 && ok "shellcheck installed" || warn "shellcheck missing"
  command -v shfmt      >/dev/null 2>&1 && ok "shfmt installed"      || warn "shfmt missing"
}

###############################################################################
# kubectl + oc
###############################################################################
K_ARCH="amd64"
detect_arch() {
  local u; u="$(uname -m)"
  case "$u" in
    x86_64|amd64)   K_ARCH="amd64" ;;
    aarch64|arm64)  K_ARCH="arm64" ;;
    armv7l)         K_ARCH="arm"   ;;
    ppc64le)        K_ARCH="ppc64le" ;;
    s390x)          K_ARCH="s390x" ;;
    *)              K_ARCH="amd64"; warn "Unknown arch $u; defaulting to amd64" ;;
  esac
}
fetch() { curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 -H 'User-Agent: dev-bootstrap/1.0' -o "$2" "$1"; }

install_oc_kubectl() {
  detect_arch
  local sysbindir="/usr/local/bin"
  local userbindir="$HOME/.local/bin"
  local bindir="$sysbindir"

  if ! SUDO test -w "$sysbindir" >/dev/null 2>&1; then
    bindir="$userbindir"
    mkdir -p "$bindir"
    if [[ ":$PATH:" != *":$bindir:"* ]]; then
      warn "Add $bindir to PATH: export PATH=\"$bindir:\$PATH\""
    fi
    info "Using user install dir $bindir (no root write)."
  fi

  local kubectl_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K_ARCH}/kubectl"
  local oc_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_CHANNEL}/openshift-client-linux.tar.gz"

  if ! command -v kubectl >/dev/null 2>&1; then
    fetch "$kubectl_url" /tmp/kubectl
    chmod +x /tmp/kubectl
    SUDO mv /tmp/kubectl "$bindir/kubectl"
    ok "kubectl installed to $bindir/kubectl"
    if curl -fsSL "https://dl.k8s.io/${KUBECTL_VERSION}/bin/linux/${K_ARCH}/kubectl.sha256" -o /tmp/kubectl.sha256; then
      (cd /tmp && sha256sum -c --status kubectl.sha256 2>/dev/null) || warn "kubectl checksum mismatch (continuing)."
    fi
  else
    ok "kubectl already present"
  fi

  if ! command -v oc >/dev/null 2>&1; then
    fetch "$oc_url" /tmp/oc.tar.gz
    tar -xzf /tmp/oc.tar.gz -C /tmp oc 2>/dev/null || true
    if [[ -f /tmp/oc ]]; then
      chmod +x /tmp/oc
      SUDO mv /tmp/oc "$bindir/oc"
      ok "oc installed to $bindir/oc"
    else
      warn "oc binary not found in archive; skipping."
    fi
  else
    ok "oc already present"
  fi

  mkdir -p "$USER_BASH_COMPLETION_DIR"
  if command -v kubectl >/dev/null 2>&1; then
    kubectl completion bash > "$USER_BASH_COMPLETION_DIR/kubectl" || true
    ok "kubectl completion saved to $USER_BASH_COMPLETION_DIR/kubectl"
  fi
  if command -v oc >/dev/null 2>&1; then
    oc completion bash > "$USER_BASH_COMPLETION_DIR/oc" || true
    ok "oc completion saved to $USER_BASH_COMPLETION_DIR/oc"
  fi
}

###############################################################################
# Repo tooling
###############################################################################
write_repo_tooling() {
  local script_path="${BASH_SOURCE[0]:-$(pwd)/install_vimrc_etc.sh}"
  local script_dir; script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  cat > "${script_dir}/Makefile" <<'MK'
SHELL := /usr/bin/env bash
SHELLCHECK ?= shellcheck
SH_SOURCES := install_vimrc_etc.sh

.PHONY: check-sh
check-sh:
	@bash -n $(SH_SOURCES)

.PHONY: lint-sh
lint-sh:
	@$(SHELLCHECK) -x -S style -s bash $(SH_SOURCES)

.PHONY: fmt-sh
fmt-sh:
	@command -v shfmt >/dev/null 2>&1 && shfmt -w -i 2 -ci -bn $(SH_SOURCES) || { echo "shfmt not installed; skipping."; }
MK
  cat > "${script_dir}/.shellcheckrc" <<'RC'
# Allow following external sources when paths are validated in code
external-sources=true
RC
  ok "Repo tooling written: Makefile and .shellcheckrc"
}

safe_source_bashrc() {
  if [[ -r "$HOME/.bashrc" ]]; then
    set +u; BASHRCSOURCED=1; . "$HOME/.bashrc" || true; set -u
  else
    warn "~/.bashrc not found; skipping source."
  fi
}

###############################################################################
# Main
###############################################################################
main() {
  info "Dev Bootstrap starting (append-only; no EPEL required)"
  detect_os

  install_packages_common
  if [[ "$ENABLE_PACKAGES" -eq 1 ]]; then install_packages; else warn "Skipping packages."; fi

  # If fonts/yamllint not in base repos, fall back to user-scope
  ensure_powerline_glyphs
  if ! command -v yamllint >/dev/null 2>&1 && [[ "$ENABLE_YAMLLINT" -eq 1 ]]; then
    ensure_yamllint_user
  fi

  # fzf: if missing from system, install user-scope & ensure PATH
  ensure_fzf_user

  if [[ "$ENABLE_VIM_PLUGINS" -eq 1 ]]; then ensure_pathogen; deploy_plugins; else warn "Skipping Vim plugins."; fi
  if [[ "$ENABLE_VIMRC" -eq 1 ]]; then install_vimrc_block; else warn "Skipping ~/.vimrc block."; fi
  if [[ "$ENABLE_YAMLLINT" -eq 1 ]]; then install_yamllint_conf; else warn "Skipping yamllint config."; fi

  if [[ "$ENABLE_BASHRC" -eq 1 ]]; then
    install_bashrc_history_block
    install_bashrc_fzf_block   # NEW robust fzf PATH + key bindings + Ctrl-R fallback
  else
    warn "Skipping ~/.bashrc blocks."
  fi

  if [[ "$ENABLE_ARGCOMPLETE" -eq 1 ]]; then install_argcomplete; else warn "Skipping argcomplete."; fi
  if [[ "$ENABLE_BASH_LINTERS" -eq 1 ]]; then install_bash_linters; else warn "Skipping bash linters."; fi
  if [[ "$ENABLE_PY_LINTERS" -eq 1 ]]; then install_python_linters; else warn "Skipping python linters."; fi

  if [[ "$ENABLE_KUBECTL_OC" -eq 1 ]]; then install_oc_kubectl; else warn "Skipping kubectl/oc install."; fi
  if [[ "$ENABLE_REPO_TOOLING" -eq 1 ]]; then write_repo_tooling; else warn "Skipping repo tooling."; fi

  ok "All done. Sourcing ~/.bashrc now (safe)."
  safe_source_bashrc
  ok "Done. For a fresh session, run: exec bash -l"
}

main
