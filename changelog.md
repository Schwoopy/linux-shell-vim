# Changelog

All notable changes to this project will be documented in this file.

---

## [0.4.4] - 2025-10-08

### Added

* **Safer sudo handling**
  * The installer **no longer requires running as sudo/root**.
  * It now **prompts for sudo only when necessary**, such as installing system packages or writing to `/usr/local/bin`.
  * Ensures user-owned configurations, plugins, and local binaries under `$HOME`.

* **Ownership and permissions verification**
  * All files and directories created under the user’s home directory are automatically owned by the **current user**.
  * Any use of `chown` now explicitly uses **absolute paths** to avoid ambiguity or permission leaks.
  * Introduced `ensure_user_ownership()` and `mkuserdir()` consistency checks across all modules.

* **Improved clipboard integration (`pbcopy` / `pbpaste`)**
  * Ensures `~/.local/bin/pbcopy` and `pbpaste` are both **user-owned and executable**.
  * Automatically exports `~/.local/bin` to `PATH` if missing.
  * Integration happens early in the script to guarantee immediate availability.

### Changed

* **Default configuration updates**
  * **tmux** is now **disabled by default** (`ENABLE_TMUX=0`), matching Ghostty behavior.
  * **Ghostty** remains disabled (`ENABLE_GHOSTTY=0`), as it requires a GUI window manager.
  * Clipboard helpers (`pbcopy`, `pbpaste`) remain **enabled by default** (`ENABLE_PBCOPY_PBPASTE=1`).

* **PATH export logic**
  * Simplified and idempotent — appends to `~/.bashrc` only once.
  * Added safety guards to prevent duplicate PATH lines across re-runs.

* **File safety**
  * Every write operation now includes a backup (`.bak.YYYYMMDD_HHMMSS`) before modification.
  * Ensures re-runs preserve user changes outside managed blocks.

* **Logging and clarity**
  * Improved `[INFO]` and `[OK]` messages for ownership repairs, sudo prompts, and clipboard installation.
  * Cleaner startup banner and section grouping for better traceability in logs.

### Fixed

* Fixed incorrect ownership when running as non-root but installing with sudo.
* Corrected rare `unbound variable` errors in ownership and directory creation functions.
* Prevented accidental overwriting of files with relative `chown` calls — all now resolved via `_abs_path()`.
* Ensured tmux and Ghostty optional blocks respect user flags and don’t run when disabled.

---

## [0.4.3] - 2025-10-07

### Added

* **Cross-desktop clipboard tools: `pbcopy` / `pbpaste`**
  * Installs lightweight wrappers to `~/.local/bin`:
    * **Wayland:** `wl-copy` / `wl-paste` (preferred)
    * **X11:** `xclip` (falls back to `xsel`)
    * **macOS:** native `pbcopy` / `pbpaste` if available
    * **WSL:** `pbcopy` uses `clip.exe`; `pbpaste` **PowerShell backend disabled** by design
  * Ensures `~/.local/bin` is on `PATH` **immediately and persistently**.
  * Clear logging and hints if no clipboard backend is found.
  * Standalone, idempotent install — doesn’t interfere with system clipboards.

* **Documentation**
  * README updated with a full `pbcopy`/`pbpaste` section:
    * Practical examples (`pbcopy < file`, `pbpaste | wc -l`, pipelines, here-strings, etc.)
    * Backend detection overview and notes for Wayland, X11, macOS, WSL.

### Changed

* **Defaults**
  * **Ghostty** default **OFF**: `ENABLE_GHOSTTY=0`, `ENABLE_GHOSTTY_DRACULA=0`.
  * **Installer flow:** integrates pbcopy/pbpaste setup earlier, ensuring availability after run.
  * Maintains idempotent `PATH` export; prevents redundant additions.

### Fixed

* `pbcopy` / `pbpaste` executables now loadable in same session.
* Fixed duplicate PATH exports.
* Safer variable handling under `set -u`.

---

## [0.4.2] - 2025-10-06

### Added

* **Ghostty config normalization**
  * Automatically renames:
    * `~/.config/ghostty/config.conf` → `config`
    * `~/.config/ghostty/config.toml` → `config`
  * Prevents Ghostty “config not found” errors.
  * Ensures `theme = dracula` is appended only once.

* **Ghostty theme safety**
  * Ensures `~/.config/ghostty` exists before writing config.
  * Skips unnecessary downloads if theme is cached or installed.

### Changed

* Simplified Dracula installer flow; cleaner “already installed” detection.
* Unified path and cache logic for Ghostty theme setup.

### Fixed

* **Ghostty config sync** — fixed theme detection and reinstallation loops.
* **`set -u` compatibility** — initialized all local variables.
* **Temp cleanup** — removes all intermediate zip/stamp files.

---

## [0.4.1] - 2025-10-05

### Added

* **tmux menus & tabs UX**
  * **Mega-menu** on **Prefix + `m`**: splits, next/prev tab, rename, sync panes, reload config, kill pane/tab.
  * **Right-click menus**: on tabs (status bar) and inside panes.
  * **Navigation**: **Alt+←/→**, **Ctrl+PgUp/PgDn**.
  * **Status bar at top**, 100k scrollback, Vi copy-mode.

* **Ghostty Dracula caching**
  * Caches “not found” state for 7 days to prevent repeated downloads; override via `GHOSTTY_DRACULA_FORCE=1`.

### Changed

* Consolidated upsert logic into `upsert_greedy`.
* Quieter plugin update flow for ble.sh and TPM.

### Fixed

* Fixed `sysbindir` and `cfgdir` unbound variable issues.
* Cleaned up Ghostty theme re-download logic.
* Resolved tmux `display-message` argument quoting errors.
