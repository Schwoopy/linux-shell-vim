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
  * **Full-path `chown` enforcement** — only absolute paths are used during ownership fixes.
  * Ownership checks integrated via `ensure_user_ownership()` after writes.

* **Improved backup and restore consistency**

  * Every modification still generates a timestamped `.bak.YYYYMMDD_HHMMSS` backup.
  * Compaction and deduplication **never** run on backup copies.

### Changed

* **Sudo handling refinement**

  * Root execution is **not required**; run as a normal user.
  * Prompts for `sudo` **only when necessary** (e.g., installing packages, writing to `/usr/local/bin`).
  * All `$HOME` content remains user-owned.

* **Logging polish**

  * Cleaner `[INFO]` and `[OK]` messages for deduplication, compaction, ownership repairs, and sudo prompts.
  * Reduced redundant log lines while keeping important details.

* **Block management simplification**

  * Replaced warning-prone `awk` patterns with literal-safe logic.
  * Reduced banner comments; each managed block now has a short, descriptive header.

* **Defaults unchanged**

  * `ENABLE_TMUX=0` (off by default).
  * `ENABLE_GHOSTTY=0` (off by default).
  * Clipboard helpers remain **on** (`ENABLE_PBTOOLS=1`).

### Fixed

* Eliminated `awk` escape warnings during `.bashrc` updates.
* Prevented duplicate `PATH`/export lines from earlier versions.
* Compactors avoid touching block delimiters.
* Ensured empty files are (re)created safely before upserts.
* Corrected legacy ownership created before 0.4.4.
* Verified `.vimrc` and `.tmux.conf` compact and reformat safely on repeat runs.

---

## [0.4.4] – 2025-10-08

### Added

* **Safer sudo handling** — prompts only when needed.
* **Ownership & permissions verification** via `ensure_user_ownership()`.
* **Improved clipboard integration** (`pbcopy`/`pbpaste`): user-owned, PATH exported automatically.

### Changed

* **Defaults**: tmux & Ghostty off; clipboard helpers on.
* **PATH export logic**: simplified and idempotent.
* **File safety**: backups on every write.
* **Logging**: clearer, sectioned output.

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
