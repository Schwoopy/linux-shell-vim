#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Dev Bootstrap (Non-Interactive)
# ==============================================================================

# Toggles
ENABLE_PACKAGES=1
ENABLE_VIM_PLUGINS=1
ENABLE_VIMRC=1
ENABLE_YAMLLINT=1
ENABLE_BASHRC=1
ENABLE_BLE=1
ENABLE_ARGCOMPLETE=1
ENABLE_BASH_LINTERS=1
ENABLE_PY_LINTERS=1

# Output & logging
CLEAN_OUTPUT=1
ENABLE_TTY_PROGRESS=1
SHOW_OVERALL_PROGRESS=1
LOG_FILE=""

# Paths
VIM_DIR="$HOME/.vim"
YAMLLINT_CONF="$HOME/.config/yamllint/config"
BLE_DIR="$HOME/.local/share/blesh"
BLE_BUILD_DIR="$HOME/.local/src/ble.sh"
USER_BASH_COMPLETION_DIR="$HOME/.bash_completion.d"

# Packages per distro
PACKAGES_RHEL_BASE=(vim-enhanced git powerline-fonts fzf yamllint curl make gawk bash-completion python3 python3-pip)
PACKAGES_DEBIAN_BASE=(vim git fonts-powerline fzf yamllint curl make gawk bash-completion python3 python3-pip)

# Python linter versions
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"

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

# Progress weights
WEIGHT_DETECT=5
WEIGHT_DIRS=10
WEIGHT_PACKAGES=28
WEIGHT_PATHOGEN=4
WEIGHT_PLUGINS=18
WEIGHT_VIMRC=4
WEIGHT_YAMLLINT=4
WEIGHT_BASHRC=8
WEIGHT_BLE=6
WEIGHT_ARGCOMPLETE=6
WEIGHT_LINTERS_BASH=4
WEIGHT_LINTERS_PY=3

# ------------------------------- Logging -------------------------------------
_have_tty() { [[ -t 1 ]] || [[ -w /dev/tty ]]; }
_to_tty()   { if [[ -w /dev/tty ]]; then printf "%b" "$*" > /dev/tty; else printf "%b" "$*"; fi; }
_logfile()  { if [[ -n "$LOG_FILE" ]]; then printf "%b" "$*" >> "$LOG_FILE"; fi; }
log()  { _to_tty "$*"; _logfile "$*"; }
info() { log "\033[1;34m[INFO]\033[0m $*\n"; }
warn() { log "\033[1;33m[WARN]\033[0m $*\n"; }
ok()   { log "\033[1;32m[ OK ]\033[0m $*\n"; }
err()  { log "\033[1;31m[ERR ]\033[0m $*\n"; }

