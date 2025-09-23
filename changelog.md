# Changelog

All notable changes to this project will be documented in this file.  
This project follows [Keep a Changelog](https://keepachangelog.com/) style (without strict semantic versioning).

---

## [Unreleased]

### Added
- Initial performance optimizations to the installer script

### Changed
- **Vim plugin installation**
  - Plugins are now cloned/updated **in parallel** (limited to CPU cores, max 8 jobs)
  - Uses `--single-branch`, `--no-tags`, and blob filtering for faster git clones
- **ble.sh installation**
  - Compiled with **all CPU cores** (`make -jN`) instead of single-threaded builds
- **pip installs**
  - Disabled version check and progress output (`PIP_DISABLE_PIP_VERSION_CHECK=1`)
  - Uses `--upgrade-strategy only-if-needed` to avoid unnecessary upgrades
  - Skips redundant `pip install --upgrade pip`
- **curl usage**
  - All downloads now use `--compressed` to reduce bandwidth and improve speed
  - `oc` client tarball is **stream-extracted** (download + extract in one step, no temp tarball)
- **Configuration file handling**
  - Introduced **write-if-changed** logic: files are only rewritten if content differs
  - Backups only created when actual changes are made
- **kubectl/oc completions**
  - Completions are regenerated only if the installed version changed
  - Skips rewriting if completion scripts are already up-to-date
- **Temporary files**
  - All temp files now stored in a **single isolated directory**, cleaned on exit
- **Package installs**
  - Quieter package manager operations (`apt-get -qq`, `dnf --setopt=tsflags=nodocs`)
  - Retries added to `apt-get` for flaky mirrors
- **Helper functions**
  - Added `has()` and `ncores()` helpers to avoid repeated `command -v` and `nproc` calls

---

## [Original] – Initial version
- Bootstrapped developer environment across Debian/Ubuntu and RHEL/Rocky
- Installed packages, Vim plugins, bash customizations, linters, kubectl/oc
- Appended config blocks to `.bashrc` and `.vimrc` safely
- Created default yamllint config
- Added repo tooling (Makefile + shellcheck config)
