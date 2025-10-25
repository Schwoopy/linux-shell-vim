# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a development environment consistently across **Debian/Ubuntu** and **RHEL/Rocky/Fedora** systems.

It installs and configures common developer tools, Vim plugins, Bash enhancements, Kubernetes CLIs, and linters — with **safe append-only config management** (no overwrites), **idempotent re-runs**, and **clean logging** (no progress bars).

> Note: **BLE**, **Ghostty**, and **tmux** are not included in the current installer.

---

## Platform Support & Test Status

* Tested

  * Fedora 42

* Pending testing

  * RHEL: 9.x

* Currently untested

  * Rocky Linux: 9.x
  * AlmaLinux: 9.x
  * Ubuntu: 22.04 LTS, 24.04 LTS
  * Debian: 12 (Bookworm)
  * Fedora: 41, 40
  * Linux Mint: 21.x
  * WSL (Ubuntu/Debian)

> The script is designed to be portable across these families. If something breaks on your distro/version, please open an issue with logs.

---

## What’s New

* No EPEL dependency — works with base repos only.
* User-scope fallbacks when repos lack packages:

  * `yamllint` via `python3 -m pip install --user yamllint`
  * Nerd Fonts (default: FiraCode) to `~/.local/share/fonts` + `fc-cache -fv`
  * `fzf` via `~/.fzf` bootstrap if not in repos
  * `shellcheck` portable binary to `~/.local/bin`
  * `shfmt` portable binary to `~/.local/bin`
* Idempotent, newline-safe updates for `~/.bashrc` and `~/.vimrc` (no duplicate blocks or creeping blank lines).
* Repo tooling: `Makefile` (ShellCheck/shfmt targets) + `.shellcheckrc`.

---

## Features

### Package Installation (base repos only)

* Debian/Ubuntu: `vim`, `git`, `fonts-powerline`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip`
* RHEL/Rocky/Fedora: `vim-enhanced`, `git`, `powerline-fonts`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip`

> If packages are missing in base repos, see **Fallback Behavior**.

### Vim

* Installs Pathogen and a curated plugin set:
  `vim-airline`, `nerdtree`, `fzf-vim`, `vim-fugitive`, `ale`, `indentLine`, `vim-gitgutter`, `vim-floaterm`, `jinja-4-vim`, `shades-of-purple`
* Appends a single, managed block to `~/.vimrc` (truecolor, sane defaults).
* Re-runs update plugins idempotently.

### Linters

* YAML: `yamllint` (repo or pip user fallback) with default config at `~/.config/yamllint/config`
* Bash: `shellcheck`, `shfmt` (repo or user-scope portable binaries)
* Python: `ruff` and `pylint` via pip (user-scope; versions configurable)

### Bash Customizations

* Eternal history (`~/.bash_eternal_history`) with timestamps
* Prompt shows git branch (`__git_ps1` when available; fallback included)
* bash-completion: system + user-scope
* fzf: system or user fallback (`~/.fzf`) with keybindings & completion
* argcomplete: user-scope activation
* carapace (optional): rich completions if present

### Kubernetes & OpenShift

* Installs `kubectl` and `oc` to `/usr/local/bin` if writable, else to `~/.local/bin`
* Generates bash completions into `~/.bash_completion.d/`

### Repo Tooling

* Writes `Makefile` with:

  * `check-sh` (bash -n), `lint-sh` (ShellCheck), `fmt-sh` (shfmt)
* Adds `.shellcheckrc` allowing external sources when paths are validated in code

---

## Fallback Behavior (No Extra Repos)

When a package isn’t available in your distro’s **base** repositories, the installer will fall back to a user-scope setup:

* `yamllint` → pip user install

  ```bash
  python3 -m pip install --user yamllint
  ```

  Ensures `~/.local/bin` is on your `PATH`.

* Powerline glyphs → installs a Nerd Font (default: FiraCode) to:

  ```
  ~/.local/share/fonts
  ```

  and refreshes font cache with `fc-cache -f`.

* `fzf` → clones bootstrap into:

  ```
  ~/.fzf
  ```

  and runs its installer with keybindings/completion enabled.

