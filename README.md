# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a development environment consistently across **Debian/Ubuntu** and **RHEL/Rocky/Fedora** systems.

It installs and configures common developer tools, Vim plugins, Bash enhancements, Kubernetes CLIs, **tmux (with TPM + Dracula theme + menus/tabs)**, and linters — with **safe append-only config management** (no overwrites) and **clean logging** (no noisy progress bars).
It also ships **cross-desktop clipboard helpers**: `pbcopy` and `pbpaste`.

> ℹ️ **Ghostty** is now **disabled by default** because it requires a running Linux window manager/desktop. You can enable it if you’re on a full desktop (see config).

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
* Appends a managed block to `~/.vimrc` (sane defaults, truecolor).
* Plugin updates are idempotent and shallow.

### 🔲 tmux Configuration (TPM + Dracula + Menus/Tabs)

* Installs **tmux** and **TPM** at `~/.tmux/plugins/tpm` (idempotent).
* Appends a managed block to `~/.tmux.conf`:

  * Truecolor (`tmux-256color` + `RGB` overrides), mouse on, 100k history, Vi copy-mode.
  * **Dracula** via TPM (`dracula/tmux`) with powerline-style status.
  * **Menus/Tabs UX**:

    * **Mega-menu**: Prefix + `m` (splits, next/prev tab, rename, sync panes, reload, kill pane/tab).
    * **Right-click menus**: on tabs (status bar) and inside panes.
    * **Navigation**: Alt+←/→, Ctrl+PgUp/PgDn.
* TPM plugins install/update non-interactively.

### 📋 Clipboard Helpers: `pbcopy` & `pbpaste` (new)

* Installs portable CLI wrappers to `~/.local/bin`:

  * **Wayland**: uses `wl-copy` / `wl-paste` (preferred).
  * **X11**: uses `xclip` (or `xsel` if `xclip` isn’t present).
  * **macOS**: transparently calls the native `pbcopy`/`pbpaste` if detected.
  * **WSL**: `pbcopy` uses `clip.exe`; `pbpaste` **PowerShell backend is intentionally disabled** (see usage/notes).

> The installer **ensures `~/.local/bin` is on your `PATH`** now and persistently adds it to both `~/.bashrc` and `~/.profile` (if present), so `pbcopy`/`pbpaste` are immediately available.

### 🧹 Linters

* **YAML**: `yamllint` (repo or user fallback) with default config at `~/.config/yamllint/config`
* **Bash**: `shellcheck` and `shfmt` (repo-based)
* **Python**: `ruff` and `pylint` via pip (user-scope; versions configurable)

### 🕰️ Bash Customizations

* **Eternal history** (`~/.bash_eternal_history`) with timestamps
* **Prompt** shows git branch (`__git_ps1` when available; lightweight fallback otherwise)
* **ble.sh** (interactive only): autosuggestions, syntax highlighting
* **bash-completion**: system + user-scope
* **fzf**: system or user fallback (`~/.fzf`) with keybindings & completion
* **argcomplete**: user-scope activation
* **carapace** (optional): rich completions if present

### ☸️ Kubernetes & OpenShift

* Installs **`kubectl`** and **`oc`**:

  * To `/usr/local/bin` if writable, else to `~/.local/bin` with a PATH hint
  * Generates completions into `~/.bash_completion.d/`

### 🧪 Terminal: Ghostty (+ Dracula) — **default OFF**

* **Fedora/RHEL-family**: optional COPR install (`alternateved/ghostty`)
* **Debian/Ubuntu**: optional community or `.deb` path (off by default)
* **Dracula theme**: installer handles nested `themes/dracula.conf` cases and selects `theme = dracula`

> Disabled by default (`ENABLE_GHOSTTY=0`) because it requires a running Linux desktop/WM. Enable only if applicable.

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

  and runs `fc-cache -f`.

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

## Using `pbcopy` and `pbpaste`

The installer places both tools at: `~/.local/bin/pbcopy` and `~/.local/bin/pbpaste` and ensures that directory is exported to your `PATH` now and on future logins.

They map to your display stack:

* **Wayland** → requires `wl-clipboard` (`wl-copy`, `wl-paste`)
* **X11** → prefers `xclip` (falls back to `xsel`)
* **macOS** → uses native `pbcopy`/`pbpaste` if detected (the script mainly targets Linux, but won’t get in your way)
* **WSL** → `pbcopy` uses `clip.exe`; `pbpaste` **PowerShell backend is disabled** (see below)

