# Changelog

All notable changes to this project will be documented in this file.

---

## [0.4.6] – 2025-10-25

### Added
- **Google Shell Style refactor**  
  Rewritten to comply with the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html):  
  `set -euo pipefail`, uppercase constants, small pure helpers, early exits, and consistent quoting.
- **Fedora 42 validation**  
  Fedora 42 confirmed working end-to-end.  
  README updated with explicit **Fedora 42 (✅ tested)** and **RHEL 9.x (🟡 pending)**.
- **Optional Ghostty (Dracula theme)**  
  Ghostty terminal support retained for Fedora/RHEL via COPR (`alternateved/ghostty`)  
  and for Debian/Ubuntu (planned). Theme auto-applies Dracula when enabled.  
  Disabled by default (`ENABLE_GHOSTTY=0`).

### Changed
- **BLE removed**  
  Replaced all `ble.sh` logic with a simpler, portable **bash-completion** prompt setup.  
  This avoids issues seen in PuTTY, standard Fedora terminal, and other non-interactive shells.
- **Safer, smaller default footprint**
  - No tmux installation or config logic (removed entirely).
  - Ghostty kept but OFF by default.
  - Clipboard helpers (`pbcopy` / `pbpaste`) remain **ON**.
- **Python linter handling**  
  - Ensures `~/.local/bin` is added to `PATH` both persistently and for the current shell.  
  - Adds fallback reinstall logic if `ruff` or `pylint` aren’t visible immediately.
- **Idempotent file healing**
  - Maintains the post-update compaction and deduplication logic for `.bashrc` and `.vimrc`.
  - Trims whitespace, removes duplicates, prevents repeated `PATH` exports.

### Removed
- **tmux and TPM support**  
  All tmux configuration, Dracula theme setup, and TPM plugin logic removed.  
  (Was originally added in 0.4.1–0.4.5; no longer shipped.)
- **BLE (bash line editor)**  
  Removed entirely for broader terminal compatibility.
- **EPEL and external repos**  
  Fully self-contained base repos + user-scope fallbacks only.

### Fixed
- **Duplicate PATH export prevention**  
  Deduplication logic now runs before writing; prevents multiple `export PATH="$HOME/.local/bin:$PATH"` lines.
- **Safer font detection**  
  Checks with `fc-list` before downloading FiraCode Nerd Font again.
- **Minor quoting and logging fixes**  
  Cleaned legacy `awk` quoting warnings and redundant `[INFO]` entries.

---

## [0.4.5] – 2025-10-09

### Added
- **Automatic whitespace & duplicate cleanup**
  - Post-update compaction for `.bashrc`, `.vimrc`, `.tmux.conf`.
  - Functions `compact_file()` and `dedupe_literal_line()` introduced.
- **Healing re-run logic**
  - Repairs previous installs without overwriting.
- **Safer user-scoped behavior**
  - Enforces absolute paths and user ownership after writes.
- **Improved backup and restore consistency**
  - Timestamped `.bak.YYYYMMDD_HHMMSS` backups remain untouched by compaction.

### Changed
- Prompts for `sudo` only when necessary.
- Cleaner `[INFO]` and `[OK]` log messages.
- Simplified `awk` and block handling.

### Fixed
- Prevented duplicate PATH lines.
- Trimmed excess blank lines.
- `.vimrc` and `.bashrc` verified idempotent.

---

## [0.4.4] – 2025-10-08
- Safer sudo handling and ownership checks.
- Clipboard integration improved (`pbcopy`/`pbpaste`).
- Defaults: tmux & Ghostty off; clipboard on.
- Logging clearer and more structured.

---

## [0.4.3] – 2025-10-07
- Added cross-desktop `pbcopy` / `pbpaste` wrappers.
- Improved backend detection.
- Prevented duplicate PATH exports.

---

## [0.4.2] – 2025-10-06
- Ghostty config normalization and cache fixes.
- Dracula theme stability improvements.

---

## [0.4.1] – 2025-10-05
- Added tmux Dracula theme and menu UX (now removed).
- Ghostty Dracula caching introduced.
