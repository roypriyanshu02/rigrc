# rigrc

*Fast, standalone Unix environment bootstrapper in pure Bash.*

A compiled, single-file Bash script to set up Unix systems. Installs packages, configures baseline environments (`.bashrc`, `.inputrc`, `.profile`, Git), wires package configs, and aliases, and applies best practices out-of-the-box so your machine is ready to work in minutes.

## Quick Start

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roypriyanshu02/rigrc/main/rigrc.sh)"
```

## CLI Options

```text
USAGE
    ./rigrc.sh [OPTIONS]

OPTIONS
    • -c, --config <file>        Load configuration file
    • -v, --verbose              Show verbose command output
    • -f, --force, --reset       Overwrite existing files and bypass locks
    •     --profile <name>       Run specific group profile
    • -y, --non-interactive      Run headlessly without interactive TUI
    •     --verify-scripts       Prompt before running custom scripts
    •     --list                 List available packages by group
    •     --fmt, --format        Format configuration and manifest files
    •     --lint                 Validate manifest and configuration syntax
    •     --clean-symlinks       Remove broken dotfile symlinks in home directory
    •     --rollback [snapshot]  Roll back snapshot from ~/.dotfiles.bak
    •     --export-diagnostics   Export diagnostic snapshot to JSON file
    •     --doctor [--fix]       Check system environment and repair missing paths
    • -h, --help                 Show help
```

## Custom Configurations

Configure once, deploy anywhere. Define your packages, aliases, environment variables, and dotfiles in a `.conf` file and take them across all your machines. Read the **[User Guide](docs/USER_GUIDE.md)** to get started.

## Contributing & Development

To add new package manifests or contribute upstream improvements, see the **[Contributing Guide](CONTRIBUTING.md)**.

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-0284c7?style=flat-square)](LICENSE)
