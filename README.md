# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a development environment consistently across **Debian/Ubuntu** and **RHEL/Rocky/Fedora** systems.

It installs and configures common developer tools, Vim plugins, Bash enhancements, Kubernetes CLIs, **optional tmux (with TPM + Dracula theme + menus/tabs)**, and linters — with **safe append-only config management** (no overwrites), **“healing” re-runs** (it compacts whitespace and removes duplicate lines), and **clean logging**.
It also ships **cross-desktop clipboard helpers**: `pbcopy` and `pbpaste`.

> ℹ️ **Ghostty** and **tmux** are **disabled by default**. Ghostty requires a running Linux desktop/window manager; tmux is optional. Enable them in **Configuration** below.

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

> If something breaks on your distro/version, please open an issue with logs.

---

## Features

### 🖥️ Packages (base repos only)

* **Debian/Ubuntu**: `vim`, `git`, `fonts-powerline`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip`, `tmux`
* **RHEL/Rocky/Fedora**: `vim-enhanced`, `git`, `powerline-fonts`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip`, `tmux`

> If `yamllint` or Powerline/Nerd fonts aren’t available, see **Fallback Behavior**.

### ✨ Vim

* Installs **Pathogen** and curated plugins:
  `vim-airline`, `nerdtree`, `fzf-vim`, `vim-fugitive`, `ale`, `indentLine`, `vim-gitgutter`, `vim-floaterm`, `jinja-4-vim`, `shades-of-purple`
* Appends one managed block to `~/.vimrc` (sane defaults, truecolor).
* Re-runs update plugins idempotently.

### 🔲 (Optional) tmux (TPM + Dracula + Menus/Tabs)

* **Disabled by default.** When enabled:

  * Installs **TPM** at `~/.tmux/plugins/tpm`.
  * Appends a managed block to `~/.tmux.conf`:

    * Truecolor (`tmux-256color` + RGB overrides), mouse on, 100k history, Vi copy-mode.
    * **Dracula** via `dracula/tmux`, powerline-style status.
    * **UX**: Mega-menu (Prefix+`m`), right-click menus, Alt+←/→, Ctrl+PgUp/PgDn.
  * TPM plugins install/update non-interactively.

### 📋 Clipboard Helpers: `pbcopy` & `pbpaste`

* Installs portable shims to `~/.local/bin`:

  * **Wayland** → `wl-copy` / `wl-paste`
  * **X11** → `xclip` (or `xsel`)
  * **macOS** → native tools if detected
  * **WSL** → `pbcopy` uses `clip.exe`; **`pbpaste` PowerShell backend intentionally disabled**
* The installer **ensures `~/.local/bin` is on your `PATH`** (appended to `~/.bashrc` only once).

### 🧹 Linters

* **YAML**: `yamllint` (repo or pip user fallback) + default config at `~/.config/yamllint/config`
* **Bash**: `shellcheck`, `shfmt`
* **Python**: `ruff`, `pylint` via pip (user-scope; versions configurable)

### 🕰️ Bash Customizations

* **Eternal history** (`~/.bash_eternal_history`) with timestamps
* **Prompt** shows git branch (`__git_ps1` when available; fallback included)
* **bash-completion**: system + user-scope
* **fzf**: system or user fallback (`~/.fzf`) with keybindings & completion
* **argcomplete**: user-scope activation
* **carapace** (optional): rich completions if present

### ☸️ Kubernetes & OpenShift

* Installs **`kubectl`** and **`oc`** to `/usr/local/bin` if writable, else to `~/.local/bin`
* Generates bash completions into `~/.bash_completion.d/`

### 🧪 Terminal: Ghostty (+ Dracula) — **default OFF**

* **Fedora/RHEL**: optional COPR install (`alternateved/ghostty`)
* **Debian/Ubuntu**: optional `.deb` or community installer path
* **Theme**: handles nested `themes/dracula.conf` and sets `theme = dracula`

> Off by default (`ENABLE_GHOSTTY=0`) since it needs a desktop/WM.

