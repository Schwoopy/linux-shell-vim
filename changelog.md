Here’s an updated **Changelog** with a new `0.4.1` release for today, capturing the tmux menus/tabs work, Ghostty Dracula caching (no re-download spam), script slimming, and the unbound-var fixes. I left your previous entries intact.

---

# Changelog

All notable changes to this project will be documented in this file.
This project follows [Keep a Changelog](https://keepachangelog.com/) style (without strict semantic versioning).

---

## [0.4.1] - 2025-10-05

### Added

* **tmux menus & tabs UX**

  * **Mega-menu** on **Prefix + `m`**: splits, next/prev tab, rename, sync-panes toggle, reload config, kill pane/tab.
  * **Right-click menus**: on tabs (status bar) and inside panes.
  * **Tabs navigation**: **Alt+← / Alt+→**, **Ctrl+PgUp / Ctrl+PgDn**; quick rename with **Prefix + `,`**.
  * **Status bar at top**, clean formats; window renumbering on.
* **Ghostty Dracula caching**

  * Caches a “not found” state for 7 days to prevent repeated downloads; override via `GHOSTTY_DRACULA_FORCE=1`.

### Changed

* **Lean script & shared helpers**

  * Consolidated upsert logic into a single `upsert_greedy` function (used for `.bashrc`, `.vimrc`, `.tmux.conf`).
  * Smaller, clearer blocks; less boilerplate; quieter output while preserving `[INFO]/[WARN]/[ OK ]/[ERR ]`.
* **Non-interactive plugin flow**

  * TPM plugins install/update quietly (no keypress), preserving **no auto-attach** behavior for tmux/ble.sh.

### Fixed

* **Unbound variables** seen in earlier runs:

  * `sysbindir` (kubectl/oc installer) and `cfgdir` (Ghostty config) now initialized robustly.
* **Ghostty Dracula re-download spam**

  * Zip contents are validated; failure cached; re-try gated unless forced.
* **tmux `display-message` argument errors**

  * Menu actions updated/quoted to avoid “too many arguments”.

---

## [0.4.0] - 2025-10-04

### Added

* **tmux support**

  * Installs **tmux** from system repositories (Debian/Fedora families).
  * Installs **TPM (tmux plugin manager)** idempotently at `~/.tmux/plugins/tpm`.
  * Appends a managed **Dracula-themed tmux configuration** block to `~/.tmux.conf`:

    * Enables truecolor (`tmux-256color`, `RGB`).
    * Sets **Dracula theme** via `dracula/tmux` plugin.
    * Enables mouse, 100k history, vi-copy mode with `y` yank.
    * Non-interactive TPM bootstrap (no auto attach).
  * Safe append-only behavior (backups with timestamps).
* **Integrated tmux + Dracula theming**

  * Dracula theme applied automatically and kept in sync with Ghostty color scheme.
  * Uses the same consistent dark palette across terminal, Vim, and tmux.
* **Improved Ghostty + Dracula integration**

  * Ensures Ghostty and tmux theming stay aligned.
  * Simplified theme download/refresh flow (zip handled in one pass).

### Changed

* **Feature grouping & modularization**

  * Added dedicated tmux installer functions (`install_tmux`, `install_tmux_conf`, `ensure_tpm_dracula`).
  * Organized `main()` to call tmux setup after Vim, Bash, and Ghostty setup.
* **Safe re-runs**

  * `.tmux.conf` block uses the same idempotent block logic as `.vimrc` and `.bashrc`.
  * Old tmux configs preserved with timestamped `.bak` files before patching.
* **Documentation**

  * README updated with **tmux support** and **Dracula theme** sections.
  * Removed redundant “What’s New” section (features summarized instead).

### Fixed

* Missing `tmux` dependency on RHEL-based systems.
* Ensured no auto-attach behavior for ble.sh or tmux after installation.
* Dracula theme duplication avoided on multiple reruns.

---

## [0.3.0] - 2025-10-04

### Added

* **Ghostty terminal support**

  * **Fedora/RHEL-family:** install from COPR `alternateved/ghostty` (idempotent enable + install).
  * **Dracula theme:** auto-install to `~/.config/ghostty/themes/dracula/` and set `theme = dracula` in config.
  * **Debian/Ubuntu:** optional hooks (disabled by default) to install from a `.deb` URL or community script.
* **PATH persistence for user tools**

  * Ensures `~/.local/bin` is added **once** to `PATH` (both for the current shell and persistently in `~/.bashrc`).
  * Verifies and (re)installs `ruff` and `pylint` if not visible on `PATH`.
* **Safer append-only config updates**

  * New newline-safe upsert logic shared by `.bashrc` and `.vimrc` blocks (no creeping blank lines).
* **Architecture detection**

  * Robust `uname - m` mapping for `kubectl`/`oc` downloads (e.g., `amd64`, `arm64`, `s390x`, `ppc64le`).

### Changed

* **Yamllint & fonts fallbacks**

  * `yamllint` installs user-scope via `python3 -m pip install --user yamllint` when absent in base repos.
  * **Nerd Fonts** fallback (default: *FiraCode*) now checks existing fonts before download and refreshes cache selectively.
* **Vim defaults**

  * `silent! colorscheme shades_of_purple` to avoid errors if theme isn’t present yet.
  * Tightened idempotency for the managed `DEV_BOOTSTRAP_VIM` block.
* **Installers**

  * `kubectl` SHA256 verification attempted when checksum URL is available (warning-only on mismatch).
  * `oc` tarball stream handled more defensively and cleans up extracted residues.
* **Logging & resilience**

  * Cleaner `[INFO]/[WARN]/[ OK ]/[ERR ]` lines; more specific failure messages and exit points.
  * Extra cleanup on exit for temp files and partial downloads.

### Fixed

* Duplicate/stacked block markers when rerunning the script.
* Extra leading blank lines introduced on repeated runs of `.bashrc`/`.vimrc`.
* Missing `install_argcomplete` guard in certain paths.
* PATH-related issues causing `ruff`/`pylint` to appear “missing” immediately after installation.

---

## [0.2.0] - 2025-09-24

### Added

* **User-scope fallbacks** when system repos don’t provide packages:

  * `yamllint` via `python3 -m pip install --user yamllint`
  * **Nerd Fonts** (default: FiraCode) to `~/.local/share/fonts` with `fc-cache -fv`
* **kubectl/oc installers**:

  * Install to `/usr/local/bin` if writable, else fallback to `~/.local/bin`
  * Generate completions into `~/.bash_completion.d/`
* **Repo tooling**:

  * `Makefile` with `lint-sh`, `fmt-sh`, and `check-sh` targets
  * `.shellcheckrc` with external source following enabled

### Changed

* **Removed EPEL dependency**: Script now works fully with base repos + user fallbacks
* **Vim plugin installation**:

  * Plugins are now cloned/updated **in parallel** (limited to CPU cores, max 8 jobs)
  * Uses `--single-branch`, `--no-tags`, and blob filtering for faster git clones
* **ble.sh installation**:

  * Compiled with **all CPU cores** (`make -jN`) instead of single-threaded builds
* **pip installs**:

  * Disabled version check and progress output (`PIP_DISABLE_PIP_VERSION_CHECK=1`)
  * Uses `--upgrade-strategy only-if-needed` to avoid unnecessary upgrades
  * Skips redundant `pip install --upgrade pip`
* **curl usage**:

  * All downloads now use `--compressed` to reduce bandwidth and improve speed
  * `oc` client tarball is **stream-extracted** (download + extract in one step, no temp tarball)
* **Configuration file handling**:

  * Introduced **write-if-changed** logic: files are only rewritten if content differs
  * Backups only created when actual changes are made
  * Fixed newline handling: reruns no longer prepend extra blank lines in `.bashrc` and `.vimrc`
* **kubectl/oc completions**:

  * Completions are regenerated only if the installed version changed
  * Skips rewriting if completion scripts are already up-to-date
* **Temporary files**:

  * All temp files now stored in a **single isolated directory**, cleaned on exit
* **Package installs**:

  * Quieter package manager operations (`apt-get -qq`, `dnf --setopt=tsflags=nodocs`)
  * Retries added to `apt-get` for flaky mirrors
* **Helper functions**:

  * Added `has()` and `ncores()` helpers to avoid repeated `command -v` and `nproc` calls
* **Logging**:

  * Removed progress bar; replaced with clean `[INFO]/[WARN]/[ OK ]/[ERR ]` log lines

---

## [0.1.0] - Initial version

### Added

* Bootstrapped developer environment across Debian/Ubuntu and RHEL/Rocky
* Installed packages, Vim plugins, bash customizations, linters, kubectl/oc
* Appended config blocks to `.bashrc` and `.vimrc` safely
* Created default yamllint config
* Added repo tooling (Makefile + shellcheck config)