#### Examples

Copy the output of a command:

```bash
kubectl get pods | pbcopy
```

Paste into a file:

```bash
pbpaste > pods.txt
```

Copy a file’s contents:

```bash
pbcopy < ~/.ssh/id_rsa.pub
```

Paste into your shell as input to another command:

```bash
pbpaste | wc -l
```

Use with here-strings:

```bash
pbcopy <<< "Hello from Dev Bootstrap!"
```

#### Notes & Tips

* If you see `no clipboard backend found`, install one:

  * Wayland: `wl-clipboard`
  * X11: `xclip` (or `xsel`)
* **WSL**:

  * `pbcopy` works via `clip.exe`.
  * `pbpaste` PowerShell backend is intentionally **disabled** (by request). If you need paste support in WSL, install an X/Wayland clipboard tool (e.g., `xclip`, `xsel`, or `wl-clipboard`) and use a compatible terminal/X server setup.

---

## After Completion

* Appends/updates blocks in `~/.bashrc`, `~/.vimrc`, and `~/.tmux.conf`
* Creates default `~/.config/yamllint/config` if missing
* Installs/updates tools, fonts, and plugins (including TPM/tmux plugins)
* **Adds `~/.local/bin` to your PATH** (persisted in `~/.bashrc` and `~/.profile`)
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

# Terminals
ENABLE_GHOSTTY=0           # default OFF (needs a desktop/WM)
ENABLE_GHOSTTY_DRACULA=0

# tmux
ENABLE_TMUX=1
ENABLE_TMUX_DRACULA=1

# Clipboard helpers
ENABLE_PBTOOLS=1           # default ON
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
* **Internet access** (for plugins, ble.sh, fonts, Ghostty theme, pip packages, **TPM/tmux plugins**)
* For `pbcopy`/`pbpaste`:

  * Wayland: `wl-copy`/`wl-paste` (package: `wl-clipboard`)
  * X11: `xclip` (or `xsel`)
  * macOS: native tools are used if present
  * WSL: `clip.exe` for `pbcopy`; `pbpaste` backend intentionally disabled

---

## Example Run

```text
[INFO] Dev Bootstrap starting (append-only; no EPEL required)
[INFO] OS family: debian (ID=ubuntu)
[ OK ] Packages installed.
[ OK ] Pathogen installed.
[ OK ] Vim plugins ready.
[ OK ] Yamllint config created at ~/.config/yamllint/config
[ OK ] Updated ~/.bashrc (history + ble.sh)
[ OK ] ble.sh installed.
[ OK ] argcomplete activated (user-scope)
[ OK ] shellcheck installed
[ OK ] shfmt installed
[ OK ] ruff installed (0.6.5)
[ OK ] pylint installed (3.2.6)
[ OK ] kubectl/oc completions saved
[ OK ] TPM ready
[ OK ] tmux plugins installed/updated
[ OK ] tmux configured. Start with: tmux
[ OK ] Installed pbcopy/pbpaste to ~/.local/bin
[ OK ] All done. Sourcing ~/.bashrc now (safe).
[ OK ] Done. For a fresh session, run: exec bash -l
```

---

## Troubleshooting

* **`pip3` not found** → installer bootstraps with `ensurepip` and falls back to distro `python3-pip`.
* **`yamllint` missing in repos** → installed user-scope via pip; `~/.local/bin` added to `PATH`.
* **Powerline glyphs not rendering** → select a Nerd Font (e.g., *FiraCode Nerd Font*) in your terminal.
* **Duplicate blocks in dotfiles** → re-runs replace prior managed blocks and trim extra blanks.
* **`shellcheck`/`shfmt` missing** → not in base repos; install from upstream if desired.
* **Ghostty on Debian/Ubuntu** → no official path in script; optional community installer available.
* **Ghostty theme not detected** → script handles nested `themes/dracula.conf`. Ensure `theme = dracula` is present in `~/.config/ghostty/config`.
* **`pbcopy`/`pbpaste` say “no backend found”** → install `wl-clipboard` (Wayland) or `xclip`/`xsel` (X11). On WSL, `pbcopy` uses `clip.exe`; `pbpaste` backend is disabled by design.

---

## ToDo

* Add support for Terraform & Helm CLIs
* Optional `pipx` isolation for Python linters
