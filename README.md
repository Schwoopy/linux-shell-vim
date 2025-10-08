# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a development environment consistently across **Debian/Ubuntu** and **RHEL/Rocky/Fedora** systems.

It installs and configures common developer tools, Vim plugins, Bash enhancements, Kubernetes CLIs, **optional tmux (with TPM + Dracula theme + menus/tabs)**, and linters — with **safe append-only config management** (no overwrites) and **clean logging** (no noisy progress bars).
It also ships **cross-desktop clipboard helpers**: `pbcopy` and `pbpaste`.

> ℹ️ **Ghostty** and **tmux** are now **disabled by default**. Ghostty requires a running Linux desktop/window manager; tmux is optional and can be enabled when you want it. See **Configuration** below.

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

### 🔲 (Optional) tmux Configuration (TPM + Dracula + Menus/Tabs)

* **Disabled by default.** When enabled:

  * Installs **TPM** at `~/.tmux/plugins/tpm` (idempotent).
  * Appends a managed block to `~/.tmux.conf`:

    * Truecolor (`tmux-256color` + `RGB` overrides), mouse on, 100k history, Vi copy-mode.
    * **Dracula** via TPM (`dracula/tmux`) with powerline-style status.
    * **Menus/Tabs UX**:

      * **Mega-menu**: Prefix + `m` (splits, next/prev tab, rename, sync panes, reload, kill pane/tab).
      * **Right-click menus**: on tabs (status bar) and inside panes.
      * **Navigation**: Alt+←/→, Ctrl+PgUp/PgDn.
  * TPM plugins install/update non-interactively.

### 📋 Clipboard Helpers: `pbcopy` & `pbpaste`

* Installs portable CLI wrappers to `~/.local/bin`:

  * **Wayland**: uses `wl-copy` / `wl-paste` (preferred).
  * **X11**: uses `xclip` (or `xsel` if `xclip` isn’t present).
  * **macOS**: uses native tools if detected (no conflicts).
  * **WSL**: `pbcopy` uses `clip.exe`; **`pbpaste` PowerShell backend is intentionally disabled** by design.
* The installer **ensures `~/.local/bin` is on your `PATH`** by appending to `~/.bashrc`.

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
* **Dracula theme**: installer handles nested `themes/dracula.conf` and selects `theme = dracula`

> Disabled by default (`ENABLE_GHOSTTY=0`) because it requires a running Linux desktop/WM.

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

The installer places both tools at: `~/.local/bin/pbcopy` and `~/.local/bin/pbpaste` and ensures that directory is exported to your `PATH` now and on future logins (via `~/.bashrc`).

They map to your display stack:

* **Wayland** → requires `wl-clipboard` (`wl-copy`, `wl-paste`)
* **X11** → prefers `xclip` (falls back to `xsel`)
* **macOS** → uses native `pbcopy`/`pbpaste` if detected
* **WSL** → `pbcopy` uses `clip.exe`; **`pbpaste` backend is disabled** (install an X/Wayland clipboard tool if you need paste)

**Examples**

```bash
kubectl get pods | pbcopy
pbpaste > pods.txt
pbcopy < ~/.ssh/id_rsa.pub
pbpaste | wc -l
pbcopy <<< "Hello from Dev Bootstrap!"
```

If you see `no clipboard backend found`, install one: `wl-clipboard` (Wayland) or `xclip`/`xsel` (X11).

---

## After Completion

* Appends/updates blocks in `~/.bashrc`, `~/.vimrc`, and `~/.tmux.conf` (if tmux enabled)
* Creates default `~/.config/yamllint/config` if missing
* Installs/updates tools, fonts, and plugins (including TPM/tmux plugins if enabled)
* **Adds `~/.local/bin` to your PATH** (persisted in `~/.bashrc`)
* Sources `~/.bashrc` in the current shell
* Suggests running `exec bash -l` for a fully fresh session

---

## Configuration

At the top of `install_vimrc_etc.sh`, toggle features:

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

# Terminals (both OFF by default)
ENABLE_GHOSTTY=0
ENABLE_GHOSTTY_DRACULA=0

# tmux (OFF by default)
ENABLE_TMUX=0
ENABLE_TMUX_DRACULA=1

# Clipboard helpers
ENABLE_PBCOPY_PBPASTE=1
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
  * WSL: `clip.exe` for `pbcopy`; `pbpaste` backend is intentionally disabled

---

## Example Run (with tmux disabled)

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
[INFO] Skipping install_tmux (disabled)
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
* **Ghostty** → optional; enable only on a desktop/WM. Theme selector handles nested `themes/dracula.conf`.
* **`pbcopy`/`pbpaste` say “no backend found”** → install `wl-clipboard` (Wayland) or `xclip`/`xsel` (X11). On WSL, `pbcopy` uses `clip.exe`; `pbpaste` backend is disabled by design.

---

## ToDo

* Add support for Terraform & Helm CLIs
* Optional `pipx` isolation for Python linters
