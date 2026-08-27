# Contributing to rigrc
 
Guidelines for adding package manifests, improving the engine, and submitting pull requests.

---

## 1. Golden Rule

> **Never edit `rigrc.sh` directly.**
>
> `rigrc.sh` is generated automatically by `build.sh` from `src/` modules, `src/base.conf`, and `packages/`. Any manual edits to `rigrc.sh` will fail CI checks.

---

## 2. Adding a New Package

Package manifests live under `packages/<category>/<tool>.conf`.

### Package Manifest Checklist

1. **Category**: Place in an existing directory (`core`, `shell`, `dev-tools`, `runtimes`, `ai-agents`, `security-and-net`, `utilities`, `sys-info`) or define a new group in `packages/_groups.conf`.
2. **Distro Targets**: Provide targets for package managers where available:
   - `apt` (Debian/Ubuntu)
   - `dnf` (Fedora/RHEL)
   - `pacman` (Arch)
   - `brew` (macOS)
   - `mise` (Polyglot tool & runtime manager)
   - `cmd` (Custom shell install scripts)
3. **Scope**:
   - `scope = system`: Installed via system package manager using `sudo`.
   - `scope = user`: Binary installed to `~/.local/bin` without root privileges.
4. **Alternatives**: If replacing a standard utility (such as `ls`, `cat`, `find`, or `cd`), set `alt = <tool>`.
5. **Defaults & Integration**:
   - Config template: `[template:<path>:once]`
   - Shell integration: `[bashrc]` block with a command check guard (`if command -v <tool> >/dev/null 2>&1; then ... fi`).
6. **Environment Conditions**: If the tool only applies to specific environments (or should be excluded from containers), add `cond = !container` or `cond = wsl`.

---

## 3. Formatting & Linting

Format and validate manifests before submitting:

```bash
# Format manifests and configuration files
./rigrc.sh --fmt

# Run syntax and schema validation
./rigrc.sh --lint
```

---

## 4. Building & Testing

Build the bundle:

```bash
make build
# or
./build.sh
```

Run tests:

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
   git commit -m "feat(packages): add helix editor package"
   ```
3. Push to your fork and open a Pull Request against `main`.
