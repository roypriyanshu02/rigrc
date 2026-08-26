# rigrc

*Declarative, high-performance Unix environment bootstrapper and dotfiles orchestrator in pure Bash.*

> **Note:** Currently focused on CLI. Desktop and GUI configurations are planned for future updates (contributions welcome).

A compiled, zero-dependency single-file engine to provision reproducible Unix systems in seconds. Orchestrates cross-distro package managers (`apt`, `dnf`, `pacman`, `brew`, `mise`, `cmd`), automates modular dotfile deployment, injects optimized shell environments (`.bashrc`, `.inputrc`, `.profile`, `.gitconfig`), and manages atomic rollback snapshots out-of-the-box.

## Quick Start

```bash
bash -c "$(curl -fsSL https://github.com/roypriyanshu02/rigrc/releases/latest/download/rigrc.sh)"
```

## Script Options

```text
USAGE
    ./rigrc.sh [OPTIONS]

OPTIONS
    • -c, --config <file>        Load configuration file
    • -v, --verbose              Show verbose command output
    • -f, --force, --reset       Overwrite existing files and bypass locks
    •     --env <name>           Run specific environment
    • -y, --non-interactive      Run headlessly without interactive TUI
    •     --verify-scripts       Prompt before running custom scripts
    •     --list                 List available packages by group
    •     --fmt, --format        Format configuration and manifest files
    •     --lint                 Validate manifest and configuration syntax
    •     --clean-symlinks       Remove broken dotfile symlinks in home directory
    •     --rollback [snapshot]  Roll back snapshot from ~/.dotfiles.bak
    •     --export-diagnostics   Export diagnostic snapshot to JSON file
    •     --doctor [--fix]       Check system environment and repair missing paths
    • -V, --version              Show version
    • -h, --help                 Show help
```

## Declarative Configuration

Define machine profiles, package sets, granular overrides (`:append`, `:override`, `:disable`), environment variables, and dotfile templates in a single declarative `.conf` file. Deploy reproducibly across servers, workstations, WSL, and containers. Read **[Power User Guide](docs/POWERUSER_GUIDE.md)** to architect your setup.

## Contributing & Manifest Development

To extend package manifests or contribute engine improvements, see **[Contributing Guide](CONTRIBUTING.md)**.

## License

[![License: MIT](https://img.shields.io/badge/license-MIT-0284c7?style=flat-square)](LICENSE)
