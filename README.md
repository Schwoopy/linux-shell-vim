# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a development environment consistently across **Debian/Ubuntu** and **RHEL/Rocky Linux** systems.  

It installs and configures common developer tools, Vim plugins, Bash enhancements, and linters — all with **progress feedback** and **safe backup/restore** of user config files.

---

## Features

### 🖥️ Package Installation
- **Debian/Ubuntu**:
  - `vim`, `git`, `fonts-powerline`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`
- **RHEL/Rocky/Fedora**:
  - `vim-enhanced`, `git`, `powerline-fonts`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`
  - Also enables `epel-release` and `bash-completion-extras`

### ✨ Vim Configuration
- Installs **Pathogen** for plugin management
- Installs popular Vim plugins:
  - `vim-airline`, `nerdtree`, `fzf-vim`, `vim-fugitive`, `ale`, `indentLine`, `vim-gitgutter`, `vim-floaterm`, `jinja-4-vim`, `shades-of-purple`
- Generates a pre-configured **`.vimrc`** with sensible defaults

### 🧹 Linters
- **YAML**: installs `yamllint` and generates a config at `~/.config/yamllint/config`
- **Bash**: installs `shellcheck` and `shfmt`
- **Python**: installs `ruff` and `pylint` via `pip` (with version pinning configurable)

### 🕰️ Bash Customizations
- **Eternal Bash History**:
  - Stores unlimited history in `~/.bash_eternal_history`
  - Timestamps each entry
  - Prevents truncation on logout
- **Prompt Enhancements**:
  - Git branch shown inline
  - Success/failure status indicator
- **ble.sh Integration**:
  - Adds autosuggestions, syntax highlighting, and smarter completion
  - Only loaded in interactive shells
- **bash-completion**: enables global and user-scope completions
- **fzf keybindings**: fuzzy search menus
- **argcomplete**: Python CLI tab completion (user-scoped setup)
- **carapace** (optional): rich completions if binary is on PATH

### 📊 Installer Behavior
- Detects OS family automatically
- Installs required packages
- Cleans and replaces existing config blocks in `~/.bashrc` idempotently
- Creates backups of modified files (`~/.bashrc.bak.YYYYMMDD_HHMMSS`)
- Displays a **progress bar** with percentages
- Supports **quiet/clean mode** (suppresses package manager noise)
- Logs to tty (and optionally to a log file)

---

## Usage

### Clone or copy script
```bash
chmod +x install_vimrc_etc.sh
```

### Run directly (non-interactive)
```bash
./install_vimrc_etc.sh
```

---

## After Completion

The script will:

- Update ~/.bashrc with new blocks
- Source ~/.bashrc in the current shell
- Suggest running exec bash -l to start a fully fresh session

---

## Configuration

Edit the top of the script (install_vimrc_etc.sh) to toggle features:

```bash
ENABLE_PACKAGES=1
ENABLE_VIM_PLUGINS=1
ENABLE_VIMRC=1
ENABLE_YAMLLINT=1
ENABLE_BASHRC=1
ENABLE_BLE=1
ENABLE_ARGCOMPLETE=1
ENABLE_BASH_LINTERS=1
ENABLE_PY_LINTERS=1

CLEAN_OUTPUT=1   # suppress package manager/gitrepo noise
SHOW_OVERALL_PROGRESS=1
```

You can also pin Python linter versions:

```bash
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"
```
---

## Safe Defaults

Idempotent: Running multiple times will not duplicate config blocks.

Backups: Every change to ~/.bashrc or config files creates a timestamped backup.

Quiet: All noisy package manager and git output is suppressed by default for clean logs.

Fail-Safe: If a tool is missing or a block is malformed, the script warns but continues.

---

## Requirements

- Bash 4+
- sudo privileges (for package installation)
- git, curl, make, gawk (will be installed automatically if missing)
- Internet access (for Vim plugins, ble.sh, and pip packages)

Example Run
```bash
$ ./install_vimrc_etc.sh
```
```bash
[INFO] Dev Bootstrap starting
[INFO] OS family: debian (ID=ubuntu)
[#################-----------------------] 45%
[INFO] Pathogen installed.
[###############-------------------------] 40%
[ OK ] Vim plugins ready.
[############################------------] 70%
[ OK ] ~/.vimrc installed.
[ OK ] Yamllint config installed.
[ OK ] Updated ~/.bashrc (# >>> ETERNAL_HISTORY_AND_GIT_PROMPT_START >>>)
[ OK ] ble.sh installed.
[ OK ] argcomplete activated (user-scope)
[ OK ] shellcheck installed
[ OK ] shfmt installed
[ OK ] ruff installed (0.6.5)
[ OK ] pylint installed (3.2.6)
[ OK ] All done. Sourcing ~/.bashrc now (safe).
[ OK ] Done. For a fresh session, run: exec bash -l
```

## Troubleshooting

pip3 not found
→ The script tries to install python3-pip. If it still fails, manually install pip.

argcomplete loader skipped
→ If activate-global-python-argcomplete is missing, the script creates a user-scope loader in ~/.bash_completion.d.

Duplicate blocks in .bashrc
→ The script cleans and replaces blocks each run. If you edited them manually, rerun the installer.

Missing tools (shellcheck, shfmt)
→ Some distros may not have these in default repos. Install from upstream if required.

## ToDo

- Adding support for kubectl
- Adding support for Openshift command
- Adding support for HELM