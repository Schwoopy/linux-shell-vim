# Changelog

All notable changes to this project will be documented in this file.

---

## [0.4.5] – 2025-10-09

### Added

* **Automatic whitespace & duplicate cleanup**

  * Added a **post-update compaction pass** for all managed dotfiles (`.bashrc`, `.vimrc`, `.tmux.conf`).
  * Introduced:

    * `compact_file()` — removes redundant blank lines and trailing whitespace.
    * `dedupe_literal_line()` — ensures single instances of exact literal lines such as
      `export PATH="$HOME/.local/bin:$PATH"`.
  * Compaction runs automatically on every re-run, keeping files neat and idempotent.

* **Healing re-run logic**

  * The installer can now **repair previous installs** instead of overwriting:

    * Removes duplicate managed blocks.
    * Trims excess blank lines.
    * Re-inserts missing managed sections cleanly.

* **Safer user-scoped behavior**

  * All file creation and directory modifications now occur strictly under the **current user**.
  * Introduced **full-path `chown` enforcement** — only absolute paths are used during ownership fixes.
  * Ownership check integrated in `ensure_user_ownership()` after every run.

* **Improved backup and restore consistency**

  * Every modification still generates a timestamped `.bak.YYYYMMDD_HHMMSS` backup.
  * Compaction and deduplication never run on the backup copies.

### Changed

* **Sudo handling refinement**

  * Root execution is **no longer required**; script runs as normal user.
  * Prompts for `sudo` only when installing system packages or writing to `/usr/local/bin`.
  * All `$HOME` content remains user-owned.

* **Logging polish**

  * Cleaner `[INFO]` and `[OK]` messages for deduplication, compaction, and ownership repairs.
  * Compact log output — reduced redundant `[INFO]` spam.
  * Consistent colored status output across all modules.

* **Block management simplification**

  * Replaced old `awk` patterns (with warning-prone escapes) with literal-safe replacements.
  * Reduced unnecessary comment banners in generated files.
  * Each block now includes a short descriptive header instead of long separators.

* **Default behavior unchanged**

  * `ENABLE_TMUX=0` (off by default).
  * `ENABLE_GHOSTTY=0` (off by default).
  * Clipboard helpers remain **enabled** (`ENABLE_PBTOOLS=1`).

### Fixed

* Eliminated `awk` escape-sequence warnings during `.bashrc` updates.
* Fixed duplicate PATH and export lines from prior versions.
* Ensured compactors don’t remove managed block delimiters.
* Corrected subtle cases where empty files weren’t re-created before upsert.
* Fixed `sudo` ownership mismatch on files created pre-0.4.4.
* Verified `.vimrc` and `.tmux.conf` now reformat safely on repeated runs.

---

## [0.4.4] – 2025-10-08

### Added

* **Safer sudo handling** — prompts only when needed.
* **Ownership and permissions verification** via `ensure_user_ownership()`.
* **Improved clipboard integration** (`pbcopy` / `pbpaste`): user-owned, PATH exported automatically.

### Changed

* **Default configuration**: `tmux` and `Ghostty` off; clipboard helpers on.
* **PATH export logic**: simplified and idempotent.
* **File safety**: backups on every write.
* **Logging**: clearer sectioned output.

### Fixed

* Ownership and `unbound variable` issues corrected.
* Relative `chown` paths replaced with absolute.
* Optional modules respect disable flags.

---

## [0.4.3] – 2025-10-07

* Introduced cross-desktop **`pbcopy` / `pbpaste`** wrappers.
* Documentation expanded with usage and backend detection.
* Prevented duplicate PATH lines; improved session availability.

---

## [0.4.2] – 2025-10-06

* Ghostty config normalization (`config.conf` → `config`).
* Dracula theme safety and caching improvements.
* Fixed Ghostty reinstall loops and temp cleanup.

---

## [0.4.1] – 2025-10-05

* Added **tmux menus/tabs UX** (Prefix + `m`, right-click menus, navigation keys).
* Added **Ghostty Dracula caching** with 7-day skip window.
* Fixed quoting and variable issues in tmux and Ghostty routines.
