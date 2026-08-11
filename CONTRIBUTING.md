# Contributing to mydotfiles

Thank you for contributing! This document outlines guidelines for submitting package manifests, upstream improvements, and bug fixes.

---

## 1. Golden Rule

> **Never edit `setup.sh` directly.**
>
> `setup.sh` is a compiled distribution bundle generated automatically by `build.sh` from `src/` modules, `default.conf`, and `packages/`. Any manual edits to `setup.sh` will be rejected by CI.

---

## 2. Adding a New Package

All packages live in declarative manifests under `packages/<category>/<tool>.conf`.

### Checklist for New Packages

1. **Choose Category**: Place in an existing directory (`core`, `shell`, `dev-tools`, `runtimes`, `ai-agents`, `security-and-net`, `utilities`, `sys-info`) or propose a new group in `packages/_groups.conf`.
2. **Multi-Distro Coverage**: Provide package targets for all standard package managers:
   - `apt` (Debian/Ubuntu)
   - `dnf` (Fedora/RHEL)
   - `pacman` (Arch)
   - `brew` (macOS)
   - `cargo` / `go` / `npm` (Language package managers)
   - `cmd` (Shell fallback for user-space installers)
3. **Set Scope**:
   - `scope = system`: Installed via system PM with `sudo`.
   - `scope = user`: Binary installed to `~/.local/bin` without root privileges.
4. **Define Alternatives**: If replacing a standard Unix utility (e.g. `ls`, `cat`, `find`, `cd`), set `alt = <tool>`.
5. **Add Sensible Defaults**:
   - Configuration template: `[template:<path>:once]`
   - Shell integration: `[bashrc]` block with command check guard (`if command -v <tool> >/dev/null 2>&1; then ... fi`).
6. **Environment Gates**: If the tool is unsupported or unneeded in specific environments, add `cond = !container` or `cond = wsl`.

---

## 3. Formatting & Linting

Before opening a pull request, run the static analysis and formatting tools:

```bash
# Format manifests and configuration files
./setup.sh --fmt

# Run static syntax and schema validation
./setup.sh --lint
```

---

## 4. Building & Testing

### Compile Standalone Distribution Bundle

```bash
make build
# or
./build.sh
```

### Run Test Suite

```bash
make test
# or
./test.sh
```

---

## 5. Submitting a Pull Request

1. Fork the repository and create a descriptive branch:
   ```bash
   git checkout -b feat/add-helix-editor
   ```
2. Commit using Conventional Commits:
   ```bash
   git commit -m "feat(packages): add helix editor package manifest"
   ```
3. Push to your fork and open a Pull Request against `main`.