# -------------------------- Overall progress bar -----------------------------
TOTAL_WEIGHT=$(( WEIGHT_DETECT + WEIGHT_DIRS + WEIGHT_PACKAGES + WEIGHT_PATHOGEN + WEIGHT_PLUGINS + WEIGHT_VIMRC + WEIGHT_YAMLLINT + WEIGHT_BASHRC + WEIGHT_BLE + WEIGHT_ARGCOMPLETE + WEIGHT_LINTERS_BASH + WEIGHT_LINTERS_PY ))
(( TOTAL_WEIGHT <= 0 )) && TOTAL_WEIGHT=100
PROGRESS_ACC=0
_progress_draw() {
  [[ "$SHOW_OVERALL_PROGRESS" -eq 1 ]] || return 0
  local pct=$1 width=${PROGRESS_WIDTH:-40}
  (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
  local fill=$(( (pct * width) / 100 )); local empty=$(( width - fill ))
  _to_tty "\r[$(printf "%${fill}s" "" | tr ' ' '#')$(printf "%${empty}s" "" | tr ' ' '-')]" \
          " ${pct}%"
}
progress_step_done() {
  PROGRESS_ACC=$(( PROGRESS_ACC + $1 ))
  local pct=$(( (PROGRESS_ACC * 100) / TOTAL_WEIGHT ))
  _progress_draw "$pct"; if (( PROGRESS_ACC >= TOTAL_WEIGHT )); then _to_tty "\n"; else _to_tty " "; fi
}

# ------------------------------ Exec helpers ---------------------------------
run_tty() {
  local cmd="$*"
  if [[ "$ENABLE_TTY_PROGRESS" -eq 1 ]] && command -v script >/dev/null 2>&1; then
    if [[ -n "$LOG_FILE" ]]; then
      if _have_tty; then script -qfc "$cmd" /dev/null 2>&1 | tee -a "$LOG_FILE" >/dev/tty; else script -qfc "$cmd" /dev/null 2>&1 | tee -a "$LOG_FILE"; fi
    else
      if _have_tty; then script -qfc "$cmd" /dev/null >/dev/tty 2>&1; else script -qfc "$cmd" /dev/null; fi
    fi
  else
    if [[ -n "$LOG_FILE" ]]; then
      if _have_tty; then bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE" >/dev/tty; else bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"; fi
    else bash -c "$cmd"; fi
  fi
}
run_quiet() { if [[ "$ENABLE_TTY_PROGRESS" -eq 1 ]] && command -v script >/dev/null 2>&1; then bash -c "script -qfc '$*' /dev/null" 1>/dev/null; else bash -c "$*" 1>/dev/null; fi; }
run_cmd() { if [[ "${CLEAN_OUTPUT:-0}" -eq 1 ]]; then run_quiet "$*"; else run_tty "$*"; fi; }

backup_file() { local f="$1"; if [[ -f "$f" || -L "$f" ]]; then local ts; ts="$(date +%Y%m%d_%H%M%S)"; run_cmd "cp -a '$f' '${f}.bak.${ts}'"; info "Backed up $f -> ${f}.bak.${ts}"; fi; }

# Replace or append a delimited block in a file (idempotent, awk-free)
upsert_block() {
  local file="$1" start="$2" end="$3" content="$4"

  # ensure file exists
  [[ -f "$file" ]] || : > "$file"
  backup_file "$file"

  # Escape for sed (/, \, &, [, ], ., *, ^, $)
  _sed_escape() { printf '%s' "$1" | sed -e 's/[\/&[\].*^$\\]/\\&/g'; }

  local s_esc e_esc
  s_esc=$(_sed_escape "$start")
  e_esc=$(_sed_escape "$end")

  # 1) remove ALL existing blocks (handles duplicates, even nested)
  #    - delete from a line matching start to the next line matching end
  local tmp; tmp="$(mktemp)"
  sed -e "/^${s_esc}\$/,/^${e_esc}\$/d" "$file" > "$tmp"

  # 2) append one clean block at EOF
  {
    cat "$tmp"
    printf '\n%s\n' "$start"
    printf '%s\n' "$content"
    printf '%s\n\n' "$end"
  } > "$file"

  rm -f "$tmp"
  ok "Updated $file ($start)"
}


# ------------------------------- Detection -----------------------------------
detect_os() {
  . /etc/os-release 2>/dev/null || { err "Missing /etc/os-release"; exit 1; }
  local id_like="${ID_LIKE:-}"
  if [[ "$ID" =~ (rhel|rocky|almalinux|centos|fedora) ]] || [[ "$id_like" =~ (rhel|fedora) ]]; then OS_FAMILY="redhat"
  elif [[ "$ID" =~ (debian|ubuntu|raspbian|linuxmint) ]] || [[ "$id_like" =~ (debian|ubuntu) ]]; then OS_FAMILY="debian"
  else OS_FAMILY="debian"; warn "Unknown distro; assuming Debian-like."; fi
  info "OS family: $OS_FAMILY (ID=${ID})"
}

# ------------------------------- Packages ------------------------------------
install_packages_common() {
  mkdir -p "$HOME/.config/yamllint" "$HOME/files" "$VIM_DIR" "$VIM_DIR/autoload" "$VIM_DIR/bundle" "$HOME/.local/share" "$BLE_DIR" "$BLE_BUILD_DIR" "$USER_BASH_COMPLETION_DIR" || true
  chmod 0755 "$HOME/.config" "$HOME/.config/yamllint" "$HOME/files" "$VIM_DIR" "$HOME/.local/share" "$BLE_DIR" "$BLE_BUILD_DIR" "$USER_BASH_COMPLETION_DIR" || true
  chmod 0750 "$VIM_DIR" "$VIM_DIR/autoload" "$VIM_DIR/bundle" || true
}
install_packages() {
  install_packages_common
  if [[ "$OS_FAMILY" == "redhat" ]]; then
    local installer="sudo dnf -y -q"; command -v dnf >/dev/null 2>&1 || installer="sudo yum -y -q"
    if [[ "${CLEAN_OUTPUT:-0}" -eq 1 ]]; then ( $installer install epel-release ) >/dev/null 2>&1 || true; ( $installer install bash-completion-extras fzf ) >/dev/null 2>&1 || true
    else run_tty "$installer install epel-release" || true; run_tty "$installer install bash-completion-extras fzf" || true; fi
    run_cmd "$installer install ${PACKAGES_RHEL_BASE[*]}"
  else
    local aptu="sudo apt-get -qq update"; local apti="sudo DEBIAN_FRONTEND=noninteractive apt-get -qq -y install"
    if [[ "${CLEAN_OUTPUT:-0}" -eq 1 ]]; then run_quiet "$aptu"; run_quiet "$apti ${PACKAGES_DEBIAN_BASE[*]}"
    else run_tty "sudo apt-get update -y -o Dpkg::Progress-Fancy=1"; run_tty "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${PACKAGES_DEBIAN_BASE[*]} -o Dpkg::Progress-Fancy=1"; fi
  fi
  ok "Packages installed."
}

# ---------------------------------- Vim --------------------------------------
ensure_pathogen() {
  local dest="$VIM_DIR/autoload/pathogen.vim"; [[ -f "$dest" ]] && { info "Pathogen present."; return 0; }
  command -v curl >/dev/null 2>&1 || { err "curl is required"; exit 1; }
  run_cmd "curl -fsSLo '$dest' https://tpo.pe/pathogen.vim"; ok "Pathogen installed."
}

deploy_plugins() {
  command -v git >/dev/null 2>&1 || { err "git is required"; exit 1; }
  local line="" name="" url="" dest=""
  while IFS= read -r line; do
    # strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    # require "name=url"
    if [[ "$line" != *"="* ]]; then
      warn "Skipping malformed plugin line: $line"; continue
    fi
    name="${line%%=*}"; url="${line#*=}"
    # guard nounset / empties
    [[ -z "${name:-}" || -z "${url:-}" ]] && { warn "Skipping broken entry: $line"; continue; }
    dest="$VIM_DIR/bundle/$name"
    if [[ -d "$dest/.git" ]]; then
      run_cmd "git -C '$dest' pull -q --ff-only || true"
    else
      run_cmd "git clone -q --depth 1 '$url' '$dest'"
    fi
  done <<< "$VIM_PLUGIN_LIST"
  ok "Vim plugins ready."
}

write_default_vimrc() {
cat <<'EOF'
" --- Managed by install_vimrc_etc.sh ---
execute pathogen#infect()
syntax on
filetype plugin indent on

set number
set relativenumber
set tabstop=2 shiftwidth=2 expandtab
set cursorline
set termguicolors
set background=dark
colorscheme shades_of_purple

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
install_vimrc() { local f="$HOME/.vimrc"; backup_file "$f"; write_default_vimrc > "$f"; chmod 0640 "$f" || true; ok "~/.vimrc installed."; }

# -------------------------------- Yamllint -----------------------------------
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
install_yamllint_conf() { mkdir -p "$(dirname "$YAMLLINT_CONF")"; backup_file "$YAMLLINT_CONF"; write_default_yamllint > "$YAMLLINT_CONF"; chmod 0640 "$YAMLLINT_CONF" || true; ok "Yamllint config installed."; }

# --------------------------------- Bashrc ------------------------------------
eternal_history_block() {
cat <<'EOF'
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE=~/.bash_eternal_history
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
HISTCONTROL=erasedups

parse_git_branch() {
  git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
}

export PS1="╭─╼[\[\e[1;36m\]\w\[\e[0m\]]-(\`if [ \$? = 0 ]; then echo \[\e[32m\]1\[\e[0m\]; else echo \[\e[31m\]0\[\e[0m\]; fi\`)-[\[\e[1;32m\]\h\[\e[0m\]]\n╰─ \u\$(if git rev-parse --git-dir > /dev/null 2>&1; then echo '@git:('; fi)\[\e[1;34m\]\$(parse_git_branch)\[\e[0m\]\$(if git rev-parse --git-dir > /dev/null 2>&1; then echo ')'; fi) >> "
PROMPT_DIRTRIM=2
EOF
}
ble_bashrc_block() {
cat <<'EOF'
# --- ble.sh (Fish-like UX in Bash) ---
# Load only if present AND only in interactive shells, tune once
if [[ $- == *i* ]] && [[ -s ~/.local/share/blesh/ble.sh ]]; then
  source ~/.local/share/blesh/ble.sh --noattach
  ble-attach >/dev/null 2>&1
  if [[ -z "${BLESH_TUNED:-}" ]]; then
    if declare -F bleopt >/dev/null 2>&1; then
      bleopt accept-line:char=^M >/dev/null 2>&1
      bleopt edit_abell=1        >/dev/null 2>&1
      # bleopt prompt_ruler=none   >/dev/null 2>&1
      bleopt complete_menu_style=desc >/dev/null 2>&1
      bleopt highlight_syntax=always >/dev/null 2>&1
    fi
    if declare -F ble-face >/dev/null 2>&1; then
      ble-face -s autosuggest=fg=242 >/dev/null 2>&1
    fi
    BLESH_TUNED=1
  fi
fi

[[ -r /usr/share/bash-completion/bash_completion ]] && \
  . /usr/share/bash-completion/bash_completion

[[ -r /usr/share/fzf/completion.bash ]]    && source /usr/share/fzf/completion.bash
[[ -r /usr/share/fzf/key-bindings.bash ]]  && source /usr/share/fzf/key-bindings.bash

if [[ $- == *i* ]] && [ -d ~/.bash_completion.d ]; then
  for f in ~/.bash_completion.d/*; do
    [ -r "$f" ] && . "$f"
  done
fi

command -v carapace >/dev/null && eval "$(carapace _carapace)"
EOF
}
install_bashrc_block() { upsert_block "$HOME/.bashrc" "# >>> ETERNAL_HISTORY_AND_GIT_PROMPT_START >>>" "# <<< ETERNAL_HISTORY_AND_GIT_PROMPT_END <<<" "$(eternal_history_block)"; }
install_ble_bashrc_block() { upsert_block "$HOME/.bashrc" "# >>> BLE_SH_START >>>" "# <<< BLE_SH_END <<<" "$(ble_bashrc_block)"; }

# --------------------------------- ble.sh ------------------------------------
install_ble() {
  command -v git >/dev/null 2>&1 || { err "git required for ble.sh"; exit 1; }
  command -v gawk >/dev/null 2>&1 || command -v awk >/dev/null 2>&1 || { err "gawk/awk required for ble.sh"; exit 1; }
  command -v make >/dev/null 2>&1 || { err "make required for ble.sh"; exit 1; }
  if [[ -d "$BLE_BUILD_DIR/.git" ]]; then info "Updating ble.sh in $BLE_BUILD_DIR"; run_cmd "git -C '$BLE_BUILD_DIR' pull -q --ff-only || true"
  else run_cmd "mkdir -p '$(dirname "$BLE_BUILD_DIR")'"; info "Cloning ble.sh"; run_cmd "git clone -q --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git '$BLE_BUILD_DIR'"; fi
  local prefix="$HOME/.local"; info "Installing ble.sh to $prefix"; run_cmd "make -s -C '$BLE_BUILD_DIR' install PREFIX='$prefix'"
  [[ -r "$HOME/.local/share/blesh/ble.sh" ]] || { err "ble.sh install failed"; exit 1; }
  ok "ble.sh installed."
}

# ----------------------------- pip / argcomplete -----------------------------
ensure_pip() {
  command -v pip3 >/dev/null 2>&1 && return 0
  if python3 -m ensurepip --version >/dev/null 2>&1; then run_cmd "python3 -m ensurepip --upgrade"; fi
  if ! command -v pip3 >/dev/null 2>&1; then
    if [[ "$OS_FAMILY" == "redhat" ]]; then local installer="sudo dnf -y -q"; command -v dnf >/dev/null 2>&1 || installer="sudo yum -y -q"; run_cmd "$installer install python3-pip" || true
    else run_cmd "sudo apt-get -qq -y install python3-pip"; fi
  fi
  command -v pip3 >/dev/null 2>&1 || { err "pip3 not available"; return 1; }
}
install_argcomplete() {
  ensure_pip || return 1
  run_cmd "pip3 install --user --upgrade pip"
  run_cmd "pip3 install --user argcomplete"
  mkdir -p "$USER_BASH_COMPLETION_DIR"
  if command -v activate-global-python-argcomplete >/dev/null 2>&1; then
    run_cmd "activate-global-python-argcomplete --dest '$USER_BASH_COMPLETION_DIR'"
    ok "argcomplete activated (user-scope)"
  else
    python3 - <<'PY' 2>/dev/null || { warn "argcomplete not importable; skipping user loader"; return 0; }
import importlib; importlib.import_module("argcomplete")
PY
    cat > "$USER_BASH_COMPLETION_DIR/python-argcomplete.sh" <<'EOS'
# user-scope argcomplete loader
if command -v register-python-argcomplete >/dev/null 2>&1; then
  for cmd in pip pip3 python3 git kubectl terraform ansible ansible-playbook; do
    if command -v "$cmd" >/dev/null 2>&1; then
      eval "$(register-python-argcomplete "$cmd")"
    fi
  done
fi
EOS
    ok "argcomplete user loader created"
  fi
}

# ------------------------------- Linters -------------------------------------
install_bash_linters() {
  info "Installing Bash linters (shellcheck, shfmt)"
  if [[ "$OS_FAMILY" == "redhat" ]]; then
    local installer="sudo dnf -y -q"; command -v dnf >/dev/null 2>&1 || installer="sudo yum -y -q"
    if [[ "${CLEAN_OUTPUT:-0}" -eq 1 ]]; then ( $installer install shellcheck ) >/dev/null 2>&1 || warn "shellcheck not in repos"; ( $installer install shfmt ) >/dev/null 2>&1 || warn "shfmt not in repos"
    else run_tty "$installer install shellcheck" || warn "shellcheck not in repos"; run_tty "$installer install shfmt" || warn "shfmt not in repos"; fi
  else
    local apti="sudo DEBIAN_FRONTEND=noninteractive apt-get -qq -y install"
    if [[ "${CLEAN_OUTPUT:-0}" -eq 1 ]]; then run_quiet "$apti shellcheck" || warn "shellcheck not in repos"; run_quiet "$apti shfmt" || warn "shfmt not in repos"
    else run_tty "sudo apt-get update -y -o Dpkg::Progress-Fancy=1"; run_tty "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y shellcheck shfmt -o Dpkg::Progress-Fancy=1" || warn "shellcheck/shfmt not available"; fi
  fi
  command -v shellcheck >/dev/null 2>&1 && ok "shellcheck installed" || warn "shellcheck missing"
  command -v shfmt      >/dev/null 2>&1 && ok "shfmt installed"      || warn "shfmt missing"
}
install_python_linters() {
  ensure_pip || return 1
  local ruff_spec="ruff"; [[ -n "${RUFF_VERSION}" ]] && ruff_spec="ruff==${RUFF_VERSION}"
  local pylint_spec="pylint"; [[ -n "${PYLINT_VERSION}" ]] && pylint_spec="pylint==${PYLINT_VERSION}"
  info "Installing Python linters: ${ruff_spec} ${pylint_spec}"
  run_cmd "pip3 install --user --upgrade ${ruff_spec} ${pylint_spec}"
  command -v ruff >/dev/null 2>&1 && ok "ruff installed ($(ruff --version 2>/dev/null | awk '{print $2}'))" || warn "ruff missing"
  command -v pylint >/dev/null 2>&1 && ok "pylint installed ($(pylint --version 2>/dev/null | awk 'NR==1{print $2}'))" || warn "pylint missing"
  case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) warn "Add ~/.local/bin to PATH for ruff/pylint: export PATH=\$HOME/.local/bin:\$PATH" ;; esac
}

# ----------------------------- Safe bashrc source ----------------------------
safe_source_bashrc() {
  if [[ -r "$HOME/.bashrc" ]]; then
    set +u; BASHRCSOURCED=1; . "$HOME/.bashrc" || true; set -u
  else warn "~/.bashrc not found; skipping source."; fi
}

# ---------------------------------- Main -------------------------------------
main() {
  info "Dev Bootstrap starting"
  detect_os;                     progress_step_done "$WEIGHT_DETECT"
  install_packages_common;       progress_step_done "$WEIGHT_DIRS"

  if [[ "$ENABLE_PACKAGES" -eq 1 ]]; then install_packages; else warn "Skipping packages."; fi
  progress_step_done "$WEIGHT_PACKAGES"

  if [[ "$ENABLE_VIM_PLUGINS" -eq 1 ]]; then ensure_pathogen; progress_step_done "$WEIGHT_PATHOGEN"; deploy_plugins; progress_step_done "$WEIGHT_PLUGINS"
  else warn "Skipping Vim plugins."; progress_step_done "$WEIGHT_PATHOGEN"; progress_step_done "$WEIGHT_PLUGINS"; fi

  if [[ "$ENABLE_VIMRC" -eq 1 ]]; then install_vimrc; else warn "Skipping ~/.vimrc."; fi
  progress_step_done "$WEIGHT_VIMRC"

  if [[ "$ENABLE_YAMLLINT" -eq 1 ]]; then install_yamllint_conf; else warn "Skipping yamllint config."; fi
  progress_step_done "$WEIGHT_YAMLLINT"

  if [[ "$ENABLE_BASHRC" -eq 1 ]]; then install_bashrc_block; else warn "Skipping ~/.bashrc modification."; fi
  progress_step_done "$WEIGHT_BASHRC"

  if [[ "$ENABLE_BLE" -eq 1 ]]; then install_ble; install_ble_bashrc_block; else warn "Skipping ble.sh."; fi
  progress_step_done "$WEIGHT_BLE"

  if [[ "$ENABLE_ARGCOMPLETE" -eq 1 ]]; then install_argcomplete; else warn "Skipping argcomplete."; fi
  progress_step_done "$WEIGHT_ARGCOMPLETE"

  if [[ "$ENABLE_BASH_LINTERS" -eq 1 ]]; then install_bash_linters; else warn "Skipping bash linters."; fi
  progress_step_done "$WEIGHT_LINTERS_BASH"

  if [[ "$ENABLE_PY_LINTERS" -eq 1 ]]; then install_python_linters; else warn "Skipping python linters."; fi
  progress_step_done "$WEIGHT_LINTERS_PY"

  ok "All done. Sourcing ~/.bashrc now (safe)."
  safe_source_bashrc
  ok "Done. For a fresh session, run: exec bash -l"
}

main