### 🔁 Idempotent “Healing”

* Safe upserts with backups (timestamped).
* **Compacts whitespace and removes duplicate literal lines** (e.g., repeated `export PATH="$HOME/.local/bin:$PATH"`).
* Keeps ownership under your current user; uses `sudo` **only** for system operations.

---

## Fallback Behavior (No Extra Repos)

* **yamllint** → user-scope:

  ```bash
  python3 -m pip install --user yamllint
  ```

  Ensures `~/.local/bin` is on `PATH`.

* **Powerline glyphs** → installs **FiraCode Nerd Font** to:

  ```
  ~/.local/share/fonts
  ```

  and refreshes cache (`fc-cache -f`).

---

## Usage

Make executable:

```bash
chmod +x install_vimrc_etc.sh
```

Run:

```bash
./install_vimrc_etc.sh
```

The script will prompt for `sudo` **only** when needed (packages, system dirs).

---

## Using `pbcopy` and `pbpaste`

Installed at `~/.local/bin/pbcopy` and `~/.local/bin/pbpaste` (PATH ensured).

Backends:

* **Wayland** → `wl-clipboard` (`wl-copy`, `wl-paste`)
* **X11** → `xclip` (or `xsel`)
* **macOS** → native tools
* **WSL** → `pbcopy` via `clip.exe`; `pbpaste` backend disabled (install X/Wayland clipboard tool if needed)

Examples:

```bash
kubectl get pods | pbcopy
pbpaste > pods.txt
pbcopy < ~/.ssh/id_rsa.pub
pbpaste | wc -l
pbcopy <<< "Hello from Dev Bootstrap!"
```

If you see `no clipboard backend found`, install `wl-clipboard` (Wayland) or `xclip`/`xsel` (X11).

---

## After Completion

* Appends/updates blocks in `~/.bashrc`, `~/.vimrc`, and (if enabled) `~/.tmux.conf`
* Creates `~/.config/yamllint/config` if missing
* Installs/updates tools, fonts, and plugins (incl. TPM/tmux plugins when enabled)
* Adds `~/.local/bin` to your `PATH` (persisted in `~/.bashrc`)
* Sources `~/.bashrc` and suggests `exec bash -l` for a fresh login shell

---

## Configuration

At the top of the script:

```bash
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

# Terminals (OFF by default)
ENABLE_GHOSTTY=0
ENABLE_GHOSTTY_DRACULA=0

# tmux (OFF by default)
ENABLE_TMUX=0
ENABLE_TMUX_DRACULA=1

# Clipboard helpers
ENABLE_PBTOOLS=1
```

Pin Python linter versions:

```bash
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"
```

Optional Ghostty on Debian/Ubuntu:

```bash
GHOSTTY_DEB_URL=""               # .deb URL to enable install
USE_UNOFFICIAL_GHOSTTY_UBUNTU=0  # set 1 to use community installer
```

---

## Requirements

* Bash 4+
* `sudo` privileges (for system packages)
* `git`, `curl`, `make`, `gawk` (auto-installed when possible)
* Internet access (plugins, fonts, pip packages, TPM/tmux plugins)
* For `pbcopy`/`pbpaste`: `wl-clipboard` (Wayland) or `xclip`/`xsel` (X11)

---

## Troubleshooting

* **`pip3` not found** → uses `ensurepip`, falls back to distro `python3-pip`.
* **`yamllint` missing in repos** → user-scope via pip; PATH is ensured.
* **Powerline glyphs not rendering** → choose a Nerd Font (e.g., FiraCode Nerd Font) in your terminal.
* **Duplicate blocks / too many blank lines** → re-run the installer; it compacts and dedupes.
* **Ghostty** → enable only on a desktop/WM; theme selector handles nested `themes/dracula.conf`.
* **`pbcopy`/`pbpaste` “no backend”** → install `wl-clipboard` or `xclip`/`xsel`. On WSL, paste backend is disabled by design.