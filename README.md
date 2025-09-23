# Dev Bootstrap Installer

This project provides a **non-interactive Bash installer script** (`install_vimrc_etc.sh`) that bootstraps a development environment consistently across **Debian/Ubuntu** and **RHEL/Rocky Linux** systems.

It installs and configures common developer tools, Vim plugins, Bash enhancements, and linters — with **optimized performance** , **safe backups** , and **idempotent updates** .

---

## 🚀 Performance Improvements

The installer has been optimized for speed and efficiency without changing its functionality:

* **Parallel Vim plugin installs** (clones/updates run concurrently, capped at CPU count or 8 jobs)
* **ble.sh builds with all cores** (`make -jN`) instead of serial compilation
* **Smarter pip installs** :
  * Disabled version checks and progress bars (`PIP_DISABLE_PIP_VERSION_CHECK=1`)
  * Uses `--upgrade-strategy only-if-needed` to skip unnecessary downloads
  * Skips redundant `pip --upgrade pip`
* **Compressed downloads** : all `curl` fetches use `--compressed`
* **Stream extraction for oc** : downloads + extracts in one step (no temp tarball written)
* **Write-if-changed config updates** : backups and rewrites only occur if content has actually changed
* **Smarter kubectl/oc completions** : regenerated only if client version changed
* **Single temp directory** : all temporary files isolated and auto-cleaned at exit
* **Quieter package installs** : suppresses unnecessary docs/suggestions (`dnf --setopt=tsflags=nodocs`, `apt-get -qq`)
* **Helper caching** : small helper functions (`has`, `ncores`) reduce repeated command lookups

👉 These improvements cut installation time significantly, especially on systems with many Vim plugins or when rebuilding ble.sh.

---

## Features

### 🖥️ Package Installation