* `shellcheck` → downloads portable binary to:

  ```
  ~/.local/bin/shellcheck
  ```

* `shfmt` → downloads portable binary to:

  ```
  ~/.local/bin/shfmt
  ```

All fallbacks are **user-owned** and do not require extra repos.

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

The script prompts for `sudo` only when needed (packages, `/usr/local/bin`).

---

## After Completion

* Appends/updates blocks in `~/.bashrc` and `~/.vimrc`
* Creates `~/.config/yamllint/config` if missing
* Installs/updates tools, fonts, and plugins
* Ensures `~/.local/bin` is on your `PATH`
* Sources `~/.bashrc` and suggests `exec bash -l` for a fresh login shell

---

## Configuration

Edit the top of `install_vimrc_etc.sh`:

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

CLEAN_OUTPUT=1   # suppress package manager/gitrepo noise
LOG_FILE=""      # optional log file path (empty = no file log)
```

Pin Python linter versions:

```bash
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"
```

Optional pins for portable binaries:

```bash
SHELLCHECK_VERSION=""   # e.g., "v0.10.0" (empty = latest)
SHFMT_VERSION=""        # e.g., "v3.7.0"  (empty = latest)
```

---

## Requirements

* Bash 4+
* `sudo` privileges (for system packages)
* `git`, `curl`, `make`, `gawk` (auto-installed when possible)
* Internet access (plugins, fonts, pip packages, portable binaries)

---

## Example Run

```text
[INFO] Dev Bootstrap starting (append-only; no EPEL required)
[INFO] OS family: debian (ID=ubuntu)
[ OK ] Packages installed (system repos only; no EPEL).
[ OK ] Pathogen installed.
[ OK ] Vim plugins ready.
[ OK ] Ensured single managed Vim block in /home/user/.vimrc
[ OK ] Yamllint config created at /home/user/.config/yamllint/config
[ OK ] Updated ~/.bashrc (history + prompt)
[ OK ] argcomplete activated (user-scope)
[ OK ] shellcheck available
[ OK ] shfmt available
[ OK ] ruff installed (0.6.5)
[ OK ] pylint installed (3.2.6)
[ OK ] kubectl completion saved to ~/.bash_completion.d/kubectl
[ OK ] oc completion saved to ~/.bash_completion.d/oc
[ OK ] All done. Sourcing ~/.bashrc now (safe).
[ OK ] Done. For a fresh session, run: exec bash -l
```

---

## Troubleshooting

* `pip3` not found
  Uses `python3 -m ensurepip --upgrade` and installs `python3-pip` via repos if needed.

* `yamllint` missing in repos
  Installs user-scope via pip; ensures `~/.local/bin` is on `PATH`.

* Powerline glyphs not rendering
  Select a Nerd Font (e.g., FiraCode Nerd Font) in your terminal profile.

* `fzf` not available in repos
  The script bootstraps `~/.fzf` and enables keybindings/completion.

* `shellcheck`/`shfmt` missing in repos
  The script installs portable binaries into `~/.local/bin`.

* Duplicate blocks or extra blank lines
  Re-run the installer; it compacts and deduplicates safely.

---

## Distro Notes

These are common variations we’ve observed:

* Fedora (some spins/mirrors)

  * `fzf` may be missing or in a different subpackage layout. The installer auto-falls back to `~/.fzf` with keybindings and completion.

* RHEL/Rocky/Alma (base without EPEL)

  * `shellcheck` and `shfmt` may be unavailable. The installer fetches portable binaries into `~/.local/bin`.
  * `yamllint` may be missing — installed user-scope via pip.

* Debian/Ubuntu minimal images

  * `fonts-powerline` may be missing on some minimal/cloud images — Nerd Font fallback is used.
  * `pip` may not be present; the installer tries `ensurepip` and then installs `python3-pip` if needed.

* WSL

  * Clipboard helpers: `pbcopy` uses `clip.exe`. `pbpaste` requires an X/Wayland clipboard tool (install `xclip`/`xsel` or `wl-clipboard`) or use Windows-native workflows.

If you hit a package gap that isn’t covered by the fallbacks above, please open an issue including your distro, version, and the log output.
