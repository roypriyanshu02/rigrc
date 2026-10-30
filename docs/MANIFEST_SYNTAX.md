# Configuration & Manifest Syntax Reference

Syntax and reference guide for user configuration files (`*.conf`) and package manifests (`packages/**/*.conf`).

---

## 1. Inheritance Model

Configuration values and templates merge across three layers:

```text
src/base.conf (base defaults) -> packages/**/*.conf (package defaults) -> *.conf (user overrides)
```

- Lower layers provide defaults.
- Higher layers append to, replace, or suppress lower layer settings using section modifiers.

---

## 2. User Configuration Syntax (`*.conf`)

User configuration files customize package selections, shell integrations, and templates for a specific machine or environment.

### Section Types

| Section Header | Purpose | Example |
| :--- | :--- | :--- |
| `[config]` | Global package selection, filters, and condition overrides | `groups = core, shell` |
| `[package:<name>]` | Package-level settings and key overrides | `[package:git]` |
| `[bashrc:<name>]` | Custom shell integration snippets & aliases | `[bashrc:append]` |
| `[template:<path>]` | Dotfile template definition and file deployment | `[template:.gitconfig]` |

### The `[config]` Section

The `[config]` section defines top-level package filtering and environment tags:

| Key | Description | Example |
| :--- | :--- | :--- |
| `groups` | Comma-separated package groups to install | `groups = core, shell, dev-tools` |
| `packages` | Explicit packages to include and lock ON | `packages = starship, fzf, zstd` |
| `custom_packages_dir` | Directory containing personal custom package manifests | `custom_packages_dir = ./packages` |
| `exclude` | Packages to block and lock OFF | `exclude = docker, podman, dotnet` |
| `cond` | Force-enable condition tags manually | `cond = wsl, desktop` |
| `disable_cond` | Force-disable condition tags manually | `disable_cond = container` |

> **Note on Case-Insensitivity**: All configuration keys in `.conf` files are case-insensitive (`groups`, `GROUPS`, and `Groups` parse identically, normalized to lowercase).

### Multi-line Value Lists

List keys (`groups`, `packages`, `exclude`) support multi-line declarations:

```ini
[config]
groups = core,
    shell,
    dev-tools

packages =
    starship,
    fzf,
    ripgrep,
    bat,
    zstd
```

### Section Modifiers

Modifiers control how a section combines with lower layers:

- `:append` *(default)*: Appends new lines to lower layer content.
- `:override`: Discards lower layer content entirely and applies only the new definition.
- `:disable`: Suppresses execution of the section or stops template deployment.

#### Complete `.conf` Example

```ini
[config]
# Active package groups (empty = all available groups)
groups = core, shell, dev-tools, runtimes

# Explicit packages to include (locked ON)
packages = starship, fzf, ripgrep, bat, zstd

# Packages to exclude (locked OFF)
exclude = docker, podman, dotnet

# Manual condition overrides (comma-separated tags)
# cond = wsl, desktop
# disable_cond = container

# ── Interactive TUI Badges ────────────────────────────────────────────────────
# When launching ./rigrc.sh interactively, packages display status badges:
#   ● (Cyan)    selected in config       Locked ON via packages/groups
#   ● (Magenta) core system              Locked ON as base system dependency
#   ✓ (Green)   already installed        Detected on host system
#   ○ (Gray)    skipped (<target> pres.) Skipped because alternative exists
#   ⊘ (Dim)     excluded in config       Locked OFF via exclude
#   ⊘ (Amber)   unavailable on <OS>      Condition mismatch (e.g. WSL only)

# ── Package Key Overrides ─────────────────────────────────────────────────────
[package:git]
git_user_name = Jane Doe
git_email = jane@example.com
git_default_branch = main
# Use !delete to completely remove an inherited key from the base layer
# git_signing_key = !delete

# ── Shell Integration Snippets ────────────────────────────────────────────────
[bashrc:append]
export EDITOR="nvim"
export VISUAL="nvim"
export PROJECTS_DIR="$HOME/Pro"

# Custom shell aliases
alias g="git"
alias ll="eza -la --icons"

# Suppress specific package shell integrations
[bashrc:fzf:disable]

# ── Template Overrides ────────────────────────────────────────────────────────
# Discard upstream template and provide your complete config
[template:.gitconfig:override]
[user]
    name = Jane Doe
    email = jane@example.com
[core]
    editor = nvim
[init]
    defaultBranch = main

# Suppress deployment of specific upstream templates
[template:starship.toml:disable]
```

---

## 3. Package Manifest Syntax (`packages/**/*.conf`)

Packages are defined in `.conf` files grouped by category under `packages/`.

### Schema Fields

| Field | Type | Description |
| :--- | :--- | :--- |
| `name` | String | Package identifier (matches `.conf` filename) |
| `binaries` | String | Comma-separated binary names to check in `$PATH` |
| `description`| String | Short tool description |
| `scope` | Enum | `system` (uses package manager / `sudo`), `user` (`~/.local/bin`), `script` |
| `apt`, `dnf`, `pacman` | String | Native distro package manager package names |
| `brew`, `mise` | String | Cross-platform / runtime tool manager targets (Homebrew, Mise) |
| `cmd` | String | Custom shell installation command / script |
| `pre` | String | Shell command to execute before installation |
| `post` | String | Shell command to execute after successful installation |
| `alt` | String | Alternative tool replaced (e.g. `alt = ls`, `alt = cat`, `alt = cd`) |
| `needs` | String | Comma-separated required package dependencies (e.g. `needs = curl, git`) |
| `optional` | Boolean | `true` if package is optional within its group |
| `cond` | String | Condition filter (e.g. `cond = !container,wsl`) |

### Example 1: System Package with Post-Hook and Template

```ini
[package]
name = bat
binaries = bat,batcat
description = Cat clone with syntax highlighting and Git integration
scope = system
apt = bat
dnf = bat
pacman = bat
post = BIN=$(command -v batcat 2>/dev/null || true); [ -x $BIN ] && sudo ln -sf $BIN /usr/local/bin/bat || true
alt = cat
optional = true

[template:~/.config/bat/config:once]
--theme="ansi"
--style="auto"

[bashrc]
if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
```

### Example 2: User-Scoped Tool with Custom Script

```ini
[package]
name = zoxide
binaries = zoxide
description = Fast directory navigation tool with jump history
scope = user
cmd = curl --proto '=https' --tlsv1.2 -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir ${XDG_BIN_HOME:-$HOME/.local/bin}
alt = cd
optional = true

[bashrc]
if command -v zoxide >/dev/null 2>&1; then
    _eval_cached zoxide zoxide init bash
fi
```

---

## 4. Condition Grammar (`cond`)

Conditions restrict package installation and template deployment to matching host environments:

- OS & Environment tags: `linux`, `wsl`, `container`, `vps`, `desktop`
- Architecture tags: `x86_64`, `amd64`, `arm64`, `aarch64` (optionally prefixed with `arch:`, e.g. `arch:x86_64`)
- Negation prefix: `!` (e.g. `!container`, `!wsl`, `!desktop`)
- Multi-condition: Comma-separated (logical AND)

```ini
# Installs on WSL outside containers
cond = wsl,!container

# Installs only on arm64/aarch64 Linux systems
cond = linux,arch:arm64
```