* **Debian/Ubuntu** :
  * `vim`, `git`, `fonts-powerline`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`
* **RHEL/Rocky/Fedora** :
  * `vim-enhanced`, `git`, `powerline-fonts`, `fzf`, `yamllint`, `curl`, `make`, `gawk`, `bash-completion`, `python3`, `python3-pip`

👉 **No EPEL dependency required.**

`epel-release` and `bash-completion-extras` are not needed. Tools not in base repos are installed **user-scope** (e.g. via `pip` or git clone).

👉 **Optimized installs** :

* Uses retry logic and compressed downloads (`curl --compressed`)
* Suppresses unnecessary package manager noise (`apt-get -qq`, `dnf --setopt=tsflags=nodocs`)
* Retries `apt-get` operations to handle flaky mirrors

---

### ✨ Vim Configuration

* Installs **Pathogen** for plugin management
* Installs popular Vim plugins:
  * `vim-airline`, `nerdtree`, `fzf-vim`, `vim-fugitive`, `ale`, `indentLine`, `vim-gitgutter`, `vim-floaterm`, `jinja-4-vim`, `shades-of-purple`
* **Parallel plugin installation** for much faster setup (clones/updates run concurrently)
* Updates **`.vimrc`** by appending a managed block (never overwrites user config)
* Skips unnecessary updates if nothing changed

---

### 🧹 Linters

* **YAML** : installs `yamllint` and generates a config at `~/.config/yamllint/config`
* **Bash** : installs `shellcheck` and `shfmt` if available in repos; otherwise warns
* **Python** :
  * Installs `ruff` and `pylint` via `pip --user`
  * Uses `--upgrade-strategy only-if-needed` for faster installs
  * Suppresses pip version checks and progress bars for speed
  * Versions can be pinned in the script config

---

### 🕰️ Bash Customizations

* **Eternal Bash History** :
  * Stores unlimited history in `~/.bash_eternal_history`
  * Timestamps each entry
  * Prevents truncation on logout
* **Prompt Enhancements** :
  * Git branch shown inline
* **ble.sh Integration** :
  * Built with **all CPU cores** (`make -jN`) for faster compilation
  * Adds autosuggestions, syntax highlighting, and smarter completion
  * Only loaded in interactive shells
* **bash-completion** : sourced if present
* **fzf keybindings** : fuzzy search menus
* **argcomplete** :
  * Python CLI tab completion (user-scoped setup)
  * Falls back to a generated loader if global activation is missing
* **carapace** (optional): rich completions if binary is on PATH

---

### 📊 Installer Behavior

* Detects OS family automatically
* Creates backups of modified files (`~/.bashrc.bak.YYYYMMDD_HHMMSS`)
* **Write-if-changed logic** : config files are only rewritten if content actually changed
* Cleans and replaces existing config blocks in `~/.bashrc` idempotently
* All temp files stored in a **single temp directory** (cleaned automatically at exit)
* Supports **quiet/clean mode** (suppresses package manager/git noise)
* Logs to tty (and optionally to a log file)

## Usage

### Clone or copy script

<pre class="overflow-visible!" data-start="4162" data-end="4203"><div class="contain-inline-size rounded-2xl relative bg-token-sidebar-surface-primary"><div class="sticky top-9"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre! language-bash"><span><span><span class="hljs-built_in">chmod</span></span><span> +x install_vimrc_etc.sh
</span></span></code></div></div></pre>

### Run directly (non-interactive)

<pre class="overflow-visible!" data-start="4240" data-end="4274"><div class="contain-inline-size rounded-2xl relative bg-token-sidebar-surface-primary"><div class="sticky top-9"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre! language-bash"><span><span>./install_vimrc_etc.sh
</span></span></code></div></div></pre>

---

## After Completion

The script will:

* Update `~/.bashrc` with new blocks
* Source `~/.bashrc` in the current shell
* Suggest running `exec bash -l` to start a fully fresh session

---

## Configuration

Edit the top of the script (`install_vimrc_etc.sh`) to toggle features:

<pre class="overflow-visible!" data-start="4560" data-end="4878"><div class="contain-inline-size rounded-2xl relative bg-token-sidebar-surface-primary"><div class="sticky top-9"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre! language-bash"><span><span>ENABLE_PACKAGES=1
ENABLE_VIM_PLUGINS=1
ENABLE_VIMRC=1
ENABLE_YAMLLINT=1
ENABLE_BASHRC=1
ENABLE_BLE=1
ENABLE_ARGCOMPLETE=1
ENABLE_BASH_LINTERS=1
ENABLE_PY_LINTERS=1
ENABLE_KUBECTL_OC=1
ENABLE_REPO_TOOLING=1

CLEAN_OUTPUT=1   </span><span><span class="hljs-comment"># suppress package manager/gitrepo noise</span></span><span>
LOG_FILE=</span><span><span class="hljs-string">""</span></span><span>      </span><span><span class="hljs-comment"># optional log file path</span></span><span>
</span></span></code></div></div></pre>

You can also pin Python linter versions:

<pre class="overflow-visible!" data-start="4922" data-end="4977"><div class="contain-inline-size rounded-2xl relative bg-token-sidebar-surface-primary"><div class="sticky top-9"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre! language-bash"><span><span>RUFF_VERSION=</span><span><span class="hljs-string">"0.6.5"</span></span><span>
PYLINT_VERSION=</span><span><span class="hljs-string">"3.2.6"</span></span><span>
</span></span></code></div></div></pre>

---

## Safe Defaults

* **Idempotent** : Running multiple times will not duplicate config blocks
* **Backups** : Every change to `~/.bashrc` or config files creates a timestamped backup
* **Write-if-changed** : Skips rewriting files if no content has changed
* **Quiet** : All noisy package manager and git output is suppressed by default for clean logs
* **Fail-Safe** : If a tool is missing or a block is malformed, the script warns but continues

---

## Requirements

* Bash 4+
* sudo privileges (for package installation)
* git, curl, make, gawk (will be installed automatically if missing)
* Internet access (for Vim plugins, ble.sh, and pip packages)

---

## Example Run

<pre class="overflow-visible!" data-start="5654" data-end="5690"><div class="contain-inline-size rounded-2xl relative bg-token-sidebar-surface-primary"><div class="sticky top-9"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre! language-bash"><span><span>$ ./install_vimrc_etc.sh
</span></span></code></div></div></pre>

<pre class="overflow-visible!" data-start="5691" data-end="6404"><div class="contain-inline-size rounded-2xl relative bg-token-sidebar-surface-primary"><div class="sticky top-9"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre! language-bash"><span><span>[INFO] Dev Bootstrap starting (append-only; no EPEL required)
[INFO] OS family: debian (ID=ubuntu)
[ OK ] Pathogen installed.
[ OK ] Vim plugins ready.
[ OK ] ~/.vimrc installed.
[ OK ] Yamllint config created at /home/user/.config/yamllint/config
[ OK ] Updated ~/.bashrc (</span><span><span class="hljs-comment"># >>> ETERNAL_HISTORY_AND_GIT_PROMPT_START >>>)</span></span><span>
[ OK ] ble.sh installed.
[ OK ] argcomplete activated (user-scope)
[ OK ] shellcheck installed
[ OK ] shfmt installed
[ OK ] ruff installed (0.6.5)
[ OK ] pylint installed (3.2.6)
[ OK ] kubectl completion up-to-date
[ OK ] oc completion saved to /home/user/.bash_completion.d/oc
[ OK ] All </span><span><span class="hljs-keyword">done</span></span><span>. Sourcing ~/.bashrc now (safe).
[ OK ] Done. For a fresh session, run: </span><span><span class="hljs-built_in">exec</span></span><span> bash -l
</span></span></code></div></div></pre>

---

## Troubleshooting

* **pip3 not found**

  → The script tries to install python3-pip. If it still fails, manually install pip.
* **argcomplete loader skipped**

  → If `activate-global-python-argcomplete` is missing, the script creates a user-scope loader in `~/.bash_completion.d`.
* **Duplicate blocks in .bashrc**

  → The script cleans and replaces blocks each run. If you edited them manually, rerun the installer.
* **Missing tools (shellcheck, shfmt)**

  → Some distros may not have these in default repos. Install from upstream if required.

---

## ToDo

* Add support for HELM installe
