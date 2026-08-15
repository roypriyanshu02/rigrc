## Description

<!-- Provide a concise summary of the changes and the problem being solved. -->

Fixes # <!-- (or Closes #) -->

## Type of Change

- [ ] New package manifest (`packages/<category>/<tool>.conf`)
- [ ] Bug fix (non-breaking fix for an existing issue)
- [ ] New feature (non-breaking addition to script flags, engine, or templates)
- [ ] Performance / optimization
- [ ] Documentation update
- [ ] Breaking change (modifies manifest syntax or script options)

## Checklist

### Development & Build Workflow

- [ ] Changes are in source files under `src/` or `packages/`, **NOT** directly in the compiled `rigrc.sh` bundle.
- [ ] Rebuilt standalone bundle with `./build.sh` (or `make build`) to verify bundle generation.

### Package Manifests (if modifying `packages/`)

- [ ] Manifest placed in appropriate group folder (`packages/<category>/<tool>.conf`).
- [ ] Multi-distro package manager targets defined where available (`apt`, `dnf`, `pacman`, `brew`, `mise`, `cmd`).
- [ ] `scope` is explicitly declared (`scope = system` or `scope = user`).
- [ ] Any `[bashrc]` shell integration hooks include command guards (`if command -v <tool> >/dev/null 2>&1; then ... fi`).

### Code Quality & Validation

- [ ] Formatted manifests and configs with `./rigrc.sh --fmt`.
- [ ] Passed static manifest validation with `./rigrc.sh --lint`.
- [ ] Passed ShellCheck checks (`shellcheck -s bash src/*.sh build.sh test.sh tests/*.sh`).
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat(packages): add zellij manifest`).

### Testing & Verification

- [ ] Automated test suite passes locally (`./test.sh` or `make test`).
- [ ] Verified installation and runtime behavior in target environment (Linux, macOS, or WSL).
