Here’s the **fully updated `CHANGELOG.md`** reflecting *all* latest changes — including the new **shellcheck/shfmt/fzf fallback logic**, **BLE removal**, **Ghostty default disablement**, and the **Google Shell Style refactor** — merged cleanly into version `0.4.7` while preserving the prior `0.4.6` entry separately.

---

# Changelog

All notable changes to this project will be documented in this file.

---

## [0.4.7] – 2025-10-26

### Added

* **User-scope fallbacks for `shellcheck` and `shfmt`**

  * Installs **portable static binaries** to `~/.local/bin` when not available in base repositories.
  * Automatically ensures `~/.local/bin` is present in both the current and persistent `PATH`.
  * Supports optional version pinning:

    ```bash
    SHELLCHECK_VERSION="v0.10.0"
    SHFMT_VERSION="v3.7.0"
    ```
  * Validates binary integrity and executable permissions post-install.

* **fzf fallback (for Fedora/RHEL minimal systems)**

  * Automatically installs from GitHub into `~/.fzf` if package not found in repos.
  * Non-interactive bootstrap enables **completion** and **keybindings**.
  * Vim plugin (`fzf-vim`) works seamlessly with the fallback installation.

* **README updates**

  * Expanded **Fallback Behavior** section for `shellcheck`, `shfmt`, and `fzf`.
  * Added **Distro Notes** section covering Fedora, RHEL/Rocky/Alma, Debian/Ubuntu, and WSL edge cases.
  * Clarified that **BLE** and **Ghostty** remain disabled by default.

* **Version pinning & PATH helpers**

  * `ensure_local_bin_path()` helper guarantees `~/.local/bin` inclusion once per file.
  * Supports explicit per-tool pinning for Python linters and binaries.

---

### Changed

* **BLE removed completely**

  * Replaced with a portable `bash-completion`-only setup.
  * Eliminates compatibility problems with PuTTY, Fedora Terminal, and non-interactive SSH shells.

* **Simplified default feature set**

  * No `tmux` or TPM logic.
  * `Ghostty` present but **disabled by default** (`ENABLE_GHOSTTY=0`).
  * Clipboard helpers (`pbcopy`, `pbpaste`) remain **enabled** by default.

* **Logging and output**

  * Cleaner `[INFO]`, `[WARN]`, and `[ OK ]` output.
  * Quieter linter and fallback installs while maintaining detailed logs.
  * Explicit confirmation when using user-scope fallbacks.

---

### Fixed

* Fedora minimal installs now work without manual `fzf` setup.
* RHEL/Rocky systems install successfully without **EPEL**.
* Duplicate `export PATH="$HOME/.local/bin:$PATH"` lines prevented via deduplication logic.
* Fonts checked via `fc-list` before re-download.
* Temporary download cleanup corrected for portable binaries.

---

## [0.4.6] – 2025-10-25

### Added

* **Google Shell Style refactor**
  Rewritten to comply with the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html):
  `set -euo pipefail`, uppercase constants, pure helpers, early exits, and consistent quoting.
* **Fedora 42 validation**
  Fedora 42 confirmed working end-to-end.
  README updated with explicit **Fedora 42 (✅ tested)** and **RHEL 9.x (🟡 pending)**.
* **Optional Ghostty (Dracula theme)**
  Ghostty terminal support retained for Fedora/RHEL via COPR (`alternateved/ghostty`)
  and for Debian/Ubuntu (planned). Theme auto-applies Dracula when enabled.
  Disabled by default (`ENABLE_GHOSTTY=0`).

### Changed

* **BLE removed**
  Replaced all `ble.sh` logic with simpler, portable **bash-completion** prompt setup.
  This avoids issues seen in PuTTY, Fedora terminal, and other non-interactive shells.
* **Safer, smaller default footprint**

  * No tmux installation or config logic (removed entirely).
  * Ghostty kept but OFF by default.
  * Clipboard helpers (`pbcopy` / `pbpaste`) remain **ON**.
* **Python linter handling**

  * Ensures `~/.local/bin` is added to `PATH` both persistently and for the current shell.
  * Adds fallback reinstall logic if `ruff` or `pylint` aren’t visible immediately.
* **Idempotent file healing**

  * Maintains the post-update compaction and deduplication logic for `.bashrc` and `.vimrc`.
  * Trims whitespace, removes duplicates, prevents repeated `PATH` exports.

### Removed

* **tmux and TPM support**
  All tmux configuration, Dracula theme setup, and TPM plugin logic removed.
  (Was originally added in 0.4.1–0.4.5; no longer shipped.)
* **BLE (bash line editor)**
  Removed entirely for broader terminal compatibility.
* **EPEL and external repos**
  Fully self-contained base repos + user-scope fallbacks only.

### Fixed

* **Duplicate PATH export prevention**
  Deduplication logic now runs before writing; prevents multiple `export PATH="$HOME/.local/bin:$PATH"` lines.
* **Safer font detection**
  Checks with `fc-list` before downloading FiraCode Nerd Font again.
* **Minor quoting and logging fixes**
  Cleaned legacy `awk` quoting warnings and redundant `[INFO]` entries.

---

## [0.4.5] – 2025-10-09

### Added

* **Automatic whitespace & duplicate cleanup**

  * Post-update compaction for `.bashrc`, `.vimrc`, `.tmux.conf`.
  * Functions `compact_file()` and `dedupe_literal_line()` introduced.
* **Healing re-run logic**

  * Repairs previous installs without overwriting.
* **Safer user-scoped behavior**

  * Enforces absolute paths and user ownership after writes.
* **Improved backup and restore consistency**

  * Timestamped `.bak.YYYYMMDD_HHMMSS` backups remain untouched by compaction.

### Changed

* Prompts for `sudo` only when necessary.
* Cleaner `[INFO]` and `[OK]` log messages.
* Simplified `awk` and block handling.

### Fixed

* Prevented duplicate PATH lines.
* Trimmed excess blank lines.
* `.vimrc` and `.bashrc` verified idempotent.

---

## [0.4.4] – 2025-10-08

* Safer sudo handling and ownership checks.
* Clipboard integration improved (`pbcopy`/`pbpaste`).
* Defaults: tmux & Ghostty off; clipboard on.
* Logging clearer and more structured.

---

## [0.4.3] – 2025-10-07

* Added cross-desktop `pbcopy` / `pbpaste` wrappers.
* Improved backend detection.
* Prevented duplicate PATH exports.

---

## [0.4.2] – 2025-10-06

* Ghostty config normalization and cache fixes.
* Dracula theme stability improvements.

---

## [0.4.1] – 2025-10-05

* Added tmux Dracula theme and menu UX (now removed).
* Ghostty Dracula caching introduced.