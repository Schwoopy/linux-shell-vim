# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a development environment consistently across **Debian/Ubuntu** and **RHEL/Rocky/Fedora** systems.

It installs and configures common developer tools, Vim plugins, Bash enhancements, Kubernetes CLIs, **Ghostty terminal (Fedora COPR) with Dracula theme**, **tmux (with TPM + Dracula theme + menus/tabs)**, and linters — with **safe append-only config management** (no overwrites) and **clean logging** (no noisy progress bars).

---

## Platform Support & Test Status

* ✅ **Tested**

  * **Fedora 42**

* 🟡 **Pending testing**

  * **RHEL**: 9.x

* ⚠️ **Currently untested**

  * **Rocky Linux**: 9.x
  * **AlmaLinux**: 9.x
  * **Ubuntu**: 22.04 LTS, 24.04 LTS
  * **Debian**: 12 (Bookworm)
  * **Fedora**: 41, 40
  * **Linux Mint**: 21.x
  * **WSL (Ubuntu/Debian)**

> The script is designed to be portable across these families. If something breaks on your distro/version, please open an issue with logs.

---

## Features

### 🖥️ Package Installation (base repos only)

* **Debian/Ubuntu**: `vim`, `git`, `fonts-powerline`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip`, `tmux`
* **RHEL/Rocky/Fedora**: `vim-enhanced`, `git`, `powerline-fonts`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip`, `tmux`

> If `yamllint` or Powerline/Nerd fonts aren’t available, see **Fallback Behavior** below.

### ✨ Vim Configuration

* Installs **Pathogen** and a curated plugin set:
  `vim-airline`, `nerdtree`, `fzf-vim`, `vim-fugitive`, `ale`, `indentLine`, `vim-gitgutter`, `vim-floaterm`, `jinja-4-vim`, `shades-of-purple`
* Appends a managed block to `~/.vimrc` (traditional line numbers, sensible defaults).
* Plugin installs/updates are idempotent and shallow.

### 🔲 tmux Configuration (TPM + Dracula + Menus/Tabs)

* Installs **tmux** from system repositories.
* Installs **TPM** at `~/.tmux/plugins/tpm` (idempotent).
* Appends a managed block to `~/.tmux.conf` that includes:

  * Truecolor (`tmux-256color` + `RGB` overrides), mouse on, history `100000`
  * Vi copy-mode with `y` to yank & exit
  * **“Tabs” UX** (status bar at top, clean formats, Alt+←/→ to switch, `,` to rename, `<`/`>` to move)
  * **Mega-menu** on **Prefix + `m`** (splits, tab actions, sync panes toggle, reload config, kill pane/tab)
  * **Right-click menus** on tabs and panes
  * **Dracula** via TPM (`set -g @plugin 'dracula/tmux'`) with powerline-style status
* Non-interactive plugin install/update via TPM (no keypress needed).
* **No auto-attach**: tmux starts only when you run `tmux`.

### 🧹 Linters

* **YAML**: installs `yamllint` (repo or user fallback) with default config at `~/.config/yamllint/config`
* **Bash**: installs `shellcheck` and `shfmt` (repo-based)
* **Python**: installs `ruff` and `pylint` via pip (user-scope; versions configurable)

### 🕰️ Bash Customizations

* **Eternal history** (`~/.bash_eternal_history`) with timestamps, no truncation
* **Prompt** shows git branch (`__git_ps1` when available; lightweight fallback otherwise)
* **ble.sh** for autosuggestions, syntax highlighting (interactive shells only, **no auto-attach**)
* **bash-completion**: system + user-scope
* **fzf**: system or user fallback (`~/.fzf`) with keybindings & completion
* **argcomplete**: user-scope activation
* **carapace** (optional): rich completions if present

### ☸️ Kubernetes & OpenShift

* Installs **`kubectl`** and **`oc`**:

  * To `/usr/local/bin` if writable, else to `~/.local/bin` with a PATH hint
  * Generates completions into `~/.bash_completion.d/`
  * `kubectl` SHA256 verified when available (warning-only on mismatch)

### 🧪 Terminal: Ghostty (+ Dracula)

* **Fedora/RHEL-family**:

  * Enables COPR **`alternateved/ghostty`** (via `dnf copr enable`) and installs **Ghostty**
* **Debian/Ubuntu**:

  * Optional install via `.deb` URL or community script (off by default)
* **Dracula theme**:

  * Installs Ghostty Dracula into `~/.config/ghostty/themes/` and ensures `theme = dracula`
  * **Idempotent with failure cache**: if the archive didn’t contain a theme on a prior run, re-download is skipped for 7 days (override with `GHOSTTY_DRACULA_FORCE=1`)

---

## Fallback Behavior (No Extra Repos)

When a package isn’t available in your distro’s **base** repositories:

* **yamllint** → installed **user-scope**:

  ```bash
  python3 -m pip install --user yamllint
  ```

  The script ensures `~/.local/bin` is on your `PATH`.

* **Powerline glyphs** → installs a **Nerd Font** (default: *FiraCode*) to:

  ```text
  ~/.local/share/fonts
  ```

  and runs `fc-cache -fv`. Select the Nerd Font (e.g., *FiraCode Nerd Font*) in your terminal profile.

