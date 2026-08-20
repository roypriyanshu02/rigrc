# Power User Guide

This guide walks through creating your personal dotfiles repository, managing machine environments, automating updates from upstream, and provisioning new systems.

---

## 1. Overview & Architecture

`rigrc` separates your personal environment settings from cross-distro package definitions:

- **Upstream Engine & Package Manifests**: Maintained in `rigrc` with multi-distro definitions (`apt`, `dnf`, `pacman`, `brew`, `mise`, `cmd`), pre/post hooks, and default configuration templates.
- **Your Personal Repository**: Contains only `rigrc.sh` (the self-extracting distribution bundle) and your personal configuration files (`*.conf`).

```mermaid
flowchart LR
    subgraph Upstream ["roypriyanshu02/rigrc"]
        Engine["Engine & Manifests"] --> Bundle["rigrc.sh"]
    end

    subgraph DotfilesRepo ["Your Dotfiles Repo"]
        Bundle -.->|"sync / download"| Script["rigrc.sh"]
        Config["custom.conf"]
    end

    subgraph Target ["Target Machine"]
        Script --> Run["./rigrc.sh --config=custom.conf"]
        Config --> Run
    end
```

---

## 2. Creating Your Personal Dotfiles Repo

### Step 1: Initialize Your Git Repository

Create a new repository on GitHub or GitLab (e.g. `yourname/dotfiles`).

```bash
mkdir my-dotfiles && cd my-dotfiles
git init
```

### Step 2: Download `rigrc.sh`

Download the latest compiled release bundle:

```bash
curl -fsSL https://github.com/roypriyanshu02/rigrc/releases/latest/download/rigrc.sh -o rigrc.sh
chmod +x rigrc.sh
```

### Step 3: Create Your Configuration File (`custom.conf`)

Review the default upstream configuration before writing your own:

- **[src/base.conf](file:///home/roypr/Pro/mydotfiles/src/base.conf)**: Baseline environment variables, shell settings, and core dotfile templates.
- **[packages/](file:///home/roypr/Pro/mydotfiles/packages)**: Package manifests organized by group (`shell/`, `dev-tools/`, etc.). Each manifest defines package manager targets, bundled dotfile templates (`[template:...]`), shell hooks (`[bashrc]`), and environment filters (`cond`).

Use these files as a reference to determine what to inherit, override (`:override`), append (`:append`), or suppress (`:disable`) in your custom configuration file:

```ini
# custom.conf: Personal machine environment

[config]
# Select package groups to install (from packages/_groups.conf)
# Available: core, package-managers, shell, runtimes, sys-info, security-and-net, dev-tools, utilities, ai-agents
INSTALL_GROUPS = core, shell, dev-tools, runtimes

# Condition overrides (force enable or disable specific features)
# COND = wsl
# DISABLE_COND = container

# ── Git Identity & Package Overrides ──────────────────────────────────────────
[package:gitconfig]
GIT_USER_NAME = Your Name
GIT_EMAIL = you@example.com

# ── Custom Shell Environment & Aliases ────────────────────────────────────────
[bashrc:append]
export EDITOR="nvim"
export PROJECTS_DIR="$HOME/Pro"
alias g="git"
alias ll="eza -la"

# Suppress fzf shell integration if unneeded
# [bashrc:fzf:disable]

# ── Dotfile Template Overrides ────────────────────────────────────────────────
# Discard upstream template and provide your complete config
[template:.gitconfig:override]
[user]
    name = Your Name
    email = you@example.com
[core]
    editor = nvim
[init]
    defaultBranch = main

# Suppress deployment of specific templates
# [template:starship.toml:disable]
```

> For full syntax details, condition tags (`wsl`, `container`), and section modifiers (`:append`, `:override`, `:disable`), see the **[Configuration & Manifest Syntax Reference](MANIFEST_SYNTAX.md)**.

### Step 4: Validate Your Configuration

Run the built-in formatter and linter before committing:

```bash
./rigrc.sh --fmt
./rigrc.sh --lint
```

### Step 5: Commit & Push

```bash
git add rigrc.sh custom.conf
git commit -m "feat: init personal dotfiles repository"
git remote add origin https://github.com/yourname/dotfiles.git
git push -u origin main
```

---

## 3. Automating Upstream Updates via GitHub Actions

To keep your `rigrc.sh` bundle up-to-date with upstream bug fixes, package additions, and distro adjustments without manual downloading:

Create `.github/workflows/sync.yml` in your personal repo:

```yaml
name: Sync Upstream

on:
  schedule:
    - cron: '0 0 * * 1' # Runs every Monday at midnight
  workflow_dispatch:      # Allows manual trigger via GitHub UI

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Download latest release bundle
        run: |
          curl -fsSL https://github.com/roypriyanshu02/rigrc/releases/latest/download/rigrc.sh -o rigrc.sh
          chmod +x rigrc.sh

      - name: Validate configuration files against new bundle
        run: |
          ./rigrc.sh --lint

      - name: Commit and push changes
        uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: "chore(upstream): update rigrc.sh release bundle"
          file_pattern: "rigrc.sh"
```

---

## 4. Provisioning a New Machine

On any fresh Linux system, WSL instance, VPS, or container:

```bash
git clone https://github.com/yourname/dotfiles.git ~/.dotfiles-repo
cd ~/.dotfiles-repo

# Interactive mode (TUI menu for selective installation)
./rigrc.sh --config=custom.conf

# Headless mode (fully automated setup for CI/CD, containers, or remote servers)
./rigrc.sh --config=custom.conf --non-interactive
```

---

## 5. Maintenance & Disaster Recovery

### Environment Diagnostics & Fixes

Audit PATH variables, broken symlinks, missing compilers, and required dependencies:

```bash
./rigrc.sh --doctor --fix
```

### Clean Broken Symlinks

Prune orphaned symlinks in `$HOME` pointing to nonexistent targets:

```bash
./rigrc.sh --clean-symlinks
```

### Rollback Previous State

Every deployment creates a timestamped backup in `~/.dotfiles.bak/` with a SHA-256 manifest:

```bash
# Interactive rollback selector
./rigrc.sh --rollback

# Roll back to a specific timestamped snapshot
./rigrc.sh --rollback=20260819_120000
```
