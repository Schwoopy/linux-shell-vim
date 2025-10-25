# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a modern developer environment across **Debian/Ubuntu** and **RHEL/Rocky/Fedora** systems.

It installs and configures common developer tools, Vim plugins, Bash enhancements, Kubernetes CLIs, and Python/Bash linters — with **safe append-only config management**, **healing re-runs**, and **clean, compact logging**.

It also installs **cross-desktop clipboard helpers** (`pbcopy` and `pbpaste`) for Linux, WSL, and macOS-style interoperability.

---

## Platform Support and Test Status

- Tested:
  - Fedora 42
- Pending testing:
  - RHEL 9.x
- Currently untested:
  - Rocky Linux 9.x  
  - AlmaLinux 9.x  
  - Ubuntu 22.04 / 24.04  
  - Debian 12 (Bookworm)  
  - Fedora 41 / 40  
  - Linux Mint 21.x  
  - WSL (Ubuntu/Debian)

If something breaks on your distribution, please open an issue with logs.

---

## What's New in v0.4.6

- Refactored for **Google Shell Style**  
  Consistent quoting, helper functions, constants, `set -euo pipefail`, and early exits.
- **BLE and tmux removed**  
  Simplified shell setup without `ble.sh` or tmux dependencies.  
  Compatible with PuTTY, Fedora Terminal, and SSH sessions.
- **Ghostty optional**  
  Optional terminal installer for Fedora/RHEL (`copr:alternateved/ghostty`) with Dracula theme.  
  Disabled by default (`ENABLE_GHOSTTY=0`).
- **Clipboard helpers enabled**  
  Adds `pbcopy` and `pbpaste` under `~/.local/bin`, ensures `PATH` includes that directory.
- **Healing re-runs**  
  Compact and deduplicate configuration files on every run (`.bashrc`, `.vimrc`).
- **Safer user-scope installs**  
  All modifications and backups occur under the current user account only.

---

## Features

### Package Installation (Base Repositories Only)

| OS Family | Installed Packages |
|------------|--------------------|
| Debian/Ubuntu | `vim`, `git`, `fonts-powerline`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip` |
| RHEL/Rocky/Fedora | `vim-enhanced`, `git`, `powerline-fonts`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`, `unzip` |

If `yamllint` or Powerline fonts are missing, see the fallback section below.

---

### Vim Configuration

- Installs **Pathogen** and curated plugins:
  `vim-airline`, `nerdtree`, `fzf-vim`, `vim-fugitive`, `ale`, `indentLine`, `vim-gitgutter`, `vim-floaterm`, `jinja-4-vim`, `shades-of-purple`
- Adds one managed block to `~/.vimrc` (sensible defaults, 24-bit color).
- Re-runs update plugins safely without duplicates.

---

### Linters

- YAML → `yamllint` (system or pip fallback)
- Bash → `shellcheck`, `shfmt`
- Python → `ruff`, `pylint` (user-scope pip install)

---

### Bash Configuration

- Eternal history (`~/.bash_eternal_history`) with timestamps
- Prompt shows current git branch if available
- System and user bash completion
- `fzf` with keybindings and completion
- `argcomplete` enabled for Python CLIs
- `carapace` integrated if present

---

### Kubernetes and OpenShift

- Installs `kubectl` and `oc`
  - To `/usr/local/bin` if writable, otherwise `~/.local/bin`
  - Creates bash completions in `~/.bash_completion.d/`
- Automatically detects CPU architecture (amd64, arm64, etc.)

---

### Optional Terminal: Ghostty

- Fedora/RHEL: Installed from `copr:alternateved/ghostty`
- Dracula theme applied automatically when enabled
- Disabled by default (`ENABLE_GHOSTTY=0`)
- Safe to enable only in desktop environments with a window manager

---

### Clipboard Helpers

Installs portable `pbcopy` and `pbpaste` wrappers into `~/.local/bin` and ensures `PATH` includes that directory.

Backends:
- Wayland → `wl-clipboard`
- X11 → `xclip` or `xsel`
- WSL → `clip.exe` (paste disabled)
- macOS → native tools

Example:
```bash
echo "hello world" | pbcopy
pbpaste > output.txt
````

If no backend is detected, install `wl-clipboard` or `xclip`.

---

## Fallback Behavior

If packages are not available in system repositories:

* `yamllint` is installed via:

  ```bash
  python3 -m pip install --user yamllint
  ```
* FiraCode Nerd Font installed to:

  ```
  ~/.local/share/fonts
  ```

  and font cache refreshed with:

  ```
  fc-cache -f
  ```

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

The script is idempotent and safe to re-run.
Each run compacts configuration files and removes duplicates automatically.

---

## Configuration

Adjust at the top of the script:

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

# Optional features
ENABLE_GHOSTTY=0
ENABLE_PBTOOLS=1
```

Pin Python linter versions:

```bash
RUFF_VERSION="0.6.5"
PYLINT_VERSION="3.2.6"
```

---

## Requirements

* Bash 4 or newer
* `sudo` privileges for package installation
* Internet access for plugin and font downloads
* `git`, `curl`, `make`, `gawk` (installed if missing)
* For clipboard support:

  * Wayland → `wl-clipboard`
  * X11 → `xclip` or `xsel`

---

## Troubleshooting

| Issue                              | Solution                                             |
| ---------------------------------- | ---------------------------------------------------- |
| `pip3` not found                   | Script installs `python3-pip` or uses `ensurepip`.   |
| Fonts not rendering                | Select “FiraCode Nerd Font” in terminal preferences. |
| Duplicate PATH lines               | Re-run script; deduplication removes extra lines.    |
| Missing `pbcopy`/`pbpaste` backend | Install `wl-clipboard` or `xclip`.                   |
| Ghostty not launching              | Enable only on desktop systems.                      |

---

## Example Run

```text
[INFO] Dev Bootstrap starting (append-only; no EPEL required)
[INFO] OS family: redhat (ID=fedora)
[ OK ] Packages installed (base repos only)
[ OK ] Pathogen installed
[ OK ] Vim plugins ready
[ OK ] Updated ~/.bashrc (history + PATH)
[ OK ] yamllint installed (user)
[ OK ] ruff installed (0.6.5)
[ OK ] pylint installed (3.2.6)
[ OK ] kubectl completion saved to ~/.bash_completion.d/kubectl
[ OK ] oc completion saved to ~/.bash_completion.d/oc
[ OK ] pbcopy/pbpaste installed under ~/.local/bin
[ OK ] All done. For a fresh shell: exec bash -l
```

---

## Versioning

This project follows a practical changelog model (no strict semantic versioning).
See [CHANGELOG.md](./CHANGELOG.md) for details.
