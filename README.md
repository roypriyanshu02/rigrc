# rigrc

*Declarative Unix bootstrapper and dotfiles manager in pure Bash.*

> **Note:** rigrc currently targets CLI environments. Desktop and GUI configurations are planned for future releases.

A compiled, standalone single-file script to bootstrap Unix systems. It installs packages across package managers (`apt`, `dnf`, `pacman`, `brew`, `mise`, `cmd`), deploys dotfiles, configures shell environments (`.bashrc`, `.inputrc`, `.profile`, `.gitconfig`), and manages rollback snapshots.

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
    •     --skip-upgrade         Skip system package manager update and upgrade
    •     --offline              Skip network checks and online package downloads
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

Define machine profiles, package sets, granular overrides (`:append`, `:override`, `:disable`), environment variables, and dotfile templates in a single `.conf` file. Works across Linux servers, workstations, WSL, and containers. See the **[Power User Guide](docs/POWERUSER_GUIDE.md)** for configuration workflows.

## Contributing

To add packages or contribute engine improvements, see the **[Contributing Guide](CONTRIBUTING.md)**.

## License

[![License: MIT](https://img.shields.io/badge/license-MIT-0284c7?style=flat-square)](LICENSE)
