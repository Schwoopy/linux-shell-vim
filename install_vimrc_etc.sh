#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Dev Bootstrap (Non-Interactive, Append-Only, No EPEL dependency)
# - Appends managed blocks to ~/.bashrc and ~/.vimrc (does NOT overwrite files)
# - Creates yamllint config only if missing
# - Vim + Pathogen + plugins
# - ble.sh (quiet, interactive-only), fzf (user fallback if not packaged)
# - argcomplete (user), Bash linters (shellcheck, shfmt), Python linters (ruff, pylint)
# - kubectl + oc installers to /usr/local/bin (or ~/.local/bin fallback) + completions
# - Writes Makefile + .shellcheckrc to help lint this script
# - Optimized: no progress bar, clean INFO/WARN/OK logs
# ==============================================================================

# --------------------------- CONFIG (edit here) -------------------------------
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

CLEAN_OUTPUT=1                  # 1 = suppress package manager/git noise
LOG_FILE=""                     # e.g. "/tmp/bootstrap.log" (empty = no file log)

VIM_DIR="$HOME/.vim"
YAMLLINT_CONF="$HOME/.config/yamllint/config"
BLE_DIR="$HOME/.local/share/blesh"
BLE_BUILD_DIR="$HOME/.local/src/ble.sh"
USER_BASH_COMPLETION_DIR="$HOME/.bash_completion.d"

# Base packages (NO EPEL). Add unzip for Nerd Font fallback.
PACKAGES_RHEL_BASE=(vim-enhanced git powerline-fonts yamllint curl make gawk bash-completion python3 python3-pip unzip)
PACKAGES_DEBIAN_BASE=(vim git fonts-powerline fzf yamllint curl make gawk bash-completion python3 python3-pip unzip)

# Python linters (pin or empty for latest)
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

# ==============================================================================
# Logging helpers
_have_tty() { [[ -t 1 ]] || [[ -w /dev/tty ]]; }
_to_tty()   { if [[ -w /dev/tty ]]; then printf "%b" "$*" > /dev/tty; else printf "%b" "$*"; fi; }
_logfile()  { if [[ -n "$LOG_FILE" ]]; then printf "%b" "$*" >> "$LOG_FILE"; fi; }
log()  { _to_tty "$*"; _logfile "$*"; }
info() { log "\033[1;34m[INFO]\033[0m $*\n"; }
warn() { log "\033[1;33m[WARN]\033[0m $*\n"; }
ok()   { log "\033[1;32m[ OK ]\033[0m $*\n"; }
err()  { log "\033[1;31m[ERR ]\033[0m $*\n"; }

# Prepare log dir if set
if [[ -n "$LOG_FILE" ]]; then mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true; fi

# Error diagnostics
trap 'err "Failed: \"$BASH_COMMAND\" at ${BASH_SOURCE[0]}:${LINENO}"' ERR

# Privilege helper
SUDO() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    err "Need root for: $* (sudo not available)"; return 1
  fi
}

# Exec helper (no bash -c), respects CLEAN_OUTPUT and LOG_FILE
exec_run() {
  if [[ -n "$LOG_FILE" ]]; then
    if (( CLEAN_OUTPUT )); then "$@" >>"$LOG_FILE" 2>&1; else "$@" 2>&1 | tee -a "$LOG_FILE"; fi
  else
    if (( CLEAN_OUTPUT )); then "$@" >/dev/null 2>&1; else "$@"; fi
  fi
}

# Temp files + cleanup
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

# ------------------------------------------------------------------------------
# Newline-safe block writer (prevents extra blank lines on reruns)
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

  # strip all leading blank lines (defensive)
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

# Exact-marker upsert (for .bashrc)
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

