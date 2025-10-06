# Changelog

All notable changes to this project will be documented in this file.

---

## [0.4.3] - 2025-10-07

### Added

* **Cross-desktop clipboard tools: `pbcopy` / `pbpaste`**

  * Installs lightweight, cross-environment clipboard wrappers to `~/.local/bin`:

    * **Wayland:** uses `wl-copy` / `wl-paste` (preferred)
    * **X11:** uses `xclip` or `xsel`
    * **macOS:** uses native `pbcopy` / `pbpaste` if available
    * **WSL:** `pbcopy` uses `clip.exe`; `pbpaste` **PowerShell backend disabled** by design
  * Adds `~/.local/bin` to `PATH` (exported immediately and persisted in `~/.bashrc` + `~/.profile`)
  * Includes clear logging and fallback hints if no backend is found.
  * Standalone, idempotent installation — no interference with system clipboards.

* **Documentation**

  * Updated **README** with a full section on how to use `pbcopy` and `pbpaste`:

    * Practical examples (`pbcopy < file`, `pbpaste | wc -l`, etc.)
    * Backend detection explanation
    * Notes for Wayland, X11, macOS, and WSL users

### Changed

* **Ghostty disabled by default**

  * `ENABLE_GHOSTTY=0` and `ENABLE_GHOSTTY_DRACULA=0` by default
  * Avoids install errors on headless or non-desktop systems (e.g., servers, WSL)
  * Can be manually enabled in config for full desktop environments

* **Installer cleanup**

  * Integrates pbcopy/pbpaste setup directly into main bootstrap flow
  * Ensures `PATH` export happens once, early in the process
  * Maintains idempotent logic for re-runs (no redundant PATH lines)

### Fixed

* Ensured `pbcopy` / `pbpaste` scripts are executable and loadable in the same session after install.
* Fixed `PATH` export guard to correctly detect pre-existing `~/.local/bin` entries.
* Minor `set -u` guard improvements for local variable safety.

---

## [0.4.2] - 2025-10-06

### Added

* **Ghostty config normalization**

  * Automatically renames:

    * `~/.config/ghostty/config.conf` → `config`
    * `~/.config/ghostty/config.toml` → `config`
  * Prevents Ghostty “config not found” errors caused by extra extensions.
  * Ensures `theme = dracula` is appended only once, even after renames.

* **Ghostty theme safety**

  * Ensures the `~/.config/ghostty` directory always exists before writing config.
  * Theme install skips unnecessary downloads if already cached or installed.

### Changed

* **Dracula installer flow**

  * Simplified logic — no re-download spam and cleaner “already installed” detection.
  * Uses a single unified path for Dracula theme setup and config validation.

* **Logging**

  * Improved `[INFO]` / `[OK]` feedback for Ghostty normalization steps.
  * Explicit confirmation when renaming a legacy `config.conf` → `config`.

### Fixed

* **Ghostty theme/config sync** — fixed cases where the theme would install but Ghostty still failed to detect `config`.
* **set -u compatibility** — safer variable initialization for `cfgdir`, `themes_dir`, and temporary paths.
* **Residual temp files** — temporary zip extractions and stamp files now cleaned consistently.

---

## [0.4.1] - 2025-10-05

### Added

* **tmux menus & tabs UX**

  * **Mega-menu** on **Prefix + `m`**: splits, next/prev tab, rename, sync-panes toggle, reload config, kill pane/tab.
  * **Right-click menus**: on tabs (status bar) and inside panes.
  * **Tabs navigation**: **Alt + ← / Alt + →**, **Ctrl + PgUp / Ctrl + PgDn**; quick rename with **Prefix + `,`**.
  * **Status bar at top**, clean formats; window renumbering on.

* **Ghostty Dracula caching**

  * Caches a “not found” state for 7 days to prevent repeated downloads; override via `GHOSTTY_DRACULA_FORCE=1`.

### Changed

* **Lean script & shared helpers**

  * Consolidated upsert logic into a single `upsert_greedy` function (used for `.bashrc`, `.vimrc`, `.tmux.conf`).
  * Smaller, clearer blocks; quieter output while preserving `[INFO]/[WARN]/[ OK ]/[ERR ]`.

* **Non-interactive plugin flow**

  * TPM plugins install/update quietly (no keypress), preserving **no auto-attach** behavior for tmux/ble.sh.

### Fixed

* **Unbound variables** seen in earlier runs:

  * `sysbindir` (kubectl/oc installer) and `cfgdir` (Ghostty config) now initialized robustly.

* **Ghostty Dracula re-download spam**

  * Zip contents are validated; failure cached; re-try gated unless forced.

* **tmux `display-message` argument errors**

  * Menu actions updated/quoted to avoid “too many arguments”.
