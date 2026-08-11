# Configuration & Manifest Syntax Reference

This document covers the complete syntax, inheritance model, section modifiers, and condition grammar used across user configuration files (`*.conf`) and package manifests (`packages/**/*.conf`).

---

## 1. The Inheritance Cascade

Configuration values and templates merge down three distinct tiers:

$$\text{default.conf (base defaults)} \longrightarrow \text{packages/*/*.conf (package defaults)} \longrightarrow \text{*.conf (user overrides)}$$

- Lower layers provide defaults.
- Higher layers append to, replace, or suppress lower layer settings using section modifiers.

---

## 2. User Configuration Syntax (`*.conf`)

User configuration files sit in the repository root and define machine-level customizations.

### Section Types

| Section Header | Purpose | Example |
| :--- | :--- | :--- |
| `[config]` | Script-level configuration & group selection | `INSTALL_GROUPS = core, shell` |
| `[package:<name>]` | Package-level settings and key overrides | `[package:gitconfig]` |
| `[bashrc:<name>]` | Custom shell integration snippets & aliases | `[bashrc:append]` |
| `[template:<path>]` | Dotfile template definition and file deployment | `[template:.gitconfig]` |

### Section Modifiers

Modifiers control how a section combines with lower layers:

- `:append` *(default)* — Appends new lines to the lower layer content.
- `:override` — Discards lower layer content entirely and applies only the new definition.
- `:disable` — Suppresses execution of the section or stops template deployment.

#### Complete `.conf` Example

```ini
[config]
# Comma-separated list of package groups (empty = all available groups)
INSTALL_GROUPS = core, shell, dev-tools, runtimes

# Manual condition overrides (comma-separated tags)
# COND = wsl, desktop
# DISABLE_COND = container

# ── Package Key Overrides ─────────────────────────────────────────────────────
[package:gitconfig]
GIT_USER_NAME = Jane Doe
GIT_EMAIL = jane@example.com
GIT_DEFAULT_BRANCH = main
# Use !delete to completely remove an inherited key from the base layer
# GIT_SIGNING_KEY = !delete

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

Every package in `packages/` is defined declaratively in its category folder.

### Schema Fields

| Field | Type | Description |
| :--- | :--- | :--- |
| `name` | String | Package identifier (matches `.conf` filename) |
| `binaries` | String | Comma-separated binary names to check in `$PATH` |
| `description`| String | Short tool description |
| `scope` | Enum | `system` (uses package manager / `sudo`), `user` (`~/.local/bin`), `script` |
| `apt`, `dnf`, `pacman`, `brew` | String | Native package manager package names |
| `cargo`, `go`, `npm` | String | Language package manager targets |
| `cmd` | String | Custom shell installation command / fallback script |
| `pre` | String | Shell command to execute before installation |
| `post` | String | Shell command to execute after successful installation |
| `alt` | String | Alternative tool replaced (e.g. `alt = ls`, `alt = cat`, `alt = cd`) |
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

Conditions gate package installation and template deployment based on the host environment:

- Distro tags: `debian`, `ubuntu`, `fedora`, `arch`, `darwin`
- Architecture tags: `arch:x86_64`, `arch:aarch64`, `arch:arm64`
- Environment tags: `wsl`, `container`, `vps`, `desktop`
- Negation prefix: `!` (e.g. `!container`, `!wsl`)
- Multi-condition: Comma-separated (logical AND)

```ini
# Installs only when running on Ubuntu or Debian, outside containers
cond = debian,!container
```