# Greedy Vim upsert: remove FIRST start token..LAST end token, then append once
upsert_vim_block() {
  local file="$1" body="$2"
  [[ -f "$file" ]] || : > "$f"
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

# Generic greedy token-based upsert (for .bashrc blocks)
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

# Detect OS
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

# Packages (no EPEL)
install_packages_common() {
  mkdir -p "$HOME/.config/yamllint" "$HOME/files" "$VIM_DIR" "$VIM_DIR/autoload" "$VIM_DIR/bundle" \
           "$HOME/.local/share" "$BLE_DIR" "$BLE_BUILD_DIR" "$USER_BASH_COMPLETION_DIR" || true
  chmod 0755 "$HOME/.config" "$HOME/.config/yamllint" "$HOME/files" "$VIM_DIR" "$HOME/.local/share" \
             "$BLE_DIR" "$BLE_BUILD_DIR" "$USER_BASH_COMPLETION_DIR" || true
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

# fzf fallback (user-scope) if system package missing
ensure_fzf_user() {
  if command -v fzf >/dev/null 2>&1; then info "fzf found in PATH"; return 0; fi
  if [[ -d "$HOME/.fzf" ]]; then info "fzf directory exists at ~/.fzf (assuming installed)"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then warn "git missing; cannot install fzf user-scope"; return 0; fi
  info "Installing fzf to ~/.fzf (user-scope; no EPEL)"
  exec_run git clone -q --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  exec_run "$HOME/.fzf/install" --key-bindings --completion --no-update-rc
  ok "fzf installed to ~/.fzf"
}

# -------------------- FALLBACKS (no EPEL): yamllint & fonts -------------------
ensure_pip() {
  if python3 -m pip --version >/dev/null 2>&1; then return 0; fi
  if python3 -m ensurepip --version >/dev/null 2>&1; then exec_run python3 -m ensurepip --upgrade; fi
  if ! python3 -m pip --version >/dev/null 2>&1; then
    if [[ "$OS_FAMILY" == "redhat" ]]; then
      if command -v dnf >/dev/null 2>&1; then exec_run SUDO dnf -y -q install python3-pip || true
      else exec_run SUDO yum -y -q install python3-pip || true
      fi
    else
      exec_run SUDO apt-get -qq -y install python3-pip
    fi
  fi
  python3 -m pip --version >/dev/null 2>&1 || { err "pip not available"; return 1; }
}

# --- argcomplete (user-scope) ---
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
    importlib.import_module("argcomplete"); sys.exit(0)
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

ensure_yamllint_user() {
  if command -v yamllint >/dev/null 2>&1; then
    ok "yamllint already present: $(command -v yamllint)"
    return 0
  fi
  ensure_pip || { warn "pip unavailable; cannot install yamllint user-scope"; return 1; }
  exec_run python3 -m pip install --user --upgrade yamllint || { warn "Failed installing yamllint via pip"; return 1; }
  case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *)
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/.local/bin:$PATH"
    info "Added ~/.local/bin to PATH"
  esac
  if command -v yamllint >/dev/null 2>&1; then ok "yamllint installed (user)"; else err "yamllint not found after install"; fi
}

# --- Nerd Fonts: detect + install (user-scope, idempotent) ---
font_installed() {
  local family="${1:-FiraCode Nerd Font}"
  if command -v fc-list >/dev/null 2>&1; then
    if fc-list : family | grep -iFq "$family"; then return 0; fi
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
    info "Nerd Font already present: $family (skipping download)"
    return 0
  fi

  info "Installing Nerd Font (user-scope): $family"
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
  if font_installed "$family"; then ok "Installed Nerd Font: $family"; else warn "Font not visible yet: $family"; fi
}
ensure_powerline_glyphs() {
  local family="${1:-FiraCode Nerd Font}"
  local zip="${2:-FiraCode.zip}"
  if command -v fc-list >/dev/null 2>&1 && fc-list : family | grep -qiE 'Nerd Font|Powerline'; then
    info "Powerline/Nerd fonts already available (fontconfig)"; return 0
  fi
  if fc-list : family 2>/dev/null | grep -qi 'Powerline'; then
    info "Powerline fonts detected via system fontconfig"; return 0
  fi
  install_nerd_fonts_user "$family" "$zip"
}

# Vim
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

# --- managed Vim block (body-only; markers added by upsert_vim_block) ---
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

# Yamllint config
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

# --- Bashrc blocks (token-based greedy upsert) ---
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
ble_bashrc_block() {
cat <<'EOF'
# --- ble.sh (Fish-like UX in Bash) ---
# Load only if present AND only in interactive shells, tune once
if [[ $- == *i* ]] && [[ -r "$HOME/.local/share/blesh/ble.sh" ]]; then
  # shellcheck source=$HOME/.local/share/blesh/ble.sh disable=SC1090
  source "$HOME/.local/share/blesh/ble.sh" --noattach
  ble-attach >/dev/null 2>&1
  if [[ -z "${BLESH_TUNED:-}" ]]; then
    if declare -F bleopt >/dev/null 2>&1; then
      bleopt accept-line:char=^M >/dev/null 2>&1
      bleopt edit_abell=1        >/dev/null 2>&1
      bleopt complete_menu_style=desc >/dev/null 2>&1
      bleopt highlight_syntax=always >/dev/null 2>&1
    fi
    if declare -F ble-face >/dev/null 2>&1; then
      ble-face -s autosuggest=fg=242 >/dev/null 2>&1
    fi
    BLESH_TUNED=1
  fi
fi

# enable bash-completion if available (system)
if [[ -r /usr/share/bash-completion/bash_completion ]]; then
  # shellcheck source=/usr/share/bash-completion/bash_completion
  . /usr/share/bash-completion/bash_completion
fi

# fzf keybindings + completion (system: Debian vs Fedora layout)
if [[ -r /usr/share/fzf/completion.bash ]]; then
  # shellcheck source=/usr/share/fzf/completion.bash
  source /usr/share/fzf/completion.bash
elif [[ -r /usr/share/fzf/shell/completion.bash ]]; then
  # shellcheck source=/usr/share/fzf/shell/completion.bash
  source /usr/share/fzf/shell/completion.bash
fi

if [[ -r /usr/share/fzf/key-bindings.bash ]]; then
  # shellcheck source=/usr/share/fzf/key-bindings.bash
  source /usr/share/fzf/key-bindings.bash
elif [[ -r /usr/share/fzf/shell/key-bindings.bash ]]; then
  # shellcheck source=/usr/share/fzf/shell/key-bindings.bash
  source /usr/share/fzf/shell/key-bindings.bash
fi

# fzf user-scope integration (if installed via ~/.fzf/install)
if [[ -r "$HOME/.fzf/shell/completion.bash" ]]; then
  # shellcheck source=$HOME/.fzf/shell/completion.bash disable=SC1090
  source "$HOME/.fzf/shell/completion.bash"
fi
if [[ -r "$HOME/.fzf/shell/key-bindings.bash" ]]; then
  # shellcheck source=$HOME/.fzf/shell/key-bindings.bash disable=SC1090
  source "$HOME/.fzf/shell/key-bindings.bash"
fi

# user-scope argcomplete (generated in ~/.bash_completion.d)
if [[ $- == *i* ]] && [[ -d "$HOME/.bash_completion.d" ]]; then
  for f in "$HOME"/.bash_completion.d/*; do
    [[ -r "$f" ]] && . "$f"
  done
fi

# carapace (optional; put 'carapace' on PATH first)
command -v carapace >/dev/null && eval "$(carapace _carapace)"
EOF
}
install_bashrc_block() {
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
install_ble_bashrc_block() {
  local f="$HOME/.bashrc"
  [[ -f "$f" ]] || : > "$f"
  upsert_block_by_token \
    "$f" \
    "BLE_SH_START" \
    "BLE_SH_END" \
    "# >>> BLE_SH_START >>>" \
    "# <<< BLE_SH_END <<<" \
    "$(ble_bashrc_block)"
}

# ble.sh
install_ble() {
  command -v git  >/dev/null 2>&1 || { err "git required for ble.sh"; exit 1; }
  (command -v gawk >/dev/null 2>&1 || command -v awk >/dev/null 2>&1) || { err "gawk/awk required for ble.sh"; exit 1; }
  command -v make >/dev/null 2>&1 || { err "make required for ble.sh"; exit 1; }
  if [[ -d "$BLE_BUILD_DIR/.git" ]]; then
    info "Updating ble.sh in $BLE_BUILD_DIR"
    exec_run git -C "$BLE_BUILD_DIR" pull -q --ff-only || true
  else
    exec_run mkdir -p "$(dirname "$BLE_BUILD_DIR")"
    info "Cloning ble.sh"
    exec_run git clone -q --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git "$BLE_BUILD_DIR"
  fi
  local prefix="$HOME/.local"
  info "Installing ble.sh to $prefix"
  exec_run make -s -C "$BLE_BUILD_DIR" install PREFIX="$prefix"
  [[ -r "$HOME/.local/share/blesh/ble.sh" ]] || { err "ble.sh install failed"; exit 1; }
  ok "ble.sh installed."
}

# Python linters (+ PATH handling + reinstall + verify)
install_python_linters() {
  ensure_pip || return 1
  local ruff_spec="ruff";   [[ -n "$RUFF_VERSION"   ]] && ruff_spec="ruff==${RUFF_VERSION}"
  local pyl_spec="pylint";  [[ -n "$PYLINT_VERSION" ]] && pyl_spec="pylint==${PYLINT_VERSION}"
  info "Installing Python linters: ${ruff_spec} ${pyl_spec} (user-scope)"
  exec_run python3 -m pip install --user --upgrade ${ruff_spec} ${pyl_spec}

  # Ensure ~/.local/bin on PATH (one-off + persist)
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *)
      export PATH="$HOME/.local/bin:$PATH"
      info "Added ~/.local/bin to PATH (current shell)"
      if ! grep -qE '(^|:)\$HOME/\.local/bin(:|$)|(^|:)~/.local/bin(:|$)' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        info "Appended PATH export to ~/.bashrc"
      fi
      hash -r || true
      ;;
  esac

  # If still missing, reinstall explicitly with pinned versions
  if ! command -v ruff >/dev/null 2>&1 || ! command -v pylint >/dev/null 2>&1; then
    warn "ruff/pylint not visible yet; reinstalling explicitly to user site"
    local re_ruff="ruff"; [[ -n "$RUFF_VERSION" ]] && re_ruff="ruff==${RUFF_VERSION}"
    local re_pyl="pylint"; [[ -n "$PYLINT_VERSION" ]] && re_pyl="pylint==${PYLINT_VERSION}"
    exec_run python3 -m pip install --user --upgrade "$re_ruff" "$re_pyl"
    hash -r || true
  fi

  # Verify
  if command -v ruff >/dev/null 2>&1; then
    ok "ruff installed ($(ruff --version 2>/dev/null | awk '{print $2}'))"
  else
    warn "ruff missing (ensure ~/.local/bin is on PATH)"
  fi
  if command -v pylint >/dev/null 2>&1; then
    ok "pylint installed ($(pylint --version 2>/dev/null | awk 'NR==1{print $2}'))"
  else
    warn "pylint missing (ensure ~/.local/bin is on PATH)"
  fi
}

# Bash linters
install_bash_linters() {
  info "Installing Bash linters (shellcheck, shfmt)"
  if [[ "$OS_FAMILY" == "redhat" ]]; then
    if command -v dnf >/dev/null 2>&1; then
      exec_run SUDO dnf -y -q install shellcheck || warn "shellcheck not available in base repos"
      exec_run SUDO dnf -y -q install shfmt      || warn "shfmt not available in base repos"
    else
      exec_run SUDO yum -y -q install shellcheck || warn "shellcheck not available in base repos"
      exec_run SUDO yum -y -q install shfmt      || warn "shfmt not available in base repos"
    fi
  else
    exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install shellcheck || warn "shellcheck not available"
    exec_run SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq -y install shfmt      || warn "shfmt not available"
  fi
  command -v shellcheck >/dev/null 2>&1 && ok "shellcheck installed" || warn "shellcheck missing (consider manual install)"
  command -v shfmt      >/dev/null 2>&1 && ok "shfmt installed"      || warn "shfmt missing (consider manual install)"
}

# Arch detection + safe fetch
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
fetch() { # fetch <url> <dest>
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 -H 'User-Agent: dev-bootstrap/1.0' -o "$2" "$1"
}

# kubectl + oc installers (to /usr/local/bin or ~/.local/bin) + bash-completions
install_oc_kubectl() {
  detect_arch
  local sysbindir="/usr/local/bin"
  local userbindir="$HOME/.local/bin"
  local bindir
  bindir="$sysbindir"

  if ! SUDO test -w "$sysbindir" >/dev/null 2>&1; then
    bindir="$userbindir"
    mkdir -p "$bindir"
    case ":$PATH:" in *":$bindir:"*) : ;; *)
      warn "Add $bindir to PATH: export PATH=\"$bindir:\$PATH\""
    esac
    info "Using user install dir $bindir (no root write)."
  fi

  local kubectl_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K_ARCH}/kubectl"
  local oc_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_CHANNEL}/openshift-client-linux.tar.gz"

  # kubectl
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

  # oc
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

  # completions (user-scope)
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

# Repo tooling (Makefile + .shellcheckrc) next to this script
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

# Source bashrc safely
safe_source_bashrc() {
  if [[ -r "$HOME/.bashrc" ]]; then
    set +u; BASHRCSOURCED=1; . "$HOME/.bashrc" || true; set -u
  else
    warn "~/.bashrc not found; skipping source."
  fi
}

# Main
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

  ensure_fzf_user

  if [[ "$ENABLE_VIM_PLUGINS" -eq 1 ]]; then ensure_pathogen; deploy_plugins; else warn "Skipping Vim plugins."; fi
  if [[ "$ENABLE_VIMRC" -eq 1 ]]; then install_vimrc_block; else warn "Skipping ~/.vimrc block."; fi
  if [[ "$ENABLE_YAMLLINT" -eq 1 ]]; then install_yamllint_conf; else warn "Skipping yamllint config."; fi

  if [[ "$ENABLE_BASHRC" -eq 1 ]]; then install_bashrc_block; else warn "Skipping ~/.bashrc history/prompt block."; fi
  if [[ "$ENABLE_BLE" -eq 1 ]]; then install_ble; install_ble_bashrc_block; else warn "Skipping ble.sh."; fi

  if [[ "$ENABLE_ARGCOMPLETE" -eq 1 ]]; then
    if declare -F install_argcomplete >/dev/null 2>&1; then
      install_argcomplete
    else
      warn "install_argcomplete() missing; skipping argcomplete."
    fi
  fi

  if [[ "$ENABLE_BASH_LINTERS" -eq 1 ]]; then install_bash_linters; else warn "Skipping bash linters."; fi
  if [[ "$ENABLE_PY_LINTERS" -eq 1 ]]; then install_python_linters; else warn "Skipping python linters."; fi

  if [[ "$ENABLE_KUBECTL_OC" -eq 1 ]]; then install_oc_kubectl; else warn "Skipping kubectl/oc install."; fi
  if [[ "$ENABLE_REPO_TOOLING" -eq 1 ]]; then write_repo_tooling; else warn "Skipping repo tooling."; fi

  ok "All done. Sourcing ~/.bashrc now (safe)."
  safe_source_bashrc
  ok "Done. For a fresh session, run: exec bash -l"
}

main