These fallbacks avoid system-wide changes and do **not** require EPEL or other extra repos.

---

## Usage

### Make the script executable

```bash
chmod +x install_vimrc_etc.sh
```

### Run directly (non-interactive)

```bash
./install_vimrc_etc.sh
```

---

## After Completion

* Appends/updates blocks in `~/.bashrc`, `~/.vimrc`, and `~/.tmux.conf`
* Creates default `~/.config/yamllint/config` if missing
* Installs/updates tools, fonts, and plugins (including TPM/tmux plugins)
* Sources `~/.bashrc` in the current shell
* Suggests running `exec bash -l` for a fully fresh session

---

## Configuration

Edit the top of `install_vimrc_etc.sh`:

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
ENABLE_KUBECTL_OC=1
ENABLE_REPO_TOOLING=1
ENABLE_GHOSTTY=1
ENABLE_GHOSTTY_DRACULA=1

# tmux
ENABLE_TMUX=1
ENABLE_TMUX_DRACULA=1

CLEAN_OUTPUT=1   # suppress package manager/gitrepo noise
LOG_FILE=""      # optional log file path (empty = no file log)
```

Pin Python linter versions:

```bash
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"
```

> Debian/Ubuntu Ghostty options (optional):
>
> ```bash
> GHOSTTY_DEB_URL=""                 # set to a .deb URL to enable install
> USE_UNOFFICIAL_GHOSTTY_UBUNTU=0    # set to 1 to use community installer
> ```
>
> Ghostty Dracula re-download:
>
> ```bash
> GHOSTTY_DRACULA_FORCE=1 ./install_vimrc_etc.sh   # force re-install of theme
> ```

---

## Safe Defaults

* **Idempotent**: Re-runs won’t duplicate or bloat your files
* **Backups**: Timestamped backups for each modified file
* **Quiet**: Suppresses noisy package manager & git output by default
* **Fail-safe**: Warns and continues if a tool is missing or a block is malformed

---

## Requirements

* Bash 4+
* `sudo` privileges (for system packages)
* `git`, `curl`, `make`, `gawk` (installed automatically when possible)
* **Internet access** (for plugins, ble.sh, Nerd Fonts, Ghostty theme, pip packages, **TPM/tmux plugins**)
* Terminal with **truecolor** support recommended (e.g., Ghostty, Kitty, Alacritty)

---

## Example Run

```text
[INFO] Dev Bootstrap starting
[INFO] OS family: debian (ID=ubuntu)
[ OK ] Packages installed.
[ OK ] Pathogen installed.
[ OK ] Vim plugins ready.
[ OK ] Updated ~/.vimrc
[ OK ] Yamllint config created at ~/.config/yamllint/config
[ OK ] Updated ~/.bashrc (history + ble.sh)
[ OK ] ble.sh installed
[ OK ] argcomplete set up
[ OK ] shellcheck installed
[ OK ] shfmt installed
[ OK ] ruff installed (0.6.5)
[ OK ] pylint installed (3.2.6)
[ OK ] kubectl/oc completions saved
[ OK ] ghostty installed via COPR
[ OK ] Dracula theme installed and enabled for Ghostty
[ OK ] TPM ready
[ OK ] tmux plugins installed/updated
[ OK ] tmux configured. Start with: tmux
[ OK ] All done. Sourcing ~/.bashrc now (safe).
[ OK ] Done. For a fresh session, run: exec bash -l
```

---

## Troubleshooting

* **`pip3` not found**
  The script runs `python3 -m ensurepip --upgrade` and installs `python3-pip` via repos if needed.

* **`yamllint` missing in repos**
  The script installs it **user-scope** with `python3 -m pip install --user yamllint` and ensures `~/.local/bin` is on `PATH`.

* **Powerline glyphs not rendering**
  Your terminal may need to use a Nerd Font (e.g., *FiraCode Nerd Font*). Select it in the terminal profile settings.

* **Duplicate blocks in `.bashrc`/`.vimrc`/`.tmux.conf`**
  The script replaces prior managed blocks and trims leading blank lines. If you edited them manually, just rerun the installer.

* **`shellcheck`/`shfmt` missing**
  Some distros don’t ship these in base repos. Install from upstream or via portable binaries if needed.

* **Ghostty on Debian/Ubuntu**
  There’s no official repo in this script. You can set `GHOSTTY_DEB_URL` to a `.deb` or opt-in to the community installer (`USE_UNOFFICIAL_GHOSTTY_UBUNTU=1`).

* **Ghostty Dracula keeps re-downloading**
  The script caches a “not found” state for 7 days to avoid repeated downloads. Force an immediate re-try with:

  ```bash
  GHOSTTY_DRACULA_FORCE=1 ./install_vimrc_etc.sh
  ```

* **tmux Dracula theme not applied**
  Ensure `~/.tmux/plugins/tpm` exists and that the managed block contains:

  ```tmux
  set -g @plugin 'tmux-plugins/tpm'
  set -g @plugin 'dracula/tmux'
  run '~/.tmux/plugins/tpm/tpm'
  ```

  Re-run the script or run `~/.tmux/plugins/tpm/bin/install_plugins`. Also use a truecolor-capable terminal.

---

## ToDo

* Add support for Terraform CLI
* Add support for Helm CLI
* Optional `pipx`-based isolation for Python linters
